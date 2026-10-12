extends Node3D

const Art=preload("res://scripts/art.gd")
const Door=preload("res://scripts/field_door.gd")
var world
var covers: Array[Vector3]=[]
var enemy_positions=[Vector3(0,0.04,26),Vector3(-26,0.04,-14),Vector3(27,0.04,-16),Vector3(-22,0.04,-44),Vector3(22,0.04,-49),Vector3(-4,0.04,-52)]
var enemy_roles=["sentry","hold","assault","assault","hold","mg"]

func plaster_material(color: Color) -> Material:
	var mat=ShaderMaterial.new()
	mat.shader=load("res://assets/shaders/plaster.gdshader")
	mat.set_shader_parameter("plaster_color",color)
	return mat

func wall(parent: Node3D, size: Vector3, pos: Vector3, mat: Material):
	return Art.solid(parent,size,pos,mat,0,"masonry")

func _ready():
	var plaster=plaster_material(Color("a89372"))
	var pale=plaster_material(Color("b7a789"))
	var worn=plaster_material(Color("93836c"))
	# Fictional frontier settlement, using Cyrenaican stone/plaster construction.
	# Six defenders occupy separate positions rather than one line of sandbags.
	house(Vector3(-18,0,12),Vector2(8,8),plaster,true)
	house(Vector3(18,0,8),Vector2(8,10),pale,false)
	house(Vector3(-22,0,-10),Vector2(10,10),worn,false)
	house(Vector3(22,0,-9),Vector2(10,10),plaster,true)
	house(Vector3(-20,0,-40),Vector2(10,10),pale,true)
	house(Vector3(20,0,-41),Vector2(10,10),worn,false)
	house(Vector3(0,0,-61),Vector2(10,8),plaster,true)
	# A larger isolated checkpoint at the village's near edge.
	world.sandbags(Vector3(-5,0,29),5,0.08)
	world.sandbags(Vector3(5,0,29),5,-0.08)
	world.sandbags(Vector3(-8,0,24),5,PI/2)
	world.crate(Vector3(4,0,23))
	wall(self,Vector3(3,1.1,0.35),Vector3(6,0.55,19),worn)
	for p in [Vector3(-5,0,27.7),Vector3(5,0,27.7),Vector3(-6.7,0,24)]:covers.append(p)
	# Walled courtyards, staggered lanes and firing points with alternate exits.
	for entry in [[Vector3(-29,0,-15),5,0.0],[Vector3(28,0,-20),4,PI/2],
		[Vector3(-12,0,-33),5,0.0],[Vector3(12,0,-34),4,0.0],
		[Vector3(0,0,-51),5,0.0],[Vector3(28,0,-50),5,PI/2]]:
		world.sandbags(entry[0],entry[1],entry[2])
		covers.append(entry[0]+Vector3(0,0,-1.1))
		covers.append(entry[0]+Vector3(0,0,1.1))
	for pair in [[Vector3(-29,0,-27),Vector3(9,1.25,0.35)],
		[Vector3(29,0,-30),Vector3(8,1.10,0.35)],
		[Vector3(-7,0,-18),Vector3(0.35,1.2,7)],
		[Vector3(8,0,-39),Vector3(0.35,1.1,7)]]:
		wall(self,pair[1],pair[0]+Vector3(0,pair[1].y/2,0),plaster)
		covers.append(pair[0]+Vector3(1,0,1))
		covers.append(pair[0]+Vector3(-1,0,-1))
	# An empty central square: well, damaged store frontage, field telephone.
	for side in [-1.0,1.0]:
		wall(self,Vector3(2.8,0.75,0.30),Vector3(-1,0.375,-30+side*1.25),worn)
		wall(self,Vector3(0.30,0.75,2.8),Vector3(-1+side*1.25,0.375,-30),worn)
	covers.append(Vector3(-1,0,-28))
	covers.append(Vector3(-1,0,-32))
	var wood=Art.material(Color("69593e"))
	for p in [Vector3(-7,0,-28),Vector3(9,0,-23),Vector3(-30,0,4),Vector3(31,0,-42)]:
		world.crate(p)
		world.crate(p+Vector3(1.2,0,-0.4),Vector3(0.75,0.55,0.8))
		covers.append(p+Vector3(0,0,-1.0))
	Art.solid(self,Vector3(2,0.16,1.1),Vector3(3,0.95,-39),wood)
	for x in [2.2,3.8]:
		Art.solid(self,Vector3(0.12,0.9,0.9),Vector3(x,0.45,-39),wood)
	Art.solid(self,Vector3(0.35,0.22,0.25),Vector3(3.5,1.14,-39),Art.material(Color("313936"),0.65),0,"metal")
	flag(Vector3(0,0,-35))
	world.sandbags(Vector3(3,0,-47),7,0)
	world.sandbags(Vector3(-0.8,0,-50),5,PI/2)
	world.sandbags(Vector3(6.8,0,-50),5,PI/2)
	covers.append(Vector3(3,0,-49))
	# No civilians are spawned. Broken masonry and abandoned furniture tell the story.
	var rng=RandomNumberGenerator.new()
	rng.seed=19400614
	for i in range(36):
		var p=Vector3(rng.randf_range(-31,31),0,rng.randf_range(-58,14))
		if absf(p.x)<5:continue
		var rubble=wall(self,Vector3(rng.randf_range(0.3,0.8),rng.randf_range(0.16,0.4),rng.randf_range(0.2,0.55)),p+Vector3(0,0.13,0),worn)
		rubble.rotation.y=rng.randf_range(-PI,PI)

