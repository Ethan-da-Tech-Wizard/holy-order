extends RefCounted

# Magazine/belt loads are explicit inventories, not unlimited firing timers.
# The carried loads are scenario choices; the weapon and feed types are period equipment.
const DATA = {
	"bar":{"name":"M1918A2 BAR", "caliber":"30-06", "capacity":20, "reserve":160, "interval":0.16, "reload":3.2, "damage":47.0, "range":175.0, "spread":0.018, "automatic":true},
	"garand":{"name":"M1 Garand", "caliber":"30-06", "capacity":8, "reserve":80, "interval":0.85, "reload":2.8, "damage":47.0, "range":170.0, "spread":0.019, "automatic":false},
	"kar98":{"name":"Karabiner 98k", "caliber":"792", "capacity":5, "reserve":60, "interval":2.0, "reload":3.6, "damage":51.0, "range":180.0, "spread":0.017, "automatic":false},
	"g43":{"name":"Gewehr 43", "caliber":"792", "capacity":10, "reserve":50, "interval":0.95, "reload":3.3, "damage":49.0, "range":180.0, "spread":0.018, "automatic":false},
	"mp40":{"name":"MP 40", "caliber":"9mm", "capacity":32, "reserve":128, "interval":0.13, "reload":3.0, "damage":24.0, "range":75.0, "spread":0.036, "automatic":true},
	"mg34":{"name":"MG 34", "caliber":"792", "capacity":250, "reserve":750, "interval":0.075, "reload":6.0, "damage":46.0, "range":230.0, "spread":0.025, "automatic":true},
	"mg42":{"name":"MG 42", "caliber":"792", "capacity":250, "reserve":750, "interval":0.05, "reload":6.0, "damage":46.0, "range":230.0, "spread":0.028, "automatic":true},
	"m2":{"name":"Browning M2 HB", "caliber":"50bmg", "capacity":100, "reserve":400, "interval":0.12, "reload":6.5, "damage":85.0, "range":260.0, "spread":0.020, "automatic":true}
}
const Art = preload("res://scripts/art.gd")
static var gun_cache: Dictionary = {}
static var soldier_cache: Dictionary = {}
static var paint: StandardMaterial3D

static func vertex_material() -> StandardMaterial3D:
	if paint == null:
		paint = StandardMaterial3D.new()
		paint.vertex_color_use_as_albedo = true
		paint.roughness = 0.79
	return paint

# Merge the primitive parts into one vertex-colored surface. Hundreds of soldiers
# share meshes rather than creating thousands of individual drawing objects.
static func bake(root: Node3D) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	append_meshes(root,Transform3D.IDENTITY,st)
	st.set_material(vertex_material())
	st.index()
	return st.commit()

static func append_meshes(node: Node3D, xf: Transform3D, st: SurfaceTool):
	for child in node.get_children():
		if not child is Node3D: continue
		var t = xf*child.transform
		if child is MeshInstance3D:
			for surface in range(child.mesh.get_surface_count()):
				var arr = child.mesh.surface_get_arrays(surface)
				var verts = arr[Mesh.ARRAY_VERTEX]
				var normals = arr[Mesh.ARRAY_NORMAL]
				var indices = arr[Mesh.ARRAY_INDEX]
				var count = verts.size() if indices == null or indices.is_empty() else indices.size()
				var mat = child.material_override
				if mat == null: mat = child.mesh.surface_get_material(surface)
				var color = mat.albedo_color if mat is StandardMaterial3D else Color.WHITE
				for i in range(count):
					var k = i if indices == null or indices.is_empty() else indices[i]
					st.set_color(color.srgb_to_linear())
					st.set_normal((t.basis.inverse().transposed()*normals[k]).normalized())
					st.add_vertex(t*verts[k])
		append_meshes(child,t,st)

static func weapon(parent: Node3D, kind: String, detailed: bool=false) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	root.name = kind
	if not gun_cache.has(kind):
		var source = Node3D.new()
		make_gun(source,kind)
		gun_cache[kind] = bake(source)
		source.free()
	var mesh = MeshInstance3D.new()
	mesh.mesh = gun_cache[kind]
	root.add_child(mesh)
	for entry in [["Muzzle",Vector3(0,0.018,-1.02 if kind=="m2" else -0.86)], ["SightLine",Vector3(0,0.084,-0.77)], ["RearSightLine",Vector3(0,0.084,0.13)]]:
		var marker = Marker3D.new()
		marker.name = entry[0]
		marker.position = entry[1]
		root.add_child(marker)
	for label in ["Bolt","ReloadClip"]:
		var part = Node3D.new()
		part.name = label
		root.add_child(part)
	if detailed:
		var steel = Art.material(Color("424a4c"),0.76,0.42)
		var mag = Art.beveled_box(root.get_node("ReloadClip"),Vector3(0.042,0.15,0.12),Vector3(0,-0.15,-0.02),steel)
		mag.name = "Magazine"
	return root

