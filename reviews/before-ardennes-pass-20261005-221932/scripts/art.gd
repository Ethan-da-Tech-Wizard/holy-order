# ==============================================================================
# Program: art.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for art.gd.
# ==============================================================================
## Procedural art library: builds every 3D model in the desert mission from primitives.
##
## There are no imported 3D model files; characters, weapons, trucks and props are
## assembled in code from boxes, cylinders, spheres and a few lofted meshes. All
## functions are static and take the parent node first, add their pieces under it and
## return the root so callers can position, animate or tint it. Materials and bevelled
## meshes are cached in static dictionaries, so building hundreds of soldiers shares
## GPU resources. Coordinates are metres; models face -z (forward) with y up.
## Other scripts call it as `Art.box(...)`, `Art.solid(...)`, `Art.soldier(...)` etc.
extends RefCounted

# Rifle model builder (the player rifle).
const Carcano = preload("res://scripts/carcano_model.gd")

# Destructible body class used by solid().
const Breakable = preload("res://scripts/breakable.gd")

# Material cache, keyed by the colour/metal/rough string.
static var materials: Dictionary = {}

# Bevelled box mesh cache, keyed by size and bevel, so identical boxes share one mesh.
static var bevel_meshes: Dictionary = {}

## Get a cached standard material.
## @param color Albedo.
## @param metal Metallic 0..1.
## @param rough Roughness 0..1 (high = matte).
## @return A shared StandardMaterial3D; do not modify it, `.duplicate()` first.
static func material(color: Color, metal: float = 0.0, rough: float = 0.85) -> StandardMaterial3D:
	var key = str(color) + str(metal) + str(rough)
	# The key is a string of the three parameters; same inputs always return the same instance.
	if materials.has(key):
		return materials[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	materials[key] = m
	return m

## Add a MeshInstance3D under `parent`.
## @param shape Mesh resource. @param pos Local position. @param mat Material override.
static func mesh(parent: Node3D, shape: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var obj = MeshInstance3D.new()
	obj.mesh = shape
	obj.material_override = mat
	obj.position = pos
	parent.add_child(obj)
	return obj

## Add an axis-aligned box mesh (visual only, no collision).
## @param size Full extents in metres, centred on `pos`.
static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b = BoxMesh.new()
	b.size = size
	return mesh(parent, b, pos, mat)

## Add a box with rounded edges, built from a subdivided box whose vertices are pushed to a rounded shape.
## @param bevel Rounding radius in metres.
static func beveled_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, bevel: float = 0.003) -> MeshInstance3D:
	# The mesh is built once per (size, bevel) pair and reused.
	var key = str(size)+str(bevel)
	if not bevel_meshes.has(key):
		var source = BoxMesh.new()
		source.size = size
		# 3 subdivisions per axis give enough vertices near the edges to round them.
		source.subdivide_width = 3
		source.subdivide_height = 3
		source.subdivide_depth = 3
		var arrays = source.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		# Inner box is the original minus the bevel; each vertex is moved to bevel metres from its nearest inner point, giving a rounded corner and smooth normals.
		var inner = size*0.5-Vector3.ONE*bevel
		for i in range(vertices.size()):
			var closest = vertices[i].clamp(-inner,inner)
			var normal = (vertices[i]-closest).normalized()
			vertices[i] = closest+normal*bevel
			normals[i] = normal
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		# Tangents are dropped because the mesh is rebuilt and the material needs none.
		arrays[Mesh.ARRAY_TANGENT] = null
		var result = ArrayMesh.new()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		bevel_meshes[key] = result
	return mesh(parent,bevel_meshes[key],pos,mat)

## Add a cylinder (standing on y) or a cone/frustum when `top` is smaller than `radius`.
## @param top Top radius; -1 means the same as `radius`.
## @param sides Number of radial segments.
static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, top: float = -1.0, sides: int = 20) -> MeshInstance3D:
	var c = CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0 else top
	c.height = height
	c.radial_segments = sides
	return mesh(parent, c, pos, mat)

## Add a sphere of the given radius.
static func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var s = SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	# 24 x 12 segments: smooth enough for heads and domes without too many triangles.
	s.radial_segments = 24
	s.rings = 12
	return mesh(parent, s, pos, mat)

