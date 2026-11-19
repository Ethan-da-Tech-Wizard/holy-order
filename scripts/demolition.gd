## Demolition satchel system for the desert mission: an ammunition-style cache
## that holds three pre-assembled charges, a player-held detonator, and the
## logic to place or throw a charge, run a cable behind the player and
## blow up walls.
##
## Role: created by game.gd, which sets `game` before _ready. It reads
## `game.player` (camera, hands, weapon id), calls game.explode() to apply
## damage and game.toast()/say() for messages. Weapon slot 4 is the
## demolition tool.
## Controls (from the toast text): 5 equip, LMB place, RMB lob, B detonate,
## F recover. The 30 m cable limit and one-charge capacity are game-balance
## abstractions, not instructions of any kind.
extends Node3D

# Period-style, preassembled field demolition satchel. The 30 m line and
# one-charge capacity are game balance abstractions, not historical instructions.
const Art=preload("res://scripts/art.gd")

## The Game node (game.gd); provides player, phase, explode(), toast(), say().
var game

## The destructible crate that holds the satchels; destroying it empties it.
var cache

## Satchels still in the cache (starts at 3).
var stock: int=3

## Visual satchel meshes sitting in the cache, one hidden per take().
var packs: Array=[]

## 0 or 1: whether the player is holding a satchel in hand.
var carried: int=0

## The deployed satchel node (null when none is placed).
var active: Node3D

## Velocity (m/s) of a lobbed satchel while it is in flight.
var velocity=Vector3.ZERO

## True once the satchel has stopped (placed on a surface or landed).
var settled: bool=false

## True when the cable exceeded CABLE_LIMIT; detonation is then impossible
## until the player recovers the satchel.
var cable_broken: bool=false

## Total length (m) of the cable path from the satchel to the player's belt.
var cable_length: float=0

## Polyline of world points the cable passes through; a new anchor is added
## each time the player moves more than 1.4 m from the previous one, so the
## cable "drags" around corners rather than being a straight line.
var anchors: Array[Vector3]=[]

## Mesh instance drawing the cable as a line strip.
var cable: MeshInstance3D

## First-person plunger box shown while a satchel is deployed.
var detonator: Node3D

## First-person satchel in the hand while one is carried.
var satchel: Node3D

## Maximum cable path length in metres before it snaps.
const CABLE_LIMIT=30.0

## Godot lifecycle hook: builds the supply crate with its three displayed
## satchels, and the hand-held detonator and satchel (hidden until used).
func _ready():
	# Crate is placed at a fixed spot near the village's western edge (-21, -39).
	cache=Art.solid(self,Vector3(1.15,0.65,0.75),Vector3(-21,0.325,-39),Art.material(Color("736647")))
	var label=Label3D.new()
	label.text="GENIO • MATERIALI"
	label.font_size=30
	label.pixel_size=0.0045
	label.position=Vector3(0,0.10,0.381)
	cache.add_child(label)
	for i in range(3):
		var pack=make_satchel(cache)
		pack.add_to_group("inventory_visual")
		pack.position=Vector3(-0.36+i*0.36,0.40,0)
		pack.scale=Vector3.ONE*0.60
		packs.append(pack)

	# Destroying the crate also destroys the satchels inside it.
	cache.geometry_changed.connect(func():
		if cache.destroyed:stock=0
	)

	# The viewmodel pieces are children of the player's hands node so they move
	# with the weapon sway.
	detonator=Node3D.new()
	game.player.hands.add_child(detonator)
	detonator.position=Vector3(0.26,-0.24,-0.49)
	Art.beveled_box(detonator,Vector3(0.15,0.13,0.11),Vector3.ZERO,Art.material(Color("655a40")),0.01)
	Art.cylinder(detonator,0.008,0.09,Vector3(0,0.10,0),Art.material(Color("6c7773"),0.7))
	Art.box(detonator,Vector3(0.10,0.025,0.025),Vector3(0,0.15,0),Art.material(Color("323c38")))
	Art.gauntlet(detonator,Vector3(-0.01,-0.11,0.02),Vector3(-0.7,0,0))
	satchel=make_satchel(game.player.hands)
	satchel.position=Vector3(0.27,-0.29,-0.58)
	detonator.hide()
	satchel.hide()
	cable=MeshInstance3D.new()
	add_child(cable)
	cable.material_override=Art.material(Color("37382f"))

## Builds a satchel visual (canvas pouch with two straps and a carry strap).
## [param parent] node to attach it to; returns the satchel root.
func make_satchel(parent: Node3D) -> Node3D:
	var root=Node3D.new()
	parent.add_child(root)
	Art.beveled_box(root,Vector3(0.34,0.19,0.24),Vector3.ZERO,Art.material(Color("817553")),0.024)
	for x in [-0.11,0.11]:
		Art.box(root,Vector3(0.04,0.20,0.245),Vector3(x,0,0),Art.material(Color("4c4d37")))
	Art.segment(root,Vector3(-0.10,0.12,0),Vector3(0.10,0.12,0),0.014,Art.material(Color("4c4d37")))
	return root

