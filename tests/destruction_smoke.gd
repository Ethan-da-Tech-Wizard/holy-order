## Smoke test for wall destruction (breakable.gd / art.gd): carving a hole must
## open a line of fire through a thin masonry wall without removing the wall's sides.
## Scenario: a 5 x 3 x 0.4 m wall; a ray through its centre is blocked, then
## a 1.2 m sphere is carved from the middle; afterwards the centre ray must be
## free and a ray 2.1 m off-centre (through intact wall) must still be blocked.
## Prints BEFORE_BLOCKED / AFTER_OPEN / SIDES_REMAIN and exits 0 on success, 1 on failure.
## Run: godot --headless --path <repo> --script res://tests/destruction_smoke.gd
extends SceneTree
const Art=preload("res://scripts/art.gd")

## SceneTree entry point; defers to run() so the scene tree is ready.
func _initialize():call_deferred("run")

## Builds the wall, waits for physics to register it, carves, waits 12 frames for
## the rebuild coroutine in Breakable to finish, then checks both rays.
func run():
	var world=Node3D.new()
	root.add_child(world)
	var wall=Art.solid(world,Vector3(5,3,0.4),Vector3(0,1.5,0),Art.material(Color.TAN),0,"masonry")

	# Physics bodies only appear in the space after a couple of physics frames.
	for i in range(4):await physics_frame
	var space=world.get_world_3d().direct_space_state
	var ray=PhysicsRayQueryParameters3D.create(Vector3(0,1,-3),Vector3(0,1,3),1)
	print("BEFORE_BLOCKED ",not space.intersect_ray(ray).is_empty())
	wall.carve(Vector3(0,1,0),1.2)

	# The CSG rebuild is asynchronous (two frames per batch plus collision baking), so allow plenty of frames.
	for i in range(12):await physics_frame
	print("AFTER_OPEN ",space.intersect_ray(ray).is_empty()," CUTS ",wall.cuts_completed)
	var outside=PhysicsRayQueryParameters3D.create(Vector3(2.1,1,-3),Vector3(2.1,1,3),1)
	print("SIDES_REMAIN ",not space.intersect_ray(outside).is_empty())
	quit(0 if space.intersect_ray(ray).is_empty() and not space.intersect_ray(outside).is_empty() else 1)
