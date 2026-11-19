## Destructible wall/hull panel for Omaha (landing craft plating, concrete,
## sandbags, masonry town walls): a Prop with per-panel integrity and
## batching support.
##
## Role: created by the Omaha world and boat builders, which set the flags.
## Visuals may be merged into MultiMeshes for speed; the first real damage
## "unbatches" the panel back into its own mesh so it can be carved.
## `structure` (if set) is told to re-check its supports so unsupported walls
## and roofs collapse (check_supports).
## Damage rules: protected concrete only takes explosive damage (25%); other
## materials take 100% explosive, 80% hull-panel, 12% masonry or 40% other.
extends "res://scripts/ardennes/prop.gd"
# Each hull panel has its own wear. Concrete keeps its ballistic strength;
# thin landing-craft plating becomes penetrable before a panel fails.

## Remaining hit points of the panel.
var integrity:float=900

## Starting integrity; used to decide when a hull panel becomes penetrable.
var max_integrity:float=900

## True when bullets can pass through the (damaged) plate.
var penetrable:bool=false

## True for bunker concrete: only explosions hurt it.
var protected_concrete:bool=false

## True for landing-craft hull plates, which report hits to their boat.
var hull_panel:bool=false

## Building or craft that owns this panel and re-checks its supports after damage.
var structure

## Data {mesh, material, transform} to rebuild an individual visual when leaving a batch.
var render_source:Dictionary={}

## MultiMesh the panel's visual currently lives in, or null.
var render_batch:MultiMesh

## Slot in render_batch.
var render_index:int=-1

## Position used to collapse the batched instance.
var render_origin=Vector3.ZERO

## Hides the batched visual, runs the Prop demolition, then asks the structure
## to check whether anything above or beside it lost its support.
func demolish():
	if destroyed:return
	if render_batch!=null:render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),render_origin))
	super.demolish()
	if is_instance_valid(structure):structure.check_supports()

## Registers a hit using the rules in the class comment and returns true.
## [param amount] damage points. [param point] hit position. [param _radius] hole size basis. [param explosive] true for blasts.
## Thin batched town walls turn into editable pieces at the first heavy (>= 95) explosion; masonry, wood and sandbags are carved once their
## local cell (0.6 m) has taken 320 (masonry) or 85 damage or any explosion hits.
## Hull panels also count hits for their vehicle and become penetrable below 64% integrity.
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

## Darkens the panel the first time it is hurt enough to be penetrable, and marks the actual opening as passable.
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

## Removes the panel's instance from its shared MultiMesh and gives it its own mesh, so it can be carved without leaving a ghost.
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

## Performs a queued cut after leaving the batch, then re-checks the structure's supports.
func commit_cut(point:Vector3,radius:float):
	unbatch()
	super.commit_cut(point,radius)
	if is_instance_valid(structure):structure.check_supports()
