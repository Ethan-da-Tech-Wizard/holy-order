## Diagnostic probe (not a pass/fail test) for the Ardennes terrain: scans a grid of the battlefield and prints
## the 15 steepest places, so one can confirm that the authored hills stay below the 0.85 slope (about 40 degrees)
## that actors and the player can walk, before any excavation.
## Method: base_surface_height is sampled every 8 m over x -160..160 and z -390..390; slope is the larger of the
## x and z height differences over a 2 m step. Prints STEEP_SLOPES with {x, z, slope} sorted steepest first.
## Run: godot --headless --path <repo> --script res://reviews/grade_probe.gd
extends SceneTree

## SceneTree entry point; defers to run().
func _initialize():call_deferred("run")

## Loads the Ardennes scene in test mode, scans the grid and prints the steepest cells.
func run():
	set_meta("battle_test",true)
	var g=load("res://scenes/ardennes.tscn").instantiate()
	root.add_child(g)
	await physics_frame
	var slopes=[]
	for x in range(-160,161,8):
		for z in range(-390,391,8):
			var h=g.world.base_surface_height(x,z)
			var slope=maxf(absf(g.world.base_surface_height(x+2,z)-h)/2,absf(g.world.base_surface_height(x,z+2)-h)/2)
			if slope>0.85:slopes.append({"x":x,"z":z,"slope":slope})
	slopes.sort_custom(func(a,b):return a.slope>b.slope)
	print("STEEP_SLOPES ",JSON.stringify(slopes.slice(0,15)))
	g.queue_free()
	await process_frame
	quit()
