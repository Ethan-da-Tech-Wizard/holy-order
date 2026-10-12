extends "res://scripts/ardennes/battle.gd"
const Layout=preload("res://scripts/omaha/layout.gd")
const Coast=preload("res://scripts/omaha/world.gd")
const LandingPlayer=preload("res://scripts/omaha/player.gd")
const Soldier=preload("res://scripts/omaha/actor.gd")
const Boat=preload("res://scripts/omaha/boat.gd")
const LandingHUD=preload("res://scripts/omaha/interface.gd")
const CoastalAudio=preload("res://scripts/omaha/audio.gd")
const Armor=preload("res://scripts/omaha/armor.gd")
const Panzer=preload("res://scripts/omaha/tank.gd")
const RocketTeam=preload("res://scripts/omaha/rocket_team.gd")
const FOG_LINE:float=95.0
var boats:Array=[]
var first_landing_at:float=Boat.APPROACH_SECONDS
var second_wave_at:float=Boat.APPROACH_SECONDS+Boat.SECOND_WAVE_DELAY
var first_wave_landed:bool=false
var second_wave_landed:bool=false
var breaches:int=0
var capture:Array[float]=[0,0,0,0,0,0,0,0]
var town_control:float=0
var secured:int=0
var lod_batches:Dictionary={}
var lod_timer:float=0
var mine_timer:float=0
var defender_cursor:int=0
var attacker_cursor:int=0
var quality:int=0
var shots_at_player:int=0
var shots_at_ai:int=0
var boat_penetrations:int=0
var flame_hits:int=0
var sim_ticks:int=0
var mine_detonations:int=0
var corpse_lod_timer:float=0
var claimed_charges:Dictionary={}
var flashes:Array=[]
var flash_batch:MultiMeshInstance3D
var active_charges:Array=[]
var wave_two_released:bool=false
var tracers:Array=[]
var tracer_batch:MultiMeshInstance3D
var detailed_soldiers:int=0
var detail_timer:float=0
var detailed:Dictionary={}
var occupied_min=Vector2.ZERO
var occupied_max=Vector2.ZERO
var defender_credit:float=0
var attacker_credit:float=0
var active_attackers:Array=[]
var active_defenders:Array=[]
var target_cells:Array=[{},{}]
var remains_batches:Dictionary={}
var tanks:Array=[]
var rocket_teams:Array=[]
var heavy_projectiles:Array=[]
var intro_active:bool=false
var landing_aborted:bool=false
var active_blast_kind:String=""
var team_timer:float=0
var town_active:bool=false
const TARGET_CELL:float=32.0

func _ready():
	Engine.max_fps=60
	test_mode="--battle-test" in OS.get_cmdline_user_args() or get_tree().has_meta("battle_test")
	combat_seed=int(get_tree().get_meta("battle_seed",19440606))
	seed(combat_seed)
	register_inputs()
	world=Coast.new()
	world.game=self
	add_child(world)
	sounds=CoastalAudio.new()
	add_child(sounds)
	player=LandingPlayer.new()
	player.game=self
	add_child(player)
	make_landing_force()
	make_defenders()
	make_armor()
	actors=friendlies+enemies
	allies_alive=Layout.AMERICANS_TOTAL-1
	germans_alive=Layout.GERMANS_TOTAL
	rebuild_spatial()
	build_lod_batches()
	build_flashes()
	build_tracers()
	var canvas=CanvasLayer.new()
	add_child(canvas)
	hud=LandingHUD.new()
	hud.game=self
	canvas.add_child(hud)
	world.world_camera.position=Vector3(-33,5.5,297)
	world.world_camera.look_at(Vector3(-20,3,-100))
	world.world_camera.current=true
	player.camera.current=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_title("Holy Order — Omaha / The Longest Shore")
	apply_quality()
	preload("res://scripts/graphics.gd").install(self)
	if get_tree().has_meta("omaha_retry"):
		get_tree().remove_meta("omaha_retry")
		begin()
	if "--battle-preview" in OS.get_cmdline_user_args():begin()

func add_soldier(team_id:int,kind:String,p:Vector3,squad_id:int):
	var a=Soldier.new()
	a.game=self
	a.team=team_id
	a.weapon_kind=kind
	a.index=friendlies.size() if team_id==1 else Layout.AMERICANS_TOTAL+enemies.size()
	a.squad=squad_id
	a.position=p
	return a

func make_landing_force():
	# Twenty craft per wave, each with 27 passengers, two gunners and a driver.
	# The player replaces one passenger: exactly 600 Americans in each wave.
	for wave in range(2):
		for lane_id in range(Layout.BOATS_PER_WAVE):
			var craft=Boat.new()
			craft.game=self
			craft.index=boats.size()
			craft.wave=wave
			craft.lane_x=(lane_id-(Layout.BOATS_PER_WAVE-1)*0.5)*Layout.FLEET_SPACING
			add_child(craft)
			boats.append(craft)
			trucks.append(craft) # Shared inspection / inventory API retains its vehicle slot.
			var sq=new_squad(1,"assault","aggressive",craft.position)
			for seat_id in range(Layout.PASSENGERS_PER_BOAT):
				if wave==0 and lane_id==Layout.BOATS_PER_WAVE/2-1 and seat_id==25:
					player.truck=craft
					player.seat=seat_id
					player.position=craft.seat_transform(seat_id).origin
					player.rotation.y=craft.rotation.y
					player.last_truck_yaw=craft.rotation.y
					continue
				var kind="bar" if seat_id in [4,15] else ("carbine" if seat_id%6==0 else "garand")
				if seat_id==17 and lane_id%3==1:kind="flamethrower"
				var a=add_soldier(1,kind,craft.seat_transform(seat_id).origin,sq)
				a.wave=wave
				a.lane=craft.lane_x
				a.sector=Layout.sector_for(craft.lane_x)
				a.seat=seat_id
				a.truck=craft
				# Three carriers spaced through the file; each has three finite charges.
				a.bangalores=3 if seat_id in Layout.ENGINEER_SEATS else 0
				a.role="engineer" if a.bangalores>0 else "rifleman"
				a.staged=wave==1
				a.order="assault"
				a.leader=seat_id==0
				add_child(a)
				a.set_reserve(wave==1)
				friendlies.append(a)
				craft.occupants.append(a)
				squads[sq].members.append(a)
				if a.leader:squads[sq].leader=a
			for slot in range(3):
				var a=add_soldier(1,"m1919" if slot<2 else "carbine",craft.crew_transform(slot).origin,sq)
				a.boat=craft
				a.role="gunner" if slot<2 else "driver"
				a.mounted=slot<2
				a.wave=wave
				a.staged=wave==1
				a.mount_facing=Vector3(0,0,-1)
				a.mount_arc=1.45
				add_child(a)
				a.set_reserve(wave==1)
				friendlies.append(a)
				craft.crew.append(a)
				squads[sq].members.append(a)
			if sounds.enabled:
				var engine=AudioStreamPlayer3D.new()
				engine.stream=load("res://assets/audio/engine.wav")
				engine.volume_db=-12
				engine.unit_size=9
				engine.max_distance=140
				craft.add_child(engine)
				craft.engine_loop=engine
				engines.append(engine)
				engine.finished.connect(func():if phase=="playing" and not craft.arrived:engine.play())

