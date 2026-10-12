extends Node3D

# Period-style, preassembled field demolition satchel. The 30 m line and
# one-charge capacity are game balance abstractions, not historical instructions.
const Art=preload("res://scripts/art.gd")
var game
var cache
var stock: int=3
var packs: Array=[]
var carried: int=0
var active: Node3D
var velocity=Vector3.ZERO
var settled: bool=false
var cable_broken: bool=false
var cable_length: float=0
var anchors: Array[Vector3]=[]
var cable: MeshInstance3D
var detonator: Node3D
var satchel: Node3D
const CABLE_LIMIT=30.0

func _ready():
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
	cache.geometry_changed.connect(func():
		if cache.destroyed:stock=0
	)
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

func make_satchel(parent: Node3D) -> Node3D:
	var root=Node3D.new()
	parent.add_child(root)
	Art.beveled_box(root,Vector3(0.34,0.19,0.24),Vector3.ZERO,Art.material(Color("817553")),0.024)
	for x in [-0.11,0.11]:
		Art.box(root,Vector3(0.04,0.20,0.245),Vector3(x,0,0),Art.material(Color("4c4d37")))
	Art.segment(root,Vector3(-0.10,0.12,0),Vector3(0.10,0.12,0),0.014,Art.material(Color("4c4d37")))
	return root

func available() -> bool:
	return not cache.destroyed and stock>0 and carried==0 and not is_instance_valid(active)

func take():
	if not available():return
	stock-=1
	packs[stock].hide()
	carried=1
	game.toast("DEMOLITION SATCHEL  •  5 equip / LMB place / RMB lob / B detonate",6)
	game.say("The pouch appears to contain an argument against architecture.",5)

func deploy(lob: bool):
	if carried<=0 or is_instance_valid(active):return
	var camera=game.player.camera
	var direction=-camera.global_basis.z
	var start=camera.global_position
	var point=start+direction*0.5
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
	settled=not lob
	velocity=direction*7+Vector3(0,2,0) if lob else Vector3.ZERO
	cable_broken=false
	cable_length=0
	anchors.clear()
	game.toast("SATCHEL DEPLOYED  •  Move clear / B detonate / F recover",4)

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

func _physics_process(delta):
	if game.phase!="playing":return
	detonator.visible=game.player.weapon==4 and is_instance_valid(active)
	satchel.visible=game.player.weapon==4 and carried>0
	if not is_instance_valid(active):return
	if not settled:
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
	var belt=game.player.global_position+Vector3(0,0.15,0)
	if anchors.is_empty():anchors.append(active.global_position)
	if not cable_broken and anchors[-1].distance_to(belt)>1.4:
		anchors.append(belt)
	cable_length=0
	for i in range(1,anchors.size()):cable_length+=anchors[i-1].distance_to(anchors[i])
	cable_length+=anchors[-1].distance_to(belt)
	if cable_length>CABLE_LIMIT and not cable_broken:
		cable_broken=true
		game.toast("Cable broken. F at the satchel to recover it.",4)
	var mesh=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in anchors:mesh.surface_add_vertex(point)
	if not cable_broken:mesh.surface_add_vertex(belt)
	mesh.surface_end()
	cable.mesh=mesh