## True if a satchel can be taken: crate intact, stock left, hands empty and
## no charge currently deployed.
func available() -> bool:
	return not cache.destroyed and stock>0 and carried==0 and not is_instance_valid(active)

## Takes one satchel from the cache (hides one displayed pack) and shows the
## controls toast. No-op if not available().
func take():
	if not available():return
	stock-=1
	packs[stock].hide()
	carried=1
	game.toast("DEMOLITION SATCHEL  •  5 equip / LMB place / RMB lob / B detonate",6)
	game.say("The pouch appears to contain an argument against architecture.",5)

## Places the satchel on a nearby surface or lobs it.
## [param lob] true throws it from the camera at 7 m/s with 2 m/s upward;
## false places it on the surface the player is looking at (ray reach 2.7 m).
## Ray mask 1 = the world layer only.
func deploy(lob: bool):
	if carried<=0 or is_instance_valid(active):return
	var camera=game.player.camera
	var direction=-camera.global_basis.z
	var start=camera.global_position
	var point=start+direction*0.5

	# Placement needs a surface within reach; the satchel is offset 0.15 m along
	# the surface normal so it does not sink into the wall.
	if not lob:
		var ray=PhysicsRayQueryParameters3D.create(start,start+direction*2.7,1)
		var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			game.toast("Look at a nearby wall or the ground to place the satchel.",3)
			return
		point=hit.position+hit.normal*0.15
	active=make_satchel(self)
	active.global_position=point
	carried=0

	# A placed satchel is settled immediately; a lobbed one flies until it hits.
	settled=not lob
	velocity=direction*7+Vector3(0,2,0) if lob else Vector3.ZERO
	cable_broken=false
	cable_length=0
	anchors.clear()
	game.toast("SATCHEL DEPLOYED  •  Move clear / B detonate / F recover",4)

## Picks up the deployed satchel again (F key): clears the cable and returns
## the charge to the player's hand.
func recover():
	if not is_instance_valid(active):return
	active.queue_free()
	active=null
	carried=1
	anchors.clear()
	cable.mesh=null
	cable_broken=false
	cable_length=0
	game.toast("Satchel recovered.",2)

## Detonates the deployed satchel (B key) if the cable is intact: removes the
## charge and calls game.explode(point, 780 damage, 6 m radius).
func detonate():
	if not is_instance_valid(active):return
	if cable_broken:
		game.toast("The cable has broken. Recover the satchel with F.",3)
		return
	var point=active.global_position
	active.queue_free()
	active=null
	anchors.clear()
	cable.mesh=null
	game.explode(point,780,6.0)
	game.toast("DEMOLITION  •  A new way through.",3)

## Per-physics-tick update: shows or hides the viewmodels, simulates a lobbed
## satchel, extends the cable and breaks it past CABLE_LIMIT.
## [param delta] fixed physics step in seconds.
func _physics_process(delta):
	# - Parameter delta is fixed at 1/60s (approx 0.01667s) by Engine.max_fps configuration.
	# - Integrates kinematic velocity vectors, applies gravitational acceleration, and updates bounding colliders.
	# - Performs raycast obstacle evaluations before committing spatial position changes.
	if game.phase!="playing":return
	detonator.visible=game.player.weapon==4 and is_instance_valid(active)
	satchel.visible=game.player.weapon==4 and carried>0
	if not is_instance_valid(active):return
	if not settled:
		# Gravity of 14 m/s^2 (stronger than real) so lobs arc quickly and land
		# where the player expects.
		velocity.y-=14*delta
		var from=active.position
		var to=from+velocity*delta
		var hit=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))
		if not hit.is_empty():
			to=hit.position+hit.normal*0.13
			settled=true
			velocity=Vector3.ZERO
		active.position=to
	if not settled:return

	# The cable runs back to the player's belt (0.15 m above their position).
	var belt=game.player.global_position+Vector3(0,0.15,0)
	if anchors.is_empty():anchors.append(active.global_position)

	# Add a bend point whenever the player gets more than 1.4 m from the last
	# one, so the path follows where the player actually walked.
	if not cable_broken and anchors[-1].distance_to(belt)>1.4:
		anchors.append(belt)
	cable_length=0
	for i in range(1,anchors.size()):cable_length+=anchors[i-1].distance_to(anchors[i])
	cable_length+=anchors[-1].distance_to(belt)
	if cable_length>CABLE_LIMIT and not cable_broken:
		cable_broken=true
		game.toast("Cable broken. F at the satchel to recover it.",4)

	# The cable is rebuilt every tick as a line strip because the player's end
	# moves constantly; ImmediateMesh is cheap for such a short strip.
	var mesh=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in anchors:mesh.surface_add_vertex(point)
	if not cable_broken:mesh.surface_add_vertex(belt)
	mesh.surface_end()
	cable.mesh=mesh