func make_defenders():
	for sector_id in range(8):
		var sq=new_squad(0,"hold","cautious",world.anchors[sector_id])
		for j in range(11):
			var kind="mg42" if j<5 else ("mp40" if j==5 else ("g43" if j%2==0 else "kar98"))
			var p=world.on_ground(world.anchors[sector_id]+Vector3((j%3-1)*11,0,10 if j<8 else -25))
			var a=add_soldier(0,kind,p,sq)
			a.sector=sector_id
			a.entrenched=true
			a.guard_radius=11
			a.leader=j==5
			if j<4:
				var nest=world.nests[sector_id*4+j]
				a.position=nest.position
				a.mounted=true
				a.role="bunker_mg" if j<3 else "field_mg"
				a.mount_facing=nest.facing
				a.mount_arc=nest.arc
				nest.operator=a
			a.rotation.y=atan2(-a.mount_facing.x,-a.mount_facing.z) if a.mounted else PI
			add_child(a)
			enemies.append(a)
			squads[sq].members.append(a)
			if a.leader:squads[sq].leader=a
	var sq=new_squad(0,"hold","cautious",Vector3(0,45,Layout.VILLAGE-30))
	# Twelve riflemen complete the 100-person beach force.
	for i in range(12):
		var a=add_soldier(0,["g43","kar98","mp40"][i%3],world.on_ground(Vector3((i-5.5)*24,0,-304)),sq)
		a.sector=Layout.sector_for(a.position.x)
		a.entrenched=true
		a.role="trench_guard"
		a.guard_radius=10
		a.rotation.y=PI
		add_child(a)
		enemies.append(a)
		squads[sq].members.append(a)
	for i in range(Layout.TOWN_DEFENDERS):
		var station=world.town_stations[i]
		var a=add_soldier(0,station.kind,station.point,sq)
		a.sector=Layout.sector_for(a.position.x)
		a.entrenched=true
		a.role="town_guard"
		a.guard_radius=6
		a.stationary=station.indoor or station.kind=="mg42"
		a.mounted=station.kind=="mg42"
		a.mount_facing=station.facing
		a.mount_arc=1.35
		a.rotation.y=atan2(-station.facing.x,-station.facing.z)
		add_child(a)
		enemies.append(a)
		squads[sq].members.append(a)
		a.set_reserve(true)

func make_armor():
	for i in range(3):
		var tank=Panzer.new()
		tank.game=self
		tank.index=i
		tank.position=world.on_ground(Vector3((i-1)*76,0,-510))
		add_child(tank)
		tanks.append(tank)
	for wave in range(2):
		for lane_id in [2,7,12,17]:
			var craft=boats[wave*Layout.BOATS_PER_WAVE+lane_id]
			var carrier=craft.occupants.filter(func(a):return a.seat==19)[0]
			var pair=RocketTeam.new()
			pair.game=self
			pair.index=rocket_teams.size()
			pair.carrier=carrier
			carrier.bazooka_team=pair.index
			add_child(pair)
			rocket_teams.append(pair)

func begin(skip_approach:bool=false):
	phase="playing"
	intro_active=true
	player.camera.current=false
	world.world_camera.current=true
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for engine in engines:engine.play()
	say("Stay in line. Keep your heads below the gunwales. Follow the file when that ramp drops.",7,"COXSWAIN")
	toast("FIRST WAVE • HOLD FAST • 2 BROWNINGS PER CRAFT",6)
	if skip_approach:skip_intro()

func skip_intro():
	if not intro_active:return
	elapsed=first_landing_at-0.6
	for craft in boats:craft.tick(0.0)
	end_intro()
	reset_physics_interpolation()

func end_intro():
	intro_active=false
	player.camera.current=true
	world.world_camera.current=false
	toast("RAMP OPENING • FOLLOW THE CREW WITH WASD",5)

func missed_landing():
	landing_aborted=true
	phase="defeat"
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	toast("The craft returned to sea. Deploy again and walk down the ramp.",10)

func _unhandled_input(event):
	if phase=="playing" and intro_active and event is InputEventKey and event.pressed and event.keycode==KEY_ENTER:
		skip_intro()
		return
	super._unhandled_input(event)

func boat_landed(craft):
	if craft.engine_loop!=null:craft.engine_loop.stop()
	if craft.wave==0 and not first_wave_landed:
		first_wave_landed=true
		dismounted=true
		dismount_at=elapsed
		say("Ramps down! Off the boats! Engineers to the wire — everyone else, cover them!",7,"SGT. HAYES")
	if craft.wave==1 and not second_wave_landed:
		second_wave_landed=true
		say("Second wave ashore! Push through the gaps and take the bluff exits!",6,"SGT. HAYES")

