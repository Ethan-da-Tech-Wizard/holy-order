extends SceneTree
const Art=preload("res://scripts/art.gd")
func _initialize():call_deferred("run")
func run():
	var world=Node3D.new()
	root.add_child(world)
	var wall=Art.solid(world,Vector3(5,3,0.4),Vector3(0,1.5,0),Art.material(Color.TAN),0,"masonry")
	for i in range(4):await physics_frame
	var space=world.get_world_3d().direct_space_state
	var ray=PhysicsRayQueryParameters3D.create(Vector3(0,1,-3),Vector3(0,1,3),1)
	print("BEFORE_BLOCKED ",not space.intersect_ray(ray).is_empty())
	wall.carve(Vector3(0,1,0),1.2)
	for i in range(12):await physics_frame
	print("AFTER_OPEN ",space.intersect_ray(ray).is_empty()," CUTS ",wall.cuts_completed)
	var outside=PhysicsRayQueryParameters3D.create(Vector3(2.1,1,-3),Vector3(2.1,1,3),1)
	print("SIDES_REMAIN ",not space.intersect_ray(outside).is_empty())
	quit(0 if space.intersect_ray(ray).is_empty() and not space.intersect_ray(outside).is_empty() else 1)
