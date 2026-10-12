extends SceneTree
var g
var frames=[]
func _initialize():call_deferred("run")
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.begin()
	g.player.set_physics_process(false)
	g.player.collision_layer=0
	g.elapsed=g.first_landing_at+14
	for boat in g.boats:boat.tick(0.016667)
	g.player.truck=null
	g.player.position=Vector3(0,65,10)
	var start=g.elapsed
	var last=Time.get_ticks_usec()
	while g.elapsed<start+45:
		await physics_frame
		var now=Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last=now
		if g.phase!="playing":g.phase="playing"
	frames.sort()
	var triangles=0
	var mesh=g.world.wires[0].wire_mesh
	for i in range(mesh.get_surface_count()):triangles+=mesh.surface_get_array_index_len(i)/3
	var report={"mode":"headless CPU frame intervals; not desktop FPS","seconds":g.elapsed-start,"frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*0.95)],"p99_ms":frames[int(frames.size()*0.99)],"wire_triangles_per_section":triangles,"wire_sections":g.world.wires.size(),"terrain_chunks":g.world.terrain_chunks.size(),"nodes":get_node_count(),"shots":g.ammo_spent,"breaches":g.breaches,"allies":g.allies_alive,"enemies":g.germans_alive}
	var tag=OS.get_environment("OMAHA_PERF_TAG")
	if tag.is_empty():tag="current"
	var file=FileAccess.open("res://reviews/omaha/performance-"+tag+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("PERFORMANCE ",JSON.stringify(report))
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit()