func apply_quality():
	quality=preload("res://scripts/graphics.gd").quality(get_tree())
	preload("res://scripts/graphics.gd").apply(self)
	world.concrete.normal_enabled=quality>0
	world.masonry.normal_enabled=quality>0
	world.concrete.uv1_triplanar=quality>0
	world.masonry.uv1_triplanar=quality>0


func step_battle(delta):
	if phase!="playing":return
	elapsed+=delta
	if intro_active and player.truck!=null:
		var craft=player.truck
		world.world_camera.position=craft.position+Vector3(-7.0,3.8,8.0)
		world.world_camera.look_at(craft.position+Vector3(0,1,-8))
		if elapsed>=first_landing_at-1.0:end_intro()
	sim_ticks+=1
	for craft in boats:
		craft.tick(delta)
	if not wave_two_released and elapsed>=Boat.SECOND_WAVE_DELAY:
		wave_two_released=true
		for craft in boats.slice(Layout.BOATS_PER_WAVE):
			for a in craft.occupants+craft.crew:a.set_reserve(false)
		rebuild_spatial()
	if not town_active and (player.position.z< -292 or friendlies.any(func(a):return a.alive and not a.staged and a.truck==null and a.boat==null and a.position.z< -292)):
		activate_town()
	for tank in tanks:tank.tick(delta)
	for pair in rocket_teams:pair.tick(delta)
	step_heavy_projectiles(delta)
	for wire in active_charges:wire.tick(delta)
	active_charges=active_charges.filter(func(w):return not w.broken)
	sense_timer-=delta
	if sense_timer<=0:
		sense_timer=0.25
		rebuild_spatial()
	squad_timer-=delta
	if squad_timer<=0:
		squad_timer=1
		update_squads()
		update_objectives(1)
	step_projectiles(delta)
	update_flashes()
	update_tracers(delta)
	for effect in effects.duplicate():
		effect.time-=delta
		if effect.time<=0:
			effect.node.queue_free()
			effects.erase(effect)
	lod_timer-=delta
	if lod_timer<=0:
		lod_timer=0.0
		update_lod()
	mine_timer-=delta
	if mine_timer<=0:
		mine_timer=0.3
		check_mines()

func think_budget(delta:float):
	# Spend the budget on living, active fighters, not offshore reserves or drivers.
	defender_credit=minf(defender_credit+minf(delta,0.05)*active_defenders.size()*1.5,8.0)
	attacker_credit=minf(attacker_credit+minf(delta,0.05)*active_attackers.size()*1.5,40.0)
	var defenders=0 if active_defenders.is_empty() else mini(int(defender_credit),4)
	var attackers=0 if active_attackers.is_empty() else mini(int(attacker_credit),20)
	defender_credit-=defenders
	attacker_credit-=attackers
	for i in range(defenders):
		var actor=active_defenders[defender_cursor%active_defenders.size()]
		defender_cursor+=1
		if actor.alive:actor.think(elapsed)
	for i in range(attackers):
		var actor=active_attackers[attacker_cursor%active_attackers.size()]
		attacker_cursor+=1
		if actor.alive:actor.think(elapsed)

func update_squads():
	for sq in squads:
		if sq.leader==null or not sq.leader.alive:
			sq.leader=null
			for a in sq.members:
				if a.alive and a.role!="driver":
					sq.leader=a
					a.leader=true
					break

func separation_for(actor)->Vector3:
	if elapsed<actor.separation_at:return actor.separation_cache
	actor.separation_at=elapsed+0.10+float(actor.index%3)*0.008
	var c=Vector2i(floori(actor.position.x/5),floori(actor.position.z/5))
	var result=Vector3.ZERO
	for dx in [-1,0,1]:
		for dz in [-1,0,1]:
			for other in spatial.get(c+Vector2i(dx,dz),[]):
				if other==actor or not other.alive or other.truck!=null or other.boat!=null:continue
				var offset=actor.position-other.position
				offset.y=0
				var squared=offset.length_squared()
				if squared>0.0001 and squared<1.1025:
					var d=sqrt(squared)
					result+=offset/d*(1.05-d)
	actor.separation_cache=result.limit_length(1)
	return actor.separation_cache

func can_detect(observer,other)->bool:
	if not actor_alive(other):return false
	if other.position.z>FOG_LINE and observer.team==0:return false
	var offset=actor_aim(other)-observer.eye()
	var distance=offset.length()
	if distance>observer.spec.range:return false
	var toward=offset.normalized()
	if observer.mounted and observer.mount_facing.dot(Vector3(toward.x,0,toward.z).normalized())<cos(observer.mount_arc):return false
	var last_shot=other.last_fired
	var remembered=float(observer.memory.get(other.get_instance_id(),-999))>elapsed
	var quiet=elapsed-last_shot>5
	var posture="prone" if other==player and player.prone else ("crouch" if other==player and player.crouched else ("stand" if other==player else other.stance))
	var speed=Vector2(other.velocity.x,other.velocity.z).length()
	if not remembered and quiet:
		var facing=-observer.global_basis.z
		if facing.dot(toward)<0.20 and distance>9:return false
		if posture=="prone" and speed<1.5 and distance>42:return false
		if posture=="crouch" and speed<2.5 and distance>120:return false
	return true

