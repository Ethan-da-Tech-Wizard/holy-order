extends CharacterBody3D

const Kit=preload("res://scripts/ardennes/weapons.gd")
const Art=preload("res://scripts/art.gd")
var game
var index:int=0
var team:int=0
var squad:int=0
var leader:bool=false
var weapon_kind:String="kar98"
var spec:Dictionary
var rounds:int=0
var reserve:int=0
var grenades:int=2
var fausts:int=0
var health:float=100
var alive:bool=true
var weapon_health:float=110
var backup_rounds:int=0
var backup_reserve:int=0
var dropped_broken:bool=false
var model:Dictionary
var gun:Node3D
var equipment:Area3D
var shape:CollisionShape3D
var target
var last_known=Vector3.ZERO
var contact_age:float=999
var destination=Vector3.ZERO
var home=Vector3.ZERO
var guard_radius:float=27
var order:String="hold"
var temperament:String="cautious"
var state:String="watch"
var suppression:float=0
var shot_clock:float=0
var reload_clock:float=0
var grenade_clock:float=6
var sense_clock:float=0
var path=PackedVector3Array()
var path_cursor:int=0
var nav_revision:int=-1
var path_refresh:float=0
var move_clock:float=0
var dig_clock:float=0
var entrenched:bool=false
var cover=Vector3.ZERO
var has_cover:bool=false
var peek=Vector3.ZERO
var move_goal=Vector3.ZERO
var truck
var seat:int=0
var mounted:bool=false
var staged:bool=false
var looted:bool=false
var shots:int=0
var grenades_thrown:int=0
var far_from_hold:float=0
var travelled:float=0
var eye_height:float=1.55
var detected:bool=false
var burst_left:int=0
var burst_pause:float=0
var reaction:float=0
var decision_count:int=0
var fire_blocked:int=0
var stuck:float=0
var knife_clock:float=0
var idle_mount_time:float=0
var last_mount_position=Vector3.ZERO

func _ready():
	spec=Kit.DATA[weapon_kind]
	rounds=spec.capacity
	reserve=spec.reserve
	if mounted:
		backup_rounds=8 if team==1 else 5
		backup_reserve=16 if team==1 else 10
	collision_layer=4 if team==0 else 8
	collision_mask=1|2
	floor_snap_length=0.65
	shape=CollisionShape3D.new()
	var cap=CapsuleShape3D.new()
	cap.radius=0.30
	cap.height=1.76
	shape.shape=cap
	shape.position.y=0.88
	add_child(shape)
	model=Kit.soldier(self,team,index)
	gun=Kit.weapon(model.root,weapon_kind)
	gun.position=Vector3(0.045,1.26,-0.25)
	gun.scale=Vector3.ONE*0.85
	if weapon_kind=="m2":gun.scale=Vector3.ONE
	equipment=Area3D.new()
	equipment.collision_layer=16
	equipment.collision_mask=0
	equipment.set_meta("wielder",self)
	gun.add_child(equipment)
	var ec=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=Vector3(0.13,0.16,1.0)
	ec.shape=box
	ec.position=Vector3(0,0,-0.20)
	equipment.add_child(ec)
	if fausts>0:
		var p=Art.cylinder(model.root,0.027,0.95,Vector3(0.26,1.18,0.24),Art.material(Color("807d4b")),-1,10)
		p.rotation.z=0.14
		Art.cylinder(model.root,0.073,0.22,Vector3(0.32,1.72,0.24),Art.material(Color("807d4b")),0.03,10)
	home=global_position
	destination=home
	move_goal=home
	shot_clock=randf_range(0.4,2.3)
	grenade_clock=randf_range(6,18)

func eye()->Vector3:
	return global_position+Vector3(0,eye_height,0)

func aim_point()->Vector3:
	return global_position+Vector3(0,0.93 if state=="dig" else 1.1,0)

