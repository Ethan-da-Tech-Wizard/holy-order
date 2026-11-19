# ==============================================================================
# Program: corpse_part.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for corpse_part.gd.
# ==============================================================================
## A body part (torso, limb or head) of a dead soldier that can be shot off.
##
## Created by corpse.gd. The part starts frozen (static) so the corpse is cheap;
## once its `integrity` runs out it is detached, unfrozen and flung by an impulse.
## Parts can draw through a shared MultiMesh batch (see `batch_visual`).
extends RigidBody3D

# Owning corpse; used for wound effects, batching and counters.
var corpse

# Which part this is; "torso" is special because its detachment wakes the corpse.
var part_name:String="torso"

# Damage left before the part comes off.
var integrity:float=55
var detached:bool=false

# Whether a wound decal was already spawned for this part.
var wound_shown:bool=false

## Configure the body as a lightweight frozen part.
func _ready():
	# Layer 32 = hit targets / pickups; mask 1 = collide with the world only.
	collision_layer=32
	collision_mask=1
	# Frozen static: no physics cost until detached.
	freeze=true
	freeze_mode=RigidBody3D.FREEZE_MODE_STATIC
	# Mass and damping chosen so detached limbs slide and settle quickly instead of rolling forever.
	mass=8
	linear_damp=0.45
	angular_damp=1.5
	can_sleep=true

## Take damage from a bullet.
## @param amount Damage points.
## @param point World impact point; the detach impulse points away from it.
func receive_hit(amount:float,point:Vector3):
	integrity-=amount
	# Only one wound mark per part.
	if not wound_shown:
		wound_shown=true
		corpse.wound(self,point)
	# Impulse = direction away from the hit (with a small lift) scaled by damage, capped at 5.
	if integrity<=0:detach((global_position-point+Vector3(0,0.2,0)).normalized()*minf(amount*0.04,5.0))

## Unfreeze the part and apply an impulse.
## @param impulse World-space linear impulse.
func detach(impulse:Vector3):
	if not detached:
		detached=true
		freeze=false
		corpse.detached_count+=1
		corpse.wound(self,global_position)
	# Random sideways tumble so detached limbs do not fall identically.
	apply_central_impulse(impulse)
	apply_torque_impulse(Vector3(randf_range(-2,2),0,randf_range(-2,2)))
