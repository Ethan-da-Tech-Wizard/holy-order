# ==============================================================================
# Program: demolition.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for demolition.gd.
# ==============================================================================
## Demolition satchel system for the desert mission: supply cache, carried satchel, cable and detonator.
##
## One instance exists per mission; `game` must be set before _ready. The player takes
## a satchel from the cache (3 in stock), places it or lobs it, walks away trailing a cable
## and detonates it with a key press. The cable is drawn as a polyline from the satchel to the
## player's belt; stretching it past 30 m breaks it (a balance device, so the player must stay
## close). Detonation calls `game.explode(point, damage, radius)`.
extends Node3D

# Period-style, preassembled field demolition satchel. The 30 m line and
# one-charge capacity are game balance abstractions, not historical instructions.
# Shared art helpers for primitives and materials.
# Period-style, preassembled field demolition satchel. The 30 m line and
# one-charge capacity are game balance abstractions, not historical instructions.
const Art=preload("res://scripts/art.gd")

# Mission controller: provides the player, toast/say messages, phase and explode().
var game

# The supply crate (a destructible solid); destroying it empties the stock.
var cache

# Satchels left in the cache.
var stock: int=3

# Visual satchels on the cache, hidden one at a time as they are taken.
var packs: Array=[]

# Satchels the player holds (0 or 1).
var carried: int=0

# The deployed satchel node, or null.
var active: Node3D

# Velocity of a lobbed satchel in m/s while in flight.
var velocity=Vector3.ZERO

# True once resting on a surface; the cable only trails after settling.
var settled: bool=false

# True after the cable stretched past the limit; the charge can then only be recovered, not fired.
var cable_broken: bool=false

# Total cable length in metres (satchel to belt via anchor points).
var cable_length: float=0

# Points the cable bends around: the satchel plus places the player passed.
var anchors: Array[Vector3]=[]

# Mesh showing the cable.
var cable: MeshInstance3D

# Hand-held detonator box shown while a satchel is deployed.
var detonator: Node3D

# Satchel shown in the player's hand while carrying one.
var satchel: Node3D

# Maximum cable length in metres.
const CABLE_LIMIT=30.0

## Build the supply cache, its label and satchels, and the first-person detonator and carried satchel.
func _ready():
	# Fixed location of the cache in world coordinates.
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
	# If the cache is shot to pieces, no more satchels can be taken.
	cache.geometry_changed.connect(func():
		if cache.destroyed:stock=0
	)
	# Held items are children of the player's hands so they follow the camera.
	detonator=Node3D.new()
	game.player.hands.add_child(detonator)
	detonator.position=Vector3(0.26,-0.24,-0.49)
	Art.beveled_box(detonator,Vector3(0.15,0.13,0.11),Vector3.ZERO,Art.material(Color("655a40")),0.01)
	Art.cylinder(detonator,0.008,0.09,Vector3(0,0.10,0),Art.material(Color("6c7773"),0.7))
	Art.box(detonator,Vector3(0.10,0.025,0.025),Vector3(0,0.15,0),Art.material(Color("323c38")))
	Art.gauntlet(detonator,Vector3(-0.01,-0.11,0.02),Vector3(-0.7,0,0))
	satchel=make_satchel(game.player.hands)
	satchel.position=Vector3(0.27,-0.29,-0.58)
	# Hidden until the player equips the satchel / has a deployed charge.
	detonator.hide()
	satchel.hide()
	# Cable is a mesh rebuilt every physics tick from the anchor list.
	cable=MeshInstance3D.new()
	add_child(cable)
	cable.material_override=Art.material(Color("37382f"))

## Build one satchel model: canvas bag, two straps and a carry strap.
## @param parent Node to attach to.
## @return The satchel root node.
func make_satchel(parent: Node3D) -> Node3D:
	var root=Node3D.new()
	parent.add_child(root)
	Art.beveled_box(root,Vector3(0.34,0.19,0.24),Vector3.ZERO,Art.material(Color("817553")),0.024)
	for x in [-0.11,0.11]:
		Art.box(root,Vector3(0.04,0.20,0.245),Vector3(x,0,0),Art.material(Color("4c4d37")))
	Art.segment(root,Vector3(-0.10,0.12,0),Vector3(0.10,0.12,0),0.014,Art.material(Color("4c4d37")))
	return root