func _physics_process(delta):
	var started=Time.get_ticks_usec() if game.profile_enabled else 0
	step_actor(delta)
	if game.profile_enabled and Time.get_ticks_usec()-started>8000:print("PROFILE actor_tick ",Time.get_ticks_usec()-started," ",state)

func step_actor(delta):
	if not alive or game.phase!="playing" or staged:return
	suppression=maxf(0,suppression-delta)
	shot_clock=maxf(0,shot_clock-delta)
	grenade_clock=maxf(0,grenade_clock-delta)
	burst_pause=maxf(0,burst_pause-delta)
	contact_age+=delta
	if mounted:
		idle_mount_time+=delta
		if team==1 and game.dismounted and idle_mount_time>12 and truck!=null:leave_mount()
	path_refresh=maxf(0,path_refresh-delta)
	knife_clock=maxf(0,knife_clock-delta)
	if reload_clock>0:
		reload_clock=maxf(0,reload_clock-delta)
		if reload_clock==0:
			var load_count=mini(spec.capacity-rounds,reserve)
			rounds+=load_count
			reserve-=load_count
	if truck!=null:
		if mounted:global_transform=truck.gunner_transform()
		else:global_transform=truck.seat_transform(seat)
		if not is_equal_approx(shape.shape.height,1.10):shape.shape.height=1.10
		shape.position.y=0.98
		model.body.position.y=-0.22 if not mounted else 0.0
		for leg in model.legs:leg.rotation.x=-PI*0.42 if not mounted else 0.0
		if mounted:try_fire()
		return
	var body_height=1.30 if state in ["dig","cover","suppressed"] else 1.76
	if not is_equal_approx(shape.shape.height,body_height):shape.shape.height=body_height
	shape.position.y=shape.shape.height*0.5
	eye_height=shape.shape.height-0.12
	model.root.position.y=lerpf(model.root.position.y,-0.40 if shape.shape.height<1.6 else 0.0,delta*8)
	if state=="dig":
		dig_clock+=delta
		if dig_clock>=5.5:
			game.world.dig(global_position+Vector3(0,0.2,0),0.63)
			entrenched=true
			state="cover"
	var moving=state in ["advance","relocate","melee","withdraw"] and not mounted
	var direction=Vector3.ZERO
	if moving:
		if path_cursor<path.size():
			var waypoint=path[path_cursor]
			waypoint.y=global_position.y
			if global_position.distance_to(waypoint)<1.1:path_cursor+=1
			else:direction=(waypoint-global_position).normalized()
		elif global_position.distance_to(destination)<3.4:
			direction=(destination-global_position)
			direction.y=0
			if direction.length()>0.8:direction=direction.normalized()
			else:direction=Vector3.ZERO
		if order=="hold" and Vector2(global_position.x-home.x,global_position.z-home.z).length()>guard_radius-0.7:
			var home_dir=home-global_position
			home_dir.y=0
			if direction.dot(home_dir)<0:direction=home_dir.normalized()
	var speed=3.5 if temperament=="aggressive" else 2.0
	if suppression>0:speed*=0.72
	if state=="melee":speed=4.1
	var separation=game.separation_for(self) if direction.length_squared()>0.1 else Vector3.ZERO
	velocity.x=move_toward(velocity.x,(direction.x+separation.x*0.5)*speed,delta*12)
	velocity.z=move_toward(velocity.z,(direction.z+separation.z*0.5)*speed,delta*12)
	if not is_on_floor():velocity.y-=20*delta
	var old=global_position
	move_and_slide()
	var dist=old.distance_to(global_position)
	travelled+=dist
	if direction.length_squared()>0.1 and dist<0.012:stuck+=delta
	else:stuck=0
	if stuck>1.4 and is_on_floor():
		velocity.y=4.2
		path_refresh=0
		stuck=0
	if order=="hold":
		var offset=global_position-home
		offset.y=0
		if offset.length()>guard_radius:
			var inside=home+offset.normalized()*guard_radius
			global_position.x=inside.x
			global_position.z=inside.z
	if order=="hold":far_from_hold=maxf(far_from_hold,Vector2(global_position.x-home.x,global_position.z-home.z).length())
	var facing=(last_known-global_position) if target!=null and contact_age<3 else direction
	facing.y=0
	if facing.length_squared()>0.2:rotation.y=lerp_angle(rotation.y,atan2(-facing.x,-facing.z),delta*7)
	move_clock+=delta*Vector2(velocity.x,velocity.z).length()*2.9
	model.legs[0].rotation.x=sin(move_clock)*minf(0.65,velocity.length()*0.18)
	model.legs[1].rotation.x=-model.legs[0].rotation.x
	try_fire()
	if global_position.y< -42:take_damage(1000,global_position,"fall")

