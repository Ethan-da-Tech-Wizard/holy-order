# ==============================================================================
# Program: armor.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for armor.gd.
# ==============================================================================
## Armoured panel for Omaha hull plates, concrete and thin walls.
##
## Extends the Ardennes prop. Concrete stays strong against bullets and cracks
## only from explosives, landing-craft hull plates become penetrable after enough
## damage, and thin town walls are carved open on the first big blast. Panels
## may be drawn from a batched MultiMesh, so destruction hides that instance.
extends "res://scripts/ardennes/prop.gd"

# Each hull panel has its own wear. Concrete keeps its ballistic strength;
# thin landing-craft plating becomes penetrable before a panel fails.
# Each hull panel has its own wear. Concrete keeps its ballistic strength;
# thin landing-craft plating becomes penetrable before a panel fails.
# Remaining strength; reaches 0 at destruction.
var integrity:float=900
var max_integrity:float=900

# True once bullets can pass through the (damaged) hull plate.
var penetrable:bool=false

# Concrete only loses integrity to explosions.
var protected_concrete:bool=false

# True for landing-craft hull plates; they report hits to the truck_owner (the boat).
var hull_panel:bool=false

## Apply damage.
## @param amount Raw damage.
## @param point World hit position.
## @param _radius Blast radius, also used to size the hole in thin walls.
## @param explosive Whether the damage is a blast.
## @return true if the hit was absorbed; false if already destroyed.
func damage_at(amount:float,point:Vector3,_radius:float=0.24,explosive:bool=false)->bool:
	if destroyed:return false
	wear+=amount
	bullet_mark(point)
	# Bullets do nothing to concrete; explosions chip at 25% strength.
	if protected_concrete:
		if explosive:integrity-=amount*0.25
	# Non-concrete panels: bullets deal 80% and explosions 100%.
	else:integrity-=amount*(1.0 if explosive else 0.8)
	# Hull panels feed the owning boat's hit statistics.
	if hull_panel:
		truck_owner.bullet_hits+=1
		truck_owner.total_damage+=amount
		# Below 64% of maximum strength the plating can be shot through.
		penetrable=integrity<max_integrity*0.64
		if penetrable:modulate_damage()
	if integrity<=0:demolish()
	return true

## Tint a damaged panel darker once so it visibly shows scarring.
func modulate_damage():
	# Only scar once.
	if has_meta("scarred"):return
	set_meta("scarred",true)
	for mesh in owned_meshes():
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override=mesh.material_override.duplicate()
			mesh.material_override.albedo_color=Color("4d5048")
	# Actual visual and ballistic openings are local to this damaged panel.
	# Actual visual and ballistic openings are local to this damaged panel.
	if hull_panel:penetrable=true
