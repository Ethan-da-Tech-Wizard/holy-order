extends SceneTree
var g
var frames=[]
var render_frames=[]
var measuring=false
var render_last:int=0
func _process(_delta):
	if not measuring:return false
	var now=Time.get_ticks_usec()
	if render_last>0:render_frames.append((now-render_last)/1000.0)
	render_last=now
	return false
func _initialize():call_deferred("run")
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	if OS.has_environment("HOLY_ORDER_PHYSICS_HZ"):Engine.physics_ticks_per_second=int(OS.get_environment("HOLY_ORDER_PHYSICS_HZ"))
	await physics_frame
	g.begin(true)
	g.player.set_physics_process(false)
	g.player.collision_layer=0
	g.elapsed=g.first_landing_at+14
	for boat in g.boats:boat.tick(0.016667)
	g.player.truck=null
	g.player.position=Vector3(0,65,10)
	var start=g.elapsed
	var last=Time.get_ticks_usec()
	var wall_start=last
	measuring=true
	while g.elapsed<start+45:
		await physics_frame
		var now=Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last=now
		if g.phase!="playing":g.phase="playing"
	measuring=false
	var wall_seconds=(Time.get_ticks_usec()-wall_start)/1000000.0
	frames.sort()
	render_frames.sort()
	var triangles=0
	var mesh=g.world.wires[0].wire_mesh
	for i in range(mesh.get_surface_count()):triangles+=mesh.surface_get_array_index_len(i)/3
	var report={"mode":"headless CPU frame intervals; not desktop FPS", "physics_hz":Engine.physics_ticks_per_second,"wall_seconds":wall_seconds,"render_frames":render_frames.size(),"render_median_ms":render_frames[render_frames.size()/2],"render_p95_ms":render_frames[int(render_frames.size()*0.95)],"render_p99_ms":render_frames[int(render_frames.size()*0.99)],"seconds":g.elapsed-start,"frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*0.95)],"p99_ms":frames[int(frames.size()*0.99)],"wire_triangles_per_section":triangles,"wire_sections":g.world.wires.size(),"terrain_chunks":g.world.terrain_chunks.size(),"nodes":get_node_count(),"shots":g.ammo_spent,"breaches":g.breaches,"allies":g.allies_alive,"enemies":g.germans_alive}
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
