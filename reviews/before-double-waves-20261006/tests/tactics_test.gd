extends SceneTree
var g
var checks: Array=[]
func _initialize():call_deferred("run")
func check(ok: bool, text: String):
	checks.append({"check":text,"passed":ok})
	print(("PASS " if ok else "FAIL ")+text)
func ticks(n: int):
	for i in range(n):await physics_frame
func blocked(a: Vector3,b: Vector3) -> bool:
	return not g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1)).is_empty()
func run():
	g=load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	current_scene=g
	await ticks(50)
	check(g.phase=="title" and g.remaining()==6,"Six actors wait safely at the title screen")
	check(g.enemies.filter(func(e):return e.role=="assault").size()==2,"Exactly two village soldiers are assigned assault roles")
	check(g.enemies.filter(func(e):return e.role in ["hold","mg"]).size()==3 and g.enemies[5].role=="mg","Three defenders include one designated MG gunner")
	check(g.world.navigation.ready_for_paths,"Navigation graph builds from the village collision")
	check(get_nodes_in_group("field_door").size()==7,"All seven houses have usable hinged doors")
	var nav=g.world.navigation
	var route=nav.path_between(Vector3(28,0,-16),Vector3(0,0,26))
	check(route.size()>10 and route[-1].distance_to(Vector3(0,0,26))<3,"Assault route reaches the isolated checkpoint around buildings")
	g.phase="playing"
	g.player.set_physics_process(false)
	for e in g.enemies:e.set_physics_process(false)
	g.player.position=Vector3(60,0,50)
	g.emit_noise(g.enemies[0].position,10,1,"melee")
	check(not g.enemies.slice(1).any(func(e):return e.alerted),"A quiet sentry melee takedown does not alert the village")
	g.emit_noise(g.enemies[0].position,175,0,"gunshot")
	check(g.enemies.slice(1).all(func(e):return e.alerted),"A sentry rifle report reaches all five village soldiers")
	check(g.enemies.slice(1).all(func(e):return not e.visible_target),"Hearing gunfire does not create visual target contact")
	for e in g.enemies.slice(1):e.decide()
	check(g.enemies.filter(func(e):return e.role=="assault").any(func(e):return e.state=="investigating"),"Assault soldiers investigate the sound direction")
	check(g.enemies[1].has_cover and g.enemies[4].has_cover,"Defenders select valid occluded cover positions")
	var e=g.enemies[1]
	var remembered=e.last_known
	g.player.position=Vector3(-60,0,55)
	e.perceive()
	check(not e.visible_target and e.last_known==remembered,"Unseen player movement does not update an enemy's remembered position")
	var miss_start=e.eye_position()+Vector3(0.8,0,10)
	g.notify_projectile(miss_start,miss_start+Vector3(0,0,-20),1)
	check(e.near_misses>0 and e.suppressed>0 and not e.has_cover,"A near miss suppresses a soldier and forces cover re-evaluation")
	e.digging=4.0
	e.hear_noise(e.position+Vector3(0,0,60),"gunshot")
	check(e.digging>0,"A distant gunshot lets an already sheltered defender continue digging")
	e.hear_noise(e.position+Vector3(0,0,2),"footstep")
	check(e.digging==0 and e.close_sound,"Very close footsteps interrupt digging and tighten the search")
	var ally=g.enemies[2]
	var ally2=g.enemies[3]
	ally.suppressed=0;ally2.suppressed=0
	g.elapsed=1
	var first=g.assault_can_move(ally)
	check(first!=g.assault_can_move(ally2),"Assault pair alternate movement and covering roles")
	g.elapsed=7
	check(g.assault_can_move(ally)!=first,"The next bound exchanges the assault pair's roles")
	# Real rounds and geometry: arrange a clear firing lane outside the settlement.
	e.position=Vector3(55,0,10)
	e.stance=0
	e.rotation.y=PI
	g.player.position=Vector3(55,0,22)
	e.target_actor=g.player
	e.visible_target=true
	g.player.health=1000
	await ticks(3)
	var initial=e.rounds+e.reserve_rounds
	for i in range(6):e.shoot()
	check(e.rounds==0 and e.shots_fired==6 and e.rounds+e.reserve_rounds==initial-6,"Enemy rifle shots consume six actual loaded rounds")
	e.shoot()
	check(e.shots_fired==6,"An empty enemy rifle cannot fire a seventh round")
	e.reload_time=0.01
	e._physics_process(0.02)
	check(e.rounds==6 and e.reserve_rounds==12,"Enemy reload transfers a real six-round clip from reserve")
	var shield=g.Art.solid(g,Vector3(5,3,0.35),Vector3(55,1.5,16),g.Art.material(Color.GRAY),0,"masonry")
	await ticks(3)
	var shots=e.shots_fired
	e.shoot()
	check(e.shots_fired==shots,"Enemy cannot fire an aimed rifle shot through an intact wall")
	shield.queue_free()
	await ticks(3)
	e.rounds=0;e.reserve_rounds=0;e.decide()
	check(e.state=="knife_assault","A soldier with no rifle ammunition resorts to a knife")
	# The MG's box is independent of rifle ammunition and has a strict 80-shot total.
	var mg=g.mg_nest
	check(mg.rounds==20 and mg.spare_trays==3,"Breda M37 starts with one 20-round tray plus three in its box")
	mg.claim(g.enemies[5])
	for n in range(80):
		mg.cooldown=0
		if mg.rounds==0:
			mg._physics_process(0.01)
			mg._physics_process(3.3)
		mg.try_fire(mg.global_position+Vector3(0,1.2,25))
	check(mg.shots_fired==80 and mg.rounds==0 and mg.spare_trays==0,"Mounted gun exhausts exactly 80 rounds and empties its adjacent box")
	mg.cooldown=0
	check(not mg.try_fire(mg.global_position+Vector3(0,1.2,25)),"An empty mounted gun cannot fabricate more ammunition")
	g.enemies[5].mounted=true
	g.enemies[5]._physics_process(0.02)
	check(not g.enemies[5].mounted and g.enemies[5].role=="hold" and g.enemies[5].rounds==6,"Dry MG gunner dismounts and retains his separate Carcano inventory")
	# Loot contains what remained at death, with no duplicate grants.
	e.rounds=2;e.reserve_rounds=7
	e.take_damage(200)
	g.player.position=e.position+Vector3(1.2,0,0)
	g.player.has_rifle=true
	g.player.select_weapon(1)
	await ticks(4)
	var reserve=g.player.reserve
	g.interact()
	var lint=g.lint
	g.interact()
	check(g.player.reserve==reserve+9 and lint>0 and g.lint==lint,"Corpse loot transfers both remaining reserve and loaded rounds, once")
	check(g.player.has_shovel,"Looting a soldier provides the entrenching tool")
	g.player.receive_equipment_damage("rifle",150)
	check(not g.player.has_rifle and not g.player.rifle.visible,"A shot-damaged player rifle breaks and is stowed")
	g.interact()
	check(g.player.has_rifle and g.player.ammo==0,"Recovering an already stripped corpse rifle cannot duplicate its cartridges")
	# Damage edits the collision, not just a cosmetic decal.
	var door=get_nodes_in_group("field_door")[0]
	var centre=door.interaction_position()
	var a=centre+Vector3(0,0,1)
	var b=centre-Vector3(0,0,1)
	check(blocked(a,b),"Closed timber door blocks the doorway")
	door.use()
	await create_timer(0.6).timeout
	check(door.opened and not blocked(a,b),"Opening the door creates a traversable aperture")
	door.use()
	await create_timer(0.6).timeout
	check(not door.opened and blocked(a,b),"The same door closes again")
	var wall=g.Art.solid(g,Vector3(5,3,0.4),Vector3(56,1.5,-6),g.Art.material(Color.GRAY),0,"masonry")
	await ticks(2)
	check(blocked(Vector3(56,1,-4),Vector3(56,1,-8)),"Masonry initially blocks a firing and traversal route")
	wall.damage_at(780,Vector3(56,1,-5.8),1.4,true)
	await ticks(12)
	check(not blocked(Vector3(56,1,-4),Vector3(56,1,-8)) and blocked(Vector3(58,1,-4),Vector3(58,1,-8)),"A demolition breach removes actual wall collision while preserving its sides")
	var stone=g.Art.solid(g,Vector3(2,2,1),Vector3(64,1,-6),g.Art.material(Color.GRAY),0,"rock")
	var wood=g.Art.solid(g,Vector3(2,2,1),Vector3(68,1,-6),g.Art.material(Color.BROWN),0,"wood")
	await ticks(2)
	check(not stone.damage_at(42,stone.position+Vector3(0,0,0.5)) and wood.damage_at(42,wood.position+Vector3(0,0,0.5)),"The same rifle hit breaches timber before it damages rock")
	var before_floor=g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(56,2,40),Vector3(56,-5,40),1))
	g.world.dig(Vector3(56,0,40))
	await ticks(15)
	var after_floor=g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(56,2,40),Vector3(56,-5,40),1))
	check(not before_floor.is_empty() and not after_floor.is_empty() and after_floor.position.y<before_floor.position.y-0.6,"Digging creates a real trench floor below the original terrain")
	g.demolition.take()
	g.demolition.take()
	check(g.demolition.carried==1 and g.demolition.stock==2,"Optional engineer cache enforces one satchel carried at a time")
	g.player.position=Vector3(56,0,30)
	g.player.rotation=Vector3.ZERO
	g.player.head.rotation=Vector3(-0.9,0,0)
	g.player.camera.rotation=Vector3.ZERO
	await ticks(2)
	g.demolition.deploy(false)
	check(is_instance_valid(g.demolition.active) and g.demolition.carried==0,"A satchel can be placed on real nearby geometry")
	g.demolition.recover()
	check(g.demolition.carried==1 and not is_instance_valid(g.demolition.active),"Recovering an unused satchel conserves the inventory")
	g.demolition.deploy(true)
	await ticks(70)
	check(is_instance_valid(g.demolition.active) and g.demolition.settled,"Lobbed satchel lands and stays available for wired detonation")
	g.player.position=Vector3(5,0,40)
	g.demolition._physics_process(0.02)
	check(g.demolition.cable_broken,"Moving beyond the available cable disables remote detonation")
	g.demolition.recover()
	# Reuse the same tactical controller for a friendly; perception finds hostiles.
	var friendly=g.Enemy.new()
	friendly.game=g;friendly.team=1;friendly.index=8
	friendly.position=Vector3(58,0,10)
	g.add_child(friendly);g.friendlies.append(friendly)
	friendly.set_physics_process(false)
	g.enemies[4].position=Vector3(58,0,20)
	friendly.rotation.y=PI
	await ticks(3)
	friendly.perceive()
	check(friendly.visible_target and friendly.target_actor==g.enemies[4],"Friendly AI uses the same controller but acquires hostile soldiers")
	g.pickup_played=true
	g.enemies[0].position=Vector3(60,0,50)
	g.enemies[0].rounds=3
	g.enemies[0].reserve_rounds=11
	g.enemies[0].weapon_health=62
	g.player.position=Vector3(61.5,0,50.4)
	var carried_reserve=g.player.reserve
	g.enemies[0].take_damage(200)
	await ticks(4)
	g.interact()
	check(g.player.ammo==3 and g.player.rifle_health==62 and g.player.reserve==carried_reserve,"Sentry pickup preserves fired rounds, existing reserves and rifle damage")
	g.interact()
	check(g.player.reserve==carried_reserve+11 and g.enemies[0].reserve_rounds==0,"Loot physically transfers the sentry's remaining reserve inventory")
	g.phase="title"
	var failed=checks.filter(func(c):return not c.passed)
	FileAccess.open("res://reviews/tactical-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed.size(),"failed":failed.size()},"  "))
	print("TACTICAL_TESTS_COMPLETE ",checks.size()," checks; ",failed.size()," failures")
	await ticks(4)
	quit(0 if failed.is_empty() else 1)