static func make_gun(root: Node3D, kind: String):
	var steel = Art.material(Color("42494a"),0.8,0.36)
	var black = Art.material(Color("171d1e"),0.6,0.48)
	var wood = Art.material(Color("624530"),0,0.66)
	var olive = Art.material(Color("555b3b"))
	var heavy = kind in ["mg34","mg42","m2"]
	var compact = kind=="mp40"
	var receiver_size = Vector3(0.075,0.11,0.29) if heavy else Vector3(0.052,0.072,0.24)
	Art.beveled_box(root,receiver_size,Vector3(0,0.015,-0.09),steel,0.006)
	var barrel = Art.cylinder(root,0.011 if not heavy else 0.023,0.64,Vector3(0,0.018,-0.53),steel,-1,16)
	barrel.rotation.x = PI/2
	if kind in ["bar","garand","kar98","g43"]:
		Art.beveled_box(root,Vector3(0.055,0.07,0.43),Vector3(0,-0.025,-0.35),wood,0.012)
		var butt = Art.beveled_box(root,Vector3(0.047,0.13,0.29),Vector3(0,-0.058,0.255),wood,0.012)
		butt.rotation.x = -0.12
		Art.beveled_box(root,Vector3(0.049,0.133,0.014),Vector3(0,-0.075,0.407),steel)
		Art.beveled_box(root,Vector3(0.04,0.07,0.15),Vector3(0,-0.045,0.079),wood,0.008)
		for z in [-0.64,-0.38]:
			Art.beveled_box(root,Vector3(0.060,0.080,0.015),Vector3(0,-0.008,z),steel)
		if kind=="bar":
			Art.beveled_box(root,Vector3(0.042,0.15,0.12),Vector3(0,-0.14,-0.06),steel)
			Art.segment(root,Vector3(-0.026,-0.03,-0.77),Vector3(-0.035,-0.045,-0.45),0.008,steel)
			Art.segment(root,Vector3(0.026,-0.03,-0.77),Vector3(0.035,-0.045,-0.45),0.008,steel)
		if kind=="g43": Art.beveled_box(root,Vector3(0.043,0.09,0.11),Vector3(0,-0.088,-0.03),steel)
		if kind=="kar98":
			Art.segment(root,Vector3(0.025,0.035,0),Vector3(0.066,-0.012,0.014),0.009,steel)
			Art.sphere(root,0.016,Vector3(0.066,-0.012,0.014),steel)
	if compact:
		Art.beveled_box(root,Vector3(0.041,0.27,0.061),Vector3(0,-0.20,-0.10),steel)
		Art.beveled_box(root,Vector3(0.04,0.13,0.055),Vector3(0,-0.092,0.06),black)
		for x in [-0.030,0.030]: Art.segment(root,Vector3(x,-0.03,0.06),Vector3(x,-0.09,0.32),0.007,steel)
		Art.segment(root,Vector3(-0.030,-0.09,0.32),Vector3(0.030,-0.09,0.32),0.009,steel)
	if heavy:
		var shroud = Art.cylinder(root,0.034,0.5,Vector3(0,0.018,-0.51),steel,-1,16)
		shroud.rotation.x = PI/2
		for z in [-0.32,-0.38,-0.44,-0.50,-0.56,-0.62,-0.68]:
			for x in [-0.032,0.032]: Art.box(root,Vector3(0.006,0.026,0.026),Vector3(x,0.018,z),black)
		Art.beveled_box(root,Vector3(0.10,0.10,0.06),Vector3(0,-0.022,0.1),wood)
		if kind=="m2":
			Art.beveled_box(root,Vector3(0.15,0.15,0.32),Vector3(0,0,-0.08),steel)
			var hb = Art.cylinder(root,0.025,0.80,Vector3(0,0.018,-0.62),steel,-1,16)
			hb.rotation.x = PI/2
			for x in [-0.12,0.12]: Art.cylinder(root,0.021,0.12,Vector3(x,-0.02,0.16),wood)
		Art.box(root,Vector3(0.16,0.15,0.20),Vector3(-0.18,-0.025,-0.06),olive)
		for x in [-0.15,-0.12,-0.09,-0.06]:
			var cartridge = Art.cylinder(root,0.006,0.055,Vector3(x,0.06,-0.04),Art.material(Color("9d8851")),-1,8)
			cartridge.rotation.x=PI/2
	# The aperture and post leave an actual line of sight through the model.
	Art.beveled_box(root,Vector3(0.045,0.030,0.15),Vector3(0,0.036,0.07),steel)
	Art.beveled_box(root,Vector3(0.022,0.034,0.021),Vector3(0,0.044,-0.77),steel)
	if kind in ["bar","garand","m2"]:
		var ring = TorusMesh.new()
		ring.inner_radius = 0.0055
		ring.outer_radius = 0.0082
		ring.rings = 16
		ring.ring_segments = 8
		var rear = Art.mesh(root,ring,Vector3(0,0.084,0.13),black)
		rear.rotation.x = PI/2
		Art.box(root,Vector3(0.006,0.029,0.009),Vector3(0,0.065,0.13),steel)
	else:
		Art.beveled_box(root,Vector3(0.029,0.027,0.055),Vector3(0,0.060,-0.16),steel)
		for x in [-0.008,0.008]:Art.box(root,Vector3(0.008,0.013,0.008),Vector3(x,0.078,-0.16),black)
	Art.box(root,Vector3(0.0022,0.023,0.007),Vector3(0,0.0725,-0.77),black)
	for x in [-0.012,0.012]: Art.box(root,Vector3(0.003,0.028,0.013),Vector3(x,0.071,-0.77),steel)

