extends Node3D

const Art = preload("res://scripts/art.gd")
var rng = RandomNumberGenerator.new()
var world_camera: Camera3D
var menu_knight: Node3D
var ground_material: Material

func _ready():
	rng.seed = 19400614
	lighting()
	landscape()
	fortifications()
	menu_knight = Art.knight(self)
	menu_knight.position = Vector3(7, 0, 22)
	menu_knight.rotation.y = -2.48
	world_camera = Camera3D.new()
	add_child(world_camera)
	world_camera.position = Vector3(10, 1.9, 25.6)
	world_camera.look_at(Vector3(3, 1.35, 23))
	world_camera.fov = 66
	world_camera.far = 550
	world_camera.current = true
	var fill = OmniLight3D.new()
	fill.position = Vector3(9.5,3.0,24.5)
	fill.light_color = Color("b5c8d0")
	fill.light_energy = 1.8
	fill.omni_range = 7
	add_child(fill)

func lighting():
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sm = ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("4d7593")
	sm.sky_horizon_color = Color("c4c8bf")
	sm.ground_bottom_color = Color("8d7656")
	sm.ground_horizon_color = Color("cdb58a")
	sm.sky_curve = 0.22
	sm.sun_angle_max = 3.0
	sm.sun_curve = 0.07
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b5c1bf")
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("c8b58e")
	env.fog_light_energy = 0.7
	env.fog_density = 0.0021
	env.fog_sky_affect = 0.08
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 0.86
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -38, 0)
	sun.light_color = Color("ffdda2")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 115
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.035
	add_child(sun)

func landscape():
	ground_material = ShaderMaterial.new()
	ground_material.shader = load("res://assets/shaders/sand.gdshader")
	Art.solid(self, Vector3(700, 1, 700), Vector3(0, -0.5, 0), ground_material)
	rock(Vector3(0,0,28.5),Vector3(3.8,2.8,3.1),true)
	# The patrol always stops on this visible dirt road, wherever the final kill occurs.
	Art.solid(self,Vector3(5.8,0.04,170),Vector3(42,0.012,-20),Art.material(Color("86775a")))
	for x in [40.9,43.1]:
		Art.box(self,Vector3(0.27,0.008,170),Vector3(x,0.037,-20),Art.material(Color("77694f")))
	# Rocky corridors leave several approaches to the line and real ballistic cover.
	for p in [Vector3(-5,0,25), Vector3(5,0,19), Vector3(-5,0,10), Vector3(7,0,4), Vector3(-9,0,-7), Vector3(5,0,-15), Vector3(-5,0,-23), Vector3(12,0,-24), Vector3(-17,0,-29)]:
		rock(p, Vector3(rng.randf_range(2,3.8), rng.randf_range(1.5,2.5), rng.randf_range(2,4)), true)
	for i in range(95):
		var p = Vector3(rng.randf_range(-90,90), 0, rng.randf_range(-115,65))
		if absf(p.x-42)<7: continue
		if absf(p.x) < 22 and p.z > -60 and p.z < 40:
			continue
		rock(p, Vector3(rng.randf_range(2,7),rng.randf_range(1.1,6),rng.randf_range(2,6)), p.length() < 75)
	for i in range(190):
		var p = Vector3(rng.randf_range(-65,65),0,rng.randf_range(-85,48))
		rock(p, Vector3(rng.randf_range(0.12,0.5),rng.randf_range(0.07,0.25),rng.randf_range(0.1,0.4)), false)
	# Distant escarpments frame the playable pocket without invisible close walls.
	for i in range(22):
		var a = TAU * i / 22.0
		rock(Vector3(cos(a)*175,0,sin(a)*160-25), Vector3(rng.randf_range(24,55),rng.randf_range(10,35),rng.randf_range(22,45)), false)
	for i in range(70):
		var x = rng.randf_range(-45,45)
		var z = rng.randf_range(-62,45)
		var bush = Node3D.new()
		add_child(bush)
		bush.position = Vector3(x,0,z)
		for j in range(4):
			var stem = Art.box(bush,Vector3(0.035, rng.randf_range(0.16,0.4),0.035),Vector3(rng.randf_range(-0.1,0.1),0.14,rng.randf_range(-0.1,0.1)),Art.material(Color("706441")))
			stem.rotation.z = rng.randf_range(-0.6,0.6)
	# Sand drift: a low-density field, never obscuring the targets.
	var dust = CPUParticles3D.new()
	dust.position = Vector3(0,2,-10)
	dust.amount = 85
	dust.lifetime = 8
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(50,4,60)
	dust.direction = Vector3(1,0,0.1)
	dust.spread = 12
	dust.initial_velocity_min = 1.2
	dust.initial_velocity_max = 2.7
	dust.gravity = Vector3.ZERO
	dust.scale_amount_min = 0.018
	dust.scale_amount_max = 0.045
	var grain = SphereMesh.new()
	grain.radius = 1
	grain.height = 2
	grain.radial_segments = 4
	grain.rings = 2
	dust.mesh = grain
	dust.material_override = Art.material(Color("d3bd91"))
	add_child(dust)

