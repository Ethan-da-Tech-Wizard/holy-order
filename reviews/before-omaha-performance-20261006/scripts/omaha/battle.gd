extends "res://scripts/ardennes/battle.gd"
const Coast=preload("res://scripts/omaha/world.gd")
const LandingPlayer=preload("res://scripts/omaha/player.gd")
const Soldier=preload("res://scripts/omaha/actor.gd")
const Boat=preload("res://scripts/omaha/boat.gd")
const LandingHUD=preload("res://scripts/omaha/interface.gd")
const CoastalAudio=preload("res://scripts/omaha/audio.gd")
const Armor=preload("res://scripts/omaha/armor.gd")
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
	actors=friendlies+enemies
	allies_alive=599
	germans_alive=100
	rebuild_spatial()
	build_lod_batches()
	build_flashes()
	var canvas=CanvasLayer.new()
	add_child(canvas)
	hud=LandingHUD.new()
	hud.game=self
	canvas.add_child(hud)
	world.world_camera.position=Vector3(-33,5.5,417)
	world.world_camera.look_at(Vector3(-72,3,-120))
	world.world_camera.current=true
	player.camera.current=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_title("Holy Order — Omaha / The Longest Shore")
	apply_quality()
	if get_tree().has_meta("omaha_retry"):
		get_tree().remove_meta("omaha_retry")
		begin()
	if "--battle-preview" in OS.get_cmdline_user_args():begin()

func add_soldier(team_id:int,kind:String,p:Vector3,squad_id:int):
	var a=Soldier.new()
	a.game=self
	a.team=team_id
	a.weapon_kind=kind
	a.index=friendlies.size() if team_id==1 else 600+enemies.size()
	a.squad=squad_id
	a.position=p
	return a

func make_landing_force():
	# EXACT strength: 20 * (27 assault passengers + 2 gunners + 1 driver) = 600.
	# The player replaces one passenger. Both waves contain 300 people, including crew.
	for wave in range(2):
		for lane_id in range(10):
			var craft=Boat.new()
			craft.game=self
			craft.index=boats.size()
			craft.wave=wave
			craft.lane_x=(lane_id-4.5)*140
			add_child(craft)
			boats.append(craft)
			trucks.append(craft) # Shared inspection / inventory API retains its vehicle slot.
			var sq=new_squad(1,"assault","aggressive",craft.position)
			for seat_id in range(27):
				if wave==0 and lane_id==4 and seat_id==25:
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
				a.sector=clampi(roundi((a.lane+665)/190),0,7)
				a.seat=seat_id
				a.truck=craft
				a.bangalores=1 if seat_id==7 else 0
				a.role="engineer" if a.bangalores>0 else "rifleman"
				a.staged=wave==1
				a.order="assault"
				a.leader=seat_id==0
				add_child(a)
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
	var sq=new_squad(0,"hold","cautious",Vector3(0,45,-600))
	for i in range(12):
		var a=add_soldier(0,["g43","kar98","mp40"][i%3],world.town_points[mini(i*3,world.town_points.size()-1)],sq)
		a.sector=clampi(roundi((a.position.x+665)/190),0,7)
		a.entrenched=true
		a.role="town_guard"
		a.guard_radius=14
		a.rotation.y=PI
		add_child(a)
		enemies.append(a)
		squads[sq].members.append(a)

func begin():
	phase="playing"
	player.camera.current=true
	world.world_camera.current=false
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for engine in engines:engine.play()
	say("Stay in line. Keep your heads below the gunwales. Follow the file when that ramp drops.",7,"COXSWAIN")
	toast("FIRST WAVE • HOLD FAST • 2 BROWNINGS PER CRAFT",6)

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

func _unhandled_input(event):
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and event.keycode==KEY_F6:
		quality=(quality+1)%3
		apply_quality()
		toast("GRAPHICS: "+["PERFORMANCE","BALANCED","QUALITY"][quality],3)

func apply_quality():
	get_viewport().scaling_3d_scale=[0.75,0.85,1.0][quality]
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED if quality<2 else Viewport.MSAA_2X
	get_viewport().screen_space_aa=Viewport.SCREEN_SPACE_AA_FXAA
	if world!=null:
		for node in world.get_children():
			if node is DirectionalLight3D:node.directional_shadow_max_distance=[60,90,120][quality]

