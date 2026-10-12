extends "res://scripts/ardennes/actor.gd"
var boat
var role:String="rifleman"
var wave:int=0
var lane:float=0
var sector:int=0
var bangalores:int=0
var bangalore_model:Node3D
var mount_facing=Vector3(0,0,1)
var mount_arc:float=PI
var memory:Dictionary={}
var last_fired:float=-999
var tick_bank:float=0
var far_visual:bool=false
var lod_mesh:MultiMesh
var lod_slot:int=-1
var lod_hidden:bool=false
var lod_running:bool=false
var lod_transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO)
var wire_wait:float=0
var charge_retreat=Vector3.ZERO
var retreat_until:float=0
var stance_pause:float=0
var flanking_wire:bool=false
var assault_stage:int=0
var separation_cache=Vector3.ZERO
var separation_at:float=-1
var engineer_clock:float=0
var terrain_grounded:bool=false
var terrain_wall=Vector3.ZERO

func simple_motion()->bool:
	return game.get("quality")==0

func motion_grounded()->bool:
	return terrain_grounded if simple_motion() else super.motion_grounded()

func motion_wall_normal()->Vector3:
	return terrain_wall if simple_motion() else super.motion_wall_normal()

func move_actor_body(delta:float):
	if not simple_motion():
		if collision_mask!=(1|2):collision_mask=1|2
		super.move_actor_body(delta)
		return
	# Sample the same triangle heights used by the visible, deformable beach.
	# Still sweep the full posture capsule against solid cover and the player.
	# This avoids repeated general-mesh floor/snap queries for every infantryman.
	if collision_mask!=(128|2):collision_mask=128|2
	var motion=Vector3(velocity.x,0,velocity.z)*delta
	var floor_now=game.world.surface_height(position.x,position.z)
	var floor_next=game.world.surface_height(position.x+motion.x,position.z+motion.z)
	var climb=floor_next-floor_now
	if climb>motion.length()*1.11+0.04:
		motion=Vector3.ZERO
		floor_next=floor_now
	var target_y=floor_next+0.025
	if position.y<=floor_now+0.16:
		motion.y=target_y-position.y
		terrain_grounded=true
		velocity.y=0
	else:
		motion.y=maxf(velocity.y*delta,target_y-position.y)
		terrain_grounded=position.y+motion.y<=target_y+0.01
		if terrain_grounded:velocity.y=0
	terrain_wall=Vector3.ZERO
	for slide in range(3):
		if motion.length_squared()<0.0000001:break
		var hit=move_and_collide(motion)
		if hit==null:break
		var normal=hit.get_normal()
		if normal.y>0.68:
			terrain_grounded=true
			velocity.y=0
		else:terrain_wall=normal
		motion=hit.get_remainder().slide(normal)

func set_reserve(waiting:bool):
	staged=waiting
	collision_layer=0 if waiting else (4 if team==0 else 8)
	equipment.collision_layer=0 if waiting else 16
	shape.set_deferred("disabled",waiting)
	equipment.get_child(0).set_deferred("disabled",waiting)
	# Boats own their passengers' poses. Only disembarked soldiers and gunners tick.
	set_physics_process(not waiting and truck==null and role!="driver")

func _ready():
	super._ready()
	# First-person sight/reload markers belong to the player, not every AI rifle.
	for marker in ["SightLine","RearSightLine","Bolt","ReloadClip"]:gun.get_node(marker).free()
	spec=spec.duplicate()
	if team==1:assault_speed=6.2 if role!="engineer" else 6.6
	if team==0:
		if weapon_kind in ["mg42","mg34"]:
			spec.range=1000.0 if mounted else 420.0
			reserve=3500 if mounted else 750
			# Preserve a beaten zone at the shorter engagement distance.
			spec.spread=0.050 if mounted else 0.027
		elif weapon_kind in ["kar98","g43"]:spec.range=360.0
	else:
		if weapon_kind in ["garand","bar"]:spec.range=420.0
		if role=="driver":health=25000
	if bangalores>0:
		bangalore_model=Node3D.new()
		model.root.add_child(bangalore_model)
		var tube=Art.cylinder(bangalore_model,0.045,1.85,Vector3(-0.27,1.15,0.27),Art.material(Color("807448")),-1,8)
		tube.rotation.z=-0.20
	if weapon_kind=="flamethrower":
		for x in [-0.13,0.13]:
			Art.cylinder(model.root,0.13,0.66,Vector3(x,1.20,0.34),Art.material(Color("5c6240")),-1,10)
		Art.segment(model.root,Vector3(0.15,0.98,0.4),Vector3(0.35,0.81,-0.15),0.028,Art.material(Color("1a2420")))

