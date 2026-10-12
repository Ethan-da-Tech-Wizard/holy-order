extends RefCounted

# Cyclic RPM applies inside an automatic burst; aim and reload time are separate.
# Semi-auto intervals are trigger limits, not a claim of a fixed historical RPM.
# See WEAPON-RATES.txt for primary references and manual-cycle choices.
# Magazine/belt loads are explicit inventories, not unlimited firing timers.
# The carried loads are scenario choices; the weapon and feed types are period equipment.
const DATA = {
	"carbine":{"name":"M1 Carbine", "caliber":"30carbine", "capacity":15, "reserve":120, "interval":0.20, "aim_interval":0.90, "reload":2.6, "damage":33.0, "range":180.0, "spread":0.023, "automatic":false},
	"m1919":{"name":"Browning M1919A4", "caliber":"30-06", "capacity":250, "reserve":2000, "interval":0.12, "cyclic_rpm":500, "reload":6.0, "damage":46.0, "range":850.0, "spread":0.020, "automatic":true},
	"flamethrower":{"name":"M1A1 Flamethrower", "caliber":"fuel", "capacity":100, "reserve":0, "interval":0.16, "reload":6.0, "damage":17.0, "range":23.0, "spread":0.06, "automatic":true},
	"bar":{"name":"M1918A2 BAR (slow)", "caliber":"30-06", "capacity":20, "reserve":160, "interval":0.16, "cyclic_rpm":375, "reload":3.2, "damage":47.0, "range":175.0, "spread":0.018, "automatic":true},
	"garand":{"name":"M1 Garand", "caliber":"30-06", "capacity":8, "reserve":80, "interval":0.20, "aim_interval":1.0, "reload":2.8, "damage":47.0, "range":170.0, "spread":0.019, "automatic":false},
	"kar98":{"name":"Karabiner 98k", "caliber":"792", "capacity":5, "reserve":60, "interval":2.0, "aim_interval":3.0, "reload":3.6, "damage":51.0, "range":180.0, "spread":0.017, "automatic":false},
	"g43":{"name":"Gewehr 43", "caliber":"792", "capacity":10, "reserve":50, "interval":0.25, "aim_interval":1.1, "reload":3.3, "damage":49.0, "range":180.0, "spread":0.018, "automatic":false},
	"mp40":{"name":"MP 40", "caliber":"9mm", "capacity":32, "reserve":128, "interval":0.12, "cyclic_rpm":500, "reload":3.0, "damage":24.0, "range":75.0, "spread":0.036, "automatic":true},
	"mg34":{"name":"MG 34", "caliber":"792", "capacity":250, "reserve":750, "interval":0.075, "cyclic_rpm":800, "reload":6.0, "damage":46.0, "range":230.0, "spread":0.025, "automatic":true},
	"mg42":{"name":"MG 42", "caliber":"792", "capacity":250, "reserve":750, "interval":0.05, "cyclic_rpm":1200, "reload":6.0, "damage":46.0, "range":230.0, "spread":0.028, "automatic":true},
	"m2":{"name":"Browning M2 HB", "caliber":"50bmg", "capacity":100, "reserve":400, "interval":0.12, "cyclic_rpm":500, "reload":6.5, "damage":85.0, "range":260.0, "spread":0.020, "automatic":true}
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
				if mat is ShaderMaterial and mat.get_shader_parameter("tint") is Color:color=mat.get_shader_parameter("tint")
				for i in range(count):
					var k = i if indices == null or indices.is_empty() else indices[i]
					st.set_color(color.srgb_to_linear())
					st.set_normal((t.basis.inverse().transposed()*normals[k]).normalized())
					st.add_vertex(t*verts[k])
		append_meshes(child,t,st)

# Dimensions and feed families also position the sights, hands and reload props.
const PROFILES={
	"carbine":{"front":-0.585,"rear":0.31,"sight":0.066,"support":-0.28,"feed":"mag","wood":"806044"},
	"garand":{"front":-0.79,"rear":0.31,"sight":0.083,"support":-0.39,"feed":"enbloc","wood":"654631"},
	"kar98":{"front":-0.79,"rear":0.32,"sight":0.058,"support":-0.39,"feed":"stripper","wood":"775638"},
	"g43":{"front":-0.80,"rear":0.315,"sight":0.069,"support":-0.37,"feed":"mag","wood":"8b6542"},
	"bar":{"front":-0.855,"rear":0.36,"sight":0.090,"support":-0.39,"feed":"mag","wood":"584232"},
	"mp40":{"front":-0.51,"rear":0.32,"sight":0.067,"support":-0.16,"feed":"mag","wood":"48382e"},
	"mg34":{"front":-0.875,"rear":0.345,"sight":0.098,"support":-0.31,"feed":"belt","wood":"64472e"},
	"mg42":{"front":-0.875,"rear":0.345,"sight":0.100,"support":-0.33,"feed":"belt","wood":"654734"},
	"m1919":{"front":-0.91,"rear":0.13,"sight":0.100,"support":-0.20,"feed":"belt","wood":"4c4331"},
	"m2":{"front":-1.22,"rear":0.43,"sight":0.145,"support":-0.20,"feed":"belt","wood":"67503a"},
	"flamethrower":{"front":-0.73,"rear":0.18,"sight":0.075,"support":-0.36,"feed":"fuel","wood":"545b3c"},
	"bazooka":{"front":-0.96,"rear":0.41,"sight":0.09,"support":-0.43,"feed":"rocket","wood":"686b42"}
}
static var firearm_material:ShaderMaterial
static func profile(kind:String)->Dictionary:return PROFILES.get(kind,PROFILES.garand)

static func weapon(parent:Node3D,kind:String,detailed:bool=false)->Node3D:
	var root=Node3D.new()
	parent.add_child(root)
	root.name=kind
	var p=profile(kind)
	if not gun_cache.has(kind):
		var source=Node3D.new()
		make_gun(source,kind)
		gun_cache[kind]=bake(source)
		source.free()
		if firearm_material==null:
			firearm_material=ShaderMaterial.new()
			firearm_material.shader=load("res://assets/omaha/weapon_finish.gdshader")
		gun_cache[kind].surface_set_material(0,firearm_material)
	var mesh=MeshInstance3D.new()
	mesh.mesh=gun_cache[kind]
	root.add_child(mesh)
	for entry in [["Muzzle",Vector3(0,0.018,p.front-0.01)],["SightLine",Vector3(0,p.sight,p.front+0.05)],["RearSightLine",Vector3(0,p.sight,0.075)]]:
		var marker=Marker3D.new()
		marker.name=entry[0]
		marker.position=entry[1]
		root.add_child(marker)
	for label in ["Bolt","ReloadClip"]:
		var part=Node3D.new()
		part.name=label
		root.add_child(part)
	if detailed:
		var steel=Art.material(Color("454b49"),0.7,0.5)
		var brass=Art.material(Color("a78c54"),0.65,0.4)
		var clip=root.get_node("ReloadClip")
		match p.feed:
			"enbloc","stripper":
				var count=8 if p.feed=="enbloc" else 5
				for i in range(count):
					var x=(float(i%2)-0.5)*0.012 if count==8 else (i-2)*0.010
					var z=float(i/2)*0.013-0.045 if count==8 else -0.025
					barrel(clip,0.0044,0.055,Vector3(x,0.025,z),brass,6)
				Art.box(clip,Vector3(0.026 if count==8 else 0.052,0.035,0.012),Vector3(0,0.003,0.002),steel)
			"belt":
				Art.box(clip,Vector3(0.16,0.13,0.18),Vector3(-0.1,-0.05,0),Art.material(Color("666547")))
				for i in range(6):barrel(clip,0.005,0.066,Vector3(-0.17+i*0.018,0.055,-0.02),brass,6)
			"fuel":Art.cylinder(clip,0.047,0.09,Vector3.ZERO,steel,-1,8)
			_:
				var length=0.24 if kind=="mp40" else (0.16 if kind=="bar" else 0.10)
				Art.beveled_box(clip,Vector3(0.034,length,0.07 if kind=="mp40" else 0.10),Vector3(0,-length/2,0),steel,0.004)
		clip.hide()
	return root

static func barrel(root:Node3D,radius:float,length:float,p:Vector3,mat:Material,sides:int=12):
	var tube=Art.cylinder(root,radius,length,p,mat,-1,sides)
	tube.rotation.x=PI/2
	return tube

static func make_gun(root:Node3D,kind:String):
	var p=profile(kind)
	var steel=Art.material(Color("3e4644"),0.8,0.4)
	var worn=Art.material(Color("646b66"),0.65,0.5)
	var black=Art.material(Color("1b211e"),0.4,0.65)
	var wood=Art.material(Color(p.wood),0,0.72)
	var olive=Art.material(Color("656746"))
	var brass=Art.material(Color("a18a53"),0.6,0.5)
	if kind=="bazooka":
		# Open tube ends are rings, with a dark bore recessed inside the mouth.
		barrel(root,0.038,1.33,Vector3(0,0.018,-0.275),olive)
		for z in [p.front,p.rear]:
			var ring=TorusMesh.new()
			ring.inner_radius=0.030
			ring.outer_radius=0.041
			ring.rings=12
			ring.ring_segments=6
			Art.mesh(root,ring,Vector3(0,0.018,z),worn).rotation.x=PI/2
			barrel(root,0.030,0.006,Vector3(0,0.018,z+(-0.003 if z<0 else 0.003)),black)
		Art.box(root,Vector3(0.055,0.10,0.19),Vector3(0,-0.054,0.19),wood)
		Art.box(root,Vector3(0.039,0.13,0.064),Vector3(0,-0.085,-0.10),wood)
		Art.box(root,Vector3(0.09,0.025,0.25),Vector3(0,-0.049,-0.48),wood)
		Art.box(root,Vector3(0.008,0.09,0.13),Vector3(-0.045,0.064,-0.34),worn)
		return
	var heavy=kind in ["mg34","mg42","m1919","m2"]
	var compact=kind=="mp40"
	var rec=Vector3(0.064,0.082,0.24)
	if kind=="bar":rec=Vector3(0.073,0.098,0.36)
	if kind=="carbine":rec=Vector3(0.044,0.06,0.18)
	if heavy:rec=Vector3(0.08,0.12,0.34)
	if kind=="m2":rec=Vector3(0.16,0.17,0.45)
	Art.beveled_box(root,rec,Vector3(0,0.012,-0.08),steel,0.004)
	barrel(root,0.012 if not heavy else 0.024,absf(p.front+0.15),Vector3(0,0.018,(p.front-0.15)*0.5),steel)
	if kind in ["carbine","garand","kar98","g43","bar"]:
		var handguard=0.45 if kind=="carbine" else (0.54 if kind=="bar" else 0.66)
		Art.beveled_box(root,Vector3(0.055,0.068,handguard),Vector3(0,-0.024,-handguard*0.5+0.015),wood,0.009)
		var butt=Art.beveled_box(root,Vector3(0.045,0.128 if kind!="carbine" else 0.11,p.rear-0.1),Vector3(0,-0.060,(p.rear+0.1)*0.5),wood,0.009)
		butt.rotation.x=-0.12
		Art.box(root,Vector3(0.046,0.13,0.012),Vector3(0,-0.072,p.rear),worn)
		Art.box(root,Vector3(0.048,0.064,0.16),Vector3(0,-0.043,0.067),wood)
		for z in [-handguard+0.04,-0.35]:Art.box(root,Vector3(0.059,0.078,0.014),Vector3(0,-0.019,z),steel)
		Art.box(root,Vector3(0.013,0.02,0.065),Vector3(0.032,0.041,-0.07),worn)
		if kind=="garand":
			barrel(root,0.016,0.16,Vector3(0,-0.025,p.front+0.105),steel)
			Art.box(root,Vector3(0.022,0.01,0.09),Vector3(0,0.056,-0.025),black)
			Art.segment(root,Vector3(0.033,0.015,-0.06),Vector3(0.058,0.015,-0.06),0.009,worn)
		if kind=="kar98":
			barrel(root,0.025,0.22,Vector3(0,0.036,-0.025),worn)
			Art.segment(root,Vector3(0.022,0.041,0.025),Vector3(0.065,-0.026,0.042),0.008,worn)
			Art.sphere(root,0.013,Vector3(0.065,-0.026,0.042),black)
		if kind=="g43":
			Art.box(root,Vector3(0.043,0.112,0.108),Vector3(0,-0.097,-0.038),steel)
			barrel(root,0.022,0.29,Vector3(0,0.032,-0.27),steel)
		if kind=="carbine":Art.box(root,Vector3(0.029,0.088,0.067),Vector3(0,-0.073,-0.06),steel)
		if kind=="bar":
			Art.box(root,Vector3(0.039,0.17,0.106),Vector3(0,-0.125,-0.07),steel)
			for side in [-1,1]:
				Art.segment(root,Vector3(side*0.03,-0.02,p.front+0.17),Vector3(side*0.048,-0.055,-0.39),0.009,steel)
			Art.box(root,Vector3(0.035,0.008,0.24),Vector3(0,0.069,-0.17),worn)
	elif compact:
		barrel(root,0.030,0.27,Vector3(0,0.018,-0.065),black)
		Art.box(root,Vector3(0.045,0.078,0.25),Vector3(0,-0.02,-0.03),wood)
		Art.box(root,Vector3(0.034,0.245,0.064),Vector3(0,-0.17,-0.17),steel)
		Art.box(root,Vector3(0.038,0.135,0.065),Vector3(0,-0.097,0.10),wood)
		for x in [-0.026,0.026]:Art.segment(root,Vector3(x,-0.06,0.06),Vector3(x,-0.073,p.rear),0.007,steel)
		Art.segment(root,Vector3(-0.026,-0.073,p.rear),Vector3(0.026,-0.073,p.rear),0.009,steel)
		Art.box(root,Vector3(0.017,0.018,0.07),Vector3(0,-0.026,p.front+0.08),black)
	elif heavy:
		var jacket_length=0.57 if kind!="m2" else 0.25
		var center=-0.55 if kind!="m2" else -0.40
		if kind=="mg42":Art.box(root,Vector3(0.064,0.065,0.56),Vector3(0,0.018,-0.56),steel)
		else:barrel(root,0.037 if kind!="m2" else 0.045,jacket_length,Vector3(0,0.018,center),steel)
		for z in range(7):
			var at=-0.31-z*0.069
			if kind=="m2" and z>2:break
			for x in [-1,1]:Art.box(root,Vector3(0.005,0.024,0.034 if kind=="mg42" else 0.018),Vector3(x*0.036,0.018,at),black)
		if kind in ["mg34","mg42"]:
			Art.box(root,Vector3(0.052,0.11,0.21),Vector3(0,-0.025,0.23),wood)
			Art.box(root,Vector3(0.037,0.13,0.065),Vector3(0,-0.1,0.055),black)
			for side in [-1,1]:Art.segment(root,Vector3(side*0.026,-0.025,-0.76),Vector3(side*0.05,-0.05,-0.44),0.008,steel)
			barrel(root,0.03 if kind=="mg42" else 0.019,0.055,Vector3(0,0.018,p.front+0.01),worn)
		elif kind=="m1919":Art.box(root,Vector3(0.045,0.13,0.075),Vector3(0,-0.09,0.105),black)
		else:
			for side in [-1,1]:
				Art.cylinder(root,0.021,0.12,Vector3(side*0.115,-0.02,0.25),wood,-1,10)
				Art.segment(root,Vector3(side*0.03,0.01,0.13),Vector3(side*0.115,0.01,0.25),0.011,steel)
			barrel(root,0.026,0.90,Vector3(0,0.018,-0.77),steel)
		Art.box(root,Vector3(0.15,0.14,0.19),Vector3(-0.16,-0.05,-0.04),olive)
		for i in range(7):barrel(root,0.0055,0.066,Vector3(-0.18+i*0.02,0.065,-0.04),brass,6)
	elif kind=="flamethrower":
		barrel(root,0.027,0.64,Vector3(0,0.01,-0.36),olive)
		barrel(root,0.043,0.13,Vector3(0,0.01,-0.67),black)
		for z in [0.06,-0.36]:Art.box(root,Vector3(0.045,0.14,0.075),Vector3(0,-0.078,z),wood)
		Art.segment(root,Vector3(0,-0.12,0.07),Vector3(0.12,-0.34,0.24),0.025,black)
		barrel(root,0.016,0.18,Vector3(0,-0.05,-0.62),steel)
	# All rear sights and front posts share their weapon's measured local sight plane.
	var front=p.front+0.05
	Art.box(root,Vector3(0.021,p.sight-0.013,0.027),Vector3(0,(p.sight-0.013)*0.5,front),steel)
	Art.box(root,Vector3(0.0025,0.022,0.007),Vector3(0,p.sight-0.011,front),black)
	for x in [-0.012,0.012]:Art.box(root,Vector3(0.003,0.026,0.014),Vector3(x,p.sight-0.006,front),worn)
	if kind in ["garand","bar","carbine","m2"]:
		var ring=TorusMesh.new()
		ring.inner_radius=0.0055
		ring.outer_radius=0.0085
		ring.rings=12
		ring.ring_segments=6
		Art.mesh(root,ring,Vector3(0,p.sight,0.075),black).rotation.x=PI/2
	else:
		for x in [-0.009,0.009]:Art.box(root,Vector3(0.01,0.015,0.01),Vector3(x,p.sight-0.004,0.075),steel)
	Art.box(root,Vector3(0.018,p.sight-0.045,0.033),Vector3(0,0.046+(p.sight-0.045)*0.5,0.075),steel)

static func firearm_hand(parent:Node3D,kind:String,left:bool)->Node3D:
	var root=Node3D.new()
	parent.add_child(root)
	var profile_data=profile(kind)
	root.position=Vector3(-0.028,-0.061,profile_data.support) if left else Vector3(0.031,-0.069,0.08)
	var plate=Art.material(Color("7d8987"),0.72,0.43)
	var glove=Art.material(Color("3b403b"),0,0.84)
	# Palms and bent fingers actually wrap under the stock/handguard.
	Art.beveled_box(root,Vector3(0.061,0.039,0.08),Vector3.ZERO,glove,0.006)
	Art.box(root,Vector3(0.065,0.014,0.065),Vector3(0,-0.021,0),plate)
	for i in range(4):
		var z=-0.028+i*0.018
		Art.segment(root,Vector3(-0.029,0,z),Vector3(0.018,0.006,z),0.009,plate)
		Art.segment(root,Vector3(0.018,0.006,z),Vector3(0.026,0.043,z),0.008,plate)
	Art.segment(root,Vector3(-0.03,0.008,0.035),Vector3(-0.026,0.045,0.005),0.011,glove)
	# Arms trail toward the shoulders/camera, well below the bore and sights.
	var elbow=Vector3(-0.23,-0.12,0.38) if left else Vector3(0.18,-0.18,0.26)
	Art.segment(root,Vector3(0,-0.025,0.042),elbow,0.039,plate)
	Art.segment(root,elbow,elbow+Vector3(-0.03 if left else 0.03,-0.03,0.12),0.046,glove)
	var mesh=MeshInstance3D.new()
	mesh.mesh=bake(root)
	for child in root.get_children():child.free()
	root.add_child(mesh)
	return root

static func soldier(parent: Node3D, team: int, variant: int) -> Dictionary:
	var key = "%d-%d" % [team,variant%3]
	if not soldier_cache.has(key):
		var torso = Node3D.new()
		var legs = Node3D.new()
		var right_arm=Node3D.new()
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
		for x in [-0.20]:
			Art.segment(torso,Vector3(x,1.41,0),Vector3(x*1.25,1.16,-0.20),0.08,cloth)
			Art.segment(torso,Vector3(x*1.25,1.16,-0.20),Vector3(x*0.3,1.22,-0.40),0.065,cloth)
			Art.sphere(torso,0.064,Vector3(x*0.3,1.22,-0.40),dark)
		Art.segment(right_arm,Vector3.ZERO,Vector3(0.05,-0.25,-0.20),0.08,cloth)
		Art.segment(right_arm,Vector3(0.05,-0.25,-0.20),Vector3(-0.14,-0.19,-0.40),0.065,cloth)
		Art.sphere(right_arm,0.064,Vector3(-0.14,-0.19,-0.40),dark)
		Art.box(torso,Vector3(0.47,0.055,0.30),Vector3(0,1.01,0),web)
		for x in [-0.145,0.145]:
			Art.box(torso,Vector3(0.038,0.41,0.31),Vector3(x,1.24,0.004),web)
			Art.beveled_box(torso,Vector3(0.12,0.115,0.060),Vector3(x,1.065,-0.18),web)
		Art.beveled_box(torso,Vector3(0.28,0.31,0.12),Vector3(0,1.22,0.205),web,0.022)
		Art.cylinder(legs,0.10,0.61,Vector3(0,-0.28,0),cloth,-1,10)
		Art.cylinder(legs,0.092,0.25,Vector3(0,-0.59,0),web,-1,10)
		Art.beveled_box(legs,Vector3(0.18,0.14,0.31),Vector3(0,-0.77,-0.062),dark,0.025)
		simplify_parts(torso)
		simplify_parts(legs)
		simplify_parts(right_arm)
		soldier_cache[key]=[bake(torso),bake(legs),bake(right_arm)]
		right_arm.free()
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
	var arm=MeshInstance3D.new()
	arm.mesh=soldier_cache[key][2]
	arm.position=Vector3(0.20,1.41,0)
	root.add_child(arm)
	return {"root":root,"body":body,"legs":leg_nodes,"right_arm":arm}

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

static func simplify_parts(root:Node):
	for child in root.get_children():
		if child is MeshInstance3D:
			if child.mesh is SphereMesh:
				child.mesh.radial_segments=12
				child.mesh.rings=6
			elif child.mesh is CylinderMesh:child.mesh.radial_segments=mini(child.mesh.radial_segments,12)
		simplify_parts(child)
