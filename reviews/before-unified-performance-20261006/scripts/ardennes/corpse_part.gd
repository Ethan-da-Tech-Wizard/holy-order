## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/ardennes/corpse_part.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## One body part (torso, limb, head) of a dead soldier's ragdoll that can be
## shot off.
##
## Role: created by corpse.gd, which sets `corpse` and `part_name`. Frozen (no
## physics cost) until its integrity reaches zero, when it detaches and
## becomes a free rigid body. Layer 32 (pickups/corpses), mask 1 (world).
## Rendering: parts may share a MultiMesh with other remains
## (corpse.game.batch_remains); a part moves its batch slot every physics tick
## only while it is awake and detached.
extends RigidBody3D

## The owning Corpse node.
var corpse

## "torso", "head", etc. The torso drives the corpse's own physics step.
var part_name:String="torso"

## Hit points; reaching zero blows the part off.
var integrity:float=55

## True once the part is free of the body.
var detached:bool=false

## Ensures the first hit adds a wound marker only once.
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

## A bullet hit: lowers integrity, shows a wound on the first hit and detaches
## the part when integrity is gone, with an impulse (capped at 5) away from the
## hit point and a small upward bias.
## [param amount] damage points. [param point] world hit position.
func receive_hit(amount:float,point:Vector3):
	integrity-=amount
	if not wound_shown:
		wound_shown=true
		corpse.wound(self,point)
	if integrity<=0:detach((global_position-point+Vector3(0,0.2,0)).normalized()*minf(amount*0.04,5.0))

## Frees the part: unfreezes it, wakes the corpse's own physics (for the torso),
## counts the dismemberment, and applies a push and random spin.
## [param impulse] central impulse vector.
func detach(impulse:Vector3):
	if not detached:
		detached=true
		freeze=false
		corpse.detached_count+=1
		corpse.wound(self,global_position)
	apply_central_impulse(impulse)
	apply_torque_impulse(Vector3(randf_range(-2,2),0,randf_range(-2,2)))
