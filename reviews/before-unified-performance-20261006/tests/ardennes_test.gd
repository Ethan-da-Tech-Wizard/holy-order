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
	check(g.world.nests.size()+g.world.secondary_nests.size()==12 and g.enemies.filter(func(a):return a.mounted).size()==12,"Twelve road-facing machine guns have actual finite-inventory gunners")
	check(g.friendlies.all(func(a):return not a.mounted and a.weapon_kind in ["bar","garand"]),"All convoy troops are seated infantry with no firing exception")
	check(g.actors.all(func(a):return a.grenades>=2 and a.rounds>0 and a.reserve>0),"Every soldier starts with finite ammunition and at least two grenades")
	check(g.player.gun_kind=="bar" and g.player.ammo==20 and g.player.reserve==120 and g.player.has_shovel,"Player begins with a twenty-round BAR, reserve ammunition, sword and shovel")
	check(g.world.terrain_chunks.size()>300 and g.world.covers.size()>1000,"The winter battlefield has hilly terrain chunks and hundreds of cover sites")
	check(g.tactics.book.plans.has("flank_left") and g.tactics.groups.size()==2,"Reusable area plans and two mission wings are initialized")
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
	for truck in g.trucks:
		if not truck.destroyed:truck.dismount("test")
	g.update_squads()
	var left=g.friendlies.filter(func(a):return a.alive and a.wing==-1).size()
	var right=g.friendlies.filter(func(a):return a.alive and a.wing==1).size()
	check(absi(left-right)<=1 and left+right==g.allies_alive,"Every dismounted survivor is assigned to a balanced left or right wing")
	check(g.tactics.groups[0].area==6 and g.tactics.groups[1].area==7,"Both wings begin by clearing the ambush hilltops")
	for e in g.enemies:
		if e.alive and e.squad-9 in [6,7]:e.take_damage(1000,Vector3.ZERO,"test")
	g.update_squads()
	check(g.tactics.opening_secured and g.tactics.groups[0].area==4 and g.tactics.groups[1].area==5,"Clearing both ambush hills sends each wing back down its own ridge")
	check(g.toast_text.contains("hilltop") or g.toast_text.contains("SECURED"),"Hilltop completion produces a navigation notification")
	var dig_point=g.world.on_ground(g.world.anchors[0]+Vector3(7,0,1))
	dig_point.x=roundf(dig_point.x)
	dig_point.z=roundf(dig_point.z)
	dig_point=g.world.on_ground(dig_point)
	g.world.dig(dig_point,1.3,0.60)
	await ticks(60)
	var pit_ray=PhysicsRayQueryParameters3D.create(dig_point+Vector3(0,5,0),dig_point-Vector3(0,6,0),1)
	var pit=g.get_world_3d().direct_space_state.intersect_ray(pit_ray)
	check(not pit.is_empty() and pit.position.y<dig_point.y-0.2 and pit.position.y>dig_point.y-2,"Digging makes a bounded physical pit without removing the terrain chunk")
	var crouch_event=InputEventAction.new()
	crouch_event.action="crouch"
	crouch_event.pressed=true
	g.player.crouched=false
	g.player.prone=false
	g.player._unhandled_input(crouch_event)
	crouch_event.pressed=false
	g.player._unhandled_input(crouch_event)
	check(g.player.crouched,"Crouch remains selected after releasing the key")
	crouch_event.pressed=true
	g.player._unhandled_input(crouch_event)
	check(not g.player.crouched,"Pressing crouch again returns to standing")
	g.player.prone=true
	g.player.update_view(0.1)
	check(not g.player.lower_body.visible,"Prone first-person view hides the upright boot geometry")
	g.player.prone=false
	g.player.grenades=4
	var grenade_before=g.grenades_live.size()
	for i in range(12):g.player.begin_grenade()
	check(g.player.grenades==4 and g.player.grenade_time>0 and g.grenades_live.size()==grenade_before,"Grenade key spam starts only one windup and cannot spawn instant throws")
	g.player.step_grenade(0.70)
	for i in range(12):g.player.begin_grenade()
	check(g.player.grenades==3 and g.grenades_live.size()==grenade_before+1,"The throw releases and consumes exactly one grenade")
	g.player.step_grenade(0.40)
	g.player.begin_grenade()
	check(g.player.grenade_time==0,"Grenade recovery prevents an immediate second throw")
	var attacker=g.friendlies.filter(func(a):return a.alive)[0]
	attacker.position=Vector3(-165,30,405)
	attacker.target=null
	attacker.threat_pressure=7
	attacker.suppression=3
	attacker.contact_age=20
	attacker.last_known=attacker.position+Vector3(30,0,-10)
	attacker.think(g.elapsed)
	check(attacker.stance=="prone" and attacker.state=="crawl","A heavily suppressed attacker without sight of an enemy crawls toward its mission")
	var mission=g.tactics.formation_goal(g,attacker)-attacker.position
	var course=attacker.destination-attacker.position
	check(Vector2(mission.x,mission.z).dot(Vector2(course.x,course.z))>0,"Suppression movement still makes progress toward the assigned hilltop")
	check(g.enemies.all(func(a):return a.order=="hold"),"All defenders retain encampment orders")
	var empty_guard=g.enemies[0]
	empty_guard.position=g.world.on_ground(Vector3(-150,0,-390))
	empty_guard.home=empty_guard.position
	empty_guard.entrenched=true
	empty_guard.rounds=0
	empty_guard.reserve=0
	var strokes_before=empty_guard.dig_strokes
	for i in range(210):
		empty_guard.think(g.elapsed+i*0.1)
		empty_guard.step_actor(0.1)
	check(empty_guard.dig_strokes==strokes_before,"An entrenched defender without ammunition holds cover instead of digging endlessly")
	var assigned_area=g.squads[attacker.squad].area
	attacker.hear_noise(g.world.anchors[7]+Vector3(0,2,0),900,0,"gunshot")
	g.tactics.update(g)
	check(g.squads[attacker.squad].area==assigned_area,"Opposite-wing gunfire does not replace the assigned mission")
	attacker.grenade_clock=0
	attacker.grenades=2
	var throw_at=Vector3(-150,30,390)
	var live_before=g.grenades_live.size()
	attacker.begin_grenade(throw_at)
	check(attacker.grenades==2 and attacker.grenade_visual.visible and g.grenades_live.size()==live_before,"AI grenades also begin with a visible windup")
	attacker.step_grenade(0.72)
	check(attacker.grenades==1 and g.grenades_live.size()==live_before+1,"AI releases one carried grenade after the windup")
	attacker.step_grenade(0.5)
	attacker.grenade_clock=0
	attacker.begin_grenade(throw_at)
	friendly.position=throw_at
	attacker.step_grenade(0.72)
	check(attacker.grenades==1 and g.grenades_live.size()==live_before+1,"AI cancels release when a friendly enters the grenade landing area")
	var deep=Vector3(140,0,350)
	deep=g.world.on_ground(deep)
	for stroke in range(5):
		g.world.dig(deep,1.65,0.45)
		await ticks(5)
	check(g.world.surface_height(deep.x,deep.z)<deep.y-1.3,"Repeated shovel work creates a deep, wide excavation")
	var scar=g.world.on_ground(Vector3(140,0,370))
	g.world.blast(scar,380,5)
	await ticks(12)
	check(g.world.surface_height(scar.x,scar.z)>=scar.y-0.18,"A grenade-sized blast makes only a shallow soil scar")
	var breach=g.world.on_ground(Vector3(140,0,310))
	var wall=g.world.solid(Vector3(6,2.8,0.3),breach+Vector3(0,1.4,0),g.world.snow,"wood")
	g.player.shape.shape.height=1.80
	g.player.shape.position.y=0.90
	g.player.position=breach+Vector3(0,0.1,2)
	await ticks(3)
	check(g.player.test_move(g.player.global_transform,Vector3(0,0,-4)),"An intact timber wall blocks the player capsule")
	g.world.blast(breach+Vector3(0,1.0,0),380,5)
	await ticks(90)
	check(not g.player.test_move(g.player.global_transform,Vector3(0,0,-4)) and not wall.destroyed,"A close grenade blast opens a traversable breach while part of the wall remains")
	var max_grade=0.0
	for x in range(-160,161,8):
		for z in range(-390,391,8):
			var h=g.world.base_surface_height(x,z)
			max_grade=maxf(max_grade,maxf(absf(g.world.base_surface_height(x+2,z)-h)/2,absf(g.world.base_surface_height(x,z+2)-h)/2))
	check(max_grade<0.90,"Authored hills stay below the walking slope limit before excavation")
	print("TERRAIN_MAX_GRADE ",max_grade)
	await clean()
	await make_game()
	g.begin()
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for a in g.actors:a.set_physics_process(false)
	var t=g.trucks[4]
	var held=g.player.ammo
	g.player.cooldown=0
	g.player.attack()
	g.player.begin_grenade()
	check(g.player.ammo==held and g.player.grenade_time==0,"The seated player cannot fire or throw grenades")
	var passenger=t.occupants[0]
	passenger.target=g.enemies[1]
	passenger.state="fire"
	passenger.shot_clock=0
	passenger.contact_age=0
	passenger.try_fire()
	check(passenger.shots==0,"AI passengers cannot fire while riding")
	var ray=PhysicsRayQueryParameters3D.create(t.to_global(Vector3(0,2.7,1)),t.to_global(Vector3(3,2.7,1)),1)
	var side_hit=g.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not side_hit.is_empty() and side_hit.collider.get_meta("truck_role","")=="armor","The troop compartment has physical steel side armor")
	var rear_ray=PhysicsRayQueryParameters3D.create(t.to_global(Vector3(0,2.7,1)),t.to_global(Vector3(0,2.7,5)),1)
	check(not g.get_world_3d().direct_space_state.intersect_ray(rear_ray).is_empty(),"Rear steel protects passengers below the viewing slit")
	var slit_ray=PhysicsRayQueryParameters3D.create(t.to_global(Vector3(0,2.94,1)),t.to_global(Vector3(0,2.94,5)),1)
	check(g.get_world_3d().direct_space_state.intersect_ray(slit_ray).is_empty(),"The armored rear retains a narrow view outside")
	var lead=g.trucks[0]
	lead.wheel_health[0]=0
	lead.wheel_health[1]=0
	lead.tick(0.01)
	var following=g.trucks[1]
	following.tick(0.2)
	check(following.bypass_attempts>0 and following.desired_lane!=0,"A following truck attempts to go around a wheel-disabled vehicle")
	for i in range(720):following.tick(1.0/60)
	check(following.progress>lead.progress+5 and not following.unloaded,"The passing truck clears the obstruction and continues its journey")
	var cripple=g.trucks[3]
	cripple.receive_part_damage(2500,cripple.wheels[0].global_position,true,cripple.wheels[0])
	cripple.receive_part_damage(2500,cripple.wheels[1].global_position,true,cripple.wheels[1])
	cripple.tick(6.1)
	check(cripple.disabled and cripple.unloaded and cripple.occupants.all(func(a):return not a.alive or a.truck==null),"A truck with two ruined wheels detects no progress and orders dismount")
	check(not g.lead_strike and g.ambush_outcome=="pending","An early disabled truck does not force the distant scripted ambush")
	g.decide_ambush([])
	check(g.ambush_outcome=="skipped" and g.rockets.is_empty(),"No arriving trucks means no authored ambush shots")
	# A controlled one-truck arrival must not invent a rear truck or a second hit.
	g.ambush_outcome="pending"
	for vehicle in g.trucks:vehicle.unloaded=true
	t.unloaded=false
	t.progress=t.END_PROGRESS
	t.arrived=true
	t.update_transform()
	var launcher=g.staged_launchers[1]
	launcher.position=t.position+Vector3(6,1,0)
	launcher.home=launcher.position
	launcher.fausts=1
	await ticks(3)
	g.decide_ambush([t])
	check(g.ambush_targets.size()==1 and g.lead_strike and g.rear_at<0,"One eligible arriving truck gets only the front strike")
	for i in range(90):g.step_projectiles(1.0/60)
	check(not t.destroyed and t.unloaded and g.lead_hit and not g.rear_hit,"The selected armored truck survives the ambush hit and unloads")
	await clean()
	await make_game()
	g.begin()
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for a in g.actors:a.set_physics_process(false)
	for vehicle in g.trucks:vehicle.unloaded=true
	var front=g.trucks[0]
	var rear=g.trucks[8]
	front.unloaded=false
	rear.unloaded=false
	front.progress=665
	rear.progress=565
	front.update_transform()
	rear.update_transform()
	for pair in [[g.staged_launchers[1],front],[g.staged_launchers[0],rear]]:
		pair[0].position=pair[1].position+Vector3(6,1,0)
		pair[0].home=pair[0].position
		pair[0].fausts=1
	await ticks(3)
	g.decide_ambush([front,rear])
	check(g.ambush_targets==[front,rear] and g.rear_at>0,"Two actual arrivals schedule distinct front and rear vehicle targets")
	for i in range(90):g.step_projectiles(1.0/60)
	g.elapsed=g.rear_at+0.01
	g.step_convoy(0.01)
	for i in range(90):g.step_projectiles(1.0/60)
	check(front.unloaded and rear.unloaded and not front.destroyed and not rear.destroyed and g.lead_hit and g.rear_hit,"Both armored ambush targets stop and unload without forced destruction")
	g.ambush_outcome="pending"
	g.staged_launchers[1].alive=false
	g.decide_ambush([g.trucks[3]])
	check(g.ambush_outcome=="skipped","A dead front launcher prevents the authored ambush")
	await clean()
	await make_game()
	g.begin()
	# Observe from outside the engagement. No player shooting, orders, buffs or invulnerability.
	g.player.truck=null
	g.player.set_physics_process(false)
	g.player.position=Vector3(-185,40,440)
	var started=Time.get_ticks_msec()
	for second in range(1,241):
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
	print("CONVOY_RESULT ",JSON.stringify(g.trucks.map(func(v):return {"truck":v.index,"progress":v.progress,"hits":v.bullet_hits,"disabled":v.disabled,"destroyed":v.destroyed,"dismount":v.dismount_reason,"passes":v.bypass_attempts})))
	print("GROUND_RECOVERIES ",g.actors.reduce(func(total,a):return total+a.terrain_recoveries,0))
	check(int(g.death_causes.get("fall",0))==0,"No soldier falls through the terrain during the four-minute battle")
	check(g.ambush_outcome in ["triggered","skipped"] and (not g.rear_hit or g.ambush_targets.size()>1),"The live convoy resolves the ambush from actual arrivals without inventing targets")
	check(g.convoy_settled and g.dismounted,"Individual trucks settle and survivors dismount in real time")
	check(g.vehicle_shots>50 and g.trucks.filter(func(t):return t.bullet_hits>0).size()>=7,"Road machine guns engage and visibly damage most of the moving convoy")
	check(g.friendlies.all(func(a):return not a.alive or a.truck!=null or a.wing!=0),"Every surviving dismounted ally retains a mission wing")
	check(g.friendlies.any(func(a):return a.truck==null and a.shots>0),"Dismounted Americans engage without the player participating")
	check(travel>200 and g.germans_alive<80,"The American force advances and inflicts casualties autonomously")
	check(g.tactics.orders_issued>0,"The command hierarchy issues reusable support and flanking plans")
	check(g.fire_checks_blocked>0,"Live combat exercises dispersion-cone friendly-fire avoidance")
	check(g.actors.all(func(a):return a.rounds>=0 and a.reserve>=0 and a.grenades>=0 and a.grenades<=2),"Combat cannot create negative ammunition or replenish bot grenades")
	check(g.actors.any(func(a):return a.reserve<a.spec.reserve or a.grenades<2),"The battle actually consumes carried supplies")
	check(g.enemies.filter(func(a):return a.order=="hold" and not a.staged).all(func(a):return a.far_from_hold<=a.guard_radius+0.01),"Defensive units retain their boundaries throughout the large battle")
	check(get_nodes_in_group("winter_corpses").size()==187-g.allies_alive-g.germans_alive,"Every casualty still has a body after four simulated minutes")
	var failed=checks.filter(func(c):return not c.passed)
	FileAccess.open("res://reviews/ardennes-tests.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":checks.size()-failed.size(),"failed":failed.size(),"checks":checks,"simulation":snapshots,"headless_wall_ms":Time.get_ticks_msec()-started,"note":"Fixed-seed, headless mechanics and autonomous battle test; not a rendering benchmark."},"  "))
	print("ARDENNES_TEST_COMPLETE ",checks.size()," checks / ",failed.size()," failures")
	await clean()
	quit(0 if failed.is_empty() else 1)
