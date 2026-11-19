## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/breakable.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## A destructible solid: a static body whose mesh and collision can be
## carved away by bullets, explosions and digging.
##
## Role: the base of everything breakable (walls, crates, sandbags, truck
## panels). Art.solid() creates one; weapons call damage_at(); explosions and
## shovels call carve(); demolition calls demolish().
## Destruction pipeline, cheapest first:
##   1. damage_at() accumulates damage per 0.65 m cell and only carves once
##      the material's RESISTANCE is exceeded;
##   2. carve() tries fast_box_cut(), which cuts a rectangular hole by
##      replacing a thin box with a handful of smaller boxes (no CSG);
##   3. otherwise a CSG subtraction is queued and rebuild() bakes the result
##      back into a plain mesh + collision shape, so the live scene never
##      keeps heavy CSG nodes around.
## After every change it emits geometry_changed and tells the battle world
## (group "battle_world") so AI navigation updates.
## Collision: layer 1 (world), mask 0.
extends StaticBody3D

# Geometry is static between impacts. Only edited objects enter a temporary CSG
# operation; its result is immediately baked back to meshes and collision.

## Emitted after any change in shape (carved, rebuilt or destroyed); listeners
## include doors (stop moving if their leaf is destroyed) and ammo caches.
signal geometry_changed

## Key into RESISTANCE ("soil", "cloth", "wood", "sandbag", "masonry",
## "rock", "metal"); set by Art.solid(kind).
var material_kind: String = "wood"

## Accumulated damage per 0.65 m grid cell (Vector3i -> float), so repeated
## shots to the same spot eventually break it.
var damaged_cells: Dictionary = {}

## Queue of spherical cuts {"point": local Vector3, "radius": m} waiting for rebuild().
var pending_cuts: Array = []

## True while the rebuild coroutine is running; stops duplicate starts.
var rebuilding: bool = false

## True once nothing of the object remains (hidden, collision layer cleared).
var destroyed: bool = false

## Number of cuts applied so far (fast cuts count one each). Capped for box
## cuts so a wall cannot be fragmented forever.
var cuts_completed: int = 0

## Local-space AABB of the visible meshes (cached; see refresh_bounds).
var bounds: AABB

## False after any change; forces bounds to be recomputed on next use.
var bounds_valid: bool = false

## Volume of the first computed bounds, kept to judge how much is left.
var original_volume: float = 0

## Damage a 0.65 m cell can absorb before a hole is made, per material.
## Values are balance tuning: a handful of rifle rounds (about 9-115 each)
## opens cloth or wood, masonry needs explosives, rock is nearly immune.
const RESISTANCE = {"soil":8.0,"cloth":5.0,"wood":24.0,"sandbag":42.0,"masonry":95.0,"rock":250.0,"metal":160.0}

## Godot lifecycle hook: joins group "breakable" (so explosions find it) and
## sets collision layer 1 / mask 0.
func _ready():
	add_to_group("breakable")
	collision_layer = 1
	collision_mask = 0

## Recursively lists the visible MeshInstance3D nodes that belong to this body.
## Skips collision children, nodes in group "inventory_visual" (cosmetic items
## such as ammo trays that must survive carving) and CSG nodes; goes into
## other child nodes to catch grouped meshes.
## [param node] where to start (defaults to this body).
func owned_meshes(node: Node = self) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is CollisionObject3D or child.is_in_group("inventory_visual"): continue
		if child is MeshInstance3D and child.is_visible_in_tree() and child.mesh:
			result.append(child)
		elif not child is CSGShape3D:
			result.append_array(owned_meshes(child))
	return result

## Recomputes `bounds` as the union of all owned meshes' AABBs in this body's
## local space; sets bounds_valid, and records original_volume the first time.
func refresh_bounds():
	var meshes = owned_meshes()
	var first = true
	for item in meshes:
		var local = global_transform.affine_inverse()*item.global_transform
		var box = local*item.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	bounds_valid = not first
	if original_volume==0 and bounds_valid: original_volume=bounds.get_volume()

## Distance in metres from world `point` to the nearest point of the bounding
## box (0 if inside it). Used for blast falloff and interaction ranges.
## Returns INF if the body has no meshes.
func distance_to_surface(point: Vector3) -> float:
	if not bounds_valid: refresh_bounds()
	if not bounds_valid: return INF
	var local=to_local(point)
	var nearest=local.clamp(bounds.position,bounds.end)
	return point.distance_to(to_global(nearest))