func acquire_target(observer):
	var nearest=[]
	var cells=target_cells[1-observer.team]
	var ordered=[]
	var origin=Vector2(observer.position.x,observer.position.z)
	var range_squared=observer.spec.range*observer.spec.range
	for cell in cells:
		# Four metres of padding covers movement between spatial refreshes.
		var offset=(origin-(Vector2(cell)+Vector2(0.5,0.5))*TARGET_CELL).abs()-Vector2.ONE*(TARGET_CELL*0.5+4.0)
		var distance=offset.max(Vector2.ZERO).length_squared()
		if distance<=range_squared:ordered.append({"cell":cell,"d":distance})
	ordered.sort_custom(func(a,b):return a.d<b.d)
	for entry in ordered:
		if nearest.size()==10 and entry.d>nearest.back().d:break
		for other in cells[entry.cell]:
			if not other.alive or other.staged:continue
			if observer.team==0 and other.position.z>FOG_LINE:continue
			var distance=observer.position.distance_squared_to(other.position)
			if distance>range_squared:continue
			if nearest.size()==10 and distance>=nearest.back().d:continue
			if not can_detect(observer,other):continue
			insert_nearest(nearest,other,distance)
	if observer.team==0 and can_detect(observer,player):insert_nearest(nearest,player,observer.position.distance_squared_to(player.position))
	# No player bonus: sort by distance, then require a visible hitbox.
	for entry in nearest.slice(0,10):
		var other=entry.actor
		var ray=PhysicsRayQueryParameters3D.create(observer.eye(),actor_aim(other),1|2|4|8)
		ray.exclude=[observer.get_rid()]
		var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider==other:
			observer.memory[other.get_instance_id()]=elapsed+6
			return other
	return null

func insert_nearest(list:Array,actor,distance:float):
	var slot=0
	while slot<list.size() and list[slot].d<distance:slot+=1
	list.insert(slot,{"actor":actor,"d":distance})
	if list.size()>10:list.pop_back()

func acquire_vehicle(observer):
	if observer.team!=0:return null
	var selected=null
	var best=INF
	for craft in boats:
		if craft.departed or craft.unloaded or not craft.has_passengers() or craft.position.z>FOG_LINE:continue
		var p=craft.target_point(observer)
		var v=p-observer.eye()
		var d=v.length_squared()
		if d>observer.spec.range*observer.spec.range or d>=best:continue
		if observer.mounted and observer.mount_facing.dot(Vector3(v.x,0,v.z).normalized())<cos(observer.mount_arc):continue
		var ray=PhysicsRayQueryParameters3D.create(observer.eye(),p,1|2|4|8)
		ray.exclude=[observer.get_rid()]
		var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and (hit.collider.get("truck_owner")==craft or hit.collider.get("truck")==craft):
			selected=craft
			best=d
	return selected

func safe_fire_line(actor,from:Vector3,to:Vector3)->bool:
	var ray=PhysicsRayQueryParameters3D.create(from,to+(to-from).normalized()*0.2,1|2|4|8)
	ray.exclude=[actor.get_rid()]
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():return true
	var obj=hit.collider
	if obj==player or obj is Soldier:return obj.team!=actor.team
	if obj.get("truck_owner")!=null:return actor.team==0
	return false

func shoot(source,from:Vector3,aim:Vector3,spread:float,damage:float,kind:String):
	source.last_fired=elapsed
	if kind=="flamethrower":
		flame_jet(source,from,aim)
		return
	if flashes.size()<96:flashes.append({"p":from,"until":elapsed+0.06})
	var direction=(aim-from).normalized()
	var right=direction.cross(Vector3.UP).normalized()
	direction=(direction+right*randfn(0,spread)+right.cross(direction)*randfn(0,spread)).normalized()
	var end=from+direction*1400
	var origin=from
	var excludes:Array[RID]=[]
	excludes.assign(source.shot_exclusions() if source.has_method("shot_exclusions") else [source.get_rid(),source.equipment.get_rid()])
	ammo_spent+=1
	if source!=player:
		if source.target==player:shots_at_player+=1
		elif source.target!=null:shots_at_ai+=1
	for pass_index in range(6):
		var q=PhysicsRayQueryParameters3D.create(origin,end,1|2|4|8|16|32)
		q.collide_with_areas=true
		q.exclude=excludes
		var hit=get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():break
		var obj=hit.collider
		if obj.has_meta("wielder"):
			obj.get_meta("wielder").damage_weapon(damage*0.6)
			excludes.append(obj.get_rid())
			origin=hit.position+direction*0.06
			continue
		if obj.has_method("receive_hit"):
			obj.receive_hit(damage,hit.position)
			excludes.append(obj.get_rid())
			origin=hit.position+direction*0.06
			continue
		if obj==player or obj is Soldier:
			var headshot=hit.position.y-obj.global_position.y>1.5
			hurt_actor(obj,damage*(1.5 if headshot else 1),source.position,"rifle")
			if obj.team==source.team:friendly_fire_hits+=1
			if source==player:hit_flash=0.18
			end=hit.position
			break
		damage_environment(hit,damage*0.7,0.16)
		var penetrates=obj is Armor and obj.hull_panel and (obj.penetrable or obj.destroyed)
		if penetrates or (obj.get("material_kind")=="wood"):
			if penetrates:boat_penetrations+=1
			damage*=0.65
			excludes.append(obj.get_rid())
			origin=hit.position+direction*0.06
			continue
		end=hit.position
		break
	if ammo_spent%3==0 or source==player:tracer(from,end,Color("ffda98") if source.team==1 else Color("efae74"))
	if ammo_spent%3==0:notify_projectile(from,end,source.team)
	if source!=player and source.position.distance_squared_to(player.position)<1960000:sounds.at("rifle",from,-6,randf_range(0.80,1.06))

func rebuild_spatial():
	spatial.clear()
	cover_reservations.clear()
	active_attackers.clear()
	active_defenders.clear()
	target_cells[0].clear()
	target_cells[1].clear()
	for actor in actors:
		if not actor.alive or actor.staged:continue
		var p=actor.position
		var cell=Vector2i(floori(p.x/5),floori(p.z/5))
		if not spatial.has(cell):spatial[cell]=[]
		spatial[cell].append(actor)
		var target_cell=Vector2i(floori(p.x/TARGET_CELL),floori(p.z/TARGET_CELL))
		var cells=target_cells[actor.team]
		if not cells.has(target_cell):cells[target_cell]=[]
		cells[target_cell].append(actor)
		if actor.truck==null and actor.role!="driver":
			if actor.team==1:active_attackers.append(actor)
			else:active_defenders.append(actor)
	occupied_min=Vector2(INF,INF)
	occupied_max=Vector2(-INF,-INF)
	for key in spatial:
		occupied_min=occupied_min.min(Vector2(key)*5-Vector2(10,10))
		occupied_max=occupied_max.max(Vector2(key)*5+Vector2(15,15))

