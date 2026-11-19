# ==============================================================================
# Program: breakable.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for breakable.gd.
# ==============================================================================
## Base class for every destructible static object (walls, sandbags, doors, trees, soil).
##
## Damage accumulates per 0.65 m cell of the object; when a cell exceeds the
## material's resistance, a spherical hole is cut. Thin wood/cloth/sandbag/masonry boxes
## are cut cheaply by splitting the box into smaller boxes (`fast_box_cut`); everything
## else goes through a temporary CSG boolean (`rebuild`) which is baked back into a normal
## mesh and collision shape. The Ardennes `prop.gd` extends this; the world script
## (group "battle_world") is notified through `geometry_updated()` so AI navigation refreshes.
## Receives damage through `damage_at()`; `demolish()` removes the object outright.
extends StaticBody3D

# Geometry is static between impacts. Only edited objects enter a temporary CSG
# operation; its result is immediately baked back to meshes and collision.
## Emitted after the mesh or collision changed (hole cut, destroyed) so doors, navigation and AI can react.
# Geometry is static between impacts. Only edited objects enter a temporary CSG
# operation; its result is immediately baked back to meshes and collision.
signal geometry_changed

# Key into RESISTANCE (and into prop.gd failure thresholds); set by whoever builds the object.
var material_kind: String = "wood"

# Cell (Vector3i of local position / 0.65 m) -> damage accumulated there since its last cut.
var damaged_cells: Dictionary = {}

# Cuts queued for the next rebuild: {point (local), radius}.
var pending_cuts: Array = []

# True while an asynchronous rebuild coroutine is running; stops overlapping rebuilds.
var rebuilding: bool = false

# Object has been completely removed.
var destroyed: bool = false

# Total holes made; fast_box_cut stops cutting once this reaches 12.
var cuts_completed: int = 0

# Local-space bounding box of visible meshes; cached and invalidated when geometry changes.
var bounds: AABB
var bounds_valid: bool = false

# Volume of the first computed bounds, kept as the reference for how intact the object is.
var original_volume: float = 0

# Damage needed to cut one cell, per material. Higher means tougher: rock 250, metal 160, masonry 95, soil 8.
const RESISTANCE = {"soil":8.0,"cloth":5.0,"wood":24.0,"sandbag":42.0,"masonry":95.0,"rock":250.0,"metal":160.0}

## Register in the "breakable" group and put the body on the world collision layer.
func _ready():
	add_to_group("breakable")
	# Layer 1 is the world; mask 0 because this body only receives hits, it never detects.
	collision_layer = 1
	collision_mask = 0

## Collect the visible mesh instances that make up this object.
## @param node Subtree root; defaults to this object.
## @return MeshInstance3D nodes, skipping colliders, "inventory_visual" decorations and CSG helpers.
func owned_meshes(node: Node = self) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is CollisionObject3D or child.is_in_group("inventory_visual"): continue
		if child is MeshInstance3D and child.is_visible_in_tree() and child.mesh:
			result.append(child)
		elif not child is CSGShape3D:
			result.append_array(owned_meshes(child))
	return result

## Recompute `bounds` from the meshes (in this object's local space).
func refresh_bounds():
	var meshes = owned_meshes()
	var first = true
	for item in meshes:
		# Mesh AABB transformed into local space; merging gives the whole object's box.
		var local = global_transform.affine_inverse()*item.global_transform
		var box = local*item.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	# No visible meshes means no valid bounds.
	bounds_valid = not first
	if original_volume==0 and bounds_valid: original_volume=bounds.get_volume()

## Distance from a world point to the object's bounding box.
## @return Metres, or INF when the object has no geometry. Used to find which props a blast reaches.
func distance_to_surface(point: Vector3) -> float:
	if not bounds_valid: refresh_bounds()
	if not bounds_valid: return INF
	# Clamp the point into the box to find the nearest box point.
	var local=to_local(point)
	var nearest=local.clamp(bounds.position,bounds.end)
	return point.distance_to(to_global(nearest))