## Add a destructible box: mesh plus collision shape inside a Breakable body.
## @param angle Rotation about y in radians.
## @param kind Material kind for resistance (wood, masonry, metal, cloth, sandbag, rock, soil).
## @return The Breakable body.
static func solid(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, angle: float = 0.0, kind: String = "wood") -> StaticBody3D:
	var body = Breakable.new()
	body.material_kind=kind
	body.position = pos
	body.rotation.y = angle
	# Layer 1 is the world; mask 0 because solids only receive hits.
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	box(body, size, Vector3.ZERO, mat)
	var cs = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	return body

## Add a thin rod between two points (used for limbs, rails and wires).
static func segment(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var c = cylinder(parent, radius, a.distance_to(b), (a + b) * 0.5, mat)
	var axis = (b - a).normalized()
	# Skip the rotation for vertical segments: the quaternion from UP to UP is degenerate.
	if absf(axis.dot(Vector3.UP)) < 0.999:
		c.quaternion = Quaternion(Vector3.UP, axis)
	return c

## Build the player's rifle (delegates to carcano_model.gd).
static func rifle(parent: Node3D) -> Node3D:
	return Carcano.build(parent)

## Build a long sword along +y with blade, fuller, cross guard, grip and pommel.
static func sword(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var steel = material(Color("b7c1c0"), 0.8, 0.24)
	var dark = material(Color("343c3d"), 0.8, 0.36)
	var leather = material(Color("45362a"))
	box(root, Vector3(0.065, 0.9, 0.019), Vector3(0, 0.61, 0), steel)
	box(root, Vector3(0.018, 0.86, 0.024), Vector3(0, 0.62, 0), dark)
	var tip = cylinder(root, 0.043, 0.16, Vector3(0, 1.14, 0), steel, 0, 4)
	tip.scale.z = 0.27
	box(root, Vector3(0.33, 0.045, 0.048), Vector3(0, 0.14, 0), dark)
	cylinder(root, 0.03, 0.23, Vector3(0, 0.005, 0), leather)
	sphere(root, 0.05, Vector3(0, -0.13, 0), dark)
	return root

## Build the shovel: wooden shaft, steel socket, blade plate and gauntlet hand.
static func shovel(parent: Node3D) -> Node3D:
	var root=Node3D.new()
	parent.add_child(root)
	var wood=material(Color("766044"),0,0.68)
	var steel=material(Color("4e5753"),0.65,0.52)
	cylinder(root,0.021,0.65,Vector3(0,0.28,0),wood,-1,20)
	cylinder(root,0.024,0.14,Vector3(0,0.63,0),steel,-1,20)
	Carcano.plate(root,PackedVector2Array([Vector2(-0.12,0.69),Vector2(0.12,0.69),Vector2(0.13,0.88),Vector2(0.075,0.99),Vector2(0,1.025),Vector2(-0.075,0.99),Vector2(-0.13,0.88)]),0.014,Vector3.ZERO,steel)
	gauntlet(root,Vector3(0,-0.02,0),Vector3.ZERO)
	return root

## Build the knight's kite shield with a red cross.
static func shield(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	# Pentagon outline for the shield.
	var outline = PackedVector2Array([Vector2(-0.32, 0.4), Vector2(0.32, 0.4), Vector2(0.34, -0.12), Vector2(0, -0.57), Vector2(-0.34, -0.12)])
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Fan triangulation from the first vertex, only the front face; the material is double sided.
	for i in range(1, 4):
		for v in [outline[0], outline[i + 1], outline[i]]:
			st.add_vertex(Vector3(v.x, v.y, -0.02))
	st.generate_normals()
	var mat = material(Color("d0c6a7"), 0.08, 0.8).duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh(root, st.commit(), Vector3.ZERO, mat)
	var edge = material(Color("5a6362"), 0.72, 0.38)
	for i in range(5):
		var a = outline[i]
		var b = outline[(i + 1) % 5]
		segment(root, Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0), 0.018, edge)
	var red = material(Color("85382d"))
	box(root, Vector3(0.074, 0.64, 0.012), Vector3(0, -0.0, 0.002), red)
	box(root, Vector3(0.40, 0.075, 0.012), Vector3(0, 0.09, 0.004), red)
	return root

## Build an armoured gauntlet (cuff, hand plate, knuckle plates, finger segments).
## @param pos Local position. @param angle Rotation in radians (x, y, z).
static func gauntlet(parent: Node3D, pos: Vector3, angle: Vector3) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation = angle
	var dark = material(Color("343f40"), 0.45, 0.58)
	var steel = material(Color("97a39f"), 0.78, 0.31)
	cylinder(root, 0.068, 0.29, Vector3(0, -0.16, 0), steel, 0.045, 24)
	cylinder(root, 0.077, 0.12, Vector3(0, -0.04, 0), steel, 0.055, 24)
	beveled_box(root, Vector3(0.112, 0.10, 0.072), Vector3(0, 0.045, -0.018), dark,0.008)
	for j in range(3):
		beveled_box(root, Vector3(0.12-j*0.007, 0.036, 0.02), Vector3(0, 0.004+j*0.033, -0.060), steel)
	for i in range(4):
		for j in range(2):
			beveled_box(root, Vector3(0.025, 0.025, 0.031), Vector3(-0.041+i*0.027, 0.083+j*0.02, -0.035+j*0.01), steel)
	return root

## Build the knight player model (tabard, mail, helm, pauldrons, two gauntlets and a carried sword).
static func knight(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var mail = material(Color("414a4a"), 0.55, 0.54)
	var linen = material(Color("cec5a6"))
	var red = material(Color("82362e"))
	var steel = material(Color("7b8784"), 0.76, 0.40)
	var leather = material(Color("423529"))
	# Torso as a tapered steel cylinder; tabard front and back with a red cross on the front.
	cylinder(root, 0.28, 0.63, Vector3(0, 1.16, 0), steel, 0.25, 12)
	box(root, Vector3(0.38, 0.82, 0.025), Vector3(0, 1.00, -0.28), linen)
	box(root, Vector3(0.065, 0.36, 0.012), Vector3(0, 1.23, -0.30), red)
	box(root, Vector3(0.25, 0.065, 0.012), Vector3(0, 1.29, -0.309), red)
	box(root,Vector3(0.45,0.98,0.028),Vector3(0,0.94,0.265),linen)
	box(root, Vector3(0.48, 0.055, 0.34), Vector3(0, 0.98, 0), leather)
	# Legs: steel cylinder thighs plus boxed feet.
	for x in [-0.13, 0.13]:
		cylinder(root, 0.10, 0.68, Vector3(x, 0.49, 0), steel)
		box(root, Vector3(0.19, 0.16, 0.34), Vector3(x, 0.09, -0.07), steel)
	# Head: mail coif, helmet dome, face plate and eye slit.
	cylinder(root, 0.19, 0.26, Vector3(0, 1.56, 0), mail, 0.17)
	var dome = sphere(root,0.205,Vector3(0,1.80,0),steel)
	dome.scale = Vector3(1,1.05,1.1)
	cylinder(root,0.185,0.19,Vector3(0,1.67,-0.04),steel,0.20,10)
	box(root,Vector3(0.25,0.10,0.1),Vector3(0,1.76,-0.19),steel)
	box(root, Vector3(0.26, 0.023, 0.023), Vector3(0, 1.81, -0.2), material(Color("161d1e")))
	box(root, Vector3(0.025, 0.30, 0.026), Vector3(0, 1.73, -0.215), steel)
	for x in [-0.11, -0.065, 0.065, 0.11]:
		for y in [1.65, 1.70]:
			sphere(root, 0.011, Vector3(x, y, -0.199), material(Color("192323")))
	# Arms are posted segments from shoulder to hand.
	segment(root, Vector3(-0.31, 1.38, 0), Vector3(-0.39, 0.96, -0.23), 0.11, steel)
	segment(root, Vector3(0.31, 1.38, 0), Vector3(0.47, 0.9, -0.05), 0.11, steel)
	# Shoulder plates (pauldrons) with lames below.
	for x in [-0.31,0.31]:
		var pauldron = sphere(root,0.19,Vector3(x,1.37,0),steel)
		pauldron.scale = Vector3(1,0.65,1.1)
		for y in [0.66,0.79,0.91]:
			box(root,Vector3(0.22,0.15,0.07),Vector3(x*0.44,y,-0.14),steel)
	# Hands and the sword, which is named "CarriedSword" so other scripts can find it.
	gauntlet(root,Vector3(-0.39,0.94,-0.23),Vector3(0,0,0))
	gauntlet(root,Vector3(0.47,0.92,-0.05),Vector3(0,0,0))
	var blade = sword(root)
	blade.name = "CarriedSword"
	blade.position = Vector3(0.47, 0.92, -0.1)
	blade.rotation.z = 2.9
	return root

## Build a soldier model.
## @param british true for the British uniform and helmet and SMLE rifle, false for the Italian one.
## @return Dictionary with root, body (upper body node, used for aiming/leaning), legs (two leg nodes for walk animation) and gun.
static func soldier(parent: Node3D, british: bool = false) -> Dictionary:
	var root = Node3D.new()
	parent.add_child(root)
	var cloth = material(Color("9b8e65") if british else Color("8a815b"))
	var webbing = material(Color("57583f"))
	var boots = material(Color("39372e"))
	var skin = material(Color("b99a76"))
	var helmet = material(Color("656c50"), 0.4, 0.68)
	var body = Node3D.new()
	root.add_child(body)
	# Torso, belt, webbing, pack and head.
	beveled_box(body, Vector3(0.48, 0.53, 0.28), Vector3(0, 1.16, 0), cloth,0.055)
	box(body, Vector3(0.50, 0.075, 0.30), Vector3(0, 0.97, 0), boots)
	for x in [-0.18, 0.18]:
		box(body, Vector3(0.065, 0.52, 0.025), Vector3(x, 1.2, -0.151), webbing)
		box(body, Vector3(0.12, 0.115, 0.10), Vector3(x, 1.04, -0.18), webbing)
	box(body, Vector3(0.29, 0.32, 0.15), Vector3(0, 1.22, 0.21), webbing)
	cylinder(body, 0.075, 0.11, Vector3(0, 1.48, 0), skin)
	var head = sphere(body, 0.17, Vector3(0, 1.65, -0.01), skin)
	head.scale = Vector3(0.85, 1.1, 0.91)
	# Helmet: a flattened dome plus brim; British helmets have a wide brim.
	var hat = sphere(body, 0.20, Vector3(0, 1.76, 0), helmet)
	hat.scale = Vector3(1.1, 0.48, 1.12) if british else Vector3(1.04, 0.65, 1.10)
	cylinder(body, 0.285 if british else 0.212, 0.026 if british else 0.045, Vector3(0, 1.74, -0.01), helmet, -1, 24)
	box(body, Vector3(0.027, 0.061, 0.045), Vector3(0, 1.64, -0.162), skin)
	for x in [-0.067, 0.067]:
		box(body, Vector3(0.038, 0.013, 0.012), Vector3(x, 1.68, -0.163), boots)
	# Two legs are separate nodes so the animation code can swing them.
	var legs: Array[Node3D] = []
	for x in [-0.135, 0.135]:
		var leg = Node3D.new()
		root.add_child(leg)
		leg.position = Vector3(x, 0.93, 0)
		beveled_box(leg, Vector3(0.19, 0.40, 0.21), Vector3(0, -0.21, 0), cloth,0.036)
		cylinder(leg, 0.096, 0.30, Vector3(0, -0.56, 0), cloth)
		beveled_box(leg, Vector3(0.18, 0.19, 0.30), Vector3(0, -0.83, -0.05), boots,0.025)
		legs.append(leg)
	# Arms: two segments each, reaching to the rifle.
	segment(body, Vector3(-0.28, 1.39, 0), Vector3(-0.31, 1.12, -0.18), 0.095, cloth)
	segment(body, Vector3(-0.31, 1.12, -0.18), Vector3(-0.04, 1.22, -0.49), 0.075, cloth)
	segment(body, Vector3(0.28, 1.39, 0), Vector3(0.39, 1.19, -0.05), 0.095, cloth)
	segment(body, Vector3(0.39, 1.19, -0.05), Vector3(0.14, 1.22, -0.26), 0.073, cloth)
	sphere(body, 0.073, Vector3(-0.04, 1.22, -0.49), skin)
	sphere(body, 0.07, Vector3(0.14, 1.22, -0.26), skin)
	# The rifle is built from the shared rifle model.
	var gun = rifle(body)
	gun.position = Vector3(0.07, 1.22, -0.43)
	# British soldiers get an SMLE-like silhouette: a protruding magazine and nose cap.
	if british:
		# Simplified SMLE silhouette: protruding ten-round magazine and nose cap.
		box(gun,Vector3(0.075,0.17,0.19),Vector3(0,-0.13,0.06),material(Color("303737"),0.65))
		box(gun,Vector3(0.093,0.12,0.085),Vector3(0,0.01,-0.89),material(Color("303737"),0.65))
	return {"root": root, "body": body, "legs": legs, "gun": gun}

## Build an enamel tea cup.
static func teacup(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var enamel = material(Color("cbcdbd"),0.3,0.32)
	var rim = material(Color("344645"),0.45,0.38)
	cylinder(root,0.063,0.12,Vector3.ZERO,enamel,-1,16)
	var ring = TorusMesh.new()
	ring.inner_radius = 0.057
	ring.outer_radius = 0.065
	ring.rings = 16
	ring.ring_segments = 8
	mesh(root,ring,Vector3(0,0.06,0),rim)
	cylinder(root,0.056,0.002,Vector3(0,0.059,0),material(Color("a6956d"),0.3,0.15),-1,16)
	var handle = TorusMesh.new()
	handle.inner_radius = 0.024
	handle.outer_radius = 0.032
	handle.rings = 12
	handle.ring_segments = 6
	mesh(root,handle,Vector3(0.075,0,0),enamel).rotation.x = PI/2
	return root

## Build the British patrol truck: cab, bonnet, cargo bed, canvas roof and four wheels.
static func patrol_truck(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var paint = material(Color("a39265"),0.25,0.65)
	var dark = material(Color("343b35"),0.2)
	var rubber = material(Color("252b29"),0.05,0.98)
	var canvas = material(Color("777552"))
	# Morris CS8-inspired 1930s British light truck: separate cab, bonnet and cargo bed.
	# Chassis is a destructible solid so the truck can be shot.
	# Morris CS8-inspired 1930s British light truck: separate cab, bonnet and cargo bed.
	solid(root,Vector3(1.9,0.35,4.3),Vector3(0,0.75,0),dark)
	box(root,Vector3(1.45,0.62,1.35),Vector3(0,1.14,-1.48),paint)
	box(root,Vector3(1.50,0.55,0.075),Vector3(0,1.1,-2.19),dark)
	# Radiator grille slats.
	for x in range(10):
		box(root,Vector3(0.035,0.46,0.02),Vector3(-0.64+x*0.14,1.1,-2.24),paint)
	# Headlamps and front wings.
	for x in [-0.79,0.79]:
		var lamp = cylinder(root,0.115,0.08,Vector3(x,1.25,-2.12),material(Color("e6d9a5"),0.2),-1,12)
		lamp.rotation.x=PI/2
		box(root,Vector3(0.45,0.10,1.40),Vector3(x,1.01,-1.45),paint)
	box(root,Vector3(2.05,0.14,0.17),Vector3(0,0.77,-2.35),dark)
	box(root,Vector3(1.75,0.11,1.2),Vector3(0,0.98,-0.24),paint)
	for x in [-0.86,0.86]:
		box(root,Vector3(0.08,0.95,1.22),Vector3(x,1.37,-0.22),paint)
		box(root,Vector3(0.045,0.65,0.045),Vector3(x,2.00,-0.83),dark)
	box(root,Vector3(1.74,0.06,0.06),Vector3(0,1.72,-0.83),dark)
	box(root,Vector3(1.74,0.06,0.06),Vector3(0,2.32,-0.83),dark)
	box(root,Vector3(0.06,0.6,0.06),Vector3(0,2.02,-0.83),dark)
	box(root,Vector3(1.88,0.08,1.32),Vector3(0,2.36,-0.16),canvas)
	for x in [-0.45,0.45]:
		box(root,Vector3(0.64,0.22,0.62),Vector3(x,1.15,-0.2),canvas)
		box(root,Vector3(0.64,0.60,0.16),Vector3(x,1.5,0.04),canvas)
	# Steering wheel.
	var wheel = TorusMesh.new()
	wheel.inner_radius=0.15
	wheel.outer_radius=0.19
	mesh(root,wheel,Vector3(0.46,1.66,-0.57),dark).rotation.x=0.6
	box(root,Vector3(1.92,0.15,2.2),Vector3(0,1.07,1.39),paint)
	for x in [-0.96,0.96]:
		box(root,Vector3(0.08,0.67,2.3),Vector3(x,1.43,1.4),paint)
		box(root,Vector3(0.07,1.30,0.07),Vector3(x,1.93,0.38),dark)
		box(root,Vector3(0.07,1.30,0.07),Vector3(x,1.93,2.4),dark)
	box(root,Vector3(1.99,0.10,2.4),Vector3(0,2.60,1.4),canvas)
	box(root,Vector3(1.92,0.6,0.08),Vector3(0,1.42,2.53),paint)
	# Four wheels: rubber tyre and hub, both rotated onto the x axis.
	for x in [-1.00,1.00]:
		for z in [-1.52,1.69]:
			var tyre = cylinder(root,0.47,0.28,Vector3(x,0.47,z),rubber,-1,16)
			tyre.rotation.z=PI/2
			var hub = cylinder(root,0.22,0.30,Vector3(x,0.47,z),paint,-1,12)
			hub.rotation.z=PI/2
	return root
