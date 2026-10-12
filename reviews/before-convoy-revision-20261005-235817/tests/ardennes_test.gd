extends SceneTree
var g
var checks:Array=[]
var snapshots:Array=[]
func _initialize():call_deferred("run")
func ticks(n):
	for i in range(n):await physics_frame
func check(ok:bool,label:String):
	checks.append({"check":label,"passed":ok})
	print(("PASS " if ok else "FAIL ")+label)
func make_game():
	g=load("res://scenes/ardennes.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await ticks(3)
func clean():
	g.phase="title"
	for i in range(1200):
		if g.world.pending_cuts.is_empty() and g.world.active_cuts.is_empty():break
		await process_frame
	g.queue_free()
	await ticks(4)
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19441223)
	await make_game()
	check(g.phase=="title","Winter mission opens at its start screen")
	check(g.trucks.size()==9 and g.friendlies.size()==107 and g.enemies.size()==80,"Nine trucks carry 107 allied actors plus the player against 80 Germans")
	check(g.trucks.all(func(t):return t.occupants.size()==(11 if t.index==4 else 12)),"Convoy seating contains twelve people per planned squad load")
	check(g.world.nests.size()==8 and g.enemies.filter(func(a):return a.mounted).size()==8,"All eight MG positions have their own actual gunner")
	check(g.friendlies.filter(func(a):return a.weapon_kind=="m2").size()==2,"Two mounted M2 Brownings are separate from infantry BARs")
	check(g.actors.all(func(a):return a.grenades>=2 and a.rounds>0 and a.reserve>0),"Every soldier starts with finite ammunition and at least two grenades")
	check(g.player.gun_kind=="bar" and g.player.ammo==20 and g.player.reserve==120 and g.player.has_shovel,"Player begins with a twenty-round BAR, reserve ammunition, sword and shovel")
	check(g.world.terrain_chunks.size()>300 and g.world.covers.size()>1000,"The winter battlefield has hilly terrain chunks and hundreds of cover sites")
	check(g.tactics.book.plans.has("flank_left") and g.tactics.groups.size()==3,"Reusable area plans and three command groups are initialized")
	g.begin()
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for a in g.actors:a.set_physics_process(false)
	var shooter=g.friendlies[20]
	var friendly=g.friendlies[21]
	var enemy=g.enemies[21]
	shooter.global_position=Vector3(0,45,0)
	friendly.global_position=Vector3(0,45,-10)
	enemy.global_position=Vector3(0,45,-20)
	await ticks(2)
	check(not g.safe_fire_line(shooter,shooter.eye(),enemy.aim_point()),"Bots refuse a shot whose dispersion cone contains a friendly")
	friendly.position.x=12
	await ticks(2)
	check(g.safe_fire_line(shooter,shooter.eye(),enemy.aim_point()),"A clear hostile firing lane is permitted")
	var hp=friendly.health
	g.shoot(shooter,shooter.eye(),friendly.aim_point(),0,24,"garand")
	check(friendly.health<hp and g.friendly_fire_hits>0,"Actual bullets can wound allies despite preventive fire discipline")
	check(not g.safe_explosive_target(shooter,friendly.position,7),"Bots reject a grenade target beside allies")
	g.player.truck=null
	g.player.position=Vector3(60,45,0)
	g.player.rotation=Vector3.ZERO
	g.player.head.rotation=Vector3.ZERO
	g.player.cooldown=0
	g.player.attack()
	check(g.player.ammo==19,"BAR fire consumes one physical magazine round")
	var broken=g.drop_weapon("kar98",5,0,g.player.position,0)
	broken.take(g.player)
	await ticks(2)
	check(g.player.gun_kind=="kar98" and g.player.has_rifle and g.player.rifle_health==0,"A broken dropped rifle is still pickable and occupies the single firearm slot")
	var ammo=g.player.ammo
	g.player.cooldown=0
	g.player.attack()
	check(g.player.ammo==ammo,"Broken guns cannot fire")
	check(get_nodes_in_group("dropped_weapons").filter(func(d):return d.kind=="bar" and not d.picked_up and d.rounds==19).size()==1,"Swapping drops the previous gun with its exact remaining loaded rounds")
	var usable=g.drop_weapon("g43",7,83,g.player.position,0)
	usable.take(g.player)
	await ticks(2)
	check(g.player.gun_kind=="g43" and g.player.ammo==7 and g.player.reserve==0,"German gun pickup does not convert the BAR's .30-06 reserve")
	g.player.stash_ammo("792",10)
	g.player.reload_weapon()
	g.player._physics_process(g.player.reload_time+0.01)
	check(g.player.ammo==10 and g.player.reserve==7,"Reload consumes only the new gun's compatible reserve")
	var victim=g.enemies[35]
	victim.position=Vector3(110,g.world.height_at(110,220),220)
	var body_reserve=victim.reserve
	var body_rounds=victim.rounds
	victim.take_damage(1000,Vector3.ZERO,"rifle")
	await ticks(2)
	var bodies=get_nodes_in_group("winter_corpses")
	check(bodies.size()==1 and bodies[0].parts.size()==6,"A death creates a persistent articulated body")
	check(get_nodes_in_group("dropped_weapons").any(func(d):return d.kind==victim.weapon_kind and d.rounds==body_rounds),"Death drops the gun with its remaining magazine")
	var part=bodies[0].parts[1]
	part.receive_hit(100,part.global_position+Vector3.RIGHT)
	check(part.detached and bodies[0].detached_count==1,"Further bullet damage can detach a body part")
	bodies[0].blast(victim.position,5,250)
	check(bodies[0].detached_count>1,"An explosion can dismember persistent remains")
	g.player.ammo_pack.containers.clear()
	g.player.grenades=2
	var before=g.player.reserve
	var result=g.loot(victim)
	check(g.player.reserve==before+body_reserve and result.grenades==2 and victim.reserve==0,"Body loot transfers only actual remaining reserve and grenades")
	check(g.player.grenade_types.count("m24")==2,"Looted German grenades retain their type within the shared four-grenade limit")
	var after=g.player.reserve
	check(g.loot(victim).is_empty() and g.player.reserve==after,"The same corpse cannot duplicate loot")
	# A full pack leaves excess rounds and grenades on the body for a later visit.
	var donor=g.enemies[37]
	g.player.ammo_pack.containers.clear()
	check(g.player.ammo_pack.add_rounds("bar",999)==160 and is_equal_approx(g.player.ammo_pack.space_used(),24),"BAR magazines fill the finite pack at eight spare magazines")
	var donor_ammo=donor.reserve
	var donor_grenades=donor.grenades
	g.player.grenades=4
	g.loot(donor)
	check(donor.reserve==donor_ammo and donor.grenades==donor_grenades and g.player.grenades==4,"Excess ammo and grenades remain on a body when the player's kit is full")
	g.player.ammo_pack.containers.clear()
	g.player.ammo_pack.add_rounds("kar98",5)
	g.player.ammo_pack.add_rounds("bar",1)
	check(is_equal_approx(g.player.ammo_pack.space_used(),3.5),"Stripper clips use less pack space, while a partial BAR magazine still uses a full slot")
	g.player.ammo_pack.add_rounds("mp40",999)
	g.player.ammo_pack.add_rounds("mg42",999)
	check(g.player.ammo_pack.space_used()<=24 and g.player.ammo_pack.weight_used()<=7.5,"Mixed calibers share both the pack's space and weight limits")
	await ticks(180)
	check(is_instance_valid(bodies[0]) and is_instance_valid(part),"Bodies and detached parts remain in the scene")
	var commander=g.tactics.commander
	commander.take_damage(1000,Vector3.ZERO,"rifle")
	g.update_squads()
	g.tactics.update(g)
	check(g.tactics.commander!=commander and g.tactics.commander.alive,"Command passes to a living subordinate when the commander is killed")
	var defender=g.enemies[0]
	defender.order="hold"
	defender.position=defender.home+Vector3(29,0,0)
	defender.state="advance"
	defender._physics_process(1.0/60)
	check(Vector2(defender.position.x-defender.home.x,defender.position.z-defender.home.z).length()<=defender.guard_radius+0.01,"A hold-area soldier cannot leave its assigned perimeter")
	for e in g.enemies:
		if e.alive and e.squad-9 in [0,1,2]:e.take_damage(1000,Vector3.ZERO,"test")
	g.dismounted=true
	g.update_squads()
	check(g.tactics.sector==1 and g.tactics.groups.all(func(group):return group.area in [3,4,5]),"Clearing the roadblock assigns surviving command groups to the ridge sector")
	check(g.toast_text.contains("SECTOR SECURED"),"Sector completion produces a navigation notification")
	var dig_point=g.world.on_ground(g.world.anchors[0]+Vector3(7,0,1))
	g.world.dig(dig_point,0.85)
	await ticks(60)
	var pit_ray=PhysicsRayQueryParameters3D.create(dig_point+Vector3(0,5,0),dig_point-Vector3(0,6,0),1)
	var pit=g.get_world_3d().direct_space_state.intersect_ray(pit_ray)
	check(not pit.is_empty() and pit.position.y<dig_point.y-0.2 and pit.position.y>dig_point.y-2,"Digging makes a bounded physical pit without removing the terrain chunk")
	await clean()
	await make_game()
	g.begin()
	# Observe from outside the engagement. No player shooting, orders, buffs or invulnerability.
	g.player.truck=null
	g.player.set_physics_process(false)
	g.player.position=Vector3(-155,40,280)
	var started=Time.get_ticks_msec()
	for second in range(1,181):
		await ticks(60)
		if second%30==0:
			var moves=0.0
			var shots=0
			var states={}
			for a in g.actors:
				moves+=a.travelled
				shots+=a.shots
				if a.alive:states[a.state]=int(states.get(a.state,0))+1
			var snap={"second":second,"phase":g.phase,"allies":g.allies_alive,"germans":g.germans_alive,"shots":shots,"travelled":moves,"states":states,"cuts":g.world.cut_jobs,"queued_cuts":g.world.pending_cuts.size(),"deaths":g.death_causes.duplicate(),"allied_deaths":g.friendly_death_causes.duplicate(),"grenades":g.grenade_detonations}
			snapshots.append(snap)
			print("SIM ",JSON.stringify(snap))
	var travel=0.0
	for a in g.friendlies:travel+=a.travelled
	check(int(g.death_causes.get("fall",0))==0,"No soldier falls through the terrain during the three-minute battle")
	check(g.lead_hit and g.rear_hit and g.trucks[0].destroyed and g.trucks[8].destroyed,"Both authored Panzerfaust projectiles hit and wreck the lead and rear trucks")
	check(g.column_stopped and g.dismounted,"The convoy stops and its survivors dismount in real time")
	check(g.friendlies.any(func(a):return a.truck==null and a.shots>0),"Dismounted Americans engage without the player participating")
	check(travel>200 and g.germans_alive<80,"The American force advances and inflicts casualties autonomously")
	check(g.tactics.orders_issued>0,"The command hierarchy issues reusable support and flanking plans")
	check(g.fire_checks_blocked>0,"Live combat exercises dispersion-cone friendly-fire avoidance")
	check(g.actors.all(func(a):return a.rounds>=0 and a.reserve>=0 and a.grenades>=0 and a.grenades<=2),"Combat cannot create negative ammunition or replenish bot grenades")
	check(g.actors.any(func(a):return a.reserve<a.spec.reserve or a.grenades<2),"The battle actually consumes carried supplies")
	check(g.enemies.filter(func(a):return a.order=="hold" and not a.staged).all(func(a):return a.far_from_hold<=a.guard_radius+0.01),"Defensive units retain their boundaries throughout the large battle")
	check(get_nodes_in_group("winter_corpses").size()==187-g.allies_alive-g.germans_alive,"Every casualty still has a body after three simulated minutes")
	var failed=checks.filter(func(c):return not c.passed)
	FileAccess.open("res://reviews/ardennes-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":checks.size()-failed.size(),"failed":failed.size(),"checks":checks,"simulation":snapshots,"headless_wall_ms":Time.get_ticks_msec()-started,"note":"Fixed-seed, headless mechanics and autonomous battle test; not a rendering benchmark."},"  "))
	print("ARDENNES_TEST_COMPLETE ",checks.size()," checks / ",failed.size()," failures")
	await clean()
	quit(0 if failed.is_empty() else 1)
