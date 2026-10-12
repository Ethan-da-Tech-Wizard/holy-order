extends Node3D

const World=preload("res://scripts/ardennes/world.gd")
const Player=preload("res://scripts/ardennes/player.gd")
const Actor=preload("res://scripts/ardennes/actor.gd")
const Truck=preload("res://scripts/ardennes/truck.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")
const Art=preload("res://scripts/art.gd")
const Sounds=preload("res://scripts/ardennes/audio.gd")
const AmmoBundle=preload("res://scripts/ardennes/ammo_bundle.gd")
const Drop=preload("res://scripts/ardennes/dropped_weapon.gd")
const Corpse=preload("res://scripts/ardennes/corpse.gd")
const Tactics=preload("res://scripts/ardennes/tactics.gd")
var tactics=Tactics.new()
var fire_checks_blocked:int=0
const HUD=preload("res://scripts/ardennes/interface.gd")
var world
var player
var hud
var sounds
var player_mounted:bool=false
var demolition=null
var enemies:Array=[]
var friendlies:Array=[]
var actors:Array=[]
var squads:Array=[]
var trucks:Array=[]
var corpses:Array=[]
var decision_credit:float=0
var grenades_live:Array=[]
var rockets:Array=[]
var effects:Array=[]
var engines:Array=[]
var phase:String="title"
var elapsed:float=0
var visual_elapsed:float=0
var column_stopped:bool=false
var lead_strike:bool=false
var rear_strike:bool=false
var lead_hit:bool=false
var rear_hit:bool=false
var rear_at:float=-1
var dismount_at:float=-1
var dismounted:bool=false
var think_cursor:int=0
var sense_timer:float=0
var squad_timer:float=0
var spatial:Dictionary={}
var allies_alive:int=107
var germans_alive:int=80
var ammo_spent:int=0
var friendly_fire_hits:int=0
var near_misses:int=0
var grenade_detonations:int=0
var toast_text:String=""
var toast_time:float=0
var subtitle:String=""
var subtitle_time:float=0
var speaker:String="SGT. HAYES"
var hit_flash:float=0
var damage_flash:float=0
var last_damage_direction=Vector3.ZERO
var winter_intro:bool=false
var staged_launchers:Array=[]
var ambush_outcome:String="pending"
var ambush_targets:Array=[]
var convoy_settled:bool=false
var vehicle_shots:int=0
var cover_reservations:Dictionary={}
var last_frame_ms:Array=[]
var test_mode:bool=false
var combat_seed:int=0
var death_causes:Dictionary={}
var friendly_death_causes:Dictionary={}
var fall_events:Array=[]
var profile_enabled:bool=OS.has_environment("HOLY_ORDER_PROFILE")

func _ready():
	Engine.max_fps=60
	test_mode="--battle-test" in OS.get_cmdline_user_args() or get_tree().has_meta("battle_test")
	combat_seed=int(get_tree().get_meta("battle_seed",0))
	if combat_seed!=0:seed(combat_seed)
	else:randomize()
	register_inputs()
	world=World.new()
	world.game=self
	add_child(world)
	sounds=Sounds.new()
	add_child(sounds)
	player=Player.new()
	player.game=self
	player.position=world.road_point(176)+Vector3(0,3,0)
	add_child(player)
	make_convoy()
	make_germans()
	actors=friendlies+enemies
	tactics.initialize(self)
	rebuild_spatial()
	var canvas=CanvasLayer.new()
	add_child(canvas)
	hud=HUD.new()
	hud.game=self
	canvas.add_child(hud)
	world.world_camera.current=true
	player.camera.current=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_title("Holy Order — Ardennes / Road of Iron")
	if get_tree().has_meta("ardennes_retry"):
		get_tree().remove_meta("ardennes_retry")
		begin()
	if "--battle-preview" in OS.get_cmdline_user_args():begin()

	preload("res://scripts/graphics.gd").install(self)

