extends SceneTree
var g
var view:SubViewport
var frames:Array=[]
var samples:Array=[]
var slow_frames:Array=[]
func _initialize():call_deferred("run")
func ticks(n):
	for i in range(n):await physics_frame
func capture(label):
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://reviews/ardennes-"+label+".png")
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19441224)
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new()
	view.size=Vector2i(1440,900)
	view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.msaa_3d=Viewport.MSAA_4X
	root.add_child(view)
	g=load("res://scenes/ardennes.tscn").instantiate()
	view.add_child(g)
	await ticks(35)
	await capture("title")
	g.begin()
	g.player.set_physics_process(false)
	g.player.set_process_unhandled_input(false)
	g.player.truck=null
	g.player.collision_layer=0
	g.player.position=Vector3(-154,50,282)
	g.player.camera.current=false
	g.world.world_camera.current=true
	g.hud.hide()
	var last=Time.get_ticks_usec()
	var captured={}
	while g.elapsed<64 and g.phase=="playing":
		var point=g.trucks[4].position
		var cam=g.world.world_camera
		if not g.dismounted:
			cam.position=point+Vector3(-16,9,21)
			cam.look_at(point+Vector3(0,1,-13))
		else:
			cam.position=g.world.on_ground(Vector3(-18,0,37))+Vector3(0,12,0)
			cam.look_at(g.world.anchors[0]+Vector3(0,1,0))
		await process_frame
		var now=Time.get_ticks_usec()
		var ms=(now-last)/1000.0
		last=now
		if g.elapsed>3:frames.append(ms)
		if ms>65 and g.elapsed>3:
			var sample={"second":snappedf(g.elapsed,0.1),"frame_ms":ms,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"cut_jobs":g.world.cut_jobs,"active_cuts":g.world.active_cuts.size(),"queued_cuts":g.world.pending_cuts.size()}
			slow_frames.append(sample)
		for mark in [8,28,42,60]:
			if g.elapsed>=mark and not captured.has(mark):
				captured[mark]=true
				await capture("battle-%02d"%mark)
				var sample={"second":mark,"allies":g.allies_alive,"germans":g.germans_alive,"shots":g.ammo_spent,"deaths":g.death_causes.duplicate(),"bodies":get_nodes_in_group("winter_corpses").size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
				samples.append(sample)
				print("GPU ",JSON.stringify(sample))
	frames.sort()
	var report={"resolution":"1440x900","msaa":"4x","observed_frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*0.95)],"p99_ms":frames[int(frames.size()*0.99)],"samples":samples,"other_game_open":false,"note":"Live autonomous convoy and combat rendering with no other game instance running. Player is an observer outside the battlefield for this automated benchmark."}
	FileAccess.open("res://reviews/ardennes-performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	FileAccess.open("res://reviews/ardennes-slow-frames.json",FileAccess.WRITE).store_string(JSON.stringify(slow_frames,"  "))
	print("GPU_COMPLETE ",JSON.stringify(report))
	g.phase="title"
	for i in range(300):
		if g.world.pending_cuts.is_empty() and g.world.active_cuts.is_empty():break
		await process_frame
	g.queue_free()
	await ticks(5)
	quit()