func notify_projectile(from:Vector3,to:Vector3,source_team:int):
	var line=to-from
	var sq=line.length_squared()
	if sq<0.001 or spatial.is_empty():return
	# Slab-clip the sample segment to occupied cells; no work on kilometres of empty sea.
	var low=0.0
	var high=1.0
	for axis in range(2):
		var dimension=0 if axis==0 else 2
		if absf(line[dimension])<0.0001:
			if from[dimension]<occupied_min[axis] or from[dimension]>occupied_max[axis]:return
		else:
			var a=(occupied_min[axis]-from[dimension])/line[dimension]
			var b=(occupied_max[axis]-from[dimension])/line[dimension]
			low=maxf(low,minf(a,b))
			high=minf(high,maxf(a,b))
	if low>high:return
	var visited={}
	var steps=maxi(1,ceili(Vector2(line.x,line.z).length()*(high-low)/7.0))
	for i in range(steps+1):
		var p=from+line*lerpf(low,high,float(i)/steps)
		var cell=Vector2i(floori(p.x/5),floori(p.z/5))
		for dx in [-1,0,1]:
			for dz in [-1,0,1]:
				var key=cell+Vector2i(dx,dz)
				if visited.has(key):continue
				visited[key]=true
				for actor in spatial.get(key,[]):
					if actor.team==source_team or actor.staged or not actor.alive:continue
					var point=actor.eye()
					var t=clampf((point-from).dot(line)/sq,0,1)
					if point.distance_squared_to(from+line*t)<3.0:
						actor.near_miss(from)
						near_misses+=1

func emit_noise(point:Vector3,radius:float,team:int,kind:String):
	if kind=="gunshot":return # Perception uses each actual shooter's last-fired timestamp.
	for actor in actors:
		if actor.alive and actor.team!=team and actor.position.distance_squared_to(point)<radius*radius:actor.hear_noise(point,radius,team,kind)

func build_tracers():
	tracer_batch=MultiMeshInstance3D.new()
	var mesh=BoxMesh.new()
	mesh.size=Vector3.ONE
	var mat=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo=true
	mesh.material=mat
	tracer_batch.multimesh=MultiMesh.new()
	tracer_batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	tracer_batch.multimesh.use_colors=true
	tracer_batch.multimesh.mesh=mesh
	tracer_batch.multimesh.instance_count=160
	tracer_batch.multimesh.visible_instance_count=0
	tracer_batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer_batch)

func tracer(from:Vector3,to:Vector3,color:Color):
	if tracers.size()>=160:return
	var delta=to-from
	var distance=delta.length()
	if distance<0.01:return
	var direction=delta/distance
	var basis=Basis(Quaternion(Vector3.UP,direction)).scaled_local(Vector3(0.045,minf(12,distance),0.045))
	tracers.append({"from":from,"direction":direction,"distance":distance,"travel":0.0,"basis":basis,"color":color})

func update_tracers(delta:float):
	var count=0
	for i in range(tracers.size()-1,-1,-1):
		var t=tracers[i]
		t.travel+=delta*800
		if t.travel>t.distance:
			tracers.remove_at(i)
			continue
		tracer_batch.multimesh.set_instance_transform(count,Transform3D(t.basis,t.from+t.direction*t.travel))
		tracer_batch.multimesh.set_instance_color(count,t.color)
		count+=1
	tracer_batch.multimesh.visible_instance_count=count

func flame_jet(source,from:Vector3,aim:Vector3):
	ammo_spent+=1
	var direction=(aim-from).normalized()
	var ray=PhysicsRayQueryParameters3D.create(from,from+direction*23,1|2|4|8)
	ray.exclude=source.shot_exclusions() if source==player else [source.get_rid()]
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	var end=hit.position if not hit.is_empty() else from+direction*23
	for other in actors+[player]:
		if not actor_alive(other) or other==source:continue
		var v=actor_aim(other)-from
		if v.length()>end.distance_to(from)+1.1 or v.length()>24 or v.normalized().dot(direction)<0.96:continue
		var q=PhysicsRayQueryParameters3D.create(from,actor_aim(other),1)
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			hurt_actor(other,19,from,"fire")
			flame_hits+=1
	tracer(from,end,Color("ff8d32"))
	if effects.size()<100:
		var fire=Art.sphere(self,0.27,end,Art.material(Color("ffb453")))
		fire.mesh.radial_segments=6
		fire.mesh.rings=4
		effects.append({"node":fire,"time":0.22})
	sounds.at("explosion",from,-20,1.8)

func build_flashes():
	flash_batch=MultiMeshInstance3D.new()
	flash_batch.multimesh=MultiMesh.new()
	flash_batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	var mesh=SphereMesh.new()
	mesh.radius=0.24
	mesh.height=0.32
	mesh.radial_segments=6
	mesh.rings=3
	var material=StandardMaterial3D.new()
	material.albedo_color=Color("ffe6b4")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material=material
	flash_batch.multimesh.mesh=mesh
	flash_batch.multimesh.instance_count=96
	flash_batch.multimesh.visible_instance_count=0
	flash_batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash_batch)

func update_flashes():
	if flash_batch==null:return
	flashes=flashes.filter(func(f):return f.until>elapsed)
	for i in range(flashes.size()):flash_batch.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,flashes[i].p))
	flash_batch.multimesh.visible_instance_count=flashes.size()

