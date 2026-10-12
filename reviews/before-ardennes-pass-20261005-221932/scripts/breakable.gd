extends StaticBody3D

# Geometry is static between impacts. Only edited objects enter a temporary CSG
# operation; its result is immediately baked back to meshes and collision.
signal geometry_changed
var material_kind: String = "wood"
var damaged_cells: Dictionary = {}
var pending_cuts: Array = []
var rebuilding: bool = false
var destroyed: bool = false
var cuts_completed: int = 0
var bounds: AABB
var bounds_valid: bool = false
var original_volume: float = 0
const RESISTANCE = {"soil":8.0,"cloth":5.0,"wood":24.0,"sandbag":42.0,"masonry":95.0,"rock":250.0,"metal":160.0}

func _ready():
	add_to_group("breakable")
	collision_layer = 1
	collision_mask = 0

func owned_meshes(node: Node = self) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is CollisionObject3D or child.is_in_group("inventory_visual"): continue
		if child is MeshInstance3D and child.is_visible_in_tree() and child.mesh:
			result.append(child)
		elif not child is CSGShape3D:
			result.append_array(owned_meshes(child))
	return result

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

func distance_to_surface(point: Vector3) -> float:
	if not bounds_valid: refresh_bounds()
	if not bounds_valid: return INF
	var local=to_local(point)
	var nearest=local.clamp(bounds.position,bounds.end)
	return point.distance_to(to_global(nearest))

func damage_at(amount: float, point: Vector3, radius: float = 0.24, explosive: bool = false) -> bool:
	if destroyed: return false
	var resistance: float = RESISTANCE.get(material_kind,95.0)
	var cell=Vector3i((to_local(point)/0.65).floor())
	damaged_cells[cell]=damaged_cells.get(cell,0.0)+amount
	if damaged_cells[cell]<resistance: return false
	damaged_cells[cell]=0.0
	var size=radius
	if explosive:
		size*=clampf(sqrt(amount/resistance)*0.60,0.28,1.35)
	elif material_kind=="rock":
		size*=0.65
	carve(point,size)
	return true

func carve(point: Vector3, radius: float):
	if destroyed: return
	pending_cuts.append({"point":to_local(point),"radius":maxf(0.07,radius)})
	if not rebuilding:
		rebuilding=true
		call_deferred("rebuild")

func rebuild():
	while not pending_cuts.is_empty() and is_inside_tree() and not destroyed:
		var batch=pending_cuts.duplicate()
		pending_cuts.clear()
		var meshes=owned_meshes()
		if meshes.is_empty(): break
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
		geometry_changed.emit()
		var worlds=get_tree().get_nodes_in_group("battle_world")
		if not worlds.is_empty(): worlds[0].geometry_updated(global_position)
		await get_tree().physics_frame
	rebuilding=false

func demolish():
	if destroyed:return
	destroyed=true
	collision_layer=0
	hide()
	geometry_changed.emit()
	var worlds=get_tree().get_nodes_in_group("battle_world")
	if not worlds.is_empty(): worlds[0].geometry_updated(global_position)
