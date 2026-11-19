# ==============================================================================
# Program: carcano_model.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for carcano_model.gd.
# ==============================================================================
## Procedural 3D model of the player's Carcano M91-style bolt-action rifle (desert mission).
##
## `build(parent)` creates the whole rifle from primitives and lofted meshes so no
## external model asset is needed. The returned root contains named child nodes that
## the player script looks up: "Bolt" (animated when cycling), "ReloadClip" (shown during
## reload), and Marker3D nodes "SightLine", "RearSightLine" and "Muzzle". The rifle
## points along -z with the muzzle at z = -0.894 m. All helpers are static.
extends RefCounted

# Original M91-inspired geometry, in metres. Open sights are geometry rather than
# an overlay. Their common height is the camera's settled aiming reference.
# Height of the sight tops above the bore axis; the camera is lined up with this for aiming.
# Original M91-inspired geometry, in metres. Open sights are geometry rather than
# an overlay. Their common height is the camera's settled aiming reference.
const SIGHT_HEIGHT: float = 0.081

# z positions of the front blade and rear notch; the sight line runs between them.
const FRONT_SIGHT_Z: float = -0.850
const REAR_SIGHT_Z: float = -0.225

# Material cache by name so each material is built once and shared by every rifle.
static var surfaces: Dictionary = {}

## Get or create a weapon material using the custom weapon_surface shader.
## @param name Cache key.
## @param color Base colour.
## @param metal Metalness 0..1.
## @param rough Base roughness 0..1.
## @param wood true to enable the shader's walnut grain.
static func surface(name: String, color: Color, metal: float, rough: float, wood: bool = false) -> Material:
	if surfaces.has(name): return surfaces[name]
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/weapon_surface.gdshader")
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("metalness", metal)
	mat.set_shader_parameter("base_roughness", rough)
	mat.set_shader_parameter("walnut", wood)
	surfaces[name] = mat
	return mat

