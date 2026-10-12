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
var animate_model:bool=true
var gun:Node3D
var equipment:Area3D
var shape:CollisionShape3D
var target
var vehicle_target
var wing:int=0
var reserved_faust:bool=false
var stance:String="stand"
var threat_pressure:float=0
var lean_amount:float=0
var grenade_throw_time:float=0
var grenade_throw_target=Vector3.ZERO
var grenade_released:bool=false
var grenade_visual:MeshInstance3D
var dig_strokes:int=0
var posture_revision:int=-1
var idle_collision_clock:float=0
var suppression_shots:int=0
var last_cover_search:float=-10
var obstruction_normal=Vector3.ZERO
var terrain_recoveries:int=0
var movement_block_time:float=0
var last_known=Vector3.ZERO
var contact_age:float=999
var destination=Vector3.ZERO
var home=Vector3.ZERO
var guard_radius:float=27
var order:String="hold"
var assault_speed:float=4.6
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
	floor_snap_length=0.55
	floor_max_angle=deg_to_rad(48)
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
	grenade_visual=Art.sphere(model.right_arm,0.05,Vector3(-0.14,-0.17,-0.4),Art.material(Color("55573b")))
	grenade_visual.mesh.radial_segments=8
	grenade_visual.mesh.rings=4
	grenade_visual.hide()
	home=global_position
	destination=home
	move_goal=home
	shot_clock=randf_range(0.4,2.3)
	grenade_clock=randf_range(6,18)

func eye()->Vector3:
	return global_position+Vector3(0,eye_height,0)+global_basis.x*lean_amount*0.22-global_basis.z*(0.65 if stance=="prone" else 0.0)

func aim_point()->Vector3:
	return global_position+Vector3(0,0.34 if stance=="prone" else (0.86 if stance=="crouch" else 1.12),0)-global_basis.z*(0.65 if stance=="prone" else 0.0)

func _physics_process(delta):
	var started=Time.get_ticks_usec() if game.profile_enabled else 0
	step_actor(delta)
	if game.profile_enabled and Time.get_ticks_usec()-started>8000:print("PROFILE actor_tick ",Time.get_ticks_usec()-started," ",state)