static func soldier(parent: Node3D, team: int, variant: int) -> Dictionary:
	var key = "%d-%d" % [team,variant%3]
	if not soldier_cache.has(key):
		var torso = Node3D.new()
		var legs = Node3D.new()
		var cloth = Art.material(Color("646747") if team==1 else Color("535b55"))
		if variant%3==1: cloth=Art.material(Color("acae9d") if team==0 else Color("6e7055"))
		var dark = Art.material(Color("332f28"))
		var web = Art.material(Color("99876a") if team==1 else Color("4a4131"))
		var skin = Art.material(Color("b19780"))
		Art.beveled_box(torso,Vector3(0.46,0.53,0.28),Vector3(0,1.20,0),cloth,0.055)
		Art.beveled_box(torso,Vector3(0.43,0.24,0.30),Vector3(0,0.91,0),cloth,0.036)
		Art.cylinder(torso,0.07,0.13,Vector3(0,1.53,0),skin,-1,10)
		var head = Art.sphere(torso,0.135,Vector3(0,1.67,-0.009),skin)
		head.scale=Vector3(0.91,1.18,0.90)
		Art.box(torso,Vector3(0.038,0.060,0.054),Vector3(0,1.67,-0.13),skin)
		Art.mesh(torso,helmet_mesh(team),Vector3(0,1.74,0.01),cloth)
		for x in [-0.20,0.20]:
			Art.segment(torso,Vector3(x,1.41,0),Vector3(x*1.25,1.16,-0.20),0.08,cloth)
			Art.segment(torso,Vector3(x*1.25,1.16,-0.20),Vector3(x*0.3,1.22,-0.40),0.065,cloth)
			Art.sphere(torso,0.064,Vector3(x*0.3,1.22,-0.40),dark)
		Art.box(torso,Vector3(0.47,0.055,0.30),Vector3(0,1.01,0),web)
		for x in [-0.145,0.145]:
			Art.box(torso,Vector3(0.038,0.41,0.31),Vector3(x,1.24,0.004),web)
			Art.beveled_box(torso,Vector3(0.12,0.115,0.060),Vector3(x,1.065,-0.18),web)
		Art.beveled_box(torso,Vector3(0.28,0.31,0.12),Vector3(0,1.22,0.205),web,0.022)
		Art.cylinder(legs,0.10,0.61,Vector3(0,-0.28,0),cloth,-1,10)
		Art.cylinder(legs,0.092,0.25,Vector3(0,-0.59,0),web,-1,10)
		Art.beveled_box(legs,Vector3(0.18,0.14,0.31),Vector3(0,-0.77,-0.062),dark,0.025)
		soldier_cache[key]=[bake(torso),bake(legs)]
		torso.free()
		legs.free()
	var root=Node3D.new()
	parent.add_child(root)
	var body=MeshInstance3D.new()
	body.mesh=soldier_cache[key][0]
	root.add_child(body)
	var leg_nodes=[]
	for x in [-0.12,0.12]:
		var leg=MeshInstance3D.new()
		leg.mesh=soldier_cache[key][1]
		leg.position=Vector3(x,0.85,0)
		root.add_child(leg)
		leg_nodes.append(leg)
	return {"root":root,"body":body,"legs":leg_nodes}

static func helmet_mesh(team:int)->ArrayMesh:
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for ring in range(7):
		for side in range(24):
			var vertices=[]
			for corner in [Vector2(side,ring),Vector2(side+1,ring),Vector2(side+1,ring+1),Vector2(side,ring+1)]:
				var angle=corner.x/24*TAU
				var front=maxf(0,-sin(angle))
				var back=maxf(0,sin(angle))
				var limit=1.70-front*0.22+back*(0.10 if team==1 else 0.23)
				var theta=corner.y/7*limit
				var flare=0.013*pow(corner.y/7,5) if team==0 else 0.004
				vertices.append(Vector3(cos(angle)*(0.164*sin(theta)+flare),cos(theta)*0.19,sin(angle)*(0.178*sin(theta)+flare)))
			for k in [0,2,1,0,3,2]:st.add_vertex(vertices[k])
	st.generate_normals()
	return st.commit()
