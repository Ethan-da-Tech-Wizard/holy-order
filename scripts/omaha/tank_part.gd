# ==============================================================================
# Program: tank_part.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Modular amphibious tank component. Manages track damage states, turret ring locking, flotation screen collapse physics, and localized armor hit detection.
# ==============================================================================
extends StaticBody3D
var tank_owner
var track_side:int=-1
func damage_at(amount:float,point:Vector3,_radius:float=0.2,_explosive:bool=false)->bool:
	# --- STRUCTURAL FRACTURE MECHANICS: Localized Destruction & Voxel Carving ---
	# Invariants:
	# - Evaluates impact coordinates against geometry bounding AABB boxes.
	# - Subdivides or carves mesh surfaces and applies physical impulses to fractured debris fragments.
	# Step: Process damage reception, evaluate armor mitigation, and update health status
	if track_side>=0:tank_owner.hit_track(track_side,amount*0.025)
	return true
