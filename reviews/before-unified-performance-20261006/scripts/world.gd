extends Node3D

const Art = preload("res://scripts/art.gd")
var rng = RandomNumberGenerator.new()
var world_camera: Camera3D
var menu_knight: Node3D
var ground_material: Material
var rock_shapes: Dictionary = {}
var village
var navigation
var geometry_revision: int = 0
var terrain_chunks: Array = []
var game

func _ready():
	add_to_group("battle_world")
	rng.seed = 19400614
	lighting()
	landscape()
	village = preload("res://scripts/village.gd").new()
	village.world = self
	add_child(village)
	make_loose_props_breakable(self)
	navigation = preload("res://scripts/field_navigation.gd").new()
	add_child(navigation)
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
	sm.sky_top_color = Color("385f7c")
	sm.sky_horizon_color = Color("b9c1c0")
	sm.ground_bottom_color = Color("8d7656")
	sm.ground_horizon_color = Color("cdb58a")
	sm.sky_curve = 0.22
	sm.sun_angle_max = 3.0
	sm.sun_curve = 0.07
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("94aabb")
	env.ambient_light_energy = 0.23
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.94
	env.fog_enabled = true
	env.fog_light_color = Color("b6b4a8")
	env.fog_light_energy = 0.58
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.08
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.002
	env.volumetric_fog_albedo = Color("c2b69c")
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 95
	env.glow_enabled = true
	env.glow_intensity = 0.18
	env.glow_hdr_threshold = 1.5
	env.ssao_enabled = true
	env.ssao_radius = 0.65
	env.ssao_intensity = 0.9
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.09
	env.adjustment_saturation = 0.83
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -38, 0)
	sun.light_color = Color("ffe1b1")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 115
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.10
	sun.shadow_normal_bias = 1.5
	add_child(sun)

func landscape():
	ground_material = ShaderMaterial.new()
	ground_material.shader = load("res://assets/shaders/sand.gdshader")
	# Individually editable soil chunks. Digging changes the surface and collision.
	for x in range(-84,84,12):
		for z in range(-108,72,12):
			var chunk=Art.solid(self,Vector3(12,24,12),Vector3(x+6,-12,z+6),ground_material,0,"soil")
			terrain_chunks.append(chunk)
	# Far ground is physical too; these large blocks frame the bounded encounter.
	for entry in [[Vector3(-217,-12,0),Vector3(266,24,700)],[Vector3(217,-12,0),Vector3(266,24,700)],
		[Vector3(0,-12,-229),Vector3(168,24,242)],[Vector3(0,-12,211),Vector3(168,24,278)]]:
		terrain_chunks.append(Art.solid(self,entry[1],entry[0],ground_material,0,"soil"))
	rock(Vector3(0,0,48),Vector3(3.8,2.8,3.1),true)
	for p in [Vector3(-5,0,42),Vector3(8,0,38),Vector3(-35,0,27),Vector3(34,0,7),Vector3(-36,0,-35),Vector3(35,0,-61)]:
		rock(p,Vector3(rng.randf_range(2,3.8),rng.randf_range(1.5,2.5),rng.randf_range(2,4)),true)
	for i in range(90):
		var p=Vector3(rng.randf_range(-90,90),0,rng.randf_range(-115,65))
		if absf(p.x-42)<7:continue
		if absf(p.x)<37 and p.z> -76 and p.z<57:continue
		rock(p,Vector3(rng.randf_range(2,7),rng.randf_range(1.1,6),rng.randf_range(2,6)),true)
	for i in range(130):
		var p=Vector3(rng.randf_range(-65,65),0,rng.randf_range(-85,57))
		if absf(p.x)<32 and p.z<22:continue
		rock(p,Vector3(rng.randf_range(0.12,0.5),rng.randf_range(0.07,0.25),rng.randf_range(0.1,0.4)),false)
	for i in range(22):
		var angle=TAU*i/22.0
		rock(Vector3(cos(angle)*175,0,sin(angle)*160-25),Vector3(rng.randf_range(24,55),rng.randf_range(10,35),rng.randf_range(22,45)),true)
	for i in range(45):
		var bush=Node3D.new()
		add_child(bush)
		bush.position=Vector3(rng.randf_range(-65,65),0,rng.randf_range(-75,55))
		if absf(bush.position.x)<30 and bush.position.z<20:
			bush.queue_free()
			continue
		for j in range(4):
			var stem=Art.box(bush,Vector3(0.035,rng.randf_range(0.16,0.4),0.035),Vector3(rng.randf_range(-0.1,0.1),0.14,rng.randf_range(-0.1,0.1)),Art.material(Color("706441")))
			stem.rotation.z=rng.randf_range(-0.6,0.6)
	var dust=CPUParticles3D.new()
	dust.position=Vector3(0,2,-10)
	dust.amount=100
	dust.lifetime=8
	dust.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents=Vector3(50,4,65)
	dust.direction=Vector3(1,0,0.1)
	dust.spread=12
	dust.initial_velocity_min=1.2
	dust.initial_velocity_max=2.7
	dust.gravity=Vector3.ZERO
	dust.scale_amount_min=0.018
	dust.scale_amount_max=0.045
	var grain=SphereMesh.new()
	grain.radius=1
	grain.height=2
	grain.radial_segments=4
	grain.rings=2
	dust.mesh=grain
	dust.material_override=Art.material(Color("d3bd91"))
	add_child(dust)