## Apply damage and cut a hole when a cell has absorbed enough.
##
## @param amount Damage points.
## @param point World impact point.
## @param radius Hole radius for bullets (metres).
## @param explosive Explosions cut bigger holes.
## @return true when a hole was cut, false when the damage was only absorbed.
func damage_at(amount: float, point: Vector3, radius: float = 0.24, explosive: bool = false) -> bool:
	if destroyed: return false
	var resistance: float = RESISTANCE.get(material_kind,95.0)
	# 0.65 m grid cells so repeated hits at the same spot add up, but far-away hits do not.
	var cell=Vector3i((to_local(point)/0.65).floor())
	damaged_cells[cell]=damaged_cells.get(cell,0.0)+amount
	if damaged_cells[cell]<resistance: return false
	# Reset the cell after cutting so the same spot needs full damage again for the next hole.
	damaged_cells[cell]=0.0
	var size=radius
	if explosive:
		size*=clampf(sqrt(amount/resistance)*0.60,0.28,1.35)
	elif material_kind=="rock":
		# Rock holes are smaller (65%) so bullets only chip it.
		size*=0.65
	carve(point,size)
	return true

## Queue a spherical hole at a world point.
## @param point World position of the hole centre.
## @param radius Hole radius in metres (at least 0.07).
func carve(point: Vector3, radius: float):
	if destroyed: return
	pending_cuts.append({"point":to_local(point),"radius":maxf(0.07,radius)})
	# Batch many cuts in the same frame into one CSG rebuild.
	if not rebuilding:
		rebuilding=true
		call_deferred("rebuild")

## Apply queued cuts using a temporary CSG tree and bake the result back.
##
## Coroutine: waits for frames, so the CSG node has time to compute. Runs until the queue is empty.
func rebuild():
	while not pending_cuts.is_empty() and is_inside_tree() and not destroyed:
		# Take all queued cuts now; new ones arriving during the awaits form the next batch.
		var batch=pending_cuts.duplicate()
		pending_cuts.clear()
		var meshes=owned_meshes()
		if meshes.is_empty(): break
		# Existing meshes become CSG sources so the cut works on the real current shape.
		var work=CSGCombiner3D.new()
		work.name="GeometryWork"
		work.visible=false
		work.calculate_tangents=false
		add_child(work)
		var cut_material: Material
		for original in meshes:
			var source=CSGMesh3D.new()
			source.mesh=original.mesh
			source.material=original.material_override
			work.add_child(source)
			source.transform=global_transform.affine_inverse()*original.global_transform
			# Cut surfaces reuse the first material found so holes do not show a default grey interior.
			if not cut_material:
				cut_material=original.material_override
				if not cut_material and original.mesh.get_surface_count()>0:
					cut_material=original.mesh.surface_get_material(0)
		for cut in batch:
			# Each cut is a subtracted sphere; 16x8 segments keep the boolean cheap.
			var tool=CSGSphere3D.new()
			tool.operation=CSGShape3D.OPERATION_SUBTRACTION
			tool.radius=cut.radius
			tool.radial_segments=16
			tool.rings=8
			tool.material=cut_material
			work.add_child(tool)
			tool.position=cut.point
		# CSG results are computed asynchronously by the engine; two frames of waiting lets it finish.
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_inside_tree(): return
		# Bake geometry and collision from the CSG tree, then drop the tree.
		var result=work.bake_static_mesh()
		var collision=work.bake_collision_shape()
		work.queue_free()
		# Nothing left means the object was cut away entirely.
		if result==null or result.get_surface_count()==0:
			destroyed=true
			collision_layer=0
			hide()
		else:
			# Replace old meshes and colliders with the baked result.
			for original in meshes:
				original.hide()
				original.queue_free()
			for child in get_children():
				if child is CollisionShape3D:
					# Disable first (deferred) so physics does not use a shape that is about to be freed.
					child.set_deferred("disabled",true)
					child.queue_free()
			var visual=MeshInstance3D.new()
			visual.mesh=result
			add_child(visual)
			var shape=CollisionShape3D.new()
			shape.shape=collision
			add_child(shape)
		# Invalidate cached bounds and tell listeners (navigation) the shape changed.
		cuts_completed+=batch.size()
		bounds_valid=false
		geometry_changed.emit()
		var worlds=get_tree().get_nodes_in_group("battle_world")
		if not worlds.is_empty(): worlds[0].geometry_updated(global_position)
		# Let a physics frame pass so collisions update before the next batch.
		await get_tree().physics_frame
	rebuilding=false

## Remove the whole object immediately (no cutting).
func demolish():
	if destroyed:return
	destroyed=true
	# Stop collisions at once; hide the visuals.
	collision_layer=0
	hide()
	geometry_changed.emit()
	var worlds=get_tree().get_nodes_in_group("battle_world")
	if not worlds.is_empty(): worlds[0].geometry_updated(global_position)
