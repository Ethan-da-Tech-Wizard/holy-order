## Archived review snapshot (before-town-armor-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script tests/ardennes_ground_probe.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Diagnostic probe for the Ardennes terrain (not a pass/fail test): checks that
## soldiers spawn on the ground and stay on it, and that digging changes the surface.
## What it prints: the first terrain chunk's normal; for every fifth German the
## spawn position, the world's surface_height there and the physics floor under it
## (SPAWN lines); after 600 physics frames of an idle battle, each soldier's position
## and is_on_floor (REST lines) and the death causes (fall deaths would point to a
## terrain/spawn bug); then digs a hole and prints the ray result and chunk edit
## state (AFTER DIG / CUT CHUNK).
## Run: godot --headless --path <repo> --script res://tests/ardennes_ground_probe.gd
extends SceneTree

## The loaded Ardennes battle controller.
var g
func _initialize():call_deferred("run")

## Awaits `n` physics frames.
func ticks(n):
	for i in range(n):await physics_frame

## Loads scenes/ardennes.tscn in test mode (tree meta "battle_test" prevents auto-pause), starts the battle with physics off, then settles actors for 600 ticks.
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

	# Start the battle but freeze the controller and player so only the Germans' own physics runs (tests floor handling in isolation).
	g.begin()
	g.set_physics_process(false)
	g.player.set_physics_process(false)

	# No targets, so nobody shoots or moves for tactical reasons during the settle period.
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
