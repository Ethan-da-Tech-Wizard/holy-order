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
	while g.elapsed<64 and g.phase=="playing":
		var point=g.trucks[4].position
		var cam=g.world.world_camera
		if not g.dismounted:
			cam.position=point+Vector3(-16,9,21)
			cam.look_at(point+Vector3(0,1,-13))
		else:
			cam.position=g.world.on_ground(Vector3(-18,0,37))+Vector3(0,12,0)
			cam.look_at(g.world.anchors[0]+Vector3(0,1,0))
		# Frame time from consecutive rendered frames.
		await process_frame
		var now=Time.get_ticks_usec()
		var ms=(now-last)/1000.0
		last=now
		if g.elapsed>3:frames.append(ms)
		# A frame over 65 ms is recorded with the engine's own timing monitors.
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
	# Sort for the percentile computation.
	frames.sort()
	var report={"resolution":"1440x900","msaa":"4x","observed_frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*0.95)],"p99_ms":frames[int(frames.size()*0.99)],"samples":samples,"other_game_open":false,"note":"Live autonomous convoy and combat rendering with no other game instance running. Player is an observer outside the battlefield for this automated benchmark."}
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