func recover_bangalore(actor)->bool:
	if actor.bangalores>0:return false
	var closest=null
	var best=24.0*24.0
	for fallen in corpses:
		if fallen.team!=1 or fallen.bangalores<=0:continue
		var claim=claimed_charges.get(fallen.index,{"actor":actor,"until":0})
		if claim.actor!=actor and claim.actor.alive and claim.until>elapsed:continue
		var d=fallen.position.distance_squared_to(actor.position)
		if d<best:
			best=d
			closest=fallen
	if closest==null:return false
	claimed_charges[closest.index]={"actor":actor,"until":elapsed+3}
	if best<9:
		actor.bangalores=closest.bangalores
		closest.bangalores=0
		actor.role="engineer"
		actor.assault_speed=6.6
	else:
		actor.state="advance"
		actor.stance="stand"
		actor.set_destination(world.on_ground(closest.position))
	return true

func assault_goal(actor)->Vector3:
	var center=world.anchors[actor.sector]
	var flank=center.x+(15 if actor.index%2==0 else -15)
	var doorway=world.on_ground(Vector3(center.x,0,center.z-8))
	var goal=Vector3.ZERO
	match actor.assault_stage:
		0:
			goal=world.on_ground(Vector3(flank,0,center.z+15))
			if actor.flat_distance(actor.position,goal)<2:actor.assault_stage=1
		1:
			goal=world.on_ground(Vector3(flank,0,center.z-12))
			if actor.position.z<center.z-9:actor.assault_stage=2
		2:
			goal=doorway
			if actor.flat_distance(actor.position,goal)<1.4:actor.assault_stage=3
		3:
			goal=center+Vector3(0,0.2,0)
			if actor.position.z>center.z-2:actor.assault_stage=4
		4:
			var room_occupied=false
			for e in enemies:
				if e.alive and e.sector==actor.sector and e.role=="bunker_mg":room_occupied=true
			goal=center+Vector3((actor.index%3-1)*1.2,0.2,0)
			if not room_occupied:actor.assault_stage=5
		5:
			goal=doorway
			if actor.flat_distance(actor.position,goal)<2:actor.assault_stage=6
		_:
			var nearest=null
			var distance=INF
			for e in enemies:
				if not e.alive or e.role=="town_guard" or e.sector!=actor.sector:continue
				var d=actor.position.distance_squared_to(e.position)
				if d<distance:
					distance=d
					nearest=e
			if nearest!=null:return world.on_ground(nearest.position+Vector3(0,0,-3))
			if actor.position.z>Layout.VILLAGE+8:return world.on_ground(Vector3(center.x+(actor.index%5-2)*3,0,Layout.VILLAGE-3))
			distance=INF
			for e in enemies:
				if not e.alive or e.role!="town_guard":continue
				var d=actor.position.distance_squared_to(e.position)
				if d<distance:
					distance=d
					nearest=e
			if nearest!=null:return nearest.position+Vector3(0,0,0.9 if nearest.position.z> -500 else 0.0)
			return world.on_ground(Vector3((actor.index%9-4)*3,0,Layout.CHURCH+20))
	return goal

func update_objectives(delta:float):
	secured=0
	for i in range(8):
		var defenders=0
		var allies=0
		for e in enemies:
			if e.alive and e.role!="town_guard" and e.sector==i:defenders+=1
		for a in friendlies:
			if a.alive and a.truck==null and a.boat==null and a.position.distance_to(world.anchors[i])<35:allies+=1
		if player.truck==null and player.position.distance_to(world.anchors[i])<35:allies+=1
		if defenders==0 and allies>0:capture[i]=minf(10,capture[i]+delta)
		if capture[i]>=10:
			secured+=1
			world.bunkers[i].secured=true
	var attackers=0
	var guards=0
	for a in friendlies:
		if a.alive and a.truck==null and a.boat==null and a.position.z<Layout.VILLAGE:attackers+=1
	if player.truck==null and player.position.z<Layout.VILLAGE:attackers+=1
	for e in enemies:
		if e.alive and e.role=="town_guard":guards+=1
	if attackers>=1 and guards==0 and tanks.all(func(t):return not t.alive):town_control=minf(12,town_control+delta)
	if secured>=3 and town_control>=12 and second_wave_landed and player.health>0:
		phase="victory"
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		sounds.play("victory",-10)

func check_mines():
	for mine in world.mines:
		if not mine.live:continue
		var c=Vector2i(floori(mine.point.x/5),floori(mine.point.z/5))
		var triggered=false
		for dx in [-1,0,1]:
			for dz in [-1,0,1]:
				for a in spatial.get(c+Vector2i(dx,dz),[]):
					if a.alive and a.truck==null and a.position.distance_squared_to(mine.point)<1.0:triggered=true
		if player.truck==null and player.position.distance_squared_to(mine.point)<1.0:triggered=true
		if triggered:
			mine.live=false
			mine_detonations+=1
			explode(mine.point+Vector3(0,0.4,0),4.0,130,null,"mine")

