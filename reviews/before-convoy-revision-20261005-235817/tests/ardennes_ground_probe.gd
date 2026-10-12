extends SceneTree
var g
func _initialize():call_deferred("run")
func ticks(n):
	for i in range(n):await physics_frame
func run():
	set_meta("battle_test",true)
	g=load("res://scenes/ardennes.tscn").instantiate()
	root.add_child(g)
	await ticks(3)
	var first=g.world.terrain_chunks[160].get_child(0).mesh
	print("NORMAL ",first.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0])
	for i in range(0,80,5):
		var e=g.enemies[i]
		var p=e.position
		var ray=PhysicsRayQueryParameters3D.create(p+Vector3(0,30,0),p-Vector3(0,35,0),1)
		var hit=g.get_world_3d().direct_space_state.intersect_ray(ray)
		print("SPAWN ",i," ",p," sampled=",g.world.surface_height(p.x,p.z)," hit=",hit.get("position",Vector3.INF)," normal=",hit.get("normal",Vector3.ZERO))
	g.begin()
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for e in g.actors:e.target=null
	await ticks(600)
	for i in range(0,80,5):
		var e=g.enemies[i]
		print("REST ",i," ",e.position," alive=",e.alive," floor=",e.is_on_floor())
	print("DEATHS ",g.death_causes)
	var p=g.world.anchors[0]+Vector3(7,0,1)
	g.world.dig(g.world.on_ground(p),0.85)
	await ticks(30)
	var ray=PhysicsRayQueryParameters3D.create(p+Vector3(0,30,0),p-Vector3(0,35,0),1)
	print("AFTER DIG ",g.get_world_3d().direct_space_state.intersect_ray(ray))
	for chunk in g.world.terrain_chunks:
		if chunk.cuts_completed>0:print("CUT CHUNK ",chunk.position," destroyed=",chunk.destroyed," meshes=",chunk.owned_meshes().size())
	g.queue_free()
	await ticks(4)
	quit()
