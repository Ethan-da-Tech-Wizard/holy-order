extends SceneTree
var g
var view:SubViewport
var frames:Array=[]
var samples:Array=[]
var slow_frames:Array=[]
var ride_frames:Array=[]
var combat_frames:Array=[]
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
	var tracked=null
	var track_clock=0.0
	while g.elapsed<125 and g.phase=="playing":
		var point=g.trucks[4].position
		var cam=g.world.world_camera
		var riding=not g.trucks[4].unloaded and not g.trucks[4].destroyed
		if riding:
			# Passenger-height view out the actual open rear. The observer is not
			# an invulnerable combatant and does not change the troop simulation.
			cam.position=g.trucks[4].seat_transform(g.player.seat).origin+Vector3(0,1.36,0)
			cam.look_at(cam.position+g.trucks[4].global_basis.z*10)
		else:
			if g.elapsed>=track_clock or tracked==null or not tracked.alive:
				track_clock=g.elapsed+12
				var available=g.friendlies.filter(func(a):return a.alive and a.truck==null)
				if not available.is_empty():
					available.sort_custom(func(a,b):return a.position.distance_squared_to(g.world.anchors[6])<b.position.distance_squared_to(g.world.anchors[6]))
				tracked=available[0]
			if tracked!=null:
				var toward=(g.world.anchors[6 if tracked.wing<0 else 7]-tracked.position).normalized()
				cam.position=g.world.on_ground(tracked.position-toward*2.5)+Vector3(0,2.0,0)
				cam.look_at(cam.position+toward*30)
		await process_frame
		var now=Time.get_ticks_usec()
		var ms=(now-last)/1000.0
		last=now
		if g.elapsed>3:
			frames.append(ms)
			if riding:ride_frames.append(ms)
			else:combat_frames.append(ms)
		if ms>65 and g.elapsed>3:
			var sample={"second":snappedf(g.elapsed,0.1),"frame_ms":ms,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"cut_jobs":g.world.cut_jobs,"active_cuts":g.world.active_cuts.size(),"queued_cuts":g.world.pending_cuts.size()}
			slow_frames.append(sample)
		for mark in [10,40,70,100,120]:
			if g.elapsed>=mark and not captured.has(mark):
				captured[mark]=true
				await capture("battle-%02d"%mark)
				last=Time.get_ticks_usec() # Exclude synchronous screenshot readback.
				var sample={"second":mark,"allies":g.allies_alive,"germans":g.germans_alive,"shots":g.ammo_spent,"deaths":g.death_causes.duplicate(),"bodies":get_nodes_in_group("winter_corpses").size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
				samples.append(sample)
				print("GPU ",JSON.stringify(sample))
	frames.sort()
	var report={"resolution":"1440x900","msaa":"4x","observed_frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*0.95)],"p99_ms":frames[int(frames.size()*0.99)],"ride":summarize(ride_frames),"combat":summarize(combat_frames),"samples":samples,"other_game_open":false,"note":"125-second live autonomous run; passenger-height rear view then camera following dismounted troops. No other test/game instance. Excludes screenshot readbacks and first 3 seconds; does not establish performance at every player viewpoint."}
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

func summarize(values:Array)->Dictionary:
	if values.is_empty():return {"frames":0}
	values.sort()
	return {"frames":values.size(),"median_ms":values[values.size()/2],"p95_ms":values[int(values.size()*0.95)],"p99_ms":values[int(values.size()*0.99)]}
