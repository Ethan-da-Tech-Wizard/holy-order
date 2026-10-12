extends SceneTree
var g
func _initialize():call_deferred("run")
func ticks(n):
	for i in range(n):await physics_frame
func run():
	g=load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	current_scene=g
	await ticks(60)
	g.phase="playing"
	g.player.position=Vector3(0,0.04,20)
	g.player.health=100000
	g.player.set_physics_process(false)
	g.player.set_process(false)
	g.pickup_played=true
	g.enemies[0].take_damage(200)
	g.emit_noise(Vector3(0,1.5,26),175,1,"gunshot")
	var positions={}
	for e in g.enemies.slice(1):positions[e.index]=e.position
	var samples=[]
	Engine.time_scale=3
	var mg_occupied=false
	var digs=0
	for cycle in range(12):
		await ticks(150)
		var actors=[]
		for e in g.enemies.slice(1):
			actors.append({"index":e.index,"role":e.role,"state":e.state,"position":str(e.position),"visible":e.visible_target,"shots":e.shots_fired,"rounds":e.rounds,"reserve":e.reserve_rounds,"destination":str(e.destination),"path_remaining":e.path.size()-e.path_cursor,"cover":e.has_cover,"dug":e.entrenched})
			if e.mounted:mg_occupied=true
			if e.entrenched:digs+=1
		samples.append(actors)
		print("AI_SAMPLE ",cycle," ",JSON.stringify(actors))
	var assault_moved=true
	for e in g.enemies:
		if e.role=="assault" and e.position.distance_to(positions[e.index])<12:assault_moved=false
	var report={"assault_advanced":assault_moved,"mg_manned":mg_occupied,"mg_shots":g.mg_nest.shots_fired,"defenders_dug":digs>0,"samples":samples}
	FileAccess.open("res://reviews/ai-simulation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("AI_SIMULATION_COMPLETE ",assault_moved," MG ",mg_occupied," shots ",g.mg_nest.shots_fired," digging ",digs)
	g.phase="title"
	Engine.time_scale=1
	await ticks(4)
	quit(0 if assault_moved and mg_occupied else 1)