func _physics_process(delta):
	if not alive or staged or game.phase!="playing":return
	if truck!=null:
		if truck.arrived:
			move_clock+=delta*5
			model.legs[0].rotation.x=sin(move_clock)*0.4
			model.legs[1].rotation.x=-model.legs[0].rotation.x
		return
	if boat!=null or mounted:
		contact_age+=delta
		shot_clock=maxf(-delta,shot_clock-delta)
		burst_pause=maxf(0,burst_pause-delta)
		suppression=maxf(0,suppression-delta)
		threat_pressure=maxf(0,threat_pressure-delta)
		grenade_clock=maxf(0,grenade_clock-delta)
		if reload_clock>0:
			reload_clock=maxf(0,reload_clock-delta)
			if reload_clock==0:
				var load_count=mini(spec.capacity-rounds,reserve)
				rounds+=load_count
				reserve-=load_count
		if role!="driver":
			if target!=null or vehicle_target!=null:
				var facing=last_known-position
				rotation.y=lerp_angle(rotation.y,atan2(-facing.x,-facing.z),delta*5)
			try_fire()
		return
	# CharacterBody3D.move_and_slide uses the engine physics delta internally.
	# Skipping its ticks slows distant troops; stagger decisions and rendering only.
	var normal_speed=assault_speed
	if team==1 and global_position.z>0:assault_speed*=0.8
	super.step_actor(delta)
	assault_speed=normal_speed
	engineer_clock-=delta
	if team==1 and bangalores>0 and engineer_clock<=0:
		engineer_clock=0.15
		var wire=game.world.blocking_wire(position,lane)
		if wire!=null and not wire.broken and wire.deploy(self):clear_charge(game.elapsed)
	if bangalore_model!=null:bangalore_model.visible=bangalores>0

func clear_charge(now:float):
	charge_retreat=game.world.on_ground(position+Vector3((index%2*2-1)*3,0,9))
	retreat_until=now+2.4
	state="withdraw"
	stance="stand"
	set_destination(charge_retreat)