func step_actor(delta):
	if not alive or game.phase!="playing":return
	suppression=maxf(0,suppression-delta)
	threat_pressure=maxf(0,threat_pressure-delta*0.8)
	shot_clock=maxf(-delta,shot_clock-delta)
	grenade_clock=maxf(0,grenade_clock-delta)
	burst_pause=maxf(0,burst_pause-delta)
	contact_age+=delta
	path_refresh=maxf(0,path_refresh-delta)
	knife_clock=maxf(0,knife_clock-delta)
	if reload_clock>0:
		reload_clock=maxf(0,reload_clock-delta)
		if reload_clock==0:
			var load_count=mini(spec.capacity-rounds,reserve)
			rounds+=load_count
			reserve-=load_count
	if truck!=null:
		global_transform=truck.seat_transform(seat)
		if not is_equal_approx(shape.shape.height,1.10):
			shape.shape.height=1.10
			shape.position.y=0.98
		model.body.position.y=-0.22
		model.right_arm.position.y=1.19
		for leg in model.legs:leg.rotation.x=-PI*0.42
		# All passengers keep weapons down, including the old truck-gunner slots.
		gun.rotation=Vector3(0.45,0,0)
		return
	step_grenade(delta)
	update_posture(delta)
	if state=="dig":
		dig_clock+=delta
		if dig_clock>=1.8:
			dig_clock=0
			var side=global_basis.x*(0.5 if dig_strokes%2==0 else -0.5)
			game.world.dig(global_position+side,1.6,0.24)
			dig_strokes+=1
			if dig_strokes>=5:
				entrenched=true
				state="cover"
	var moving=state in ["advance","relocate","melee","withdraw","crawl"] and not mounted and grenade_throw_time<=0
	var direction=Vector3.ZERO
	if moving:
		if path_cursor<path.size():
			var waypoint=path[path_cursor]
			waypoint.y=global_position.y
			if global_position.distance_to(waypoint)<0.7:path_cursor+=1
			else:direction=(waypoint-global_position).normalized()
		else:
			direction=destination-global_position
			direction.y=0
			if direction.length()>0.6:direction=direction.normalized()
			else:direction=Vector3.ZERO
		if order=="hold" and Vector2(global_position.x-home.x,global_position.z-home.z).length()>guard_radius-0.9:
			var home_dir=home-global_position
			home_dir.y=0
			if direction.dot(home_dir)<0:direction=home_dir.normalized()
	var speed=assault_speed if order=="assault" else 2.5
	if stance=="crouch":speed*=0.64
	if stance=="prone":speed=1.10
	if state=="melee":speed=4.8
	var separation=game.separation_for(self) if direction.length_squared()>0.1 else Vector3.ZERO
	direction=(direction+separation*0.7).limit_length(1)
	if obstruction_normal.length_squared()>0.1 and direction.dot(obstruction_normal)<-0.1:
		# Slide along a local obstacle while the next route is being refreshed.
		var tangent=direction.slide(obstruction_normal)
		if tangent.length_squared()<0.08:tangent=obstruction_normal.cross(Vector3.UP)*(1 if index%2 else -1)
		direction=(direction*0.3+tangent.normalized()*0.7).normalized()
	velocity.x=move_toward(velocity.x,direction.x*speed,delta*15)
	velocity.z=move_toward(velocity.z,direction.z*speed,delta*15)
	if not is_on_floor():velocity.y-=20*delta
	var old=global_position
	idle_collision_clock-=delta
	if direction.length_squared()>0.02 or velocity.length_squared()>0.02 or not is_on_floor() or idle_collision_clock<=0:
		move_and_slide()
		idle_collision_clock=0.16
	# A posture change can put the long prone capsule through a sloping triangle.
	# The terrain is a heightfield with no tunnels: keep its foot reference above
	# the current excavated surface, including when a collider is replaced.
	var ground=game.world.surface_height(global_position.x,global_position.z)
	if global_position.y<ground-0.12:
		global_position.y=ground+0.025
		velocity.y=maxf(0,velocity.y)
		terrain_recoveries+=1
	var distance=old.distance_to(global_position)
	travelled+=distance
	obstruction_normal=Vector3.ZERO
	if moving and direction.length_squared()>0.1 and distance<0.009:
		stuck+=delta
		if get_slide_collision_count()>0:
			var normal=get_slide_collision(0).get_normal()
			if absf(normal.y)<0.45:obstruction_normal=normal
	else:stuck=0
	if stuck>0.6:
		path_refresh=0
		if is_on_floor() and stance!="prone" and try_step(direction):stuck=0
	if stuck>2.5:
		var side=global_basis.x*(2 if index%2 else -2)
		set_destination(limit_goal(destination+side))
		stuck=0
	if order=="hold":
		var offset=global_position-home
		offset.y=0
		if offset.length()>guard_radius:
			var inside=home+offset.normalized()*guard_radius
			global_position.x=inside.x
			global_position.z=inside.z
		far_from_hold=maxf(far_from_hold,Vector2(global_position.x-home.x,global_position.z-home.z).length())
	var facing=(last_known-global_position) if (target!=null or vehicle_target!=null) and not moving else direction
	facing.y=0
	if facing.length_squared()>0.2:rotation.y=lerp_angle(rotation.y,atan2(-facing.x,-facing.z),delta*9)
	move_clock+=delta*Vector2(velocity.x,velocity.z).length()*3.1
	var gait=0.15 if stance=="prone" else 0.60
	if animate_model:
		model.legs[0].rotation.x=sin(move_clock)*minf(gait,velocity.length()*0.14)
		model.legs[1].rotation.x=-model.legs[0].rotation.x
	try_fire()
	if global_position.y< -42:take_damage(1000,global_position,"fall")