## Add a MeshInstance3D with the given mesh, position and material.
## @return The new node.
static func mesh(parent: Node3D, shape: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var obj = MeshInstance3D.new()
	obj.mesh = shape
	obj.material_override = mat
	obj.position = pos
	parent.add_child(obj)
	return obj

## Add a cylinder lying along the z axis (the rifle's long axis).
## @param radius Metres. @param length Metres. @param sides Radial segments.
static func cylinder(parent: Node3D, radius: float, length: float, pos: Vector3, mat: Material, sides: int = 24) -> MeshInstance3D:
	var shape = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = length
	shape.radial_segments = sides
	var obj = mesh(parent, shape, pos, mat)
	# Godot cylinders stand on y; rotate 90 degrees so they point along z.
	obj.rotation.x = PI / 2
	return obj

## Add a thin rod between two points.
## @param radius Rod radius in metres.
static func segment(parent: Node3D, start: Vector3, end: Vector3, radius: float, mat: Material):
	var obj = cylinder(parent, radius, start.distance_to(end), (start + end) * 0.5, mat)
	# Rotate from +y (the cylinder's axis before aiming) to the segment direction.
	obj.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return obj

# Elliptical sections [z, centre_y, half_width, half_height] yield a contoured
# stock with continuous normals, instead of boxes sharing harsh ninety-degree edges.
## Build a smooth tube through elliptical cross sections.
## @param sections Array of [z, centre_y, half_width, half_height], in order along z.
## @param sides Segments around each ellipse.
# Elliptical sections [z, centre_y, half_width, half_height] yield a contoured
# stock with continuous normals, instead of boxes sharing harsh ninety-degree edges.
static func loft(parent: Node3D, sections: Array, mat: Material, sides: int = 24) -> MeshInstance3D:
	var st = SurfaceTool.new()
	# Vertices: one ring of `sides` points per section, with UV v = z.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section in sections:
		for j in range(sides):
			var angle = TAU * j / sides
			st.set_uv(Vector2(float(j) / sides, section[0]))
			st.add_vertex(Vector3(cos(angle) * section[2], section[1] + sin(angle) * section[3], section[0]))
	# Join consecutive rings with two triangles per quad.
	for i in range(sections.size() - 1):
		for j in range(sides):
			var a = i * sides + j
			var b = i * sides + (j + 1) % sides
			for index in [a, a + sides, b, b, a + sides, b + sides]: st.add_index(index)
	# Smooth normals across the whole tube.
	st.generate_normals()
	var obj = mesh(parent, st.commit(), Vector3.ZERO, mat)
	# Separate end caps retain a crisp edge at the butt plate and fore-end tip.
	# Separate end caps retain a crisp edge at the butt plate and fore-end tip.
	for index in [0, sections.size() - 1]:
		var section = sections[index]
		var cap = cylinder(parent, 1.0, 0.001, Vector3(0, section[1], section[0]), mat, sides)
		cap.scale = Vector3(section[2], 1, section[3])
	return obj

## Extrude a flat 2D outline into a thin solid plate (used for sights and the bolt slot).
## @param outline Polygon in the xy plane (x sideways, y up), metres.
## @param depth Thickness along z.
## @param pos Position of the plate.
static func plate(parent: Node3D, outline: PackedVector2Array, depth: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Triangulate the outline once and use it for both faces.
	var faces = Geometry2D.triangulate_polygon(outline)
	# The back face uses reversed winding so it faces outward.
	for side in [-1.0, 1.0]:
		for i in range(0, faces.size(), 3):
			var order = [faces[i], faces[i + 1], faces[i + 2]] if side < 0 else [faces[i + 2], faces[i + 1], faces[i]]
			for j in order:
				st.add_vertex(Vector3(outline[j].x, outline[j].y, side * depth * 0.5))
	# Side walls: two triangles per outline edge.
	for i in range(outline.size()):
		var a = outline[i]
		var b = outline[(i + 1) % outline.size()]
		for v in [Vector3(a.x,a.y,-depth/2), Vector3(a.x,a.y,depth/2), Vector3(b.x,b.y,-depth/2),
			Vector3(b.x,b.y,-depth/2), Vector3(a.x,a.y,depth/2), Vector3(b.x,b.y,depth/2)]: st.add_vertex(v)
	st.generate_normals()
	return mesh(parent, st.commit(), pos, mat)

## Assemble the complete rifle under `parent`.
## @return The rifle root node (name "CarcanoM91").
static func build(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "CarcanoM91"
	parent.add_child(root)
	# Materials: walnut stock, blued and worn steel, sight black, bore black, brass cartridges.
	var wood = surface("walnut", Color("67432b"), 0, 0.51, true)
	var steel = surface("blued_steel", Color("333c40"), 0.85, 0.38)
	var worn = surface("worn_steel", Color("67716f"), 0.88, 0.34)
	var sight = surface("sight", Color("252b2b"), 0.35, 0.78)
	var black = surface("bore", Color("070909"), 0.05, 0.95)
	var brass = surface("brass", Color("ac8750"), 0.72, 0.37)
	# Stock, from butt (z -0.72) to the fore-end tip; each row is one elliptical section.
	loft(root, [
		[-0.720, 0.000, 0.019, 0.021], [-0.700, -0.002, 0.023, 0.026],
		[-0.600, -0.005, 0.025, 0.030], [-0.430, -0.008, 0.027, 0.032],
		[-0.270, -0.011, 0.028, 0.034], [-0.100, -0.013, 0.032, 0.036],
		[0.075, -0.018, 0.032, 0.039], [0.145, -0.035, 0.027, 0.031],
		[0.195, -0.052, 0.023, 0.030], [0.250, -0.066, 0.027, 0.055],
		[0.305, -0.070, 0.031, 0.074], [0.410, -0.073, 0.033, 0.078]
	], wood)
	# Thin steel band at the fore-end tip.
	loft(root, [[0.410,-0.073,0.0335,0.0785],[0.417,-0.073,0.034,0.079]], steel)
	# Receiver and exposed, tapered barrel. The complete rifle is about 1.3 metres.
	# Receiver and exposed, tapered barrel. The complete rifle is about 1.3 metres.
	cylinder(root, 0.024, 0.215, Vector3(0,0.031,-0.145), steel)
	var barrel = CylinderMesh.new()
	barrel.bottom_radius = 0.018
	barrel.top_radius = 0.0115
	barrel.height = 0.660
	barrel.radial_segments = 32
	mesh(root, barrel, Vector3(0,0.037,-0.560), steel).rotation.x = -PI/2
	# Dark disc at the muzzle suggests the bore.
	cylinder(root, 0.007, 0.001, Vector3(0,0.037,-0.891), black)
	# Wooden hand guard above the barrel and two steel barrel bands.
	loft(root, [[-0.624,0.028,0.024,0.016],[-0.600,0.029,0.027,0.017],[-0.340,0.033,0.028,0.017]], wood)
	for z in [-0.699, -0.496]:
		loft(root, [[z-0.009,0.005,0.029,0.044],[z+0.009,0.005,0.029,0.044]], steel)
	# Ejection opening, rails and a movable bolt with a straight M91 handle.
	# Ejection opening, rails and a movable bolt with a straight M91 handle.
	plate(root, PackedVector2Array([Vector2(-0.022,0.010),Vector2(0.022,0.010),Vector2(0.022,0.038),Vector2(-0.022,0.038)]),0.12,Vector3(0,0,-0.004),black)
	for x in [-0.022,0.022]: cylinder(root,0.006,0.185,Vector3(x,0.036,0.014),steel)
	# The bolt is its own node so the player script can slide it back and forth.
	var bolt = Node3D.new()
	bolt.name = "Bolt"
	bolt.position = Vector3(0,0.038,0.045)
	root.add_child(bolt)
	cylinder(bolt,0.014,0.168,Vector3(0,0,-0.035),worn)
	segment(bolt,Vector3(0.010,0,0.016),Vector3(0.076,-0.007,0.016),0.007,worn)
	var knob = SphereMesh.new()
	knob.radius=0.014
	knob.height=0.028
	knob.radial_segments=24
	knob.rings=12
	mesh(bolt,knob,Vector3(0.078,-0.007,0.016),steel)
	# Tangent sight leaf and elevation slider, low enough to see through the notch.
	# Tangent sight leaf and elevation slider, low enough to see through the notch.
	plate(root,PackedVector2Array([Vector2(-0.013,0.048),Vector2(0.013,0.048),Vector2(0.011,0.059),Vector2(-0.011,0.059)]),0.147,Vector3(0,0,-0.306),steel)
	plate(root,PackedVector2Array([Vector2(-0.017,0.055),Vector2(0.017,0.055),Vector2(0.017,0.066),Vector2(-0.017,0.066)]),0.016,Vector3(0,0,-0.290),worn)
	# The open V is not filled by a box or a receiver surface behind it.
	# The open V is not filled by a box or a receiver surface behind it.
	var notch = PackedVector2Array([
		Vector2(-0.013,0.066),Vector2(0.013,0.066),Vector2(0.013,0.077),Vector2(0.010,SIGHT_HEIGHT),
		Vector2(0.0040,SIGHT_HEIGHT),Vector2(0,0.075),Vector2(-0.0040,SIGHT_HEIGHT),Vector2(-0.010,SIGHT_HEIGHT),Vector2(-0.013,0.077)
	])
	plate(root,notch,0.007,Vector3(0,0,REAR_SIGHT_Z),sight).name="RearNotch"
	# Front sight base and blade.
	cylinder(root,0.016,0.024,Vector3(0,0.037,FRONT_SIGHT_Z),steel)
	var post = PackedVector2Array([Vector2(-0.007,0.050),Vector2(0.007,0.050),Vector2(0.0022,SIGHT_HEIGHT),Vector2(-0.0022,SIGHT_HEIGHT)])
	plate(root,post,0.010,Vector3(0,0,FRONT_SIGHT_Z),sight).name="FrontBlade"
	# Markers used by the player for aiming and for spawning bullets and muzzle flash.
	for entry in [["SightLine",Vector3(0,SIGHT_HEIGHT,FRONT_SIGHT_Z)],["RearSightLine",Vector3(0,SIGHT_HEIGHT,REAR_SIGHT_Z)],["Muzzle",Vector3(0,0.037,-0.894)]]:
		var marker=Marker3D.new()
		marker.name=entry[0]
		marker.position=entry[1]
		root.add_child(marker)
	# Magazine body and rounded trigger guard rather than a solid rectangular lump.
	# Magazine body and rounded trigger guard rather than a solid rectangular lump.
	loft(root,[[-0.073,-0.051,0.021,0.039],[-0.059,-0.053,0.023,0.041],[0.019,-0.053,0.023,0.041],[0.027,-0.051,0.021,0.039]],steel,16)
	var guard_points = [Vector3(0,-0.040,0.035),Vector3(0,-0.077,0.043),Vector3(0,-0.089,0.061),Vector3(0,-0.087,0.112),Vector3(0,-0.062,0.139),Vector3(0,-0.042,0.134)]
	for i in range(guard_points.size()-1): segment(root,guard_points[i],guard_points[i+1],0.004,steel)
	segment(root,Vector3(0,-0.038,0.058),Vector3(0,-0.069,0.079),0.0035,worn)
	# A visible six-round en-bloc clip for the short reload animation.
	# A visible six-round en-bloc clip for the short reload animation.
	var clip = Node3D.new()
	clip.name="ReloadClip"
	root.add_child(clip)
	for side in [-1.0,1.0]:
		plate(clip,PackedVector2Array([Vector2(-0.001,-0.022),Vector2(0.001,-0.022),Vector2(0.001,0.023),Vector2(-0.001,0.023)]),0.042,Vector3(side*0.012,0,0.008),worn)
	# Six brass cartridges with bullets, stacked in a staggered pattern; the clip starts hidden.
	for i in range(6):
		var pos = Vector3(-0.0048 if i%2==0 else 0.0048,float(i/2)*0.010-0.008,-0.004)
		cylinder(clip,0.0042,0.047,pos,brass,12)
		cylinder(clip,0.0031,0.019,pos+Vector3(0,0,-0.031),worn,12)
	clip.visible=false
	return root
