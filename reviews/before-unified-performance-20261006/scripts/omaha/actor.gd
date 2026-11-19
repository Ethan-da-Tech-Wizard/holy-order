## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/omaha/actor.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
extends "res://scripts/ardennes/actor.gd"
var boat

## Role string (see class comment).
var role:String="rifleman"

## 0 or 1: which landing wave the soldier belongs to.
var wave:int=0

## x of the assault lane (see Layout.ASSAULT_LANES) the soldier follows.
var lane:float=0

## Defence sector (0..7) for German gunners.
var sector:int=0

## Bangalore torpedoes carried (engineers).
var bangalores:int=0

## Visual tube on the engineer's body; hidden when none is left.
var bangalore_model:Node3D

## Direction the mounted gun faces.
var mount_facing=Vector3(0,0,1)

## Half-angle (radians) the gun can traverse.
var mount_arc:float=PI

## Reserved for sharing contact memory; not used by the current logic.
var memory:Dictionary={}

## Game time of the last shot; used by AI awareness of who is shooting.
var last_fired:float=-999

## Reserved for time-slicing; unused.
var tick_bank:float=0

## True when a far-away soldier is drawn as a cheap level-of-detail instance.
var far_visual:bool=false

## Reserved; unused.
var wire_wait:float=0

## Position to fall back to after setting a bangalore.
var charge_retreat=Vector3.ZERO

## Time until which the soldier keeps retreating.
var retreat_until:float=0

## Reserved; unused.
var stance_pause:float=0

## Reserved; unused.
var flanking_wire:bool=false

## Reserved; unused.
var assault_stage:int=0

## Cached neighbour push vector.
var separation_cache=Vector3.ZERO

## Time the cache was computed.
var separation_at:float=-1

## Countdown between wire checks for engineers (0.15 s).
var engineer_clock:float=0

func _ready():
	super._ready()
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

## Per-tick work. Passengers only animate their legs. Boat crew, mounted and stationary soldiers handle timers, reload, floor check and firing only. Everyone else
## runs the Ardennes step_actor (slower, x0.8, in the surf), and engineers look for wire to blow.
## [param delta] physics step in seconds.
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

## After setting a bangalore: retreat about 9 m behind (offset sideways by index) for 2.4 s so the engineer is clear of the blast.
## [param now] game time.
func clear_charge(now:float):
	charge_retreat=game.world.on_ground(position+Vector3((index%2*2-1)*3,0,9))
	retreat_until=now+2.4
	state="withdraw"
	stance="stand"
	set_destination(charge_retreat)

## Decision step (see the base class). Americans: avoid grenades about to explode, throw grenades at 8-29 m, use the knife within 2.2 m, obey the rocket team, then deal with wire:
## follow a gap, wait prone while a charge burns (withdrawing if within 9 m), engineers
## set charges, others rally and recover bangalores; otherwise advance to the assault goal in bounds (one in eight pauses to fire) and charge with
## the knife when out of ammunition. Germans hold position inside their guard radius and fire, standing in trenches and going prone under pressure.
## [param now] game time.
func think(now:float):
	# - Transitions between Patrol, Alert, Combat, Flank, and Fallback states based on threat distance.
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
		var gap=game.world.nearest_gap(wire.row,lane)
		if gap!=null and (absf(gap.position.x-lane)<72 or bangalores==0):
			bound_toward(game.world.on_ground(gap.position+Vector3((index%5-2)*1.05,0,-7)),now)
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
			stance="stand"
			set_destination(game.world.on_ground(wire.position+Vector3(0,0,2.3)))
			if wire.deploy(self):clear_charge(now)
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

## Moves toward `goal` in bounds: one in ten soldiers (by index and time, 1.25 s slots) fires from cover while the rest advance.
func bound_toward(goal:Vector3,now:float):
	# Short covering bursts; nine files keep charging while one covers.
	var cover_slot=(int(now/1.25)+index)%10==0 and target!=null and position.z<0
	state="fire" if cover_slot else "advance"
	stance="prone" if cover_slot and threat_pressure>3 else ("crouch" if cover_slot else "stand")
	if not cover_slot:set_destination(goal)

## Fires like the base class, but Americans also fire an inaccurate (x1.8 spread) covering shot while advancing (not engineers); records the shot time and gives sustained MG fire visible bursts with cooling pauses.
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

## Steps off the landing craft: only after it has arrived; places the soldier on the ground at the seat position with a small forward velocity and re-enables physics.
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

## Sounds only create a search direction (last_known) and never give sight through walls; ignored for friendly noise and when contact is fresh (< 1.2 s).
func hear_noise(point:Vector3,radius:float,source_team:int,kind:String):
	if not alive or staged or source_team==team:return
	# A sound creates a search direction, never visibility through a wall.
	if global_position.distance_to(point)>radius:return
	if kind=="footstep" and global_position.distance_to(point)>radius:return
	if contact_age>1.2:
		last_known=point
		contact_age=3.0

## Ignores damage while parked in the reserve; otherwise as the base class.
func take_damage(amount:float,source:Vector3=Vector3.ZERO,kind:String="rifle"):
	if staged:return
	super.take_damage(amount,source,kind)
