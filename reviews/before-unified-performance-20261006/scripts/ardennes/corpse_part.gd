# ==============================================================================
# Program: corpse_part.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for corpse_part.gd.
# ==============================================================================
extends RigidBody3D
var corpse
var part_name:String="torso"
var integrity:float=55
var detached:bool=false
var wound_shown:bool=false

func _ready():
	collision_layer=32
	collision_mask=1
	freeze=true
	freeze_mode=RigidBody3D.FREEZE_MODE_STATIC
	mass=8
	linear_damp=0.45
	angular_damp=1.5
	can_sleep=true

func receive_hit(amount:float,point:Vector3):
	integrity-=amount
	if not wound_shown:
		wound_shown=true
		corpse.wound(self,point)
	if integrity<=0:detach((global_position-point+Vector3(0,0.2,0)).normalized()*minf(amount*0.04,5.0))

func detach(impulse:Vector3):
	if not detached:
		detached=true
		freeze=false
		corpse.detached_count+=1
		corpse.wound(self,global_position)
	apply_central_impulse(impulse)
	apply_torque_impulse(Vector3(randf_range(-2,2),0,randf_range(-2,2)))