func build_lod_batches():
	for actor in actors:
		var key=str(actor.team)+"/"+actor.weapon_kind
		if lod_batches.has(key):continue
		var root=Node3D.new()
		var cloth=Art.material(Color("65694b") if actor.team==1 else Color("505b54"))
		var dark=Art.material(Color("292f29"))
		var skin=Art.material(Color("a9947c"))
		Art.box(root,Vector3(0.43,0.59,0.28),Vector3(0,1.15,0),cloth)
		Art.box(root,Vector3(0.3,0.32,0.12),Vector3(0,1.24,0.2),dark)
		Art.cylinder(root,0.115,0.25,Vector3(0,1.59,0),skin,-1,6)
		Art.cylinder(root,0.195,0.17,Vector3(0,1.76,0),cloth,0.13,8)
		for x in [-0.12,0.12]:
			Art.box(root,Vector3(0.17,0.72,0.19),Vector3(x,0.49,0),cloth)
			Art.box(root,Vector3(0.18,0.17,0.29),Vector3(x,0.1,-0.05),dark)
		for x in [-0.27,0.27]:
			Art.box(root,Vector3(0.14,0.39,0.18),Vector3(x,1.21,-0.03),cloth)
			Art.box(root,Vector3(0.13,0.13,0.35),Vector3(x*0.65,1.08,-0.22),cloth)
		var gun_profile=Kit.profile(actor.weapon_kind)
		var gun_root=Node3D.new()
		root.add_child(gun_root)
		gun_root.position=Vector3(0.045,1.26,-0.25)
		gun_root.scale=Vector3.ONE*0.85
		Art.box(gun_root,Vector3(0.055,0.075,absf(gun_profile.front)),Vector3(0,0,gun_profile.front*0.5),dark)
		Art.box(gun_root,Vector3(0.05,0.11,gun_profile.rear),Vector3(0,-0.045,gun_profile.rear*0.5),Art.material(Color(gun_profile.wood)))
		if gun_profile.feed=="mag":
			Art.box(gun_root,Vector3(0.045,0.26 if actor.weapon_kind=="mp40" else 0.12,0.075),Vector3(0,-0.1,-0.1),dark)
		elif gun_profile.feed=="belt":
			Art.box(gun_root,Vector3(0.17,0.14,0.16),Vector3(-0.14,-0.01,-0.04),cloth)
			Art.box(gun_root,Vector3(0.075,0.075,0.5),Vector3(0,0,-0.54),dark)
		elif actor.weapon_kind=="flamethrower":
			for x in [-0.12,0.12]:Art.cylinder(root,0.12,0.65,Vector3(x,1.17,0.36),cloth,-1,6)
		var mesh=Kit.bake(root)
		root.free()
		var material=ShaderMaterial.new()
		material.shader=load("res://assets/omaha/distant_soldier.gdshader")
		mesh.surface_set_material(0,material)
		var batch=MultiMeshInstance3D.new()
		batch.multimesh=MultiMesh.new()
		batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		batch.multimesh.use_custom_data=true
		batch.multimesh.mesh=mesh
		batch.multimesh.instance_count=actors.filter(func(a):return a.team==actor.team and a.weapon_kind==actor.weapon_kind).size()
		batch.multimesh.visible_instance_count=0
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
		lod_batches[key]=batch
	# Stable instance slots prevent interpolation from blending different soldiers.
	var slots={}
	for actor in actors:
		var key=str(actor.team)+"/"+actor.weapon_kind
		var slot=int(slots.get(key,0))
		actor.lod_mesh=lod_batches[key].multimesh
		actor.lod_slot=slot
		actor.lod_mesh.set_instance_custom_data(slot,Color(float(actor.index%19)/19.0,0,0,1))
		slots[key]=slot+1
	for key in lod_batches:
		var batch=lod_batches[key]
		batch.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_ON
		batch.multimesh.visible_instance_count=-1
	update_lod()

func update_lod():
	var viewpoint=player.position if phase!="title" else world.world_camera.position
	detail_timer-=get_physics_process_delta_time()
	if detail_timer<=0:
		detail_timer=0.2
		var nearby=[]
		var threshold=pow([20,40,65][quality],2)
		for actor in actors:
			if not actor.alive or (actor.boat!=null and actor.boat.departed):continue
			var d=actor.position.distance_squared_to(viewpoint)
			if d<threshold:nearby.append({"actor":actor,"d":d})
		nearby.sort_custom(func(a,b):return a.d<b.d)
		detailed.clear()
		for entry in nearby.slice(0,[16,36,60][quality]):detailed[entry.actor.get_instance_id()]=true
		detailed_soldiers=detailed.size()
	for actor in actors:
		var i=actor.lod_slot
		var mm=actor.lod_mesh
		var active=actor.alive and not (actor.boat!=null and actor.boat.departed)
		if not active and actor.lod_hidden:continue
		actor.lod_hidden=not active
		var far=active and not detailed.has(actor.get_instance_id())
		var was_far=actor.far_visual
		actor.far_visual=far
		actor.animate_model=active and not far
		if actor.model.root.visible!=(active and not far):actor.model.root.visible=active and not far
		var xf=Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),actor.position)
		if far:
			xf=actor.global_transform
			if actor.truck==null and actor.boat==null:
				var prone=actor.stance=="prone"
				var pose=Transform3D(Basis(Vector3.RIGHT,-PI/2 if prone else 0.0),Vector3(0,0.34 if prone else (-0.42 if actor.stance=="crouch" else 0.0),0))
				xf=actor.global_transform*pose
		if xf!=actor.lod_transform:
			mm.set_instance_transform(i,xf)
			actor.lod_transform=xf
		var running=active and actor.velocity.length_squared()>0.2
		if running!=actor.lod_running:
			mm.set_instance_custom_data(i,Color(float(actor.index%19)/19.0,1.0 if running else 0.0,0,1))
			actor.lod_running=running
		if was_far!=far:mm.reset_instance_physics_interpolation(i)

func actor_died(actor,kind:String):
	# Keep the established persistent bodies, loot, damaged weapons and finite inventory.
	super.actor_died(actor,kind)
	if phase=="victory":phase="playing" # Mission ends at secured exits / town, not a kill counter.

func batch_remains(visual:MeshInstance3D)->Dictionary:
	# Persistent bodies and loot keep their hitboxes and inventory, while shared
	# meshes draw together instead of adding seven draw calls for every casualty.
	var p=visual.global_position
	var key="%d/%d/%d"%[visual.mesh.get_instance_id(),floori(p.x/96),floori(p.z/96)]
	if not remains_batches.has(key):
		var batch=MultiMeshInstance3D.new()
		batch.multimesh=MultiMesh.new()
		batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh=visual.mesh
		batch.multimesh.instance_count=Layout.AMERICANS_TOTAL+Layout.GERMANS_TOTAL
		batch.multimesh.visible_instance_count=0
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.visibility_range_end=350
		batch.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_ON
		add_child(batch)
		remains_batches[key]=batch
	var mm=remains_batches[key].multimesh
	var slot=mm.visible_instance_count
	if slot>=mm.instance_count:return {}
	mm.set_instance_transform(slot,visual.global_transform)
	mm.reset_instance_physics_interpolation(slot)
	mm.visible_instance_count+=1
	visual.hide()
	return {"mm":mm,"slot":slot}