func rock(pos: Vector3, size: Vector3, collide: bool):
	var root = StaticBody3D.new() if collide else Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation.y = rng.randf_range(-PI,PI)
	var color = Color("938060").lerp(Color("b6a181"),rng.randf())
	var s = Art.sphere(root,1,Vector3(0,size.y*0.30,0),Art.material(color))
	s.scale = size*0.62
	s.rotation.z = rng.randf_range(-0.2,0.2)
	if collide:
		var c = CollisionShape3D.new()
		var sh = BoxShape3D.new()
		sh.size = size*Vector3(0.82,0.75,0.82)
		c.shape = sh
		c.position.y = size.y*0.30
		root.add_child(c)

func sandbags(pos: Vector3, length: int, angle: float = 0.0):
	var root = Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation.y = angle
	var bags = [Art.material(Color("b29c71")),Art.material(Color("bda67c")),Art.material(Color("9c8b63"))]
	var wall_collider=Art.solid(root,Vector3(length*0.72,1.10,0.62),Vector3(0,0.55,0),Art.material(Color("9e8b67")))
	wall_collider.get_child(0).visible=false
	for row in range(3):
		for i in range(length):
			var bag = Art.sphere(root,0.5,Vector3((i-(length-1)*0.5)*0.72+(0.13 if row%2 else -0.06),0.2+row*0.35,0),bags[rng.randi_range(0,2)])
			bag.scale = Vector3(0.86,0.43,0.74)
			bag.rotation.y = rng.randf_range(-0.1,0.1)

func crate(pos: Vector3, size: Vector3 = Vector3(1.1,0.9,0.9)):
	var wood = Art.material(Color("736c4c"))
	var dark = Art.material(Color("4e4b36"))
	var root = Art.solid(self,size,pos+Vector3(0,size.y/2,0),wood)
	for x in [-0.35,0.35]:
		Art.box(root,Vector3(0.07,size.y+0.01,size.z+0.016),Vector3(x,0,0),dark)
	for y in [-0.25,0.25]:
		Art.box(root,Vector3(size.x+0.015,0.065,size.z+0.018),Vector3(0,y,0),dark)

func tent(pos: Vector3):
	var root = Node3D.new()
	add_child(root)
	root.position = pos
	var canvas = Art.material(Color("767558"))
	canvas = canvas.duplicate()
	canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	Art.solid(root,Vector3(5,1.6,0.12),Vector3(0,0.8,-3),canvas)
	for x in [-2.5,2.5]:
		Art.solid(root,Vector3(0.12,1.6,6),Vector3(x,0.8,0),canvas)
		var roof = Art.box(root,Vector3(2.85,0.055,6.1),Vector3(x*0.5,2.3,0),canvas)
		roof.rotation.z = -signf(x)*0.49
		for z in [-3.0,3.0]:
			Art.segment(root,Vector3(x,1.6,z),Vector3(x*1.6,0,z*1.22),0.014,Art.material(Color("514937")))
	for z in [-3.0,3.0]:
		Art.cylinder(root,0.045,3,Vector3(0,1.5,z),Art.material(Color("514737")))