func update_posture(delta:float):
	var prone_now=stance=="prone"
	var slope=0.0
	if prone_now:
		var front=global_position-global_basis.z*1.3
		slope=atan2(game.world.surface_height(front.x,front.z)-game.world.surface_height(global_position.x,global_position.z),1.3)
		slope=clampf(slope,-0.75,0.75)
	var h=1.76 if stance=="stand" else (1.65 if prone_now else 1.20)
	var pose=2 if prone_now else (1 if stance=="crouch" else 0)
	var pose_changed=pose!=posture_revision
	if pose!=posture_revision:
		posture_revision=pose
		shape.shape.height=h
		shape.rotation.x=PI/2 if prone_now else 0.0
		shape.position=Vector3(0,0.32,-0.60) if prone_now else Vector3(0,h*0.5,0)
	if prone_now:
		shape.rotation.x=PI/2+slope
		shape.position=Vector3(0,0.34+sin(slope)*0.60,-cos(slope)*0.60)
	eye_height=0.39 if prone_now else (1.08 if stance=="crouch" else 1.60)
	if not animate_model:
		# The hidden detailed gun still supplies a real muzzle for ballistic rays.
		if pose_changed:
			model.root.rotation.x=-PI/2+slope if prone_now else 0.0
			model.root.position.y=0.34 if prone_now else (-0.42 if stance=="crouch" else 0.0)
		return
	model.root.rotation.x=lerp_angle(model.root.rotation.x,-PI/2+slope if prone_now else 0.0,delta*9)
	model.root.rotation.z=lerp_angle(model.root.rotation.z,-lean_amount*0.14,delta*9)
	model.root.position.y=lerpf(model.root.position.y,0.34 if prone_now else (-0.42 if stance=="crouch" else 0.0),delta*9)
	model.root.position.x=lerpf(model.root.position.x,lean_amount*0.18,delta*9)
	model.body.position.y=0
	model.right_arm.position.y=1.41

func try_step(direction:Vector3)->bool:
	if direction.length_squared()<0.1:return false
	var ahead=global_position+direction*0.8
	var q=PhysicsRayQueryParameters3D.create(ahead+Vector3(0,0.8,0),ahead-Vector3(0,0.1,0),1)
	var hit=get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y<0.68:return false
	var lift=hit.position.y-global_position.y
	if lift<0.04 or lift>0.55:return false
	var clear=PhysicsRayQueryParameters3D.create(hit.position+Vector3(0,0.06,0),hit.position+Vector3(0,1.8,0),1)
	if not get_world_3d().direct_space_state.intersect_ray(clear).is_empty():return false
	global_position.y+=lift+0.025
	return true