func step_battle(delta):
	if phase!="playing":return
	elapsed+=delta
	sim_ticks+=1
	for craft in boats:
		craft.tick(delta)
		if craft.wave==1 and not craft.departed and elapsed>=Boat.SECOND_WAVE_DELAY:
			for a in craft.occupants+craft.crew:a.staged=false
	for wire in world.wires:wire.tick(delta)
	sense_timer-=delta
	if sense_timer<=0:
		sense_timer=0.25
		rebuild_spatial()
	# 100 defenders are refreshed at ~2.4 Hz; attackers at ~1 Hz.
	for i in range(4):
		var a=enemies[defender_cursor%enemies.size()]
		defender_cursor+=1
		if a.alive:a.think(elapsed)
	for i in range(10):
		var a=friendlies[attacker_cursor%friendlies.size()]
		attacker_cursor+=1
		if a.alive:a.think(elapsed)
	squad_timer-=delta
	if squad_timer<=0:
		squad_timer=1
		update_squads()
		update_objectives(1)
	step_projectiles(delta)
	update_flashes()
	for effect in effects.duplicate():
		effect.time-=delta
		if effect.time<=0:
			effect.node.queue_free()
			effects.erase(effect)
	lod_timer-=delta
	if lod_timer<=0:
		lod_timer=0.15
		update_lod()
	mine_timer-=delta
	if mine_timer<=0:
		mine_timer=0.3
		check_mines()

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
	var c=Vector2i(floori(actor.position.x/5),floori(actor.position.z/5))
	var result=Vector3.ZERO
	for dx in [-1,0,1]:
		for dz in [-1,0,1]:
			for other in spatial.get(c+Vector2i(dx,dz),[]):
				if other==actor or not other.alive or other.truck!=null or other.boat!=null:continue
				var offset=actor.position-other.position
				offset.y=0
				var d=offset.length()
				if d>0.01 and d<1.05:result+=offset/d*(1.05-d)
	return result.limit_length(1)

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
	var candidates=friendlies if observer.team==0 else enemies
	var nearest=[]
	for other in candidates:
		if can_detect(observer,other):nearest.append({"actor":other,"d":observer.position.distance_squared_to(other.position)})
	if observer.team==0 and can_detect(observer,player):nearest.append({"actor":player,"d":observer.position.distance_squared_to(player.position)})
	nearest.sort_custom(func(a,b):return a.d<b.d)
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
	excludes.assign(source.shot_exclusions() if source==player else [source.get_rid(),source.equipment.get_rid()])
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

func notify_projectile(from:Vector3,to:Vector3,source_team:int):
	var line=to-from
	var sq=line.length_squared()
	if sq<0.001:return
	# Coarse spatial sampling avoids scanning 700 troops for every automatic round.
	var visited:Dictionary={}
	var steps=mini(120,maxi(1,ceili(line.length()/5.0)))
	for i in range(steps+1):
		var p=from.lerp(to,float(i)/steps)
		var cell=Vector2i(floori(p.x/5),floori(p.z/5))
		if visited.has(cell):continue
		visited[cell]=true
		for dx in [-1,0,1]:
			for dz in [-1,0,1]:
				for actor in spatial.get(cell+Vector2i(dx,dz),[]):
					if actor.team==source_team or actor.staged:continue
					var point=actor.eye()
					var t=clampf((point-from).dot(line)/sq,0,1)
					if point.distance_squared_to(from+line*t)<3.0:
						actor.near_miss(from)
						near_misses+=1

func emit_noise(point:Vector3,radius:float,team:int,kind:String):
	if kind=="gunshot":return # Perception uses each actual shooter's last-fired timestamp.
	for actor in actors:
		if actor.alive and actor.team!=team and actor.position.distance_squared_to(point)<radius*radius:actor.hear_noise(point,radius,team,kind)

func tracer(from:Vector3,to:Vector3,color:Color):
	if effects.size()>120:return
	var root=Node3D.new()
	add_child(root)
	var mat=Art.material(color).duplicate()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var start=from
	var end=from.lerp(to,0.96)
	var mesh=Art.segment(root,start,start+(end-start).normalized()*minf(16,from.distance_to(to)),0.025,mat)
	mesh.mesh.radial_segments=4
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var duration=clampf(from.distance_to(to)/800,0.055,0.45)
	create_tween().tween_property(root,"position",end-start,duration)
	effects.append({"node":root,"time":duration})

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