func fortifications():
	# Forward sentry, then the six-man outpost. Open ends permit a sword-only route.
	sandbags(Vector3(0,0,7),3)
	sandbags(Vector3(-12,0,-31),7,0.12)
	sandbags(Vector3(-3,0,-32),6)
	sandbags(Vector3(8,0,-32),7,-0.12)
	sandbags(Vector3(17,0,-39),5,PI/2)
	sandbags(Vector3(-19,0,-40),5,PI/2)
	sandbags(Vector3(1,0,-45),4)
	for pos in [Vector3(12,0,-41),Vector3(13.2,0,-42),Vector3(-13,0,-44),Vector3(-12,0,-44),Vector3(1,0,20)]:
		crate(pos)
	tent(Vector3(-9,0,-49))
	tent(Vector3(9,0,-51))
	# Ruined outbuilding, rather than a fully fortified historical reconstruction.
	var stucco = Art.material(Color("bca47b"))
	Art.solid(self,Vector3(9,3.4,0.5),Vector3(0,1.7,-59),stucco)
	Art.solid(self,Vector3(0.5,2.3,5),Vector3(-4.3,1.15,-56.6),stucco)
	Art.solid(self,Vector3(0.5,2.8,5),Vector3(4.3,1.4,-56.6),stucco)
	for x in [-3.5,-1.9,0.8,2.5]:
		Art.box(self,Vector3(1.1,rng.randf_range(0.25,0.7),0.53),Vector3(x,3.5,-59),stucco)
	# Italian Kingdom tricolour with a simplified Savoy shield; no modern flag swap.
	Art.cylinder(self,0.055,7,Vector3(1,3.5,-50),Art.material(Color("716959"),0.45))
	for i in range(3):
		var mat = ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/flag.gdshader")
		mat.set_shader_parameter("color",[Color("49634b"),Color("ddd4b7"),Color("964b3f")][i])
		var p = PlaneMesh.new()
		p.size = Vector2(0.8,1.5)
		p.subdivide_width = 8
		p.orientation = PlaneMesh.FACE_Z
		Art.mesh(self,p,Vector3(1.4+i*0.8,5.7,-50),mat)
	Art.box(self,Vector3(0.39,0.57,0.022),Vector3(2.2,5.7,-49.96),Art.material(Color("384e64")))
	Art.box(self,Vector3(0.32,0.48,0.025),Vector3(2.2,5.7,-49.94),Art.material(Color("923d36")))
	Art.box(self,Vector3(0.09,0.48,0.028),Vector3(2.2,5.7,-49.92),Art.material(Color("e1d9c2")))
	Art.box(self,Vector3(0.32,0.09,0.030),Vector3(2.2,5.73,-49.9),Art.material(Color("e1d9c2")))
	# Field telephone and map table.
	Art.solid(self,Vector3(1.8,0.15,1.1),Vector3(0,0.95,-48),Art.material(Color("65543e")))
	for x in [-0.72,0.72]:
		for z in [-48.4,-47.6]:
			Art.box(self,Vector3(0.07,0.9,0.07),Vector3(x,0.45,z),Art.material(Color("4c4535")))
	Art.box(self,Vector3(0.65,0.01,0.6),Vector3(-0.30,1.031,-48),Art.material(Color("c9bd92")))
	Art.box(self,Vector3(0.32,0.20,0.23),Vector3(0.50,1.14,-48),Art.material(Color("333b33")))
	# Broken stone threshold, the only remnant of the displacement at spawn.
	for x in [-2.0,2.0]:
		rock(Vector3(x,0,39),Vector3(1.2,2.6,1.3),true)
	Art.solid(self,Vector3(3.5,0.16,2),Vector3(0,0.08,38.7),Art.material(Color("686c65")))