func think(now:float):
	if not alive:return
	decision_count+=1
	if truck!=null:return
	if nav_revision!=game.world.geometry_revision:
		if has_cover and game.world.cover_changed(cover,nav_revision):has_cover=false
		nav_revision=game.world.geometry_revision
	var sq=game.squads[squad]
	order="hold" if team==0 else "assault"
	temperament="cautious" if team==0 else "aggressive"
	var closest=game.acquire_target(self)
	vehicle_target=null
	if team==0 and (closest==null or closest.global_position.distance_squared_to(global_position)>1600):vehicle_target=game.acquire_vehicle(self)
	if vehicle_target!=null:
		target=null
		last_known=vehicle_target.target_point(self)
		contact_age=0
		state="mounted" if mounted else "fire"
		stance="stand" if mounted or entrenched else "crouch"
	elif closest!=null:
		if target!=closest:reaction=now+randf_range(0.20,0.65)
		target=closest
		last_known=game.actor_aim(target)
		contact_age=0
		detected=true
		suppression_shots=0
		game.report_contact(self,last_known)
	else:
		target=null
		if sq.contact_age<8 and contact_age>sq.contact_age:
			last_known=sq.contact
			contact_age=sq.contact_age
	if rounds==0 and reserve>0 and reload_clock==0:reload_clock=spec.reload
	if mounted:
		state="mounted"
		stance="stand"
		if rounds+reserve==0 or weapon_health<=0:leave_mount()
		return
	if vehicle_target!=null:return
	if grenade_throw_time>0:
		state="throw"
		return
	var heavy=threat_pressure>=3 or suppression>2.5
	if weapon_health<=0 or rounds+reserve==0:
		state="melee" if target!=null else ("advance" if order=="assault" else ("cover" if entrenched else "dig"))
		stance="crouch" if heavy else "stand"
		if target!=null:
			if global_position.distance_to(game.actor_aim(target))<2.3 and knife_clock<=0:
				game.hurt_actor(target,35,global_position,"melee")
				knife_clock=1.1
			set_destination(limit_goal(last_known))
		elif order=="assault":set_destination(game.tactics.formation_goal(game,self))
		return
	if target!=null:
		var distance=eye().distance_to(last_known)
		if distance<2.0 and knife_clock<=0:
			game.hurt_actor(target,35,global_position,"melee")
			knife_clock=1.1
		if fausts>0 and not reserved_faust and distance>18 and distance<65 and shot_clock==0 and game.safe_explosive_target(self,last_known,8):
			fausts-=1
			shot_clock=4
			game.launch_faust(self,last_known,null,false)
		if grenades>0 and grenade_clock==0 and distance>10 and distance<31:
			if game.safe_explosive_target(self,last_known,7) and game.can_lob(eye(),last_known):
				begin_grenade(last_known)
				return
			grenade_clock=2.0
	var goal=home if order=="hold" else game.tactics.formation_goal(game,self)
	if order=="hold":
		if Vector2(position.x-home.x,position.z-home.z).length()>guard_radius-3:
			state="relocate"
			stance="prone" if heavy else "crouch"
			set_destination(home)
			return
		if contact_age<20 and now-last_cover_search>2.0 and (not has_cover or fire_blocked>=3):choose_cover(last_known,20)
		if heavy and target==null:
			stance="prone"
			state="crawl" if has_cover and flat_distance(global_position,cover)>1.1 else "cover"
			if state=="crawl":set_destination(cover)
		elif has_cover and flat_distance(global_position,cover)>1.4:
			stance="crouch"
			state="relocate"
			set_destination(cover)
		elif target!=null:
			state="fire"
			stance="stand" if entrenched or fire_blocked>0 else "crouch"
			lean_amount=(1 if index%2 else -1) if has_cover else 0
			if fire_blocked>=3:
				fire_blocked=0
				state="relocate"
				set_destination(peek if has_cover else limit_goal(global_position+global_basis.x*2))
		elif not entrenched and not heavy:
			state="dig"
			stance="crouch"
		else:
			state="cover"
			stance="crouch"
		return
	# The mission goal never becomes an unrelated gunshot or a bunker on the
	# opposite wing. Nearby contacts change movement/cover, not the assigned hill.
	var moving_slot=(int(now/2.7)+index)%2==0
	if heavy and target==null:
		stance="prone"
		state="crawl"
		lean_amount=0
		if now-last_cover_search>2.5:choose_cover(last_known,18,goal)
		advance_to_goal(goal,11)
	elif heavy:
		stance="crouch" if has_cover or entrenched else "prone"
		if now-last_cover_search>2:choose_cover(last_known,18,goal)
		if has_cover and flat_distance(position,cover)>1.4:
			state="crawl" if stance=="prone" else "relocate"
			set_destination(cover)
		else:
			state="fire"
			lean_amount=1 if index%2 else -1
	elif target!=null and (not moving_slot or flat_distance(position,last_known)<13):
		state="fire"
		stance="crouch" if has_cover else "stand"
		lean_amount=(1 if index%2 else -1) if has_cover else 0
		if fire_blocked>=3:
			fire_blocked=0
			state="relocate"
			advance_to_goal(goal,9)
	else:
		state="advance"
		stance="stand" if suppression<1 else "crouch"
		lean_amount=0
		if now-last_cover_search>2.2:choose_cover(last_known if contact_age<15 else goal,25,goal)
		advance_to_goal(goal,17)

func flat_distance(a:Vector3,b:Vector3)->float:
	return Vector2(a.x-b.x,a.z-b.z).length()

func advance_to_goal(goal:Vector3,step:float):
	if path_refresh>0 and path_cursor<path.size():return
	var offset=goal-global_position
	offset.y=0
	var next=global_position+offset.limit_length(step)
	if has_cover and flat_distance(cover,goal)<flat_distance(global_position,goal)-2 and flat_distance(global_position,cover)<step+5:next=cover
	set_destination(game.world.on_ground(next))

func limit_goal(goal:Vector3)->Vector3:
	if order!="hold":return goal
	var offset=goal-home
	offset.y=0
	if offset.length()>guard_radius-2:goal=home+offset.normalized()*(guard_radius-2)
	return game.world.on_ground(goal)

func set_destination(goal:Vector3):
	goal=limit_goal(goal)
	if flat_distance(destination,goal)<1.5 and path_refresh>0:return
	destination=goal
	path=game.world.path_between(global_position,destination)
	path_cursor=1 if path.size()>1 else 0
	path_refresh=randf_range(1.0,1.8)
	if state=="watch":state="advance"

