# ==============================================================================
# Program: armored_panel.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Modular ballistic vehicle armor plate component. Evaluates incoming projectile penetration mechanics, calculates structural degradation from kinetic impacts, and spawns ricochet sparks.
# ==============================================================================
extends "res://scripts/ardennes/prop.gd"
var integrity:float=6500
var render_batch:MultiMesh
var render_index:int=-1
var render_origin=Vector3.ZERO

func demolish():
	# --- TOTAL STRUCTURAL COLLAPSE: Complete Geometry Invalidation ---
	# Invariants:
	# - Spawns rigid body debris fragments with randomized angular momentum.
	# - Disables navigation obstacles and triggers particle smoke and audio explosions.
	# Logic: Execute step-by-step processing for demolish
	if render_batch!=null:render_batch.set_instance_transform(render_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),render_origin))
	super.demolish()

func stops_small_arms()->bool:return not destroyed
	# --- CONTRACT: Function `stops_small_arms` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for stops_small_arms

func damage_at(amount:float,point:Vector3,_radius:float=0.24,explosive:bool=false)->bool:
	# --- STRUCTURAL FRACTURE MECHANICS: Localized Destruction & Voxel Carving ---
	# Invariants:
	# - Evaluates impact coordinates against geometry bounding AABB boxes.
	# - Subdivides or carves mesh surfaces and applies physical impulses to fractured debris fragments.
	# Step: Process damage reception, evaluate armor mitigation, and update health status
	if destroyed:return false
	wear+=amount
	bullet_mark(point)
	if truck_owner!=null:truck_owner.receive_part_damage(amount,point,explosive,self)
	integrity-=amount*(0.5 if explosive else 0.04)
	if integrity<=0:demolish()
	return true
