extends "res://scripts/breakable.gd"

var battle_world
var tree_health:float=0
var is_tree:bool=false
var wear:float=0
var truck_owner
var marks:MultiMeshInstance3D
var marks_used:int=0
static var mark_mesh:SphereMesh
static var mark_material:StandardMaterial3D

func damage_at(amount:float,point:Vector3,radius:float=0.24,explosive:bool=false)->bool:
	if destroyed:return false
	if material_kind=="soil" and not explosive and radius<0.3:return false
	wear+=amount
	if truck_owner!=null:
		truck_owner.receive_part_damage(amount,point,explosive,self)
		if has_meta("wheel_index"):
			bullet_mark(point)
			return true
	if is_tree:
		tree_health-=amount
		if tree_health<=0:
			battle_world.fell_tree(self)
			return true
	elif material_kind!="soil":
		var failure={"wood":420.0,"cloth":400.0,"sandbag":820.0,"rock":1900.0,"metal":1400.0}.get(material_kind,900.0)
		if wear>=failure:
			demolish()
			return true
	if not explosive and radius<0.3:
		bullet_mark(point)
		# Passenger panels already permit ballistic penetration. Ordinary bullet
		# marks are instanced; don't run a mesh boolean for every automatic round.
		if truck_owner!=null:return true
		var cell=Vector3i((to_local(point)/0.65).floor())
		damaged_cells[cell]=damaged_cells.get(cell,0.0)+amount
		if damaged_cells[cell]<float(RESISTANCE.get(material_kind,95.0))*4 or cuts_completed>=8:return true
		damaged_cells[cell]=0
		carve(point,maxf(0.23,radius))
		return true
	return super.damage_at(amount,point,radius,explosive)

func bullet_mark(point:Vector3):
	if marks_used>=32:return
	if marks==null:
		if mark_mesh==null:
			mark_mesh=SphereMesh.new()
			mark_mesh.radius=0.028
			mark_mesh.height=0.056
			mark_mesh.radial_segments=6
			mark_mesh.rings=3
			mark_material=StandardMaterial3D.new()
			mark_material.albedo_color=Color("171a18")
			mark_material.roughness=1
			mark_mesh.material=mark_material
		marks=MultiMeshInstance3D.new()
		marks.add_to_group("inventory_visual")
		marks.multimesh=MultiMesh.new()
		marks.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		marks.multimesh.mesh=mark_mesh
		marks.multimesh.instance_count=32
		marks.multimesh.visible_instance_count=0
		marks.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marks)
	marks.multimesh.set_instance_transform(marks_used,Transform3D(Basis.IDENTITY,to_local(point)))
	marks_used+=1
	marks.multimesh.visible_instance_count=marks_used

func carve(point:Vector3,radius:float):
	if destroyed:return
	if battle_world!=null:battle_world.queue_cut(self,point,radius)
	else:super.carve(point,radius)

func commit_cut(point:Vector3,radius:float):
	if material_kind=="soil" and battle_world!=null:battle_world.deform_ground(self,point,radius)
	else:super.carve(point,radius)
