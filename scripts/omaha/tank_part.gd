# ==============================================================================
# Program: tank_part.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 18, 2026
# Purpose: Articulated turret and track assembly component with independent rotation and armor angling.
# ==============================================================================
extends StaticBody3D
var tank_owner
var track_side:int=-1
func damage_at(amount:float,point:Vector3,_radius:float=0.2,_explosive:bool=false)->bool:
	# Step: Process damage reception, evaluate armor mitigation, and update health status
	if track_side>=0:tank_owner.hit_track(track_side,amount*0.025)
	return true
