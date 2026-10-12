extends SceneTree
var g
var snapshots=[]
var sample_times=[]
var durations=[]
func _initialize():call_deferred("run")
func snapshot():
	var states={}
	var positions=[]
	var living=0
	var stuck=0
	var engineers=0
	var spread=[]
	var crossed=0
	for a in g.friendlies:
		if not a.alive or a.boat!=null or a.staged:continue
		living+=1
		states[a.state]=int(states.get(a.state,0))+1
		if a.stuck>0.5:stuck+=1
		if a.bangalores>0:engineers+=1
		if a.truck==null:
			positions.append(a.position.z)
			spread.append(a.position.x)
			if a.position.z<g.Layout.WIRE_ROWS[2]-2:crossed+=1
	positions.sort()
	spread.sort()
	var record={"time":snappedf(g.elapsed,0.1),"allies":g.allies_alive,"enemies":g.germans_alive,"shots":g.ammo_spent,"vehicle_shots":g.vehicle_shots,"penetrations":g.boat_penetrations,"breaches":g.breaches,"grenades":g.grenade_detonations,"secured":g.secured,"town":g.town_control,"states":states,"foot_soldiers":positions.size(),"past_all_wire":crossed,"width_90_percent":spread[int(spread.size()*0.95)]-spread[int(spread.size()*0.05)] if spread.size()>1 else 0,"front_z":positions[0] if not positions.is_empty() else 0,"median_z":positions[int(positions.size()/2)] if not positions.is_empty() else 0,"stuck":stuck,"engineers":engineers,"shots_at_player":g.shots_at_player,"shots_at_ai":g.shots_at_ai,"departed":g.boats.filter(func(b):return b.departed).size(),"friendly_deaths":g.friendly_death_causes.duplicate()}
	snapshots.append(record)
	print("SNAPSHOT ",JSON.stringify(record))
	var file=FileAccess.open("res://reviews/omaha/simulation-progress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshots,"  "))
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.begin()
	# Observe without an unattended player death aborting the AI battle.
	# No team health/ammo buffs: observer is moved away after disembarkation.
	g.player.set_physics_process(false)
	g.player.collision_layer=0
	var targets=[45,65,90,120,180,240,275,300,360,480,600]
	if OS.has_environment("OMAHA_SIM_END"):
		targets=targets.filter(func(t):return t<=int(OS.get_environment("OMAHA_SIM_END")))
	var index=0
	var last=Time.get_ticks_usec()
	while g.elapsed<targets.back()+0.1:
		await physics_frame
		if g.player.truck==null:g.player.position=Vector3(1100,80,0)
		var now=Time.get_ticks_usec()
		durations.append((now-last)/1000.0)
		last=now
		if g.elapsed>=targets[index]:
			snapshot()
			index+=1
			if index>=targets.size():break
		if g.phase!="playing":g.phase="playing"
	durations.sort()
	var result={"seed":19440606,"mode":"headless simulation, not GPU FPS","snapshots":snapshots,"median_step_ms":durations[int(durations.size()*0.5)],"p95_step_ms":durations[int(durations.size()*0.95)],"p99_step_ms":durations[int(durations.size()*0.99)]}
	var file=FileAccess.open("res://reviews/omaha/simulation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("RESULT ",JSON.stringify(result))
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit()
