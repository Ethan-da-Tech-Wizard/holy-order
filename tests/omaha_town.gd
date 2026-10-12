extends SceneTree
const Kit=preload("res://scripts/ardennes/weapons.gd")
var g
var checks=[]
func _initialize():call_deferred("run")
func check(label:String,ok:bool,data=null):
	checks.append({"check":label,"ok":ok,"data":data})
	print("PASS " if ok else "FAIL ",label," ",data if data!=null else "")
func ticks(n:int):
	for i in range(n):await physics_frame
func run():
	set_meta("battle_test",true)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await ticks(3)
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for a in g.actors:a.set_physics_process(false)
	check("100 beach defenders plus 150 staged town defenders",g.enemies.filter(func(a):return a.role=="town_guard" and a.staged).size()==150 and g.enemies.size()==250)
	check("24 occupied three-level houses and 150 defended stations",g.world.houses.size()==24 and g.world.town_stations.size()==150 and g.world.town_stations.filter(func(s):return s.indoor).size()==96)
	check("Three tanks, eight AI-only launchers, ordinary rifles retained",g.tanks.size()==3 and g.rocket_teams.size()==8 and g.rocket_teams.all(func(t):return t.carrier.team==1 and t.carrier.weapon_kind=="garand" and t.rockets==6) and g.player.get("bazooka_team")==null and not Kit.DATA.has("bazooka"))
	g.begin(true)
	check("Skip ends cinematic before arrival and leaves player aboard",not g.intro_active and g.elapsed<g.first_landing_at and g.player.truck!=null and not g.player.truck.arrived and g.player.camera.current)
	g.phase="title"
	# Freeze the firefight and isolate actual city collision and damage.
	for a in g.actors:
		a.staged=true
		a.collision_layer=0
		a.equipment.collision_layer=0
	g.player.truck=null
	g.player.position=Vector3(900,80,0)
	g.player.collision_layer=0
	g.rebuild_spatial()
	await ticks(2)
	var house=g.world.houses[9]
	var ports=0
	for h in g.world.houses:
		for s in h.stations:
			var from=s.point+Vector3(0,1.5,0)
			var ray=PhysicsRayQueryParameters3D.create(from,from+s.facing*4,1)
			if g.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():ports+=1
	check("All 96 indoor stations have physical firing apertures",ports==96,ports)
	var stairs_clear=true
	for h in g.world.houses:
		for level in [1,2]:
			var p=h.position+Vector3(0,level*3.2,0)
			var ray=PhysicsRayQueryParameters3D.create(p+Vector3(0,0.5,0),p-Vector3(0,0.5,0),1)
			var hit=g.get_world_3d().direct_space_state.intersect_ray(ray)
			stairs_clear=stairs_clear and not hit.is_empty() and absf(hit.position.y-p.y)<0.05
	check("Upper floors have supporting collision",stairs_clear)
	var mover=g.friendlies[8]
	mover.staged=false
	mover.truck=null
	mover.boat=null
	mover.bangalores=0
	mover.position=house.position+Vector3(0,0.04,15)
	mover.order="assault"
	mover.state="advance"
	mover.stance="stand"
	mover.target=null
	mover.set_destination(house.position+Vector3(-5.8,6.43,-11.4))
	var stair_route=mover.path.duplicate()
	g.phase="playing"
	for i in range(25*Engine.physics_ticks_per_second):
		await physics_frame
		g.elapsed+=1.0/Engine.physics_ticks_per_second
		mover._physics_process(1.0/Engine.physics_ticks_per_second)
	check("Infantry can walk from street to attic through the stairwell",mover.position.y>house.position.y+6 and mover.position.distance_to(mover.destination)<3,{"position":str(mover.position-house.position),"goal":str(mover.destination-house.position),"route":str(stair_route)})
	mover.set_destination(house.position+Vector3(0,0.03,-24))
	for i in range(25*Engine.physics_ticks_per_second):
		await physics_frame
		g.elapsed+=1.0/Engine.physics_ticks_per_second
		mover._physics_process(1.0/Engine.physics_ticks_per_second)
	check("Infantry can descend both flights and exit into the street",mover.position.y<house.position.y+0.5 and mover.position.distance_to(mover.destination)<3,str(mover.position-house.position))
	var exits_clear=true
	var exit_positions=[]
	for x in [-72.0,0.0,72.0]:
		mover.position=g.world.on_ground(Vector3(x,0,-332))+Vector3(0,0.025,0)
		mover.velocity=Vector3.ZERO
		mover.stuck=0
		mover.obstruction_normal=Vector3.ZERO
		mover.path_refresh=0
		mover.state="advance"
		mover.set_destination(g.world.on_ground(Vector3(g.world.closest_road_x(x),0,-364)))
		for i in range(12*Engine.physics_ticks_per_second):
			await physics_frame
			g.elapsed+=1.0/Engine.physics_ticks_per_second
			mover._physics_process(1.0/Engine.physics_ticks_per_second)
		exits_clear=exits_clear and mover.position.distance_to(mover.destination)<2
		exit_positions.append(str(mover.position))
	check("All three bluff draws connect to the town without an impassable slope",exits_clear,exit_positions)
	# Both finite rocket stores and exclusive loader claims survive casualty changes.
	var pair=g.rocket_teams[0]
	var carrier=pair.carrier
	carrier.staged=false
	carrier.truck=null
	carrier.boat=null
	carrier.position=g.world.on_ground(Vector3(250,0,-70))
	var buddies=[g.friendlies[5],g.friendlies[7],g.friendlies[9],g.friendlies[10]]
	for i in range(buddies.size()):
		var b=buddies[i]
		b.staged=false
		b.truck=null
		b.boat=null
		b.bangalores=0
		b.position=carrier.position+Vector3(1+i*0.3,0,1)
	pair.decision_clock=0
	pair.tick(0.1)
	check("Exactly one eligible rifleman is nominated loader",pair.loader!=null and buddies.filter(func(a):return a.loader_for==pair.index).size()==1)
	pair.loaded=false
	pair.rockets=4
	pair.reload_progress=0
	pair.loader.position=carrier.position+Vector3(10,0,0)
	pair.tick(7)
	check("Loader must be physically beside carrier to reload",not pair.loaded and pair.reload_progress==0)
	pair.loader.position=carrier.position+Vector3(1.85,0,0.6)
	pair.tick(6.9)
	check("Nearby loader reloads without fabricating reserve ammunition",pair.loaded and pair.rockets==4)
	var old_loader=pair.loader
	old_loader.alive=false
	pair.decision_clock=0
	pair.tick(0.1)
	check("A dead loader is released and replaced once",pair.loader!=null and pair.loader!=old_loader and old_loader.loader_for==-1 and buddies.filter(func(a):return a.alive and a.loader_for==pair.index).size()==1)
	for buddy in buddies:
		if buddy.alive:buddy.position=carrier.position+Vector3(5,0,0)
	carrier.alive=false
	pair.decision_clock=0
	pair.tick(0.1)
	check("Carrier casualty drops launcher and releases old helper",pair.carrier==null and pair.loader==null and pair.recoverer!=null and pair.rockets==4)
	pair.recoverer.position=pair.dropped_at
	pair.decision_clock=0
	pair.tick(0.1)
	pair.decision_clock=0
	pair.tick(0.1)
	check("Recovered launcher has one new carrier and one distinct loader",pair.recoveries==1 and pair.carrier!=carrier and pair.loader!=null and pair.loader!=pair.carrier and pair.carrier.bazooka_team==pair.index and pair.loader.loader_for==pair.index and pair.rockets==4)
	var all_claims={}
	var exclusive=true
	for team in g.rocket_teams:
		if team.loader==null:continue
		exclusive=exclusive and not all_claims.has(team.loader.get_instance_id())
		all_claims[team.loader.get_instance_id()]=team.index
	check("No helper belongs to multiple launcher teams",exclusive)
	# Tank armour and tracks respond separately to different weapons.
	var tank=g.tanks[0]
	var hp=tank.health
	var track=tank.tracks[0]
	var front=tank.to_global(Vector3(0,1.4,-2.75))
	for i in range(300):tank.damage_at(50,front)
	check("Hundreds of ordinary hull hits cannot destroy tank",tank.health==hp and tank.tracks[0]==track)
	var tp=tank.to_global(Vector3(-1.43,0.5,0))
	tank.receive_blast(tp,6,160,"grenade")
	check("One close grenade damages but cannot break fresh tracks or hull",tank.tracks[0]>0 and tank.tracks[0]<track and tank.health==hp)
	for i in range(6):tank.receive_blast(tp,6,160,"grenade")
	check("Repeated grenades disable tracks without killing the tank",not tank.mobile() and tank.alive and tank.health==hp)
	var t2=g.tanks[1]
	for i in range(8):t2.hit_track(0,50*0.025)
	check("A short rifle burst cannot knock out the tracks",t2.mobile())
	for i in range(400):t2.hit_track(0,50*0.025)
	check("Sustained small-arms fire can eventually sever a track",not t2.mobile() and t2.health==420)
	var side=tank.to_global(Vector3(-1.5,1.2,0))
	tank.hit_rocket(side)
	check("HEAT hit damages hull while wreck requires multiple hits",tank.health<hp and tank.alive)
	while tank.alive:tank.hit_rocket(side)
	check("Repeated penetrating rockets destroy tank",not tank.alive and tank.health==0)
	# A live team fires an actual swept rocket along a clear street.
	var live_tank=g.tanks[2]
	live_tank.position=Vector3(114,g.Layout.TOWN_GROUND+0.04,-382)
	live_tank.rotation.y=PI
	pair.carrier.position=g.world.on_ground(Vector3(114,0,-336))
	pair.carrier.velocity=Vector3.ZERO
	pair.loader.position=pair.carrier.position+Vector3(1.85,0,0.6)
	pair.loaded=true
	pair.target=null
	var before_shots=pair.shots
	var before_rockets=pair.rockets
	await ticks(3)
	pair.decision_clock=0
	pair.tick(0.1)
	check("A team launches a physical rocket at visible armour",pair.shots==before_shots+1 and pair.rockets==before_rockets-1 and g.heavy_projectiles.size()==1)
	for i in range(40):
		g.step_heavy_projectiles(0.05)
		await physics_frame
	check("Swept rocket collides with tank and damages its hull",live_tank.health<420 and g.heavy_projectiles.is_empty(),live_tank.health)
	# Immobilisation leaves the gun operational, with no player-targeting bonus.
	pair.carrier.position=Vector3(114,g.Layout.TOWN_GROUND+0.04,-348)
	pair.loader.position=pair.carrier.position+Vector3(2,0,0)
	g.player.position=Vector3(114,g.Layout.TOWN_GROUND+0.04,-332)
	g.player.collision_layer=2
	g.rebuild_spatial()
	await ticks(3)
	live_tank.choose_target()
	check("Tank acquires a nearer detected soldier ahead of the player",live_tank.target!=null and live_tank.target!=g.player)
	live_tank.tracks[0]=0
	g.town_active=true
	live_tank.cannon_clock=0
	live_tank.turret.global_rotation.y=PI
	live_tank.tick(0.05)
	check("A tank with broken tracks can still fire its cannon",not live_tank.mobile() and live_tank.shots>0)
	for shot in g.heavy_projectiles:shot.visual.queue_free()
	g.heavy_projectiles.clear()
	g.player.position=Vector3(900,80,0)
	g.player.collision_layer=0
	pair.carrier.staged=true
	pair.loader.staged=true
	live_tank.tracks.assign([460.0,460.0])
	live_tank.target=null
	live_tank.decision_clock=1000
	live_tank.plan_route(Vector3(114,g.Layout.TOWN_GROUND,-358))
	var old_pos=live_tank.position
	for i in range(160):
		await physics_frame
		live_tank.move_tank(0.05)
	check("Tank drives on town streets while staying behind beach defences",live_tank.position.distance_to(old_pos)>12 and absf(live_tank.position.x-114)<1.0 and live_tank.position.z<=g.Layout.TOWN_FRONT and live_tank.position.z>=g.Layout.TOWN_BACK,live_tank.position)
	# Damage performs real local collision edits; occupied collapse is fatal.
	var wall=house.panels.filter(func(p):return p.position.z>12 and p.position.y<1 and p.bounds.size.x>4)[0]
	var point=wall.global_position
	var q=PhysicsRayQueryParameters3D.create(point+Vector3(0,0,2),point-Vector3(0,0,2),1)
	check("House wall blocks shots before damage",not g.get_world_3d().direct_space_state.intersect_ray(q).is_empty())
	for i in range(12):wall.damage_at(35,point,0.16,false)
	await ticks(15)
	check("Accumulated bullets open a real small local hole",g.get_world_3d().direct_space_state.intersect_ray(q).is_empty() and wall.cuts_completed>0 and not wall.destroyed)
	var wall2=house.panels.filter(func(p):return p.position.z< -12 and p.position.y<1 and p.bounds.size.x>4)[0]
	var p2=wall2.global_position
	g.explode(p2+Vector3(0,0,-0.2),6,130,null,"grenade")
	await ticks(25)
	check("Grenades breach local masonry without automatically collapsing house",wall2.cuts_completed>0 and not house.collapsed)
	var victim=g.enemies[102]
	victim.staged=false
	victim.alive=true
	victim.health=100
	victim.position=house.position+Vector3(0,6.43,0)
	for support in house.supports.duplicate():
		if not house.collapsed:support.damage_at(5000,support.global_position,0.8,true)
	check("Unsupported structure collapses and kills its upstairs occupant",house.collapsed and not victim.alive and house.rubble.size()==8 and house.panels.all(func(p):return p.destroyed and p.collision_layer==0))
	# Per-weapon sights, distinct geometry and inventory feeds remain aligned.
	var signatures={}
	var aligned=true
	g.player.position=Vector3(250,70,0)
	g.player.rotation=Vector3.ZERO
	g.player.head.rotation=Vector3.ZERO
	g.player.camera.current=true
	g.player.aiming=true
	for kind in Kit.DATA:
		g.player.set_firearm(kind,Kit.DATA[kind].capacity,100)
		g.player.aiming=true
		for i in range(80):g.player.update_view(1.0/60)
		var front_sight=g.player.rifle.get_node("SightLine").global_position
		var rear_sight=g.player.rifle.get_node("RearSightLine").global_position
		var center=root.get_visible_rect().size*0.5
		aligned=aligned and g.player.camera.unproject_position(front_sight).distance_to(center)<0.4 and g.player.camera.unproject_position(rear_sight).distance_to(center)<0.4
		var mesh=Kit.gun_cache[kind]
		var signature=str(mesh.surface_get_array_len(0))+str(mesh.get_aabb())
		signatures[signature]=true
	check("All eleven firearm models have distinct geometry",signatures.size()==Kit.DATA.size())
	check("Every firearm aligns front and rear sights with screen centre",aligned)
	var result={"passed":checks.filter(func(c):return c.ok).size(),"total":checks.size(),"checks":checks}
	FileAccess.open("res://reviews/omaha/town-armor-checks.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	g.phase="title"
	g.queue_free()
	await ticks(3)
	quit(0 if result.passed==result.total else 1)
