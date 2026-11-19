# ==============================================================================
# Program: destruction_smoke.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Automated test script verifying runtime performance, physics stability, or behavior correctness for destruction_smoke.gd.
# ==============================================================================
## Smoke test for wall destruction: a 5 x 3 x 0.4 m masonry wall is cut and the opening is checked.
##
## Prints BEFORE_BLOCKED (a ray through the wall is blocked), AFTER_OPEN (the same ray passes after
## a 1.2 m cut at the centre; CUTS reports how many cuts were applied) and SIDES_REMAIN (a ray
## 2.1 m off centre still hits). Exits 0 only if the hole is open and the sides stay solid.
## Exercises breakable.gd `carve` / `rebuild` and the collision shape bake.
## Run: `godot --headless --path . --script res://tests/destruction_smoke.gd`.
extends SceneTree

# The art helper provides the destructible solid.
const Art=preload("res://scripts/art.gd")
func _initialize():call_deferred("run")
func run():
	# A bare Node3D world: no mission scene is needed to test geometry cutting.
	var world=Node3D.new()
	root.add_child(world)
	# Masonry kind so the wall takes the CSG path of breakable.gd, not the fast box split.
	var wall=Art.solid(world,Vector3(5,3,0.4),Vector3(0,1.5,0),Art.material(Color.TAN),0,"masonry")
	# Wait for the physics server to register the collider.
	for i in range(4):await physics_frame
	var space=world.get_world_3d().direct_space_state
	# Ray across the wall thickness at height 1 m, hitting layer 1.
	var ray=PhysicsRayQueryParameters3D.create(Vector3(0,1,-3),Vector3(0,1,3),1)
	print("BEFORE_BLOCKED ",not space.intersect_ray(ray).is_empty())
	# Carve a 1.2 m hole through the centre.
	wall.carve(Vector3(0,1,0),1.2)
	# Twelve ticks give the asynchronous CSG rebuild time to finish.
	for i in range(12):await physics_frame
	print("AFTER_OPEN ",space.intersect_ray(ray).is_empty()," CUTS ",wall.cuts_completed)
	# A ray 2.1 m off centre must still hit, proving the cut did not remove the whole wall.
	var outside=PhysicsRayQueryParameters3D.create(Vector3(2.1,1,-3),Vector3(2.1,1,3),1)
	print("SIDES_REMAIN ",not space.intersect_ray(outside).is_empty())
	quit(0 if space.intersect_ray(ray).is_empty() and not space.intersect_ray(outside).is_empty() else 1)
