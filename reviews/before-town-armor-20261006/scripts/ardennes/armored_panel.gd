# ==============================================================================
# Program: armored_panel.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for armored_panel.gd.
# ==============================================================================
## Steel plate on a truck (cab armour, shields) that blocks small arms.
##
## Extends the generic breakable prop. Hits are also forwarded to the owning truck
## so the vehicle tracks damage per part. Plates are rendered through a shared
## MultiMesh for speed, so demolition hides the plate by scaling its instance to zero.
extends "res://scripts/ardennes/prop.gd"

# Remaining plate strength. Rifle rounds barely scratch it (see the 0.04 factor); explosives do real harm.
var integrity:float=6500

# MultiMesh that draws this plate, and the plate's slot in it (-1 means not batched).
var render_batch:MultiMesh
var render_index:int=-1

# Where the plate sat, so the hidden instance keeps a valid position.
var render_origin=Vector3.ZERO

## Destroy the plate and hide its batched mesh instance.
func demolish():
	# A zero-scale transform is the cheap way to hide one MultiMesh instance without rebuilding the batch.
	if render_batch!=null:render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),render_origin))
	super.demolish()

## Armoured panels stop small-arms bullets while intact.
## @return true until the plate is destroyed.
func stops_small_arms()->bool:return not destroyed

## Apply damage from a bullet or explosion.
## @param amount Raw damage.
## @param point World hit point (for the bullet mark and truck bookkeeping).
## @param _radius Blast radius (unused here; kept to match the prop interface).
## @param explosive true if the damage came from an explosion.
## @return true if the hit was absorbed, false if the plate was already destroyed.
func damage_at(amount:float,point:Vector3,_radius:float=0.24,explosive:bool=false)->bool:
	if destroyed:return false
	# Wear accumulates separately from integrity and is read by the prop's visuals.
	wear+=amount
	bullet_mark(point)
	# Tell the owning truck so its health and destruction logic see damage on this part.
	if truck_owner!=null:truck_owner.receive_part_damage(amount,point,explosive,self)
	# Explosives deal 0.5 of their damage to integrity, bullets only 4%, so plate is nearly bullet-proof but fragile to blasts.
	integrity-=amount*(0.5 if explosive else 0.04)
	if integrity<=0:demolish()
	return true
