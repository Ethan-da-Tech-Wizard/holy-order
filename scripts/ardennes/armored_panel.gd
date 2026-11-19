## One plate of vehicle armour (hull, turret or door panel) that can be damaged
## and destroyed independently of the rest of its vehicle.
##
## Role: built by truck.gd (and the Omaha tank builders) as a Prop child of the
## vehicle. Small arms do not penetrate it (stops_small_arms), explosives and
## sustained fire wear down `integrity`, and every hit is forwarded to the
## owning vehicle (`truck_owner`) so it can show damage and fail systems.
## Batching: vehicle_visuals.gd merges panel meshes into one MultiMesh; this
## panel remembers its slot (render_batch / render_index / render_origin) so it
## can collapse that instance when it is destroyed.
extends "res://scripts/ardennes/prop.gd"

## Remaining armour hit points. Bullets take only 4% of their damage from it,
## explosions 50%, so it takes about 6500 / 0.04 = 162,500 bullet damage but
## only 13,000 explosive damage to destroy a panel.
var integrity:float=6500

## MultiMesh holding this panel's visual (set by vehicle_visuals.gd), or null.
var render_batch:MultiMesh

## This panel's instance slot in render_batch; -1 when not batched.
var render_index:int=-1

## Local position the instance is collapsed to when destroyed.
var render_origin=Vector3.ZERO

## Hides the panel's batched instance (scales it to zero at its origin; the
## MultiMesh cannot delete one instance) then runs the normal Prop demolition.
func demolish():
	if render_batch!=null:render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),render_origin))
	super.demolish()

## True while the panel is intact: rifle-class bullets are stopped by it, which
## AI line-of-fire checks use (destroyed panels become openings).
func stops_small_arms()->bool:return not destroyed

## Registers a hit: wear grows, a bullet mark is drawn, the owning vehicle is
## told, and integrity falls (50% of explosive damage, 4% of other damage).
## Destroyed at zero integrity. Returns false only if already destroyed.
## [param amount] damage points. [param point] world impact point.
## [param _radius] ignored here. [param explosive] true for blasts.
func damage_at(amount:float,point:Vector3,_radius:float=0.24,explosive:bool=false)->bool:
	if destroyed:return false
	wear+=amount
	bullet_mark(point)
	if truck_owner!=null:truck_owner.receive_part_damage(amount,point,explosive,self)
	integrity-=amount*(0.5 if explosive else 0.04)
	if integrity<=0:demolish()
	return true
