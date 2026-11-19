## A hit area on a tank (hull plate, turret, or track) that forwards damage to its tank.
##
## Role: created by tank.gd, which sets `tank_owner` and, for track pieces, `track_side` (0 left, 1 right; -1 for armour). Shots hitting a track
## damage that track (2.5% of the damage), so tracks can be immobilised without destroying the tank.
extends StaticBody3D

## The Tank node that owns this part.
var tank_owner

## Which track this part is (0 or 1), or -1 if it is not a track.
var track_side:int=-1

## Called by projectile code. Passes a small share of damage to the tank's track when this part is a track and always reports the hit as handled (true), so bullets do not harm the plate itself.
## [param amount] damage points. [param point] hit position (unused). [param _radius] and [param _explosive] ignored.
func damage_at(amount:float,point:Vector3,_radius:float=0.2,_explosive:bool=false)->bool:
	if track_side>=0:tank_owner.hit_track(track_side,amount*0.025)
	return true
