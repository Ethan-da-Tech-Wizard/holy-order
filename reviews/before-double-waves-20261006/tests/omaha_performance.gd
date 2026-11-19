# ==============================================================================
# Program: omaha_performance.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for omaha_performance.gd.
# ==============================================================================
## Headless CPU timing test for the Omaha landing (45 s of heavy combat).
##
## Starts the mission, skips to 14 s after the first landing, places the player high above the
## beach and records the interval between physics frames and between rendered frames for 45
## simulated seconds. Writes median/p95/p99 values, the physics rate and the wire mesh triangle
## count to reviews/omaha/performance-<tag>.json. The numbers are CPU frame intervals in headless mode, not desktop
## FPS. Environment: HOLY_ORDER_PHYSICS_HZ overrides the physics tick rate; OMAHA_PERF_TAG names the output file (default "current").
extends SceneTree

# Mission instance.
var g

# Physics-frame intervals and render-frame intervals, in milliseconds.
var frames=[]
var render_frames=[]

# True only while the timed window is running.
var measuring=false

# Timestamp (microseconds) of the previous rendered frame.
var render_last:int=0

## Record the time between rendered frames while measuring.
## @return false so the frame continues normally (returning true would quit the main loop).
func _process(_delta):
	if not measuring:return false
	var now=Time.get_ticks_usec()
	if render_last>0:render_frames.append((now-render_last)/1000.0)
	render_last=now
	return false
func _initialize():call_deferred("run")
func run():
	# Deterministic test mode and the D-Day seed 19440606.
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	# Uncapped FPS so the loop is limited only by the simulation.
	Engine.max_fps=0
	# Allow comparing different physics rates from the command line.
	if OS.has_environment("HOLY_ORDER_PHYSICS_HZ"):Engine.physics_ticks_per_second=int(OS.get_environment("HOLY_ORDER_PHYSICS_HZ"))
	await physics_frame
	# Start, then park the player in the air so no player input or death affects the run.
	g.begin()
	g.player.set_physics_process(false)
	g.player.collision_layer=0
	# Jump forward in time so boats have landed and the beach fight is in full swing; tick the boats once to settle their positions.
	g.elapsed=g.first_landing_at+14
	for boat in g.boats:boat.tick(0.016667)
	g.player.truck=null
	g.player.position=Vector3(0,65,10)
	# Measure 45 s of mission time.
	var start=g.elapsed
	var last=Time.get_ticks_usec()
	var wall_start=last
	measuring=true
	while g.elapsed<start+45:
		await physics_frame
		var now=Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last=now
		# The test forces play phase, in case the game wants to change it.
		if g.phase!="playing":g.phase="playing"
	measuring=false
	var wall_seconds=(Time.get_ticks_usec()-wall_start)/1000000.0
	frames.sort()
	render_frames.sort()
	# Size of the wire mesh in triangles, as a rendering cost indicator.
	var triangles=0
	var mesh=g.world.wires[0].wire_mesh
	for i in range(mesh.get_surface_count()):triangles+=mesh.surface_get_array_index_len(i)/3
	var report={"mode":"headless CPU frame intervals; not desktop FPS", "physics_hz":Engine.physics_ticks_per_second,"wall_seconds":wall_seconds,"render_frames":render_frames.size(),"render_median_ms":render_frames[render_frames.size()/2],"render_p95_ms":render_frames[int(render_frames.size()*0.95)],"render_p99_ms":render_frames[int(render_frames.size()*0.99)],"seconds":g.elapsed-start,"frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*0.95)],"p99_ms":frames[int(frames.size()*0.99)],"wire_triangles_per_section":triangles,"wire_sections":g.world.wires.size(),"terrain_chunks":g.world.terrain_chunks.size(),"nodes":get_node_count(),"shots":g.ammo_spent,"breaches":g.breaches,"allies":g.allies_alive,"enemies":g.germans_alive}
	# Output file tag from the environment.
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
