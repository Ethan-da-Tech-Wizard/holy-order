# ==============================================================================
# Program: ardennes_benchmark.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for ardennes_benchmark.gd.
# ==============================================================================
## Performance benchmark for the Ardennes battle (1440x900, 4x MSAA, 125 s of simulated battle).
##
## Runs the mission in a SubViewport with its own world, using a free observer camera that
## first rides in the truck and later follows a soldier on the ground. It records every frame
## time and writes median, p95 and p99 frame times (overall, riding, and combat) to
## reviews/ardennes-performance.json, slow frames (>65 ms) with engine monitors to
## reviews/ardennes-slow-frames.json, and screenshots at 10, 40, 70, 100 and 120 s.
## Needs a GPU/display; not meant for headless CI. Run with `godot --path . --script res://tests/ardennes_benchmark.gd`.
extends SceneTree

# Mission instance.
var g

# Off-screen viewport the battle renders into so resolution and MSAA are fixed regardless of the window.
var view:SubViewport

# frames: all frame times (ms). samples: periodic battle snapshots. slow_frames: details on frames over 65 ms. ride_frames/combat_frames: frame times split by phase of the observer.
var frames:Array=[]
var samples:Array=[]
var slow_frames:Array=[]
var ride_frames:Array=[]
var combat_frames:Array=[]
func _initialize():call_deferred("run")

## Wait n physics ticks.
func ticks(n):
	for i in range(n):await physics_frame

## Save a screenshot of the viewport to reviews/ardennes-<label>.png.
func capture(label):
	# Wait until the frame is fully drawn before reading pixels.
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://reviews/ardennes-"+label+".png")

## Run the benchmark.
func run():
	# Test flags read by the battle script: deterministic seed (19441224) and test-mode behaviour.
	set_meta("battle_test",true)
	set_meta("battle_seed",19441224)
	# Mute audio so the benchmark does not depend on sound hardware.
	AudioServer.set_bus_mute(0,true)
	# Own World3D so this test's scene does not touch the main viewport.
	view=SubViewport.new()
	view.size=Vector2i(1440,900)
	view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	# 4x MSAA matches the highest quality a player would use.
	view.msaa_3d=Viewport.MSAA_4X
	root.add_child(view)
	g=load("res://scenes/ardennes.tscn").instantiate()
	view.add_child(g)
	# Let the scene settle before the title screenshot.
	await ticks(35)
	await capture("title")
	g.begin()
	# Disable the player's own control and collision so the observer cannot affect the simulation.
	g.player.set_physics_process(false)
	g.player.set_process_unhandled_input(false)
	g.player.truck=null
	g.player.collision_layer=0
	g.player.position=Vector3(-154,50,282)
	g.player.camera.current=false
	# Use the world's free camera for observing.
	g.world.world_camera.current=true
	g.hud.hide()
	var last=Time.get_ticks_usec()
	var captured={}
	var tracked=null
	var track_clock=0.0
	# Run until 125 s of battle time pass (or the phase changes).
	while g.elapsed<125 and g.phase=="playing":
		var point=g.trucks[4].position
		var cam=g.world.world_camera
		var riding=not g.trucks[4].unloaded and not g.trucks[4].destroyed
		# While truck 4 is still carrying troops, observe from a passenger-height spot.
		if riding:
			# Passenger-height view out the actual open rear. The observer is not
			# an invulnerable combatant and does not change the troop simulation.
			# Passenger-height view out the actual open rear. The observer is not
			# an invulnerable combatant and does not change the troop simulation.
			cam.position=g.trucks[4].seat_transform(g.player.seat).origin+Vector3(0,1.36,0)
			cam.look_at(cam.position+g.trucks[4].global_basis.z*10)
		else:
			# After unloading, follow the living friendly closest to the ambush hill; re-pick every 12 s.
			if g.elapsed>=track_clock or tracked==null or not tracked.alive:
				track_clock=g.elapsed+12
				var available=g.friendlies.filter(func(a):return a.alive and a.truck==null)
				if not available.is_empty():
					available.sort_custom(func(a,b):return a.position.distance_squared_to(g.world.anchors[6])<b.position.distance_squared_to(g.world.anchors[6]))
				tracked=available[0]
			if tracked!=null:
				var toward=(g.world.anchors[6 if tracked.wing<0 else 7]-tracked.position).normalized()
				# Camera sits 2.5 m behind the tracked soldier and looks 30 m toward the objective.
				cam.position=g.world.on_ground(tracked.position-toward*2.5)+Vector3(0,2.0,0)
				cam.look_at(cam.position+toward*30)
		# Frame time from consecutive rendered frames.
		await process_frame
		var now=Time.get_ticks_usec()
		var ms=(now-last)/1000.0
		last=now
		# Ignore the first 3 s of start-up.
		if g.elapsed>3:
			frames.append(ms)
			if riding:ride_frames.append(ms)
			else:combat_frames.append(ms)
		# A frame over 65 ms is recorded with the engine's own timing monitors.
		if ms>65 and g.elapsed>3:
			var sample={"second":snappedf(g.elapsed,0.1),"frame_ms":ms,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"cut_jobs":g.world.cut_jobs,"active_cuts":g.world.active_cuts.size(),"queued_cuts":g.world.pending_cuts.size()}
			slow_frames.append(sample)
		# Periodic screenshots plus a snapshot of casualties, shots and render statistics.
		for mark in [10,40,70,100,120]:
			if g.elapsed>=mark and not captured.has(mark):
				captured[mark]=true
				await capture("battle-%02d"%mark)
				# Reset the timer so the screenshot readback cost does not appear as a slow frame.
				last=Time.get_ticks_usec() # Exclude synchronous screenshot readback.
				var sample={"second":mark,"allies":g.allies_alive,"germans":g.germans_alive,"shots":g.ammo_spent,"deaths":g.death_causes.duplicate(),"bodies":get_nodes_in_group("winter_corpses").size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
				samples.append(sample)
				print("GPU ",JSON.stringify(sample))
	# Sort for the percentile computation.
	frames.sort()
	var report={"resolution":"1440x900","msaa":"4x","observed_frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*0.95)],"p99_ms":frames[int(frames.size()*0.99)],"ride":summarize(ride_frames),"combat":summarize(combat_frames),"samples":samples,"other_game_open":false,"note":"125-second live autonomous run; passenger-height rear view then camera following dismounted troops. No other test/game instance. Excludes screenshot readbacks and first 3 seconds; does not establish performance at every player viewpoint."}
	FileAccess.open("res://reviews/ardennes-performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	FileAccess.open("res://reviews/ardennes-slow-frames.json",FileAccess.WRITE).store_string(JSON.stringify(slow_frames,"  "))
	print("GPU_COMPLETE ",JSON.stringify(report))
	# Return to the title phase and wait for pending terrain cuts so the scene can free cleanly.
	g.phase="title"
	for i in range(300):
		if g.world.pending_cuts.is_empty() and g.world.active_cuts.is_empty():break
		await process_frame
	g.queue_free()
	await ticks(5)
	quit()

## Summarise a list of frame times.
## @param values Frame times in ms (sorted in place).
## @return {frames, median_ms, p95_ms, p99_ms}, or {frames: 0} if empty.
func summarize(values:Array)->Dictionary:
	if values.is_empty():return {"frames":0}
	values.sort()
	return {"frames":values.size(),"median_ms":values[values.size()/2],"p95_ms":values[int(values.size()*0.95)],"p99_ms":values[int(values.size()*0.99)]}