func recover_bangalore(actor):
	if actor.bangalores>0:return
	for fallen in corpses:
		if fallen.team==1 and fallen.bangalores>0 and fallen.position.distance_squared_to(actor.position)<64:
			actor.bangalores=fallen.bangalores
			fallen.bangalores=0
			return

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
			if actor.position.z> -482:return world.on_ground(Vector3(center.x+(actor.index%5-2)*3,0,-493))
			distance=INF
			for e in enemies:
				if not e.alive:continue
				var d=actor.position.distance_squared_to(e.position)
				if d<distance:
					distance=d
					nearest=e
			if nearest!=null:return world.on_ground(nearest.position+Vector3(0,0,6))
			return world.on_ground(Vector3((actor.index%9-4)*3,0,-720))
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
		if a.alive and a.truck==null and a.boat==null and a.position.z< -490:attackers+=1
	if player.truck==null and player.position.z< -490:attackers+=1
	for e in enemies:
		if e.alive and e.role=="town_guard":guards+=1
	if attackers>=1 and guards==0:town_control=minf(12,town_control+delta)
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
		Art.box(root,Vector3(0.065,0.09,0.78),Vector3(0.06,1.25,-0.38),dark)
		Art.box(root,Vector3(0.05,0.11,0.29),Vector3(0.06,1.22,0.1),Art.material(Color("544332")))
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
		batch.multimesh.instance_count=600
		batch.multimesh.visible_instance_count=0
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
		lod_batches[key]=batch
	update_lod()

func update_lod():
	var counts:Dictionary={}
	var viewpoint=player.position if phase!="title" else world.world_camera.position
	for actor in actors:
		if not actor.alive:continue
		if actor.boat!=null and actor.boat.departed:continue
		var key=str(actor.team)+"/"+actor.weapon_kind
		actor.far_visual=actor.position.distance_squared_to(viewpoint)>pow([65,90,120][quality],2)
		actor.model.root.visible=not actor.far_visual
		if actor.far_visual:
			var i=int(counts.get(key,0))
			var xf=actor.global_transform
			if actor.truck==null and actor.boat==null:xf=actor.global_transform*actor.model.root.transform
			lod_batches[key].multimesh.set_instance_transform(i,xf)
			lod_batches[key].multimesh.set_instance_custom_data(i,Color(float(actor.index%19)/19.0,1.0 if actor.velocity.length_squared()>0.2 else 0.0,0,1))
			counts[key]=i+1
	for key in lod_batches:lod_batches[key].multimesh.visible_instance_count=counts.get(key,0)

func actor_died(actor,kind:String):
	# Keep the established persistent bodies, loot, damaged weapons and finite inventory.
	super.actor_died(actor,kind)
	if phase=="victory":phase="playing" # Mission ends at secured exits / town, not a kill counter.
	# Bodies remain. Their visual parts use distance culling to limit late-battle draw calls.
	for child in get_children():
		if child is Corpse and child.soldier==actor:
			for part in child.parts:
				for visual in part.get_children():
					if visual is GeometryInstance3D:
						visual.visibility_range_end=220
						visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			break

func interact():
	if player.truck!=null:
		player.truck.dismount()
		return
	super.interact()

func objective_target()->Vector3:
	if player.truck!=null:return world.on_ground(Vector3(player.truck.lane_x,0,-214))
	if secured>=3:
		var guard=null
		var distance=INF
		for e in enemies:
			if not e.alive or e.role!="town_guard":continue
			var d=player.position.distance_squared_to(e.position)
			if d<distance:
				distance=d
				guard=e
		return guard.position if guard!=null else world.on_ground(Vector3(0,0,-720))
	var wire=world.blocking_wire(player.position,player.position.x)
	if wire!=null:
		var gap=world.nearest_gap(wire.row,player.position.x)
		return gap.position if gap!=null else wire.position
	var best=INF
	var goal=world.on_ground(Vector3(0,0,-720))
	for i in range(8):
		if capture[i]>=10:continue
		var d=player.position.distance_squared_to(world.anchors[i])
		if d<best:
			best=d
			goal=world.bunkers[i].rear
	return goal

func objective_text()->String:
	if player.truck!=null:return "Follow the file when the ramp drops" if player.truck.arrived else "Stay low • first wave inbound"
	if player.position.z> -326:return "Reach the seawall • follow a wire breach"
	return "Take bluff exits %d / 3 • clear the village"%mini(secured,3)

func retry():
	get_tree().set_meta("omaha_retry",true)
	get_tree().change_scene_to_file("res://scenes/omaha.tscn")

func _exit_tree():
	# Scene-specific quality settings must not leak into the winter/desert missions.
	get_viewport().scaling_3d_scale=1.0
	get_viewport().msaa_3d=ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d",2)
	get_viewport().screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	super._exit_tree()
