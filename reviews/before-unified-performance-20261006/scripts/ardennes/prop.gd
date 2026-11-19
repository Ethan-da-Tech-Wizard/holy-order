## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/ardennes/prop.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Battlefield prop for Ardennes/Omaha: a Breakable extended with trees,
## cumulative wear, bullet marks and routing of expensive edits through the
## battle world.
##
## Differences from the base Breakable:
##   - damage accumulates in `wear` and destroys the object when it passes a
##     material-specific failure value, instead of carving a hole;
##   - bullets leave cheap instanced marks (max 8) instead of triggering CSG;
##   - carves are queued on `battle_world` so the world can spread them over
##     frames; soil changes go to its ground deformation.
## Also the base for armored_panel.gd and parts of vehicles (truck_owner).
extends "res://scripts/breakable.gd"

## The world node (ardennes/world.gd or omaha/world.gd) offering queue_cut,
## deform_ground and fell_tree; null in tests.
var battle_world

## Remaining damage before a tree falls.
var tree_health:float=0

## True for tree trunks: they fall (battle_world.fell_tree) instead of breaking.
var is_tree:bool=false

## Total damage taken, compared against a per-material failure value.
var wear:float=0

## Vehicle this prop belongs to (receives damage reports), or null.
var truck_owner

## MultiMesh of bullet marks on this prop.
var marks:MultiMeshInstance3D

## Marks drawn so far (max 8).
var marks_used:int=0

## Shared tiny sphere used for every bullet mark.
static var mark_mesh:SphereMesh

## Shared near-black material for marks.
static var mark_material:StandardMaterial3D

## Applies damage: ignores small hits on soil, adds wear, reports to the
## owning vehicle, drops trees at zero tree_health, destroys other materials
## at their failure value (wood 420, cloth 400, sandbag 820, rock 1900, metal
## 1400, default 900), draws bullet marks for small hits, and otherwise
## falls back to the base carving.
## [param amount] damage points. [param point] world hit point.
## [param radius] hit size; below 0.3 m is a bullet. [param explosive] blast flag.
## Returns true if the hit was consumed.
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

	# Bullets leave a mark and stop here: a full CSG carve per automatic round
	# would be far too slow.
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

## Draws a small dark dot at `point`. The MultiMesh is created lazily with 8
## instances; beyond that no more marks are added. Marked "inventory_visual"
## so carving does not treat it as part of the solid.
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

## Routes a cut through the battle world's queue so many cuts per frame are
## spread out; falls back to the base class when there is no world.
func carve(point:Vector3,radius:float):
	if destroyed:return
	if battle_world!=null:battle_world.queue_cut(self,point,radius)
	else:super.carve(point,radius)

## Executes a queued cut: soil deforms the terrain, everything else is carved
## by the base class.
func commit_cut(point:Vector3,radius:float):
	if material_kind=="soil" and battle_world!=null:battle_world.deform_ground(self,point,radius)
	else:super.carve(point,radius)