func think(now:float):
	if not alive or staged or truck!=null or role=="driver":return
	decision_count+=1
	if bangalore_model!=null:bangalore_model.visible=bangalores>0
	var seen=game.acquire_target(self)
	vehicle_target=null
	if team==0:
		var craft=game.acquire_vehicle(self)
		if craft!=null and (seen==null or position.distance_squared_to(craft.target_point(self))<position.distance_squared_to(seen.position)):vehicle_target=craft
	if vehicle_target!=null:
		target=null
		last_known=vehicle_target.target_point(self)
		contact_age=0
	elif seen!=null:
		if target!=seen:reaction=now+randf_range(0.18,0.48)
		target=seen
		last_known=game.actor_aim(seen)
		contact_age=0
		detected=true
		game.report_contact(self,last_known)
	else:target=null
	if rounds==0 and reserve>0 and reload_clock==0:reload_clock=spec.reload
	if mounted:
		state="mounted"
		stance="stand"
		# Mounted guns stay in their fortified arcs. No roaming beach gunner swarm.
		return
	if grenade_throw_time>0:return
	for grenade in game.grenades_live:
		if grenade.fuse>2.2:continue
		var away=position-grenade.node.position
		away.y=0
		if away.length()<8.2:
			if away.length()<0.1:away=Vector3(0,0,1)
			state="withdraw"
			stance="stand"
			set_destination(limit_goal(game.world.on_ground(position+away.normalized()*9)))
			return
	if target!=null:
		var d=eye().distance_to(last_known)
		if grenades>0 and grenade_clock==0 and d>8 and d<29:
			if game.safe_explosive_target(self,last_known,6) and game.can_lob(eye(),last_known):
				begin_grenade(last_known)
				return
		if d<2.2 and knife_clock<=0:
			game.hurt_actor(target,35,position,"melee")
			knife_clock=1.1
	if team==0:
		order="hold"
		if flat_distance(position,home)>guard_radius-1:
			state="relocate"
			set_destination(home)
		else:
			state="fire" if target!=null else "watch"
			stance="stand" if entrenched else ("prone" if threat_pressure>3 else "crouch")
		return
	order="assault"
	if retreat_until>now:
		state="withdraw"
		stance="stand"
		set_destination(charge_retreat)
		return
	var wire=game.world.blocking_wire(position,lane)
	if wire!=null:
		# Every boat owns a local file. Engineers open its next belt before looking
		# sideways; followers use that opening or a neighbouring file's nearby gap.
		if wire.broken:
			bound_toward(game.world.on_ground(wire.position+Vector3((index%5-2)*1.05,0,-7)),now)
			return
		if wire.charge:
			state="fire" if target!=null else "cover"
			stance="prone"
			if position.distance_to(wire.position)<9:
				state="withdraw"
				stance="stand"
				set_destination(game.world.on_ground(wire.position+Vector3((index%5-2)*2,0,10)))
			return
		if bangalores>0:
			state="advance"
			stance="stand"
			set_destination(game.world.on_ground(wire.position+Vector3(0,0,2.3)))
			if wire.deploy(self):clear_charge(now)
			return
		var gap=game.world.nearest_gap(wire.row,lane,18.0)
		if gap!=null:
			bound_toward(game.world.on_ground(gap.position+Vector3((index%5-2)*1.05,0,-7)),now)
			return
		if position.z>wire.position.z+14:
			bound_toward(game.world.on_ground(Vector3(lane+(index%9-4)*1.4,0,wire.position.z+11)),now)
			return
		if game.recover_bangalore(self):return
		# Rally behind the engineers. Never scatter to the distant wire ends.
		state="fire" if target!=null else "cover"
		stance="prone"
		return
	var goal=game.assault_goal(self)
	var moving=(int(now/1.5)+index)%8!=0 or target==null or weapon_kind=="flamethrower"
	state="advance" if moving else "fire"
	stance="crouch" if not moving and threat_pressure>2 else "stand"
	if moving:set_destination(goal)
	if rounds+reserve==0 and target!=null:
		state="melee"
		set_destination(last_known)

func bound_toward(goal:Vector3,now:float):
	# Short covering bursts; nine files keep charging while one covers.
	var cover_slot=(int(now/1.25)+index)%10==0 and target!=null and position.z<0
	state="fire" if cover_slot else "advance"
	stance="prone" if cover_slot and threat_pressure>3 else ("crouch" if cover_slot else "stand")
	if not cover_slot:set_destination(goal)

func try_fire():
	if role=="driver" or staged:return
	var previous=shots
	var previous_state=state
	var previous_spread=spec.spread
	# Assault rifles can fire an inaccurate covering shot while their file moves.
	# Engineers keep charging; collision/line-of-fire checks still protect allies.
	if team==1 and state=="advance" and target!=null and bangalores==0:
		state="fire"
		spec.spread*=1.8
	super.try_fire()
	state=previous_state
	spec.spread=previous_spread
	if shots>previous:
		last_fired=game.elapsed
		# Sustained defensive belts with visible traversing bursts and cooling pauses.
		if mounted and weapon_kind in ["mg42","m1919"] and burst_pause>0:
			burst_pause=randf_range(0.25,0.55)
			burst_left=randi_range(9,18)

func dismount():
	if truck==null or not truck.arrived:return
	var craft=truck
	var p=craft.seat_transform(seat).origin
	truck=null
	boat=null
	staged=false
	position=game.world.on_ground(p)+Vector3(0,0.15,0)
	collision_layer=8
	home=position
	state="advance"
	stance="stand"
	posture_revision=-1
	for leg in model.legs:leg.rotation.x=0
	shape.shape.height=1.76
	shape.position.y=0.88
	velocity=Vector3(0,0,-2)
	set_physics_process(true)

func hear_noise(point:Vector3,radius:float,source_team:int,kind:String):
	if not alive or staged or source_team==team:return
	# A sound creates a search direction, never visibility through a wall.
	if global_position.distance_to(point)>radius:return
	if kind=="footstep" and global_position.distance_to(point)>radius:return
	if contact_age>1.2:
		last_known=point
		contact_age=3.0

func take_damage(amount:float,source:Vector3=Vector3.ZERO,kind:String="rifle"):
	if staged:return
	super.take_damage(amount,source,kind)