func think(now:float):
	if not alive or staged:return
	decision_count+=1
	if nav_revision!=game.world.geometry_revision:
		if has_cover and game.world.cover_changed(cover,nav_revision):has_cover=false
		nav_revision=game.world.geometry_revision
	var sq=game.squads[squad]
	order="hold" if mounted and team==0 else sq.order
	temperament=sq.temperament
	if truck!=null and not mounted:return
	var closest=game.acquire_target(self)
	if closest!=null:
		if target!=closest:reaction=now+randf_range(0.35,1.2)
		target=closest
		last_known=game.actor_aim(target)
		contact_age=0
		detected=true
		game.report_contact(self,last_known)
	else:
		target=null
		if sq.contact_age<14 and contact_age>sq.contact_age:
			last_known=sq.contact
			contact_age=sq.contact_age
	if rounds==0 and reserve>0 and reload_clock==0:reload_clock=spec.reload
	if mounted:
		state="mounted"
		if rounds==0 and reserve==0 or weapon_health<=0:
			leave_mount()
		return
	if weapon_health<=0 or rounds+reserve==0:
		state="melee"
		if target!=null and global_position.distance_to(game.actor_aim(target))<2.3 and knife_clock<=0:
			game.hurt_actor(target,35,global_position,"melee")
			knife_clock=1.1
		if contact_age<20:set_destination(limit_goal(last_known))
		elif order=="assault":set_destination(game.tactics.formation_goal(game,self))
		return
	if target!=null:
		var distance=eye().distance_to(last_known)
		if distance<2.0 and knife_clock<=0:
			game.hurt_actor(target,35,global_position,"melee")
			knife_clock=1.1
		if fausts>0 and distance>16 and distance<65 and shot_clock==0:
			if game.safe_explosive_target(self,last_known,8):
				fausts-=1
				shot_clock=4
				game.launch_faust(self,last_known,null,false)
		if grenades>0 and grenade_clock==0 and distance>10 and distance<32:
			if game.safe_explosive_target(self,last_known,7) and game.can_lob(eye(),last_known):
				grenades-=1
				grenades_thrown+=1
				grenade_clock=randf_range(12,22)
				game.bot_grenade(self,last_known)
			else:grenade_clock=2.0
	if fire_blocked>=3 and not mounted:
		fire_blocked=0
		state="relocate"
		var side=(last_known-global_position).cross(Vector3.UP).normalized()
		set_destination(limit_goal(global_position+side*(3.5 if index%2==0 else -3.5)))
		return
	if contact_age>25:
		if order=="hold":
			if global_position.distance_to(home)>4:set_destination(home)
			else:state="watch"
		elif sq.order=="assault":
			state="advance"
			set_destination(game.tactics.formation_goal(game,self))
		return
	if order=="hold":
		if not has_cover or (suppression>1.0 and randf()<0.35):choose_cover(last_known,22)
		if has_cover and global_position.distance_to(cover)>2.0:
			state="relocate"
			set_destination(cover)
		elif target!=null:
			state="fire" if suppression<0.8 else "suppressed"
		elif not entrenched and suppression==0 and global_position.distance_to(last_known)>35:
			state="dig"
		else:
			state="relocate" if has_cover and global_position.distance_to(peek)>1.0 else "cover"
			if state=="relocate":set_destination(peek)
	else:
		var distance=global_position.distance_to(last_known)
		var moving_slot=(int(now/(3.2 if temperament=="aggressive" else 5.0))+index)%2==0
		if suppression>1.0:
			if not has_cover:choose_cover(last_known,18)
			state="relocate"
			set_destination(cover if has_cover else global_position)
		elif target!=null and (not moving_slot or distance< (15 if temperament=="aggressive" else 32)):
			state="fire"
		else:
			state="advance"
			if path_refresh==0:
				choose_cover(last_known,24)
				var toward=(last_known-global_position).normalized()
				var goal=global_position+toward*(14 if temperament=="aggressive" else 8)
				if has_cover and cover.distance_to(last_known)<distance-2:goal=cover
				set_destination(goal)

