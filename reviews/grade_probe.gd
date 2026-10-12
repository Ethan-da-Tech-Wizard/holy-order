extends SceneTree
func _initialize():call_deferred("run")
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
