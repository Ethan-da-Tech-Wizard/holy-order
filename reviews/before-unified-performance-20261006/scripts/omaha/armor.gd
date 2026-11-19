## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/omaha/armor.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
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
var render_batch:MultiMesh
var render_index:int=-1

func demolish():
	if render_batch!=null:render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),global_position))
	super.demolish()

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
		if explosive:integrity-=amount*0.25
	else:integrity-=amount*(1.0 if explosive else 0.8)
	if hull_panel:
		truck_owner.bullet_hits+=1
		truck_owner.total_damage+=amount
		penetrable=integrity<max_integrity*0.64
		if penetrable:modulate_damage()
	if integrity<=0:demolish()
	return true

## Darkens the panel the first time it is hurt enough to be penetrable, and marks the actual opening as passable.
func modulate_damage():
	if has_meta("scarred"):return
	set_meta("scarred",true)
	for mesh in owned_meshes():
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override=mesh.material_override.duplicate()
			mesh.material_override.albedo_color=Color("4d5048")
	# Actual visual and ballistic openings are local to this damaged panel.
	if hull_panel:penetrable=true
