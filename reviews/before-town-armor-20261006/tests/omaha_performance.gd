## Archived review snapshot (before-town-armor-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script tests/omaha_performance.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Performance probe for the Omaha mission: measures frame intervals during 45
## simulated seconds of the beach battle with the full force.
## Method: loads scenes/omaha.tscn in test mode with the seed 19440606, jumps to
## 14 s after the first landing with the player hovering (65 m up, frozen), then
## records every physics frame interval (and render frame interval through
## _process) while the battle runs. The report (median, p95 etc. of the sorted
## samples, wire mesh triangle count) is printed and written to
## reviews/omaha/performance-<tag>.json. These are headless CPU intervals, not
## desktop FPS (stated in the report's "mode").
## Environment variables: HOLY_ORDER_PHYSICS_HZ overrides the physics rate;
## OMAHA_PERF_TAG names the output file (default "current").
## Run: godot --headless --path <repo> --script res://tests/omaha_performance.gd
extends SceneTree

## The Omaha battle controller.
var g

## Physics frame intervals (ms).
var frames=[]

## Render frame intervals (ms).
var render_frames=[]

## True while samples are collected.
var measuring=false

## Timestamp (microseconds) of the previous render frame.
var render_last:int=0

## Records the interval since the previous rendered frame while measuring. Returns false so the engine keeps running.
func _process(_delta):
	if not measuring:return false
	var now=Time.get_ticks_usec()
	if render_last>0:render_frames.append((now-render_last)/1000.0)
	render_last=now
	return false

## SceneTree entry point; defers to run().
func _initialize():call_deferred("run")

## Sets up the scene, runs the 45 s measurement loop, then writes and prints the report and quits.
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	if OS.has_environment("HOLY_ORDER_PHYSICS_HZ"):Engine.physics_ticks_per_second=int(OS.get_environment("HOLY_ORDER_PHYSICS_HZ"))
	await physics_frame
	g.begin()
	g.player.set_physics_process(false)
	g.player.collision_layer=0

	# Start measuring when the troops are on the beach and the fight is at its busiest.
	g.elapsed=g.first_landing_at+14
	for boat in g.boats:boat.tick(0.016667)
	g.player.truck=null
	g.player.position=Vector3(0,65,10)
	var start=g.elapsed
	var last=Time.get_ticks_usec()
	var wall_start=last
	measuring=true

	# Keeps the phase "playing" even if the player's state (frozen, invulnerable placement) would end it.
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