func choose_cover(threat:Vector3,radius:float,mission:Vector3=Vector3.INF):
	last_cover_search=game.elapsed
	var best=INF
	var chosen=Vector3.ZERO
	var chosen_peek=Vector3.ZERO
	for point in game.world.cover_candidates(global_position,radius):
		if game.cover_occupied(self,point):continue
		if order=="hold" and Vector2(point.x-home.x,point.z-home.z).length()>guard_radius-2:continue
		var ray=PhysicsRayQueryParameters3D.create(threat,point+Vector3(0,0.70,0),1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		var score=global_position.distance_to(point)
		if order=="assault" and mission!=Vector3.INF:score+=point.distance_to(mission)*0.7
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
		if not found:chosen_peek=point
		# Defilade is still useful when no standing firing point is exposed.
		chosen=point
		best=score
	has_cover=best<INF
	if has_cover:
		cover=chosen
		peek=limit_goal(chosen_peek)

func try_fire():
	if truck!=null or grenade_throw_time>0 or game.elapsed<reaction:return
	if shot_clock>0.000001 or reload_clock>0 or burst_pause>0 or rounds<=0 or weapon_health<=0:return
	if not mounted and state not in ["fire","watch","cover","suppressed"]:return
	var aim=last_known
	if vehicle_target!=null:
		if vehicle_target.destroyed or vehicle_target.unloaded or not vehicle_target.has_passengers():return
		aim=vehicle_target.target_point(self)
	elif target!=null and game.actor_alive(target) and contact_age<0.9:aim=game.actor_aim(target)
	elif not (detected and contact_age<3.0 and suppression_shots<4):return
	gun.look_at(aim,Vector3.UP)
	var from=gun.get_node("Muzzle").global_position
	if from.distance_to(aim)>spec.range:return
	if not game.safe_fire_line(self,from,aim):
		shot_clock=0.18
		return
	var spread=spec.spread*(1.8 if threat_pressure>3 else 1.0)*(0.70 if stance=="prone" else 1.0)
	game.shoot(self,from,aim,spread,spec.damage,weapon_kind)
	if vehicle_target!=null:game.vehicle_shots+=1
	if target==null and vehicle_target==null:suppression_shots+=1
	rounds-=1
	shots+=1
	shot_clock+=spec.interval if spec.automatic else spec.get("aim_interval",spec.interval)
	if spec.automatic:
		if burst_left<=0:burst_left=randi_range(5,10) if vehicle_target!=null else randi_range(3,6)
		burst_left-=1
		if burst_left==0:burst_pause=randf_range(0.55,1.1)

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
	threat_pressure=minf(8,threat_pressure+1.15)
	if contact_age>1:
		last_known=point
		contact_age=3
	if state=="dig":state="suppressed"

func take_damage(amount:float,source:Vector3=Vector3.ZERO,kind:String="rifle"):
	if not alive:return
	health=maxf(0,health-amount)
	suppression=maxf(suppression,2.5)
	threat_pressure=minf(8,threat_pressure+2.2)
	if source!=Vector3.ZERO and contact_age>1:
		last_known=source
		contact_age=1
	if health>0:return
	alive=false
	if mounted and weapon_kind=="m2":last_mount_position=gun.global_position
	state="dead"
	grenade_throw_time=0
	grenade_visual.hide()
	set_physics_process(false)
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
	model.right_arm.position.y=1.41
	posture_revision=-1
	gun.rotation=Vector3.ZERO
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

func begin_grenade(point:Vector3):
	if grenades<=0 or grenade_throw_time>0 or grenade_clock>0 or truck!=null:return
	grenade_throw_time=1.1
	grenade_throw_target=point
	grenade_released=false
	grenade_clock=randf_range(13,22)
	grenade_visual.show()
	gun.hide()
	state="throw"
	stance="crouch"

func step_grenade(delta:float):
	if grenade_throw_time<=0:
		model.right_arm.rotation.x=lerp_angle(model.right_arm.rotation.x,0,delta*10)
		return
	grenade_throw_time=maxf(0,grenade_throw_time-delta)
	var progress=1-grenade_throw_time/1.1
	model.right_arm.rotation.x=-1.5*smoothstep(0,0.45,progress)+2.6*smoothstep(0.45,0.65,progress)
	if not grenade_released and grenade_throw_time<=0.42:
		grenade_released=true
		# Recheck the landing area after windup: a friendly may have moved into it.
		if grenades>0 and game.safe_explosive_target(self,grenade_throw_target,7):
			grenades-=1
			grenades_thrown+=1
			game.bot_grenade(self,grenade_throw_target)
		grenade_visual.hide()
	if grenade_throw_time==0:
		gun.visible=weapon_health>0
		state="cover" if order=="hold" else "advance"