func rock(pos: Vector3, size: Vector3, collide: bool):
	var root = Art.Breakable.new()
	root.material_kind="rock"
	add_child(root)
	root.position = pos
	root.rotation.y = rng.randf_range(-PI,PI)
	var color = Color("938060").lerp(Color("b6a181"),rng.randf())
	var stone = ShaderMaterial.new()
	stone.shader = preload("res://assets/shaders/stone.gdshader")
	stone.set_shader_parameter("stone_color",color)
	var variant = absi(int(pos.x*7+pos.z*13)) % 8
	var s = Art.mesh(root,rock_mesh(variant),Vector3(0,size.y*0.30,0),stone)
	s.scale = size*0.62
	s.rotation.z = rng.randf_range(-0.2,0.2)
	if true:
		var c = CollisionShape3D.new()
		var sh = BoxShape3D.new()
		sh.size = size*Vector3(0.82,0.75,0.82)
		c.shape = sh
		c.position.y = size.y*0.30
		root.add_child(c)

func rock_mesh(variant: int) -> ArrayMesh:
	if rock_shapes.has(variant): return rock_shapes[variant]
	var source = SphereMesh.new()
	source.radius = 1
	source.height = 2
	source.radial_segments = 28
	source.rings = 16
	var arrays = source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise = FastNoiseLite.new()
	noise.seed = 9400+variant*719
	noise.frequency = 1.7
	noise.fractal_octaves = 3
	for i in range(vertices.size()):
		var p = vertices[i]
		var uneven = noise.get_noise_3dv(p)
		p *= 1.0+uneven*0.33
		p.x += noise.get_noise_3dv(p+Vector3(7,2,1))*0.12
		p.z += noise.get_noise_3dv(p+Vector3(1,5,7))*0.10
		p.y = maxf(-0.72,p.y+sin(p.y*10+uneven*3)*0.025)
		vertices[i]=p
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var raw = ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var surface = SurfaceTool.new()
	surface.create_from(raw,0)
	surface.generate_normals()
	var result=surface.commit()
	rock_shapes[variant]=result
	return result

func sandbags(pos: Vector3, length: int, angle: float = 0.0):
	var root=Art.Breakable.new()
	root.material_kind="sandbag"
	add_child(root)
	root.position=pos
	root.rotation.y=angle
	var collision=CollisionShape3D.new()
	var shape=BoxShape3D.new()
	shape.size=Vector3(length*0.72,1.10,0.62)
	collision.shape=shape
	collision.position.y=0.55
	root.add_child(collision)
	var bags=[Art.material(Color("a18b66")),Art.material(Color("b39b72")),Art.material(Color("998460"))]
	for row in range(3):
		for i in range(length):
			var bag=Art.sphere(root,0.5,Vector3((i-(length-1)*0.5)*0.72+(0.13 if row%2 else -0.06),0.2+row*0.35,0),bags[rng.randi_range(0,2)])
			bag.scale=Vector3(0.86,0.43,0.74)
			bag.rotation.y=rng.randf_range(-0.1,0.1)
	return root

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

func geometry_updated(point: Vector3):
	geometry_revision+=1
	if is_instance_valid(navigation):navigation.mark_dirty(point)

func blast(point: Vector3, power: float = 300, radius: float = 4.2):
	for body in get_tree().get_nodes_in_group("breakable"):
		if body.destroyed:continue
		var distance=body.distance_to_surface(point)
		if distance>radius:continue
		var amount=power*clampf(1-distance/radius,0.2,1)
		if body.material_kind=="soil":
			body.carve(point-Vector3(0,0.20,0),minf(1.8,radius-distance))
		else:
			body.damage_at(amount,point,minf(2.05,radius-distance+0.25),true)

func dig(point: Vector3, depth: float = 0.82):
	var centre=point-Vector3(0,depth*0.34,0)
	for chunk in terrain_chunks:
		if is_instance_valid(chunk) and not chunk.destroyed and chunk.distance_to_surface(centre)<depth:
			chunk.carve(centre,depth)

func nearby_door(point: Vector3, distance: float = 2.6):
	var best=null
	for door in get_tree().get_nodes_in_group("field_door"):
		if not door.available():continue
		var d=point.distance_to(door.interaction_position())
		if d<distance:
			distance=d
			best=door
	return best

func make_loose_props_breakable(node: Node):
	# Convert decorative geometry into independently hittable physical props, while
	# keeping doors and existing breakable bodies as their own objects.
	for child in node.get_children():
		if child is CollisionObject3D or child is CSGShape3D or child is CPUParticles3D:continue
		if child is MeshInstance3D:
			var wrapper=Art.Breakable.new()
			wrapper.material_kind="wood"
			node.add_child(wrapper)
			wrapper.transform=child.transform
			child.reparent(wrapper,false)
			child.transform=Transform3D.IDENTITY
			var collision=CollisionShape3D.new()
			var shape=BoxShape3D.new()
			var box=child.mesh.get_aabb()
			shape.size=box.size.max(Vector3.ONE*0.025)
			collision.shape=shape
			collision.position=box.get_center()
			wrapper.add_child(collision)
			if box.size.length()<0.65:wrapper.collision_layer=16
		elif child is Node3D:
			make_loose_props_breakable(child)