func interact():
	if player.truck!=null:
		player.truck.dismount()
		return
	super.interact()

func objective_target()->Vector3:
	if player.truck!=null:return world.on_ground(Vector3(player.truck.lane_x,0,Layout.WIRE_ROWS[0]))
	if secured>=3:
		var guard=null
		var distance=INF
		for e in enemies:
			if not e.alive or e.role!="town_guard":continue
			var d=player.position.distance_squared_to(e.position)
			if d<distance:
				distance=d
				guard=e
		return guard.position if guard!=null else world.on_ground(Vector3(0,0,Layout.CHURCH+20))
	var wire=world.blocking_wire(player.position,player.position.x)
	if wire!=null:
		var gap=world.nearest_gap(wire.row,player.position.x)
		return gap.position if gap!=null else wire.position
	var best=INF
	var goal=world.on_ground(Vector3(0,0,Layout.CHURCH+20))
	for i in range(8):
		if capture[i]>=10:continue
		var d=player.position.distance_squared_to(world.anchors[i])
		if d<best:
			best=d
			goal=world.bunkers[i].rear
	return goal

func objective_text()->String:
	if player.truck!=null:
		if player.truck.departing:return "MISSED THE RAMP • CRAFT RETURNING TO SEA"
		if player.truck.arrived:return "WASD off ramp • boat leaves in %ds"%maxi(0,ceili(player.truck.landed_at+36-elapsed))
		return "Stay low • first wave inbound"
	if player.position.z>Layout.WIRE_ROWS[2]:return "Reach the seawall • follow a wire breach"
	return "Exits %d/3 • town guards %d • tanks %d"%[mini(secured,3),enemies.filter(func(a):return a.alive and a.role=="town_guard").size(),tanks.filter(func(t):return t.alive).size()]

func retry():
	get_tree().set_meta("omaha_retry",true)
	get_tree().change_scene_to_file("res://scenes/omaha.tscn")

func _exit_tree():
	super._exit_tree()

func launch_heavy(source,from:Vector3,aim:Vector3,kind:String):
	if heavy_projectiles.size()>=32:return
	var speed=90.0 if kind=="bazooka" else 160.0
	var gravity=3.5 if kind=="bazooka" else 9.8
	var time=from.distance_to(aim)/speed
	var direction=(aim+Vector3(0,0.5*gravity*time*time,0)-from).normalized()
	var excludes:Array[RID]=[]
	excludes.assign(source.shot_exclusions() if source.has_method("shot_exclusions") else [source.get_rid(),source.equipment.get_rid()])
	var visual=Node3D.new()
	add_child(visual)
	visual.position=from
	visual.look_at(from+direction)
	var finish=Art.material(Color("e7bc76") if kind=="tank_shell" else Color("c0ac78"))
	var projectile=Art.cylinder(visual,0.035,0.38,Vector3.ZERO,finish,-1,6)
	projectile.rotation.x=PI/2
	projectile.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	heavy_projectiles.append({"p":from,"v":direction*speed,"g":gravity,"time":0.0,"source":source,"kind":kind,"exclude":excludes,"visual":visual})
	if flashes.size()<96:flashes.append({"p":from,"until":elapsed+0.15})
	sounds.at("explosion",from,-10 if kind=="bazooka" else -2,0.8)
	emit_noise(from,260,source.team,"gunshot")

func step_heavy_projectiles(delta:float):
	for shot in heavy_projectiles.duplicate():
		var next=shot.p+shot.v*delta+Vector3(0,-0.5*shot.g*delta*delta,0)
		var q=PhysicsRayQueryParameters3D.create(shot.p,next,1|2|4|8)
		q.exclude=shot.exclude
		var hit=get_world_3d().direct_space_state.intersect_ray(q)
		tracer(shot.p,hit.position if not hit.is_empty() else next,Color("ffc87e"))
		shot.time+=delta
		if not hit.is_empty():
			var point=hit.position
			var tank=hit.collider.get("tank_owner")
			if tank!=null and shot.kind=="bazooka":tank.hit_rocket(point)
			# The detonation sits outside the struck surface so cover rays stay valid.
			explode(point+hit.normal*0.10,6.0 if shot.kind=="bazooka" else 7.5,160 if shot.kind=="bazooka" else 210,shot.source,shot.kind)
			shot.visual.queue_free()
			heavy_projectiles.erase(shot)
		elif shot.time>5.0:
			shot.visual.queue_free()
			heavy_projectiles.erase(shot)
		else:
			shot.p=next
			shot.v.y-=shot.g*delta
			shot.visual.position=next
			shot.visual.look_at(next+shot.v)

func explode(point:Vector3,radius:float,damage:float,source,kind:String="grenade"):
	var previous=active_blast_kind
	active_blast_kind=kind
	super.explode(point,radius,damage,source,kind)
	for tank in tanks:tank.receive_blast(point,radius,damage,kind)
	active_blast_kind=previous

func activate_town():
	if town_active:return
	town_active=true
	for a in enemies:
		if a.role=="town_guard":a.set_reserve(false)
	rebuild_spatial()

func actor_alive(actor)->bool:
	if is_instance_valid(actor) and actor is Soldier and actor.role=="town_guard":return actor.alive
	return super.actor_alive(actor)

func hurt_actor(actor,damage:float,source:Vector3,kind:String):
	if actor is Soldier and actor.role=="town_guard" and actor.staged:
		activate_town()
		actor.set_reserve(false)
	super.hurt_actor(actor,damage,source,kind)