func limit_goal(goal:Vector3)->Vector3:
	if order!="hold":return goal
	var offset=goal-home
	offset.y=0
	if offset.length()>guard_radius-2:goal=home+offset.normalized()*(guard_radius-2)
	return game.world.on_ground(goal)

func set_destination(goal:Vector3):
	goal=limit_goal(goal)
	if destination.distance_to(goal)<2 and path_refresh>0:return
	destination=goal
	path=game.world.path_between(global_position,destination)
	path_cursor=1 if path.size()>1 else 0
	path_refresh=randf_range(1.8,3.5)
	if state=="watch":state="advance"

func choose_cover(threat:Vector3,radius:float):
	var best=INF
	var chosen=Vector3.ZERO
	var chosen_peek=Vector3.ZERO
	for point in game.world.cover_candidates(global_position,radius):
		if game.cover_occupied(self,point):continue
		if order=="hold" and Vector2(point.x-home.x,point.z-home.z).length()>guard_radius-2:continue
		var ray=PhysicsRayQueryParameters3D.create(threat,point+Vector3(0,0.70,0),1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		var score=global_position.distance_to(point)
		if order=="assault":score+=point.distance_to(threat)*0.35
		if score>=best:continue
		var side=(threat-point).cross(Vector3.UP).normalized()
		var found=false
		for offset in [Vector3.ZERO,side*1.5,-side*1.5]:
			var candidate=point+offset
			var exposed=PhysicsRayQueryParameters3D.create(candidate+Vector3(0,1.6,0),threat,1)
			if get_world_3d().direct_space_state.intersect_ray(exposed).is_empty():
				chosen_peek=game.world.on_ground(candidate)
				found=true
				break
		if not found:continue
		chosen=point
		best=score
	has_cover=best<INF
	if has_cover:
		cover=chosen
		peek=limit_goal(chosen_peek)

func try_fire():
	if target==null or not game.actor_alive(target) or contact_age>0.7 or game.elapsed<reaction:return
	if shot_clock>0 or reload_clock>0 or burst_pause>0 or rounds<=0 or weapon_health<=0:return
	if not mounted and state not in ["fire","watch","cover","suppressed"]:return
	gun.look_at(game.actor_aim(target),Vector3.UP)
	var from=gun.get_node("Muzzle").global_position
	var aim=game.actor_aim(target)
	if from.distance_to(aim)>spec.range:return
	if not game.safe_fire_line(self,from,aim):
		# A blocked lane is checked again shortly. Rechecking every physics tick for
		# every waiting rifleman needlessly repeated the entire friendly-fire scan.
		shot_clock=0.16
		return
	var spread=spec.spread*(2.1 if suppression>0 else 1.0)
	if truck!=null:spread*=1.7
	game.shoot(self,from,aim,spread,spec.damage,weapon_kind)
	rounds-=1
	idle_mount_time=0
	shots+=1
	shot_clock=spec.interval*randf_range(0.95,1.30)
	if spec.automatic:
		if burst_left<=0:burst_left=randi_range(3,7)
		burst_left-=1
		if burst_left==0:burst_pause=randf_range(0.9,1.8)

func hear_noise(point:Vector3,radius:float,source_team:int,_kind:String):
	if not alive or staged or source_team==team:return
	var distance=global_position.distance_to(point)
	if distance>radius:return
	if team==1 and game.dismounted and distance>38:
		var sq=game.squads[squad]
		if sq.has("area") and point.distance_to(game.world.anchors[sq.area])>48:return
	if contact_age<1.2:return
	last_known=point+Vector3(randf_range(-1,1),0,randf_range(-1,1))*clampf(distance*0.07,1.0,12.0)
	contact_age=minf(contact_age,5.0)
	game.report_contact(self,last_known)

func near_miss(point:Vector3):
	if not alive:return
	suppression=maxf(suppression,randf_range(1.5,3.5))
	if contact_age>1:
		last_known=point
		contact_age=3
	if state=="dig":state="suppressed"

func take_damage(amount:float,source:Vector3=Vector3.ZERO,kind:String="rifle"):
	if not alive:return
	health=maxf(0,health-amount)
	suppression=maxf(suppression,2.5)
	if source!=Vector3.ZERO and contact_age>1:
		last_known=source
		contact_age=1
	if health>0:return
	alive=false
	if mounted and weapon_kind=="m2":last_mount_position=gun.global_position
	state="dead"
	collision_layer=0
	equipment.collision_layer=0
	velocity=Vector3.ZERO
	if mounted:
		mounted=false
		if weapon_kind=="m2":gun.hide()
	if truck!=null:
		var p=global_position
		truck=null
		global_position=game.world.on_ground(p+Vector3(randf_range(-1,1)*2.7,0,randf_range(-1,1)))
	var tween=create_tween()
	tween.tween_property(model.root,"rotation:z",1.50*signf(randf()-0.5),0.42)
	game.actor_died(self,kind)
	model.root.hide()

func damage_weapon(amount:float):
	weapon_health=maxf(0,weapon_health-amount)
	if weapon_health==0 and not dropped_broken:
		dropped_broken=true
		game.drop_weapon(weapon_kind,rounds,0,global_position,rotation.y,weapon_kind=="m2")
		rounds=0
		gun.hide()

func dismount():
	if truck==null:return
	var vehicle=truck
	var side=-1 if seat%2==0 else 1
	var local=Vector3(side*2.9,0,-0.5+float(seat/2)*0.7)
	var position_out=game.world.on_ground(vehicle.to_global(local))+Vector3(0,0.25,0)
	truck=null
	global_position=position_out
	shape.shape.height=1.76
	shape.position.y=0.88
	model.body.position.y=0
	for leg in model.legs:leg.rotation.x=0
	home=position_out
	state="advance"
	if weapon_kind=="m2" and vehicle.destroyed:
		mounted=false
		switch_to_rifle()
	elif weapon_kind=="m2":
		# A .50 stays on its ring mount. It is never carried as a rifle.
		truck=vehicle
		mounted=true
	else:mounted=false

func switch_to_rifle():
	weapon_kind="garand" if team==1 else "kar98"
	spec=Kit.DATA[weapon_kind]
	# A separately tracked emergency personal rifle, not an infinite refill of the MG.
	rounds=backup_rounds
	reserve=backup_reserve
	backup_rounds=0
	backup_reserve=0
	weapon_health=100
	var old_gun=gun
	gun=Kit.weapon(model.root,weapon_kind)
	equipment.reparent(gun,false)
	old_gun.queue_free()
	gun.position=Vector3(0.045,1.26,-0.25)
	gun.scale=Vector3.ONE*0.85

func leave_mount():
	if not mounted:return
	mounted=false
	if weapon_kind=="m2" and truck!=null:
		game.drop_weapon("m2",rounds,weapon_health,gun.global_position,rotation.y,true)
		var vehicle=truck
		truck=null
		global_position=game.world.on_ground(vehicle.to_global(Vector3(3,0,0)))+Vector3(0,0.25,0)
		model.body.position.y=0
		for leg in model.legs:leg.rotation.x=0
	switch_to_rifle()
	state="advance"
