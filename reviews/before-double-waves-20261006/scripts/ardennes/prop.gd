# ==============================================================================
# Program: prop.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for prop.gd.
# ==============================================================================
## Generic destructible world prop (tree, wall, sandbag, crate, truck part, soil).
##
## Built on breakable.gd. Adds material-specific wear thresholds, tree felling,
## cheap instanced bullet marks and routing of cuts/craters through the Ardennes
## battle world, which batches terrain edits. Truck panels (armored_panel.gd,
## armor.gd) extend this. Receives damage through `damage_at()`.
extends "res://scripts/breakable.gd"

# The Ardennes battle controller; queued cuts and ground deformation go through it.
var battle_world

# Hit points left for a tree; only used when `is_tree`.
var tree_health:float=0
var is_tree:bool=false

# Accumulated damage; compared with a per-material failure limit.
var wear:float=0

# Owning truck if this is a vehicle part, so damage is reported upward.
var truck_owner

# Shared MultiMesh of up to 8 bullet marks on this prop.
var marks:MultiMeshInstance3D
var marks_used:int=0

# Static caches so all props share one mark mesh and material instead of building their own.
static var mark_mesh:SphereMesh
static var mark_material:StandardMaterial3D

## Apply damage from a bullet (small radius) or blast.
##
## @param amount Damage points.
## @param point World hit position.
## @param radius Impact radius in metres; under 0.3 counts as a bullet.
## @param explosive true for grenades, shells and similar.
## @return true if the hit was handled here, false if destroyed already.
func damage_at(amount:float,point:Vector3,radius:float=0.24,explosive:bool=false)->bool:
	if destroyed:return false
	# Rifle fire cannot dig soil; only explosions deform terrain.
	if material_kind=="soil" and not explosive and radius<0.3:return false
	# Wear persists across hits so many small hits can still destroy a prop.
	wear+=amount
	if truck_owner!=null:
		truck_owner.receive_part_damage(amount,point,explosive,self)
		# Wheels just show a mark and the truck handles their damage.
		if has_meta("wheel_index"):
			bullet_mark(point)
			return true
	# Trees fall after enough total damage; the world animates the fall.
	if is_tree:
		tree_health-=amount
		if tree_health<=0:
			battle_world.fell_tree(self)
			return true
	# Failure thresholds in wear points per material (rock takes most, cloth and wood least).
	elif material_kind!="soil":
		var failure={"wood":420.0,"cloth":400.0,"sandbag":820.0,"rock":1900.0,"metal":1400.0}.get(material_kind,900.0)
		if wear>=failure:
			demolish()
			return true
	# Bullets leave a decal and never carve geometry.
	if not explosive and radius<0.3:
		bullet_mark(point)
		# Passenger panels already permit ballistic penetration. Ordinary bullet
		# marks are instanced; don't run a mesh boolean for every automatic round.
		# Passenger panels already permit ballistic penetration. Ordinary bullet
		# marks are instanced; don't run a mesh boolean for every automatic round.
		if truck_owner!=null:return true
		return true

	# Explosions fall through to the base class, which carves a real hole.
	return super.damage_at(amount,point,radius,explosive)

## Add a bullet-hole decal at a world point.
## @param point World position; converted to local space so the mark follows the prop.
func bullet_mark(point:Vector3):
	# Eight marks per prop is the limit, which bounds memory and draw cost.
	if marks_used>=8:return
	# Lazily create the shared MultiMesh the first time a mark is needed.
	if marks==null:
		if mark_mesh==null:
			mark_mesh=SphereMesh.new()
			# A tiny low-poly sphere (radius 2.8 cm) is cheaper than a decal.
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
		marks.multimesh.instance_count=8
		marks.multimesh.visible_instance_count=0
		marks.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marks)
	marks.multimesh.set_instance_transform(marks_used,Transform3D(Basis.IDENTITY,to_local(point)))
	marks_used+=1
	marks.multimesh.visible_instance_count=marks_used

## Request a hole in the prop.
## @param point World position of the cut centre.
## @param radius Cut radius in metres.
func carve(point:Vector3,radius:float):
	if destroyed:return
	# Route through the world so many cuts in one frame are batched.
	if battle_world!=null:battle_world.queue_cut(self,point,radius)
	else:super.carve(point,radius)

## Apply a queued cut now (called by the world when it processes its cut queue).
func commit_cut(point:Vector3,radius:float):
	# Soil is a terrain mesh and needs heightfield deformation instead of a boolean cut.
	if material_kind=="soil" and battle_world!=null:battle_world.deform_ground(self,point,radius)
	else:super.carve(point,radius)
