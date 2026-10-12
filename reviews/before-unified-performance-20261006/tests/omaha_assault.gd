extends SceneTree
var g
var attack=[]
var defend=[]
var results=[]
func _initialize():call_deferred("run")
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.phase="playing"
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	g.player.truck=null
	g.player.position=Vector3(1100,80,0)
	g.player.collision_layer=0
	for a in g.actors:
		a.staged=true
		a.set_physics_process(false)
		a.collision_layer=0
		a.equipment.collision_layer=0
	var center=g.world.anchors[3]
	for a in g.friendlies:
		if a.boat!=null or attack.size()>=42:continue
		a.truck=null
		a.staged=false
		a.position=g.world.on_ground(center+Vector3((attack.size()%7-3)*2.0,0,28+int(attack.size()/7)*1.7))
		a.sector=3
		a.lane=center.x
		a.home=a.position
		a.assault_stage=0
		a.collision_layer=8
		a.equipment.collision_layer=16
		a.set_physics_process(true)
		attack.append(a)
	for e in g.enemies:
		if e.sector!=3 or e.role=="town_guard":continue
		e.staged=false
		e.collision_layer=4
		e.equipment.collision_layer=16
		e.set_physics_process(true)
		defend.append(e)
	g.elapsed=500
	g.rebuild_spatial()
	for tick in range(150*60):
		await physics_frame
		g.elapsed+=1.0/60
		if tick%20==0:
			g.rebuild_spatial()
			for a in attack+defend:
				if a.alive:a.think(g.elapsed)
		g.step_projectiles(1.0/60)
		g.update_tracers(1.0/60)
		g.update_flashes()
		for effect in g.effects.duplicate():
			effect.time-=1.0/60
			if effect.time<=0:
				effect.node.queue_free()
				g.effects.erase(effect)
		if tick%1800==0:
			var states={}
			for a in attack:
				if a.alive:states[str(a.assault_stage)]=int(states.get(str(a.assault_stage),0))+1
			var record={"seconds":tick/60,"attackers":attack.filter(func(a):return a.alive).size(),"defenders":defend.filter(func(a):return a.alive).size(),"stages":states,"grenades":g.grenade_detonations}
			results.append(record)
			print("ASSAULT ",JSON.stringify(record))
		if defend.all(func(e):return not e.alive):break
	var remaining=defend.filter(func(e):return e.alive)
	var survivors=attack.filter(func(a):return a.alive)
	var report={"fixture":"42 infantry starting behind wire vs one complete 11-man strongpoint; unchanged health/ammo", "snapshots":results,"survivors":survivors.size(),"remaining_defenders":remaining.map(func(a):return {"index":a.index,"role":a.role,"health":a.health,"position":str(a.position)}),"soldiers":survivors.map(func(a):return {"index":a.index,"stage":a.assault_stage,"position":str(a.position),"state":a.state,"ammo":a.rounds+a.reserve}),"success":remaining.is_empty()}
	var file=FileAccess.open("res://reviews/omaha/inland-assault.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("ASSAULT_RESULT ",JSON.stringify(report))
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit(0 if report.success else 1)
