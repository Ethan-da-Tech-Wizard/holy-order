# ==============================================================================
# Program: ardennes_ground_probe.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for ardennes_ground_probe.gd.
# ==============================================================================
## Diagnostic probe for Ardennes terrain collision (prints data, asserts nothing).
##
## Prints the first terrain normal, compares each sampled enemy's spawn position against a physics
## ray and `world.surface_height`, lets the troops rest for 600 ticks to see whether they stand
## on the floor, then digs a crater and prints what the ray hits afterwards plus which terrain
## chunks were cut. Read the lines tagged NORMAL, SPAWN, REST, DEATHS, AFTER DIG and CUT CHUNK
## in the output. Run: `godot --headless --path . --script res://tests/ardennes_ground_probe.gd`.
extends SceneTree
var g
func _initialize():call_deferred("run")
func ticks(n):
	for i in range(n):await physics_frame
func run():
	# Test-mode flag read by the battle script.
	set_meta("battle_test",true)
	g=load("res://scenes/ardennes.tscn").instantiate()
	root.add_child(g)
	# Wait for the world to build its terrain chunks.
	await ticks(3)
	# Inspect the first vertex normal of one terrain chunk (index 160) as a sanity check that normals were generated.
	var first=g.world.terrain_chunks[160].get_child(0).mesh
	print("NORMAL ",first.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0])
	# Every fifth of the first 80 enemies: compare the physics floor with the world height function.
	for i in range(0,80,5):
		var e=g.enemies[i]
		var p=e.position
		# Ray from 30 m above to 35 m below on the world layer (1).
		var ray=PhysicsRayQueryParameters3D.create(p+Vector3(0,30,0),p-Vector3(0,35,0),1)
		var hit=g.get_world_3d().direct_space_state.intersect_ray(ray)
		print("SPAWN ",i," ",p," sampled=",g.world.surface_height(p.x,p.z)," hit=",hit.get("position",Vector3.INF)," normal=",hit.get("normal",Vector3.ZERO))
	# Start the battle but freeze game logic and targeting so troops only fall and rest.
	g.begin()
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for e in g.actors:e.target=null
	# 600 ticks is enough for every soldier to land and settle.
	await ticks(600)
	for i in range(0,80,5):
		# Report where they ended up, alive state and floor contact. Any dead soldier means they fell through or into something.
		var e=g.enemies[i]
		print("REST ",i," ",e.position," alive=",e.alive," floor=",e.is_on_floor())
	# Causes of death recorded by the battle; unexpected terrain deaths would show up here.
	print("DEATHS ",g.death_causes)
	# Dig test: crater near the first gun position and check the ground height again.
	var p=g.world.anchors[0]+Vector3(7,0,1)
	g.world.dig(g.world.on_ground(p),0.85)
	await ticks(30)
	var ray=PhysicsRayQueryParameters3D.create(p+Vector3(0,30,0),p-Vector3(0,35,0),1)
	print("AFTER DIG ",g.get_world_3d().direct_space_state.intersect_ray(ray))
	# Chunks with completed cuts show whether the dig actually edited the terrain mesh.
	for chunk in g.world.terrain_chunks:
		if chunk.cuts_completed>0:print("CUT CHUNK ",chunk.position," destroyed=",chunk.destroyed," meshes=",chunk.owned_meshes().size())
	g.queue_free()
	await ticks(4)
	quit()
