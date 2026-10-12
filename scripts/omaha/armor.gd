extends "res://scripts/ardennes/prop.gd"
# Each hull panel has its own wear. Concrete keeps its ballistic strength;
# thin landing-craft plating becomes penetrable before a panel fails.
var integrity:float=900
var max_integrity:float=900
var penetrable:bool=false
var protected_concrete:bool=false
var hull_panel:bool=false
var structure
var render_source:Dictionary={}
var render_batch:MultiMesh
var render_index:int=-1
var render_origin=Vector3.ZERO

func demolish():
	if destroyed:return
	if render_batch!=null:render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),render_origin))
	super.demolish()
	if is_instance_valid(structure):structure.check_supports()

func damage_at(amount:float,point:Vector3,_radius:float=0.24,explosive:bool=false)->bool:
	if destroyed:return false
	wear+=amount
	bullet_mark(point)
	if protected_concrete:
		if explosive:
			integrity-=amount*0.25
			if get_meta("thin_wall",false) and amount>=95:
				# Batched town walls become small editable pieces at the first breach.
				unbatch()
				carve(point,clampf(_radius*0.60,0.40,0.85))
	else:
		integrity-=amount*(1.0 if explosive else (0.8 if hull_panel else (0.12 if material_kind=="masonry" else 0.4)))
		if material_kind in ["masonry","wood","sandbag"]:
			var cell=Vector3i((to_local(point)/0.6).floor())
			damaged_cells[cell]=damaged_cells.get(cell,0.0)+amount
			var threshold=320 if material_kind=="masonry" else 85
			if explosive or damaged_cells[cell]>=threshold:
				damaged_cells[cell]=0.0
				unbatch()
				carve(point,clampf(_radius*(0.62 if explosive else 1.9),0.30,0.85))
	if hull_panel:
		truck_owner.bullet_hits+=1
		truck_owner.total_damage+=amount
		penetrable=integrity<max_integrity*0.64
		if penetrable:modulate_damage()
	if integrity<=0:demolish()
	elif is_instance_valid(structure):structure.check_supports()
	return true

func modulate_damage():
	if has_meta("scarred"):return
	set_meta("scarred",true)
	if render_batch!=null and render_batch.use_colors:render_batch.set_instance_color(render_index,Color(0.50,0.52,0.48))
	for mesh in owned_meshes():
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override=mesh.material_override.duplicate()
			mesh.material_override.albedo_color=Color("4d5048")
	# Actual visual and ballistic openings are local to this damaged panel.
	if hull_panel:penetrable=true

func unbatch():
	if render_batch==null:return
	render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),render_origin))
	render_batch=null
	if not render_source.is_empty():
		var visual=MeshInstance3D.new()
		visual.mesh=render_source.mesh
		visual.material_override=render_source.material
		visual.transform=render_source.transform
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
		render_source.clear()
	for child in get_children():
		if child is MeshInstance3D:child.show()

func commit_cut(point:Vector3,radius:float):
	unbatch()
	super.commit_cut(point,radius)
	if is_instance_valid(structure):structure.check_supports()