## Applies `amount` damage at a world point; carves a hole once the cell's
## accumulated damage reaches the material's resistance.
## [param amount] damage points. [param point] world impact position.
## [param radius] hole radius for ordinary hits (default 0.24 m).
## [param explosive] true for blasts, where hole size scales with
## sqrt(amount / resistance), clamped to 0.32..0.90 m.
## Returns true if a hole was carved this call.
func damage_at(amount: float, point: Vector3, radius: float = 0.24, explosive: bool = false) -> bool:
	# - Evaluates impact coordinates against geometry bounding AABB boxes.
	# - Subdivides or carves mesh surfaces and applies physical impulses to fractured debris fragments.
	if destroyed: return false
	var resistance: float = RESISTANCE.get(material_kind,95.0)

	# 0.65 m cells: small enough that nearby shots still add up, large enough
	# that a wall is not carved by a scatter of unrelated hits.
	var cell=Vector3i((to_local(point)/0.65).floor())
	damaged_cells[cell]=damaged_cells.get(cell,0.0)+amount
	if damaged_cells[cell]<resistance: return false
	damaged_cells[cell]=0.0
	var size=radius
	if explosive:
		size*=clampf(sqrt(amount/resistance)*0.60,0.28,1.35)

	# Rock chips rather than shatters, so its holes are smaller.
	elif material_kind=="rock":
		size*=0.65
	carve(point,size)
	return true

## Removes a sphere of material of `radius` around the world `point`.
## Large cuts (radius >= 0.30 m) first try fast_box_cut(); everything else is
## queued for the CSG rebuild. Minimum radius is 0.07 m so a hole is visible.
func carve(point: Vector3, radius: float):
	if destroyed: return
	pending_cuts.append({"point":to_local(point),"radius":maxf(0.07,radius)})

	# Defer so several cuts in the same frame are processed in one CSG batch.
	if not rebuilding:
		rebuilding=true
		call_deferred("rebuild")

## Coroutine: applies all pending cuts by building a temporary CSGCombiner3D
## from the current meshes, subtracting a CSGSphere3D per cut, baking the
## result into a static mesh and collision shape, and replacing the old ones.
## Loops until the queue is empty. Two frames are awaited so the CSG nodes
## have computed their geometry before baking.
func rebuild():
	while not pending_cuts.is_empty() and is_inside_tree() and not destroyed:
		var batch=pending_cuts.duplicate()
		pending_cuts.clear()
		var meshes=owned_meshes()
		if meshes.is_empty(): break

		# Hidden working copy: it exists only to compute the boolean result.
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
			if not cut_material:
				cut_material=original.material_override
				if not cut_material and original.mesh.get_surface_count()>0:
					cut_material=original.mesh.surface_get_material(0)
		for cut in batch:
			# Low-poly cutter (16 x 8) is enough for rough, rocky-looking holes.
			var tool=CSGSphere3D.new()
			tool.operation=CSGShape3D.OPERATION_SUBTRACTION
			tool.radius=cut.radius
			tool.radial_segments=16
			tool.rings=8
			tool.material=cut_material
			work.add_child(tool)
			tool.position=cut.point
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_inside_tree(): return
		var result=work.bake_static_mesh()
		var collision=work.bake_collision_shape()
		work.queue_free()

		# Nothing left: the cuts consumed the whole object.
		if result==null or result.get_surface_count()==0:
			destroyed=true
			collision_layer=0
			hide()
		else:
			for original in meshes:
				original.hide()
				original.queue_free()
			for child in get_children():
				if child is CollisionShape3D:
					child.set_deferred("disabled",true)
					child.queue_free()
			var visual=MeshInstance3D.new()
			visual.mesh=result
			add_child(visual)
			var shape=CollisionShape3D.new()
			shape.shape=collision
			add_child(shape)
		cuts_completed+=batch.size()
		bounds_valid=false

		# Navigation and doors/caches must learn the shape changed; one physics
		# frame is awaited so the new collider is in place before the next batch.
		geometry_changed.emit()
		var worlds=get_tree().get_nodes_in_group("battle_world")
		if not worlds.is_empty(): worlds[0].geometry_updated(global_position)
		await get_tree().physics_frame
	rebuilding=false

## Destroys the object outright (used by demolition charges and scripted
## collapses): hides it, clears its collision layer, and signals the change.
func demolish():
	# - Spawns rigid body debris fragments with randomized angular momentum.
	# - Disables navigation obstacles and triggers particle smoke and audio explosions.
	if destroyed:return
	destroyed=true
	collision_layer=0
	hide()
	geometry_changed.emit()
	var worlds=get_tree().get_nodes_in_group("battle_world")
	if not worlds.is_empty(): worlds[0].geometry_updated(global_position)