## Whether a satchel can be taken from the cache right now.
func available() -> bool:
	return not cache.destroyed and stock>0 and carried==0 and not is_instance_valid(active)

## Take one satchel from the cache; shows the control hints.
func take():
	if not available():return
	stock-=1
	packs[stock].hide()
	carried=1
	game.toast("DEMOLITION SATCHEL  •  5 equip / LMB place / RMB lob / B detonate",6)
	game.say("The pouch appears to contain an argument against architecture.",5)

## Place (look at a surface) or lob a satchel.
## @param lob true to throw it in an arc, false to place it on a nearby surface.
func deploy(lob: bool):
	if carried<=0 or is_instance_valid(active):return
	var camera=game.player.camera
	var direction=-camera.global_basis.z
	var start=camera.global_position
	# Placement starts just in front of the camera for lobs.
	var point=start+direction*0.5
	if not lob:
		# Ray 2.7 m ahead on the world layer; place only works on nearby surfaces.
		var ray=PhysicsRayQueryParameters3D.create(start,start+direction*2.7,1)
		var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			game.toast("Look at a nearby wall or the ground to place the satchel.",3)
			return
		# Offset 15 cm along the surface normal so the satchel sits on, not in, the surface.
		point=hit.position+hit.normal*0.15
	active=make_satchel(self)
	active.global_position=point
	carried=0
	settled=not lob
	# Lob velocity: 7 m/s along the view direction plus 2 m/s upward.
	velocity=direction*7+Vector3(0,2,0) if lob else Vector3.ZERO
	cable_broken=false
	cable_length=0
	anchors.clear()
	game.toast("SATCHEL DEPLOYED  •  Move clear / B detonate / F recover",4)

## Pick the deployed satchel back up (key F).
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

## Blow up the deployed satchel.
func detonate():
	if not is_instance_valid(active):return
	# A broken cable cannot trigger; the player must recover the satchel.
	if cable_broken:
		game.toast("The cable has broken. Recover the satchel with F.",3)
		return
	var point=active.global_position
	active.queue_free()
	active=null
	anchors.clear()
	cable.mesh=null
	# 780 damage with a 6 m radius is enough to open walls (see breakable.gd resistance table).
	game.explode(point,780,6.0)
	game.toast("DEMOLITION  •  A new way through.",3)

## Per-tick update: item visibility, projectile flight and cable.
## @param delta Seconds since last tick.
func _physics_process(delta):
	if game.phase!="playing":return
	# Weapon slot 4 is the demolition kit.
	detonator.visible=game.player.weapon==4 and is_instance_valid(active)
	satchel.visible=game.player.weapon==4 and carried>0
	if not is_instance_valid(active):return
	if not settled:
		# Simple ballistic flight: gravity 14 m/s^2, ray test along each step so it cannot tunnel through walls.
		velocity.y-=14*delta
		var from=active.position
		var to=from+velocity*delta
		var hit=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))
		if not hit.is_empty():
			# Stick at the hit point, nudged 13 cm out along the normal.
			to=hit.position+hit.normal*0.13
			settled=true
			velocity=Vector3.ZERO
		active.position=to
	if not settled:return
	# Belt is about hip height on the player.
	var belt=game.player.global_position+Vector3(0,0.15,0)
	if anchors.is_empty():anchors.append(active.global_position)
	# Add a bend point whenever the player has moved more than 1.4 m from the last anchor.
	if not cable_broken and anchors[-1].distance_to(belt)>1.4:
		anchors.append(belt)
	cable_length=0
	# Cable length = sum of segments plus the last leg to the player's belt.
	for i in range(1,anchors.size()):cable_length+=anchors[i-1].distance_to(anchors[i])
	cable_length+=anchors[-1].distance_to(belt)
	# Stretching beyond the limit severs the cable.
	if cable_length>CABLE_LIMIT and not cable_broken:
		cable_broken=true
		game.toast("Cable broken. F at the satchel to recover it.",4)
	# Rebuild the line strip mesh every tick; cheap for a handful of points.
	var mesh=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in anchors:mesh.surface_add_vertex(point)
	if not cable_broken:mesh.surface_add_vertex(belt)
	mesh.surface_end()
	cable.mesh=mesh
