extends "res://scripts/ardennes/prop.gd"
var integrity:float=6500
var render_batch:MultiMesh
var render_index:int=-1
var render_origin=Vector3.ZERO

func demolish():
	if render_batch!=null:render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),render_origin))
	super.demolish()

func stops_small_arms()->bool:return not destroyed

func damage_at(amount:float,point:Vector3,_radius:float=0.24,explosive:bool=false)->bool:
	if destroyed:return false
	wear+=amount
	bullet_mark(point)
	if truck_owner!=null:truck_owner.receive_part_damage(amount,point,explosive,self)
	integrity-=amount*(0.5 if explosive else 0.04)
	if integrity<=0:demolish()
	return true
