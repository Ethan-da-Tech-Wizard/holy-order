extends Node3D
const Art=preload("res://scripts/art.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")
const Part=preload("res://scripts/ardennes/corpse_part.gd")
var game
var soldier
var parts:Array=[]
var detached_count:int=0
static var meshes:Dictionary={}

func _ready():
	add_to_group("winter_corpses")
	var side=1 if soldier.index%2==0 else -1
	var pose=Basis(Vector3.FORWARD,side*PI/2)
	var cloth=Art.material(Color("646747") if soldier.team==1 else Color("535b55"))
	var skin=Art.material(Color("b19780"))
	var boot=Art.material(Color("342e26"))
	var data=[
		["torso",Vector3(0,1.15,0),Vector3(0.44,0.67,0.30)],
		["head",Vector3(0,1.74,0),Vector3(0.31,0.32,0.32)],
		["left arm",Vector3(-0.30,1.20,0),Vector3(0.16,0.61,0.17)],
		["right arm",Vector3(0.30,1.20,0),Vector3(0.16,0.61,0.17)],
		["left leg",Vector3(-0.13,0.44,0),Vector3(0.20,0.82,0.23)],
		["right leg",Vector3(0.13,0.44,0),Vector3(0.20,0.82,0.23)]]
	for entry in data:
		var part=Part.new()
		part.corpse=self
		part.part_name=entry[0]
		part.integrity=85 if entry[0]=="torso" else 45
		add_child(part)
		var p=global_position+global_basis*(pose*entry[1])
		p=game.world.on_ground(p)+Vector3(0,0.18,0)
		part.global_position=p
		part.basis=pose
		var key="%d/%s"%[soldier.team,entry[0]]
		if not meshes.has(key):
			var root=Node3D.new()
			if entry[0]=="head":
				Art.sphere(root,0.13,Vector3.ZERO,skin)
				var helmet=Art.sphere(root,0.17,Vector3(0,0.075,0.005),cloth)
				helmet.scale.y=0.55
				Art.cylinder(root,0.177,0.032,Vector3(0,0.057,0.005),cloth,-1,16)
			else:
				Art.beveled_box(root,entry[2],Vector3.ZERO,cloth,0.035)
				if "leg" in entry[0]:Art.beveled_box(root,Vector3(0.20,0.16,0.33),Vector3(0,-0.35,-0.06),boot,0.025)
				if "arm" in entry[0]:Art.sphere(root,0.077,Vector3(0,-0.32,0),boot)
				if entry[0]=="torso":
					Art.box(root,Vector3(0.45,0.06,0.31),Vector3(0,-0.16,0),Art.material(Color("99876a")))
			meshes[key]=Kit.bake(root)
			root.free()
		var mesh=MeshInstance3D.new()
		mesh.mesh=meshes[key]
		part.add_child(mesh)
		var cs=CollisionShape3D.new()
		var box=BoxShape3D.new()
		box.size=entry[2]
		cs.shape=box
		part.add_child(cs)
		parts.append(part)

func wound(part,point:Vector3):
	var red=Art.material(Color("522b2a"),0,0.83)
	var patch=Art.sphere(part,0.055,part.to_local(point),red)
	patch.scale=Vector3(1.3,0.55,1.2)
	# A persistent dark stain on the snow, kept small and finite for each body part.
	if not part.has_meta("stain"):
		part.set_meta("stain",true)
		var p=game.world.on_ground(point)+Vector3(0,0.025,0)
		Art.cylinder(self,0.22,0.012,to_local(p),red,-1,12)

func blast(point:Vector3,radius:float,power:float):
	for part in parts:
		var d=part.global_position.distance_to(point)
		if d>radius:continue
		part.receive_hit(power*(1-d/radius),point)
		if part.detached:part.apply_central_impulse((part.global_position-point).normalized()*power*(1-d/radius)*0.10+Vector3(0,1,0))

func _physics_process(_delta):
	if not parts.is_empty() and parts[0].detached:
		soldier.global_position=parts[0].global_position