func register_inputs():
	var bindings={"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"sprint":KEY_SHIFT,"jump":KEY_SPACE,"crouch":KEY_C,"prone":KEY_Z,"objectives":KEY_J,"lean_left":KEY_Q,"lean_right":KEY_E,"reload":KEY_R,"interact":KEY_F,"grenade":KEY_G,"weapon_sword":KEY_1,"weapon_rifle":KEY_2,"weapon_fists":KEY_3,"weapon_shovel":KEY_4,"inventory":KEY_TAB,"pause":KEY_ESCAPE,"fullscreen":KEY_F11}
	for action in bindings:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event=InputEventKey.new()
		event.physical_keycode=bindings[action]
		InputMap.action_add_event(action,event)
	for action in ["attack","aim"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT if action=="attack" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action,event)

func new_squad(team:int,order:String,temperament:String,anchor:Vector3)->int:
	var i=squads.size()
	squads.append({"team":team,"order":order,"temperament":temperament,"anchor":anchor,"objective":anchor,"leader":null,"members":[],"contact":Vector3.ZERO,"contact_age":999.0})
	return i

func make_convoy():
	# One twelve-man rifle squad is the planned load in each CCKW, not its maximum capacity.
	# Nine loads = 108 seats; the player replaces one passenger. Seven central loads = 84 seats.
	for i in range(9):
		var vehicle=Truck.new()
		vehicle.game=self
		vehicle.index=i
		vehicle.progress=150-i*14
		add_child(vehicle)
		trucks.append(vehicle)
		var sq=new_squad(1,"assault","cautious" if i%3==0 else "aggressive",vehicle.position)
		squads[sq].objective=world.anchors[0]
		for seat in range(12):
			if i==4 and seat==10:
				player.truck=vehicle
				player.seat=seat
				player.rotation.y=vehicle.rotation.y+PI
				player.last_truck_yaw=vehicle.rotation.y
				player.position=vehicle.seat_transform(seat).origin
				continue
			var actor=Actor.new()
			actor.game=self
			actor.index=friendlies.size()
			actor.team=1
			actor.squad=sq
			actor.leader=seat==0
			actor.weapon_kind="bar" if seat==2 else "garand"
			actor.truck=vehicle
			actor.seat=seat
			actor.mounted=false
			actor.position=vehicle.seat_transform(seat).origin
			actor.order="assault"
			actor.temperament=squads[sq].temperament
			add_child(actor)
			friendlies.append(actor)
			vehicle.occupants.append(actor)
			squads[sq].members.append(actor)
			if actor.leader:squads[sq].leader=actor
		if sounds.enabled:
			var engine=AudioStreamPlayer3D.new()
			engine.stream=sounds.streams.engine
			engine.volume_db=-10
			engine.unit_size=5
			engine.max_distance=100
			vehicle.add_child(engine)
			vehicle.engine_loop=engine
			engine.finished.connect(func():if phase=="playing" and not vehicle.destroyed and not vehicle.unloaded:engine.play())
			engines.append(engine)

func make_germans():
	for i in range(8):
		var anchor=world.anchors[i]
		var sq=new_squad(0,"hold","cautious",anchor)
		for j in range(10):
			var actor=Actor.new()
			actor.game=self
			actor.index=enemies.size()+107
			actor.squad=sq
			actor.team=0
			actor.leader=j==0
			actor.weapon_kind="mp40" if j==0 else ("g43" if j==2 else "kar98")
			if j==1:
				actor.weapon_kind=world.nests[i].kind
				actor.mounted=true
				world.nests[i].operator=actor
			var facing=(Vector3(world.road_x(anchor.z),anchor.y,anchor.z+15)-anchor).normalized()
			var right=facing.cross(Vector3.UP)
			var slots=[Vector2(0,-6),Vector2(0,0),Vector2(-8,-2),Vector2(8,-2),Vector2(-5,-4),Vector2(5,-4),Vector2(-10,2),Vector2(10,2),Vector2(-13,-5),Vector2(13,-5)]
			if j==4 and world.secondary_nests.has(i):
				actor.weapon_kind="mg42"
				actor.mounted=true
				world.secondary_nests[i].operator=actor
			var offset=right*slots[j].x+facing*slots[j].y
			actor.position=world.on_ground(anchor+offset)+Vector3(0,0.1,0)
			if j==1:actor.position=anchor+Vector3(0,0.1,0)
			if j==4 and world.secondary_nests.has(i):actor.position=world.secondary_nests[i].position+Vector3(0,0.1,0)
			actor.order="hold" if actor.mounted else squads[sq].order
			actor.temperament=squads[sq].temperament
			if j==3 and i in [4,5,6,7]:actor.fausts=1
			add_child(actor)
			actor.home=anchor
			actor.guard_radius=27
			actor.rotation.y=atan2(anchor.x-world.road_x(anchor.z),-16.0)
			enemies.append(actor)
			squads[sq].members.append(actor)
			if actor.leader:squads[sq].leader=actor
			if j==3 and i in [6,7]:
				var z=-143.0 if i==6 else -238.0
				actor.position=world.on_ground(Vector3(world.road_x(z)+(-22 if i==6 else 22),0,z))+Vector3(0,0.1,0)
				actor.home=actor.position
				actor.guard_radius=13
				actor.reserved_faust=true
				staged_launchers.append(actor)

func begin():
	phase="playing"
	player.camera.current=true
	world.world_camera.current=false
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for engine in engines:engine.play()
	say("Stay seated. Weapons safe until we dismount. Watch the road behind us.",5,"SGT. HAYES")
	toast("COVERED TRANSPORT  •  LOOK OUT THE REAR  •  HOLD FIRE UNTIL DISMOUNT",7)

func _unhandled_input(event):
	if event.is_action_pressed("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if event.is_action_pressed("pause"):
		if phase=="playing":pause_game("paused")
		elif phase in ["paused","inventory","objectives"]:resume_game()
	for pair in [["inventory","inventory"],["objectives","objectives"]]:
		if event.is_action_pressed(pair[0]):
			if phase=="playing":pause_game(pair[1])
			elif phase==pair[1]:resume_game()
	if phase=="title" and event is InputEventKey and event.pressed and event.keycode==KEY_ENTER:begin()

func pause_game(menu:String="paused"):
	phase=menu
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for engine in engines:engine.stream_paused=true

func resume_game():
	phase="playing"
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for engine in engines:engine.stream_paused=false

func _notification(what):
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and phase=="playing" and not test_mode:pause_game()

func _process(delta):
	visual_elapsed+=delta
	if phase!="playing":return
	if is_physics_processing():think_budget(delta)
	last_frame_ms.append(delta*1000)
	if last_frame_ms.size()>600:last_frame_ms.pop_front()
	toast_time=maxf(0,toast_time-delta)
	subtitle_time=maxf(0,subtitle_time-delta)
	hit_flash=maxf(0,hit_flash-delta)
	damage_flash=maxf(0,damage_flash-delta)

func _physics_process(delta):
	var started=Time.get_ticks_usec() if profile_enabled else 0
	step_battle(delta)
	if profile_enabled and Time.get_ticks_usec()-started>8000:print("PROFILE battle_tick ",Time.get_ticks_usec()-started)

func step_battle(delta):
	if phase!="playing":return
	elapsed+=delta
	step_convoy(delta)
	if dismounted and not winter_intro and elapsed>dismount_at+9:
		winter_intro=true
		say("At last. A war with weather appropriate for this outfit.",5,"THE KNIGHT")
	sense_timer-=delta
	if sense_timer<=0:
		sense_timer=0.25
		rebuild_spatial()
	squad_timer-=delta
	if squad_timer<=0:
		squad_timer=1.0
		update_squads()
	for sq in squads:sq.contact_age+=delta
	step_projectiles(delta)
	for effect in effects.duplicate():
		effect.time-=delta
		if effect.time<=0:
			effect.node.queue_free()
			effects.erase(effect)

func think_budget(delta:float):
	# Distribute decisions across rendered frames, including those between physics
	# ticks. A slow frame cannot produce an unbounded catch-up spike.
	if elapsed<=3 or actors.is_empty():return
	decision_credit=minf(decision_credit+minf(delta,0.05)*360.0,24.0)
	var jobs=mini(int(decision_credit),12)
	decision_credit-=jobs
	for i in range(jobs):
		var actor=actors[think_cursor%actors.size()]
		think_cursor+=1
		if actor.alive:actor.think(elapsed)

func update_squads():
	for sq in squads:
		if sq.leader==null or not sq.leader.alive:
			sq.leader=null
			for a in sq.members:
				if a.alive:
					sq.leader=a
					a.leader=true
					break
	if dismounted:tactics.update(self)

func report_contact(actor,point:Vector3):
	var sq=squads[actor.squad]
	sq.contact=point
	sq.contact_age=0
	# Leaders relay a location, never an unseen target object through terrain.
	if actor.leader:
		for other in squads:
			if other.team==actor.team and other.leader!=null and other.leader.alive and other.leader.global_position.distance_to(actor.global_position)<55 and other.contact_age>1:
				other.contact=point
				other.contact_age=1

func rebuild_spatial():
	spatial.clear()
	cover_reservations.clear()
	for actor in actors:
		if not actor.alive:continue
		var c=Vector2i(floori(actor.position.x/5),floori(actor.position.z/5))
		if not spatial.has(c):spatial[c]=[]
		spatial[c].append(actor)
		if actor.has_cover:
			var reservation=Vector3i(floori(actor.cover.x/3),actor.team,floori(actor.cover.z/3))
			if not cover_reservations.has(reservation):cover_reservations[reservation]=[]
			cover_reservations[reservation].append(actor)

func separation_for(actor)->Vector3:
	var c=Vector2i(floori(actor.position.x/5),floori(actor.position.z/5))
	var result=Vector3.ZERO
	for dx in [-1,0,1]:
		for dz in [-1,0,1]:
			for other in spatial.get(c+Vector2i(dx,dz),[]):
				if other==actor or not other.alive or other.truck!=null:continue
				var v=actor.position-other.position
				v.y=0
				var d=v.length()
				var space=tactics.book.spacing.entrenched if actor.entrenched and other.entrenched else tactics.book.spacing.separation
				if d>0.01 and d<space:result+=v/d*(space-d)/space
	return result.limit_length(1.0)

func actor_alive(actor)->bool:
	if actor==null or not is_instance_valid(actor):return false
	return actor.health>0 if actor==player else actor.alive and not actor.staged

func actor_aim(actor)->Vector3:
	return actor.aim_point()

func acquire_target(actor):
	var candidates=friendlies.duplicate() if actor.team==0 else enemies.duplicate()
	if actor.team==0:candidates.append(player)
	var nearest:Array=[]
	for other in candidates:
		if not actor_alive(other):continue
		var d=actor.global_position.distance_squared_to(other.global_position)
		if d>pow(actor.spec.range,2):continue
		if actor.contact_age>20:
			var toward=(other.global_position-actor.global_position).normalized()
			if (-actor.global_basis.z).dot(toward)<-0.20 and d>400:continue
		nearest.append({"actor":other,"d":d})
	nearest.sort_custom(func(a,b):return a.d<b.d)
	for entry in nearest.slice(0,5):
		var other=entry.actor
		var ray=PhysicsRayQueryParameters3D.create(actor.eye(),actor_aim(other),1|2|4|8)
		ray.exclude=[actor.get_rid()]
		var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider==other:return other
	return null

func safe_fire_line(actor,from:Vector3,to:Vector3)->bool:
	# Check the likely dispersion cone and nearby allies' motion, not only the center ray.
	var length=from.distance_to(to)
	var axis=(to-from).normalized()
	var friends=friendlies if actor.team==1 else enemies
	for other in friends+([player] if actor.team==1 else []):
		if other==actor or not actor_alive(other):continue
		var point=actor_aim(other)+other.velocity*0.25
		var along=(point-from).dot(axis)
		if along<0.3 or along>length+2:continue
		var radius=0.65+actor.spec.spread*along*2.7
		if point.distance_to(from+axis*along)<radius:
			fire_checks_blocked+=1
			actor.fire_blocked+=1
			return false
	var direction=(to-from).normalized()
	var ray=PhysicsRayQueryParameters3D.create(from,to+direction*0.3,1|2|4|8)
	ray.exclude=[actor.get_rid()]
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():return true
	if hit.collider==player:return actor.team!=1
	if hit.collider is Actor:return hit.collider.team!=actor.team
	if hit.collider.get("truck_owner")!=null:return actor.team==0
	return false

func safe_explosive_target(actor,point:Vector3,radius:float)->bool:
	var friends=friendlies if actor.team==1 else enemies
	for other in friends:
		if not other.alive:continue
		var future=other.global_position+other.velocity*1.2
		if other.global_position.distance_to(point)<radius or future.distance_to(point)<radius:return false
	if actor.team==1 and player.health>0 and player.position.distance_to(point)<radius:return false
	return true

func can_lob(from:Vector3,to:Vector3)->bool:
	var last=from
	for i in range(1,7):
		var t=i/6.0
		var p=from.lerp(to,t)+Vector3(0,5.5*sin(t*PI),0)
		var hit=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(last,p,1))
		if not hit.is_empty() and i<6:return false
		last=p
	return true

func shoot(source,from:Vector3,aim:Vector3,spread:float,damage:float,kind:String):
	var direction=(aim-from).normalized()
	var right=direction.cross(Vector3.UP).normalized()
	var up=right.cross(direction).normalized()
	direction=(direction+right*randfn(0,spread)+up*randfn(0,spread)).normalized()
	var end=from+direction*430
	var origin=from
	var excludes:Array[RID]=[]
	excludes.assign(source.shot_exclusions() if source==player else [source.get_rid(),source.equipment.get_rid()])
	ammo_spent+=1
	for pass_index in range(4):
		var q=PhysicsRayQueryParameters3D.create(origin,end,1|2|4|8|16|32)
		q.collide_with_areas=true
		q.exclude=excludes
		var hit=get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():break
		var obj=hit.collider
		if obj.has_meta("wielder"):
			obj.get_meta("wielder").damage_weapon(damage*0.8)
			excludes.append(obj.get_rid())
			origin=hit.position+direction*0.04
			continue
		if obj.has_method("receive_hit"):
			obj.receive_hit(damage,hit.position)
			excludes.append(obj.get_rid())
			origin=hit.position+direction*0.04
			continue
		if obj==player or obj is Actor:
			var headshot=hit.position.y-obj.global_position.y>1.5
			hurt_actor(obj,damage*(1.7 if headshot else 1.0),source.global_position,"rifle")
			if obj.team==source.team:friendly_fire_hits+=1
			if source==player:hit_flash=0.18
			end=hit.position
			break
		damage_environment(hit,damage*(1.8 if kind=="m2" else 0.65),0.16)
		var armored=obj.has_method("stops_small_arms") and obj.stops_small_arms()
		if not armored and obj.has_method("damage_at") and (obj.material_kind in ["wood","cloth"] or obj.get("truck_owner")!=null) and pass_index<3:
			# Unarmored cargo panels can be penetrated. Passengers remain separate hitboxes.
			damage*=0.72
			excludes.append(obj.get_rid())
			origin=hit.position+direction*0.04
			continue
		end=hit.position
		break
	if ammo_spent%4==0 or source==player:tracer(from,end,Color("f2c88a") if source.team==1 else Color("eea473"))
	notify_projectile(from,end,source.team)
	if source!=player:sounds.at("rifle",from,-10,0.72 if kind=="m2" else randf_range(0.91,1.09))
	emit_noise(from,260,source.team,"gunshot")

func hurt_actor(actor,damage:float,source:Vector3,kind:String):
	if not actor_alive(actor):return
	if actor.truck!=null and actor.truck.has_method("passenger_damage"):
		damage=actor.truck.passenger_damage(damage,kind)
	actor.take_damage(damage,source,kind)

func notify_projectile(from:Vector3,to:Vector3,_source_team:int):
	var line=to-from
	var sq_len=line.length_squared()
	if sq_len<0.001:return
	for actor in actors:
		if not actor.alive or actor.staged:continue
		var point=actor.eye()
		var t=clampf((point-from).dot(line)/sq_len,0,1)
		if point.distance_squared_to(from+line*t)<2.25 and point.distance_squared_to(from)>4:
			actor.near_miss(from)
			near_misses+=1

func emit_noise(point:Vector3,radius:float,team:int,kind:String):
	for actor in actors:
		if actor.team!=team and actor.alive:actor.hear_noise(point,radius,team,kind)

func damage_environment(hit:Dictionary,amount:float,radius:float):
	if hit.collider.has_method("damage_at"):hit.collider.damage_at(amount,hit.position,radius)

func tracer(from:Vector3,to:Vector3,color:Color):
	if effects.size()>64:return
	var root=Node3D.new()
	add_child(root)
	var mat=Art.material(color).duplicate()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var segment=to-from
	var length=minf(segment.length(),22)
	var beam=Art.box(root,Vector3(0.018,0.018,length),to-segment.normalized()*length*0.5,mat)
	if absf(segment.normalized().dot(Vector3.UP))<0.99:beam.look_at(to)
	beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effects.append({"node":root,"time":0.055})

func impact(point:Vector3,color:Color):
	if effects.size()>64:return
	var node=Art.sphere(self,0.055,point,Art.material(color))
	node.mesh.radial_segments=6
	node.mesh.rings=3
	effects.append({"node":node,"time":0.15})

func scripted_strike(vehicle,shooter,is_lead:bool):
	# Eligibility is evaluated against the live vehicle and launcher. No teleport,
	# invulnerable performer, or replacement target is created for a missing truck.
	shooter.fausts-=1
	launch_faust(shooter,vehicle.to_global(Vector3(0,1.4,-1.8)),vehicle,true)
	if is_lead:lead_strike=true
	else:rear_strike=true
	say("Panzerfaust! Front of the arriving column!" if is_lead else "They've hit the last truck in the kill zone!",4,"SGT. HAYES")

func launch_faust(source,aim:Vector3,vehicle=null,scripted:bool=false):
	var from=source.eye()+Vector3(0,0.12,0)
	var goal=aim
	if not scripted:
		var distance=from.distance_to(aim)
		goal+=Vector3(randfn(0,distance*0.055),randfn(0,distance*0.025),randfn(0,distance*0.045))
	var node=Art.sphere(self,0.075,from,Art.material(Color("c3a970")))
	rockets.append({"node":node,"from":from,"aim":goal,"age":0.0,"duration":maxf(0.35,from.distance_to(goal)/42.0),"vehicle":vehicle,"scripted":scripted,"source":source})
	emit_noise(from,260,source.team,"explosion")

func throw_grenade(from:Vector3,direction:Vector3):
	spawn_grenade(from,direction.normalized()*15.0+Vector3(0,5.0,0),1,player,player.last_grenade_type)

func bot_grenade(actor,target:Vector3):
	var from=actor.eye()
	var flight=1.6
	var velocity=(target-from)/flight+Vector3(0,9.0*flight*0.5,0)
	spawn_grenade(from,velocity,actor.team,actor)

func spawn_grenade(from:Vector3,velocity:Vector3,team:int,source,grenade_kind:String=""):
	if grenade_kind=="":grenade_kind="m24" if team==0 else "mk2"
	var node=Node3D.new()
	add_child(node)
	node.position=from
	var green=Art.material(Color("55573b"))
	if grenade_kind=="m24":
		Art.cylinder(node,0.019,0.21,Vector3.ZERO,Art.material(Color("8c7049")),-1,8)
		Art.cylinder(node,0.04,0.07,Vector3(0,0.12,0),green,-1,10)
	else:
		var mesh=Art.sphere(node,0.052,Vector3.ZERO,green)
		mesh.scale.y=1.3
	grenades_live.append({"node":node,"velocity":velocity,"age":0.0,"fuse":randf_range(4.0,4.8),"source":source,"team":team,"kind":grenade_kind})

func step_projectiles(delta:float):
	for grenade in grenades_live.duplicate():
		grenade.age+=delta
		grenade.fuse-=delta
		grenade.velocity.y-=9.0*delta
		var from=grenade.node.position
		var to=from+grenade.velocity*delta
		var q=PhysicsRayQueryParameters3D.create(from,to,1|2|4|8)
		if grenade.age<0.3:q.exclude=[grenade.source.get_rid()]
		var hit=get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			to=hit.position+hit.normal*0.09
			grenade.velocity=grenade.velocity.bounce(hit.normal)*0.32
			if grenade.velocity.length()<0.65:grenade.velocity=Vector3.ZERO
		grenade.node.position=to
		grenade.node.rotate_x(delta*4)
		if grenade.fuse<=0:
			explode(to,5.8 if grenade.kind=="m24" else 7.0,125 if grenade.kind=="m24" else 115,grenade.source,"grenade")
			grenade_detonations+=1
			grenade.node.queue_free()
			grenades_live.erase(grenade)
	for rocket in rockets.duplicate():
		rocket.age+=delta
		var t=minf(1,rocket.age/rocket.duration)
		var goal=rocket.aim
		if rocket.scripted and is_instance_valid(rocket.vehicle):goal=rocket.vehicle.to_global(Vector3(0,1.4,-1.8))
		var pos=rocket.from.lerp(goal,t)+Vector3(0,1.1*sin(t*PI),0)
		var hit={}
		if not rocket.scripted:
			var q=PhysicsRayQueryParameters3D.create(rocket.node.position,pos,1|2|4|8)
			q.exclude=[rocket.source.get_rid()]
			hit=get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():pos=hit.position
		tracer(rocket.node.position,pos,Color("e8bc7b"))
		rocket.node.position=pos
		if t>=1 or not hit.is_empty():
			explode(pos,7.5,155,rocket.source,"rocket")
			if rocket.scripted and is_instance_valid(rocket.vehicle):
				rocket.vehicle.receive_ambush_strike(pos)
				if not ambush_targets.is_empty() and rocket.vehicle==ambush_targets[0]:lead_hit=true
				else:rear_hit=true
			rocket.node.queue_free()
			rockets.erase(rocket)

func explode(point:Vector3,radius:float,damage:float,source,kind:String="grenade"):
	for actor in actors+[player]:
		if not actor_alive(actor):continue
		var aim=actor_aim(actor)
		var distance=point.distance_to(aim)
		if distance>radius:continue
		var cover=1.0
		var ray=PhysicsRayQueryParameters3D.create(point+Vector3(0,0.1,0),aim,1)
		var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():cover=0.18 if hit.collider.get("material_kind") in ["rock","soil","masonry","sandbag"] else 0.55
		var amount=damage*pow(1.0-distance/radius,0.65)*cover
		hurt_actor(actor,amount,point,"explosion")
		if source!=null and source.team==actor.team and amount>1:friendly_fire_hits+=1
	for corpse in get_tree().get_nodes_in_group("winter_corpses"):
		corpse.blast(point,radius,damage*1.4)
	for weapon in get_tree().get_nodes_in_group("dropped_weapons"):
		var d=weapon.global_position.distance_to(point)
		if d<radius:weapon.receive_hit(damage*(1-d/radius),point)
	world.blast(point,380,radius*0.7,1.35 if kind=="rocket" else 1.15,0.38 if kind=="rocket" else 0.24)
	sounds.at("explosion",point,-2,randf_range(0.85,1.05))
	emit_noise(point,300,-1,"explosion")
	var root=Node3D.new()
	add_child(root)
	root.position=point
	var mat=Art.material(Color("c88d42")).duplicate()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var flash=Art.sphere(root,0.5,Vector3.ZERO,mat)
	var tween=create_tween()
	tween.tween_property(flash,"scale",Vector3.ONE*5,0.11)
	tween.tween_callback(flash.hide)
	flash.mesh.radial_segments=8
	flash.mesh.rings=4
	for i in range(3):
		var dust=Art.sphere(root,randf_range(0.3,0.7),Vector3.ZERO,Art.material(Color("5c5c53")))
		dust.mesh.radial_segments=6
		dust.mesh.rings=3
		var end=Vector3(randf_range(-3,3),randf_range(1,4),randf_range(-3,3))
		create_tween().tween_property(dust,"position",end,0.9)
	effects.append({"node":root,"time":1.1})

func add_wreck_fire(point:Vector3):
	var smoke=GPUParticles3D.new()
	add_child(smoke)
	smoke.position=point
	smoke.amount=35
	smoke.lifetime=6
	smoke.visibility_aabb=AABB(Vector3(-10,-2,-10),Vector3(20,28,20))
	var p=ParticleProcessMaterial.new()
	p.direction=Vector3(0.15,1,0)
	p.spread=12
	p.initial_velocity_min=2.0
	p.initial_velocity_max=3.4
	p.gravity=Vector3(0.04,0.2,0)
	p.scale_min=1.2
	p.scale_max=2.8
	var gradient=Gradient.new()
	gradient.set_color(0,Color(0.10,0.11,0.10,0.8))
	gradient.set_color(1,Color(0.20,0.22,0.23,0))
	var ramp=GradientTexture1D.new()
	ramp.gradient=gradient
	p.color_ramp=ramp
	smoke.process_material=p
	var quad=QuadMesh.new()
	quad.size=Vector2(3,3)
	var mat=StandardMaterial3D.new()
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo=true
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var texture=GradientTexture2D.new()
	var radial=Gradient.new()
	radial.set_color(0,Color(1,1,1,0.7))
	radial.set_color(1,Color(1,1,1,0))
	texture.gradient=radial
	texture.fill=GradientTexture2D.FILL_RADIAL
	texture.fill_from=Vector2(0.5,0.5)
	texture.fill_to=Vector2(1,0.5)
	mat.albedo_texture=texture
	quad.material=mat
	smoke.draw_pass_1=quad
	var light=OmniLight3D.new()
	add_child(light)
	light.position=point
	light.light_color=Color("ff943e")
	light.light_energy=2
	light.omni_range=7

func vehicle_wrecked(vehicle,_scripted:bool):
	if vehicle.engine_loop!=null:vehicle.engine_loop.stop()
	# A local wreck is a traffic obstruction. Other trucks keep trying to pass it.

func truck_dismounted(vehicle):
	if vehicle.engine_loop!=null:vehicle.engine_loop.stop()
	if not dismounted:
		dismounted=true
		dismount_at=elapsed
		say("Dismount! Left and right sections: clear the ambush hills, then work back down the road!",7,"SGT. HAYES")
		toast("LEFT / RIGHT HILLTOPS MARKED • Choose either route • J orders",7)
	tactics.assign_dismounted(self)
	tactics.update(self)

func actor_died(actor,kind:String):
	death_causes[kind]=int(death_causes.get(kind,0))+1
	if kind=="fall":
		fall_events.append({"index":actor.index,"position":str(actor.position),"surface":world.surface_height(actor.position.x,actor.position.z),"state":actor.state})
		print("FALL_DIAGNOSTIC ",JSON.stringify(fall_events.back()))
	if actor.team==1:friendly_death_causes[kind]=int(friendly_death_causes.get(kind,0))+1
	corpses.append(actor)
	var remains=Corpse.new()
	remains.game=self
	remains.soldier=actor
	remains.position=actor.position
	remains.rotation.y=actor.rotation.y
	add_child(remains)
	if not actor.dropped_broken:
		drop_weapon(actor.weapon_kind,actor.rounds,actor.weapon_health,actor.last_mount_position if actor.weapon_kind=="m2" else actor.position,actor.rotation.y,actor.weapon_kind=="m2")
		actor.rounds=0
	if actor.backup_rounds>0:
		drop_weapon("garand" if actor.team==1 else "kar98",actor.backup_rounds,100,actor.position+Vector3(0.5,0,0),actor.rotation.y)
		actor.backup_rounds=0
	if actor.team==0:germans_alive-=1
	else:allies_alive-=1
	if germans_alive<=0 and player.health>0:
		phase="victory"
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		sounds.play("victory",-10)

func interact():
	if player.truck!=null:
		if player.truck.stopped:player.truck.dismount("orders")
		else:toast("Stay seated. Weapons remain safe until the truck stops and we dismount.",3)
		return
	for bundle in get_tree().get_nodes_in_group("ammo_bundles"):
		if bundle.position.distance_to(player.position)<2.6:
			bundle.take(player)
			return
	var pickup=null
	var closest_aim=0.62
	for item in get_tree().get_nodes_in_group("dropped_weapons"):
		if item.picked_up or item.mounted or item.global_position.distance_to(player.position)>3.4:continue
		var alignment=(-player.camera.global_basis.z).dot((item.global_position-player.camera.global_position).normalized())
		if alignment>closest_aim:
			closest_aim=alignment
			pickup=item
	if pickup!=null:
		pickup.take(player)
		return
	var nearest=null
	var best=3.2
	for actor in corpses:
		var distance=player.position.distance_to(actor.position)
		if not actor.looted and distance<best:
			nearest=actor
			best=distance
	if nearest==null:
		toast("F  •  Search a fallen soldier within reach.",2)
		return
	loot(nearest)

func loot(actor)->Dictionary:
	if actor.looted:return {}
	var taken_grenades=mini(actor.grenades,maxi(0,4-player.grenades))
	var result={"rounds":0,"grenades":taken_grenades,"caliber":actor.spec.caliber}
	player.add_grenades("m24" if actor.team==0 else "mk2",taken_grenades)
	actor.grenades-=taken_grenades
	result.rounds=player.stash_ammo(actor.spec.caliber,actor.reserve,actor.weapon_kind)
	actor.reserve-=result.rounds
	if actor.backup_reserve>0:
		var n=player.stash_ammo("30-06" if actor.team==1 else "792",actor.backup_reserve,"garand" if actor.team==1 else "kar98")
		actor.backup_reserve-=n
	actor.looted=actor.reserve==0 and actor.grenades==0 and actor.backup_reserve==0
	toast("Recovered %d rounds, %d grenades. Pack %.1f / 24; grenades %d / 4."%[result.rounds,result.grenades,player.ammo_pack.space_used(),player.grenades],4)
	return result

func objective_target()->Vector3:
	if player.truck!=null:return world.road_point(Truck.END_PROGRESS)
	var best=INF
	var goal=world.anchors[6]
	for area in tactics.active_areas(self):
		var d=player.position.distance_squared_to(world.anchors[area])
		if d<best:
			best=d
			goal=world.anchors[area]
	return goal

func objective_text()->String:
	if player.truck!=null:
		if player.truck.disabled:return "Wheels hit. Await dismount orders."
		return "Stay seated. Watch the road behind."
	var cleared=0
	for i in range(8):
		if not tactics.area_alive(self,i):cleared+=1
	return "Clear both ridges • %d / 8 hilltops secured"%cleared

func toast(text:String,duration:float=3):
	toast_text=text
	toast_time=duration

func say(text:String,duration:float=5,who:String="THE KNIGHT"):
	subtitle=text
	subtitle_time=duration
	speaker=who

func defeat():
	if phase!="playing":return
	phase="defeat"
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for engine in engines:engine.stop()

func retry():
	get_tree().set_meta("ardennes_retry",true)
	get_tree().reload_current_scene()

func leave_mg():pass

func _exit_tree():
	for engine in engines:
		if is_instance_valid(engine):
			engine.stop()
			engine.stream=null

func drop_weapon(kind:String,loaded:int,condition:float,point:Vector3,yaw:float,mounted:bool=false):
	var drop=Drop.new()
	drop.game=self
	drop.kind=kind
	drop.rounds=loaded
	drop.condition=condition
	drop.mounted=mounted
	drop.position=point if mounted else world.on_ground(point+Vector3(0.7,0,0.5))+Vector3(0,0.13,0)
	drop.rotation.y=yaw+0.4
	add_child(drop)
	return drop

func swap_weapon(drop):
	if player.has_rifle:drop_weapon(player.gun_kind,player.ammo,player.rifle_health,player.position,player.rotation.y)
	var loaded=drop.rounds
	if drop.kind in ["mg34","mg42"] and loaded>50:
		var bundle=AmmoBundle.new()
		bundle.game=self
		bundle.contents=[{"kind":drop.kind,"rounds":loaded-50}]
		bundle.position=drop.position+Vector3(0.5,0.1,0)
		add_child(bundle)
		loaded=50
	player.set_firearm(drop.kind,loaded,drop.condition)
	drop.rounds=0
	toast("Carrying %s%s. Previous firearm dropped."%[Kit.DATA[drop.kind].name," — BROKEN" if drop.condition<=0 else ""],3)

func cover_occupied(actor,point:Vector3)->bool:
	var cell=Vector3i(floori(point.x/3),actor.team,floori(point.z/3))
	for x in [-1,0,1]:
		for z in [-1,0,1]:
			for other in cover_reservations.get(cell+Vector3i(x,0,z),[]):
				if other!=actor and other.alive and other.has_cover and other.cover.distance_squared_to(point)<5.5:return true
	return false

func drop_pack():
	if player.ammo_pack.containers.is_empty():return
	var bundle=AmmoBundle.new()
	bundle.game=self
	bundle.contents=player.ammo_pack.containers.duplicate(true)
	player.ammo_pack.containers.clear()
	bundle.position=world.on_ground(player.position-player.global_basis.z*1.3)+Vector3(0,0.14,0)
	add_child(bundle)
	toast("Spare ammunition placed on the ground. F picks up what fits.",3)
	hud.last_phase=""

func ambush_candidates()->Array:
	var candidates=trucks.filter(func(t):return not t.destroyed and not t.unloaded and not t.disabled and t.has_passengers() and t.progress>=540 and t.progress<=Truck.END_PROGRESS+1)
	candidates.sort_custom(func(a,b):return a.progress>b.progress)
	return candidates

func launcher_can_hit(shooter,vehicle)->bool:
	if shooter==null or not shooter.alive or shooter.fausts<=0:return false
	var point=vehicle.to_global(Vector3(0,1.4,-1.8))
	if shooter.eye().distance_to(point)>78:return false
	var q=PhysicsRayQueryParameters3D.create(shooter.eye(),point,1)
	var hit=get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider.get("truck_owner")==vehicle

func decide_ambush(candidates:Array):
	if ambush_outcome!="pending":return
	ambush_outcome="skipped"
	if candidates.is_empty():return
	var front=candidates[0]
	var front_launcher=staged_launchers[1]
	if not launcher_can_hit(front_launcher,front):return
	ambush_outcome="triggered"
	ambush_targets=[front]
	scripted_strike(front,front_launcher,true)
	if candidates.size()>1:
		var rear=candidates.back()
		if rear!=front and launcher_can_hit(staged_launchers[0],rear):
			ambush_targets.append(rear)
			rear_at=elapsed+3.5
	# One arriving truck receives only one strike. Non-arrivals are never substituted.
	dismount_at=elapsed+5.5

func step_convoy(delta:float):
	for truck in trucks:truck.tick(delta)
	if ambush_outcome=="pending":
		var candidates=ambush_candidates()
		if not candidates.is_empty() and candidates[0].arrived:decide_ambush(candidates)
		elif trucks.all(func(t):return t.destroyed or t.unloaded):decide_ambush([])
	if rear_at>0 and elapsed>=rear_at and not rear_strike:
		rear_at=-1
		if ambush_targets.size()>1:
			var rear=ambush_targets[1]
			if not rear.destroyed and rear.has_passengers() and launcher_can_hit(staged_launchers[0],rear):scripted_strike(rear,staged_launchers[0],false)
	if ambush_outcome=="triggered" and dismount_at>0 and elapsed>=dismount_at:
		for truck in trucks:
			if not truck.destroyed and not truck.unloaded and truck.progress>=540:truck.dismount("ambush")
	convoy_settled=trucks.all(func(t):return t.destroyed or t.unloaded)
	column_stopped=convoy_settled

func acquire_vehicle(actor):
	if actor.team!=0:return null
	var best=null
	var score=INF
	for truck in trucks:
		if truck.destroyed or truck.unloaded or not truck.has_passengers():continue
		var point=truck.target_point(actor)
		var distance=actor.eye().distance_squared_to(point)
		if distance>actor.spec.range*actor.spec.range:continue
		var q=PhysicsRayQueryParameters3D.create(actor.eye(),point,1)
		var hit=get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.collider.get("truck_owner")!=truck:continue
		var value=distance+maxf(0,6-(elapsed-truck.last_hit_time))*700+float((truck.index+actor.index)%4)*100
		if value<score:
			score=value
			best=truck
	return best
