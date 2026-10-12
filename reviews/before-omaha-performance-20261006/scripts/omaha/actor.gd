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
var wire_wait:float=0
var charge_retreat=Vector3.ZERO
var retreat_until:float=0
var stance_pause:float=0
var flanking_wire:bool=false
var assault_stage:int=0

func _ready():
	super._ready()
	spec=spec.duplicate()
	if team==0:
		if weapon_kind in ["mg42","mg34"]:
			spec.range=1000.0 if mounted else 420.0
			reserve=3500 if mounted else 750
			spec.spread=0.024 if mounted else 0.027
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
	if not alive or game.phase!="playing":return
	if truck!=null:
		if truck.arrived:
			move_clock+=delta*5
			model.legs[0].rotation.x=sin(move_clock)*0.4
			model.legs[1].rotation.x=-model.legs[0].rotation.x
		return
	if boat!=null or mounted:
		contact_age+=delta
		shot_clock=maxf(0,shot_clock-delta)
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
	super.step_actor(delta)
	if global_position.z>0:
		velocity.x*=0.75
		velocity.z*=0.75
	if bangalore_model!=null:bangalore_model.visible=bangalores>0

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
		if flanking_wire:
			state="advance"
			stance="stand"
			var edge=800.0*signf(lane if absf(lane)>1 else 1.0)
			set_destination(game.world.on_ground(Vector3(edge,0,position.z if absf(position.x)<789 else -339)))
			return
		var gap=game.world.nearest_gap(wire.row,position.x)
		if gap!=null:
			bound_toward(game.world.on_ground(gap.position+Vector3((index%3-1)*1.0,0,-5)),now)
			return
		if wire.charge:
			state="fire" if target!=null else "cover"
			stance="prone"
			if position.distance_to(wire.position)<9:
				state="withdraw"
				set_destination(game.world.on_ground(wire.position+Vector3((index%5-2)*2,0,10)))
			return
		if bangalores>0:
			state="advance"
			stance="crouch" if threat_pressure>4 and int(now+index)%7==0 else "stand"
			set_destination(game.world.on_ground(wire.position+Vector3(0,0,2.3)))
			if wire.deploy(self):
				charge_retreat=game.world.on_ground(position+Vector3((index%2*2-1)*5,0,8))
				retreat_until=now+5.5
			return
		if position.z>wire.position.z+14:
			bound_toward(game.world.on_ground(Vector3(lane+(index%9-4)*2,0,wire.position.z+11)),now)
			return
		game.recover_bangalore(self)
		# Wait under cover for the engineers; some squads can outflank the wire end.
		if now>game.first_landing_at+110 and (index%7==0 or now>game.first_landing_at+230):
			flanking_wire=true
			state="advance"
			stance="crouch"
			var end=800.0*signf(lane if absf(lane)>1 else 1.0)
			set_destination(game.world.on_ground(Vector3(end,0,wire.position.z+(8 if absf(position.x)<786 else -8))))
		else:
			state="fire" if target!=null else "cover"
			stance="prone"
		return
	flanking_wire=false
	var goal=game.assault_goal(self)
	var moving=(int(now/3.0)+index)%4!=0 or target==null or weapon_kind=="flamethrower"
	state="advance" if moving else "fire"
	stance="crouch" if not moving and threat_pressure>2 else "stand"
	if moving:set_destination(goal)
	if rounds+reserve==0 and target!=null:
		state="melee"
		set_destination(last_known)

func bound_toward(goal:Vector3,now:float):
	# Suppression creates a short covered pause, then another bound. It must not
	# trap a whole assault wave in an indefinitely refreshed exposed prone state.
	var cover_slot=(int(now/2.4)+index)%4==0 and target!=null and position.z<0
	state="fire" if cover_slot else "advance"
	stance="prone" if cover_slot and threat_pressure>3 else ("crouch" if cover_slot else "stand")
	if not cover_slot:set_destination(goal)

func try_fire():
	if role=="driver" or staged:return
	var previous=shots
	super.try_fire()
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
