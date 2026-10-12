extends StaticBody3D
var tank_owner
var track_side:int=-1
func damage_at(amount:float,point:Vector3,_radius:float=0.2,_explosive:bool=false)->bool:
	if track_side>=0:tank_owner.hit_track(track_side,amount*0.025)
	return true