func house(pos: Vector3, size: Vector2, plaster: Material, damaged: bool):
	var root=Node3D.new()
	add_child(root)
	root.position=pos
	var w=size.x
	var d=size.y
	var height=3.2
	var wood=Art.material(Color("6e6046"))
	# An actual doorway, with an independently hinged, destructible timber door.
	for side in [-1.0,1.0]:
		var panel=wall(root,Vector3((w-1.8)*0.5,height,0.35),Vector3(side*(w+1.8)*0.25,height/2,d/2),plaster)
		if damaged and side>0:
			panel.carve(root.to_global(Vector3(w/2-0.25,2.9,d/2)),0.92)
	wall(root,Vector3(1.8,height-2.25,0.35),Vector3(0,(height+2.25)/2,d/2),plaster)
	var door=Door.new()
	root.add_child(door)
	door.position=Vector3(-0.86,0,d/2+0.02)
	# Rear window: low sill and a broad open firing aperture.
	wall(root,Vector3(w,0.9,0.35),Vector3(0,0.45,-d/2),plaster)
	wall(root,Vector3(w,1.0,0.35),Vector3(0,2.7,-d/2),plaster)
	for side in [-1.0,1.0]:
		wall(root,Vector3((w-1.6)*0.5,1.3,0.35),Vector3(side*(w+1.6)*0.25,1.55,-d/2),plaster)
	# Side windows can be used for shooting or mantled into from the lane.
	for x in [-w/2,w/2]:
		wall(root,Vector3(0.35,0.9,d),Vector3(x,0.45,0),plaster)
		wall(root,Vector3(0.35,0.85,d),Vector3(x,2.775,0),plaster)
		for side in [-1.0,1.0]:
			wall(root,Vector3(0.35,1.45,(d-1.8)*0.5),Vector3(x,1.625,side*(d+1.8)*0.25),plaster)
	# A flat, breakable roof. One quarter is already shell-damaged on ruined houses.
	for x in [-w/4,w/4]:
		for z in [-d/4,d/4]:
			if damaged and x>0 and z>0:continue
			Art.solid(root,Vector3(w/2,0.22,d/2),Vector3(x,3.22,z),plaster,0,"masonry")
	for z in [-d/2,d/2]:
		wall(root,Vector3(w,0.45,0.28),Vector3(0,3.5,z),plaster)
	wall(root,Vector3(0.28,0.45,d),Vector3(-w/2,3.5,0),plaster)
	# Timber ramp and crates give multiple parkour routes to the roofs.
	var ramp=Art.solid(root,Vector3(1.65,0.17,8.6),Vector3(w/2+1.0,1.63,0.1),wood)
	ramp.rotation.x=0.382
	Art.solid(root,Vector3(2.5,0.18,1.6),Vector3(w/2,3.22,-3.6),wood)
	Art.solid(root,Vector3(1.2,0.78,1.1),Vector3(-w/2-1,0.39,1.7),wood)
	wall(root,Vector3(1.1,1.50,1.1),Vector3(-w/2-0.8,0.75,-0.1),plaster)
	for z in [-d/2-1.0,d/2+1.2]:
		for x in [-w/2-1.0,w/2+1.0]:covers.append(pos+Vector3(x,0,z))
	covers.append(pos+Vector3(0,0,-d/2+0.9))
	covers.append(pos+Vector3(-w/2+0.9,0,0))
	covers.append(pos+Vector3(w/2-0.9,0,0))
	covers.append(pos+Vector3(0,0,d/2-0.9))
	# Abandoned bench and storage jars, all ordinary destructible props.
	Art.solid(root,Vector3(2.4,0.16,0.55),Vector3(-2,0.55,-d/2+1.1),wood)
	for x in [-3,-1]:Art.solid(root,Vector3(0.15,0.5,0.5),Vector3(x,0.25,-d/2+1.1),wood)

func flag(pos: Vector3):
	var pole=Art.solid(self,Vector3(0.10,6.5,0.10),pos+Vector3(0,3.25,0),Art.material(Color("706c59"),0.6),0,"metal")
	for i in range(3):
		var mat=ShaderMaterial.new()
		mat.shader=load("res://assets/shaders/flag.gdshader")
		mat.set_shader_parameter("color",[Color("49634b"),Color("ddd4b7"),Color("964b3f")][i])
		Art.solid(self,Vector3(0.8,1.5,0.025),pos+Vector3(0.4+i*0.8,5.4,0),mat,0,"cloth")
	Art.solid(self,Vector3(0.34,0.48,0.028),pos+Vector3(1.2,5.4,0.035),Art.material(Color("963f33")),0,"cloth")
	Art.solid(self,Vector3(0.08,0.48,0.035),pos+Vector3(1.2,5.4,0.065),Art.material(Color("e1d9c2")),0,"cloth")
	Art.solid(self,Vector3(0.34,0.08,0.035),pos+Vector3(1.2,5.4,0.065),Art.material(Color("e1d9c2")),0,"cloth")
