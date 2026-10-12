extends "res://scripts/ardennes/prop.gd"
# Each hull panel has its own wear. Concrete keeps its ballistic strength;
# thin landing-craft plating becomes penetrable before a panel fails.
var integrity:float=900
var max_integrity:float=900
var penetrable:bool=false
var protected_concrete:bool=false
var hull_panel:bool=false
var render_batch:MultiMesh
var render_index:int=-1
var render_origin=Vector3.ZERO

func demolish():
	if render_batch!=null:render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),render_origin))
	super.demolish()

func damage_at(amount:float,point:Vector3,_radius:float=0.24,explosive:bool=false)->bool:
	if destroyed:return false
	wear+=amount
	bullet_mark(point)
	if protected_concrete:
		if explosive:
			integrity-=amount*0.25
			if get_meta("thin_wall",false) and amount>=95:
				# Batched town walls become small editable pieces at the first breach.
				if render_batch!=null:
					render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),render_origin))
					render_batch=null
					for child in get_children():
						if child is MeshInstance3D:child.show()
				carve(point,clampf(_radius*0.60,0.40,0.85))
	else:integrity-=amount*(1.0 if explosive else 0.8)
	if hull_panel:
		truck_owner.bullet_hits+=1
		truck_owner.total_damage+=amount
		penetrable=integrity<max_integrity*0.64
		if penetrable:modulate_damage()
	if integrity<=0:demolish()
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
