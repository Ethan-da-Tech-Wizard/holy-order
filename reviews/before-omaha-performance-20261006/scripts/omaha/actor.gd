# ==============================================================================
# Program: actor.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for actor.gd.
# ==============================================================================
## Omaha soldier: the Ardennes actor with beach-specific roles, orders and engineer behaviour.
##
## Team 1 (Americans) land from boats, bound across the beach, breach the wire with Bangalore
## torpedoes and assault the strongpoints; team 0 (Germans) hold fortified positions, usually
## on mounted machine guns. This script extends ardennes/actor.gd and overrides setup, the
## physics step, decision making (`think`), firing, dismounting, hearing and damage. `think()` is
## called by the battle controller at a staggered rate, not every frame.
extends "res://scripts/ardennes/actor.gd"

# Boat the soldier is aboard (a Boat node) or null; `truck` holds the same boat while seated.
var boat

# Job: "rifleman", "engineer", "gunner" (boat Browning), "driver" (coxswain), etc.
var role:String="rifleman"

# Landing wave 0 or 1.
var wave:int=0

# x coordinate of the assault lane the soldier follows across the beach.
var lane:float=0

# Index of the defence sector (0..7) this soldier belongs to.
var sector:int=0

# Bangalore torpedoes carried (only engineers have any) and the pipe model strapped to the back.
var bangalores:int=0
var bangalore_model:Node3D

# Fixed gun mount direction and half-arc (radians) for mounted gunners.
var mount_facing=Vector3(0,0,1)
var mount_arc:float=PI

# Perception memory (target id -> info), used by the controller's detection code.
var memory:Dictionary={}

# Time of the last shot, used so firing gives away a hidden player or soldier.
var last_fired:float=-999

# Spare time bank for staggered updates (not read or written in this script).
var tick_bank:float=0

# True for distant soldiers drawn in a cheaper way by the battle controller.
var far_visual:bool=false

# Seconds spent waiting at the wire (not read or written in this script).
var wire_wait:float=0

# Where to retreat after planting a charge, and until when (mission seconds).
var charge_retreat=Vector3.ZERO
var retreat_until:float=0

# Seconds to hold a stance before changing it (not read or written in this script).
var stance_pause:float=0

# True while the soldier is walking to a flank gap instead of the nearest breach.
var flanking_wire:bool=false

# Progress through the strongpoint assault route (see tests/omaha_routes.gd): 0 approach ... 4 inside, 5 rear exit, 6 sweep.
var assault_stage:int=0

## Set up weapon ranges, speed and extra visuals once the base actor is ready.
func _ready():
	super._ready()
	# The spec dictionary is shared by weapon kind; copy it so per-soldier range and spread changes do not leak.
	spec=spec.duplicate()
	if team==0:
		# German machine guns: mounted guns reach 1000 m with a huge belt and tight cone, portable ones 420 m with 750 rounds.
		if weapon_kind in ["mg42","mg34"]:
			spec.range=1000.0 if mounted else 420.0
			reserve=3500 if mounted else 750
			spec.spread=0.024 if mounted else 0.027
		# German bolt rifles reach 360 m; American Garands and BARs 420 m.
		elif weapon_kind in ["kar98","g43"]:spec.range=360.0
	else:
		if weapon_kind in ["garand","bar"]:spec.range=420.0
		# Boat drivers have large health so they survive the approach.
		if role=="driver":health=25000
	# Engineers carry a visible Bangalore pipe on the back.
	if bangalores>0:
		bangalore_model=Node3D.new()
		model.root.add_child(bangalore_model)
		var tube=Art.cylinder(bangalore_model,0.045,1.85,Vector3(-0.27,1.15,0.27),Art.material(Color("807448")),-1,8)
		tube.rotation.z=-0.20
	# Flamethrower soldiers get two fuel tanks and a hose.
	if weapon_kind=="flamethrower":
		for x in [-0.13,0.13]:
			Art.cylinder(model.root,0.13,0.66,Vector3(x,1.20,0.34),Art.material(Color("5c6240")),-1,10)
		Art.segment(model.root,Vector3(0.15,0.98,0.4),Vector3(0.35,0.81,-0.15),0.028,Art.material(Color("1a2420")))

## Per-tick behaviour: ride in a boat, shoot from a mount or move on foot.
## @param delta Seconds.
func _physics_process(delta):
	if not alive or game.phase!="playing":return
	# Seated in a landing craft: only march in place once the craft has arrived.
	if truck!=null:
		if truck.arrived:
			move_clock+=delta*5
			model.legs[0].rotation.x=sin(move_clock)*0.4
			model.legs[1].rotation.x=-model.legs[0].rotation.x
		return
	# Aboard a boat or on a gun mount: keep the timers running by hand, turn toward the target and fire; no movement.
	if boat!=null or mounted:
		contact_age+=delta
		shot_clock=maxf(0,shot_clock-delta)
		burst_pause=maxf(0,burst_pause-delta)
		suppression=maxf(0,suppression-delta)
		threat_pressure=maxf(0,threat_pressure-delta)
		grenade_clock=maxf(0,grenade_clock-delta)
		# Reload when the timer ends.
		if reload_clock>0:
			reload_clock=maxf(0,reload_clock-delta)
			if reload_clock==0:
				var load_count=mini(spec.capacity-rounds,reserve)
				rounds+=load_count
				reserve-=load_count
		# Coxswains never shoot or turn.
		if role!="driver":
			if target!=null or vehicle_target!=null:
				var facing=last_known-position
				rotation.y=lerp_angle(rotation.y,atan2(-facing.x,-facing.z),delta*5)
			try_fire()
		return
	# CharacterBody3D.move_and_slide uses the engine physics delta internally.
	# Skipping its ticks slows distant troops; stagger decisions and rendering only.
	# Run the base movement step, then restore the speed.
	# CharacterBody3D.move_and_slide uses the engine physics delta internally.
	# Skipping its ticks slows distant troops; stagger decisions and rendering only.
	super.step_actor(delta)
	if global_position.z>0:
		velocity.x*=0.75
		velocity.z*=0.75
	if bangalore_model!=null:bangalore_model.visible=bangalores>0

## Decide what to do (target, stance, destination); called at a staggered rate.
## @param now Mission time in seconds.
func think(now:float):
	# Only active soldiers on foot; coxswains never decide.
	if not alive or staged or truck!=null or role=="driver":return
	decision_count+=1
	if bangalore_model!=null:bangalore_model.visible=bangalores>0
	# Pick the best target: a boat for the Germans (when closer than any soldier), otherwise the nearest visible enemy soldier.
	var seen=game.acquire_target(self)
	vehicle_target=null
	if team==0:
		var craft=game.acquire_vehicle(self)
		if craft!=null and (seen==null or position.distance_squared_to(craft.target_point(self))<position.distance_squared_to(seen.position)):vehicle_target=craft
	if vehicle_target!=null:
		target=null
		last_known=vehicle_target.target_point(self)
		contact_age=0
	# Reaction delay of 0.18-0.48 s when the target changes, so soldiers do not snap to new targets.
	elif seen!=null:
		if target!=seen:reaction=now+randf_range(0.18,0.48)
		target=seen
		last_known=game.actor_aim(seen)
		contact_age=0
		detected=true
		# Share the contact so nearby squadmates react.
		game.report_contact(self,last_known)
	else:target=null
	# Start a reload when empty and spare rounds exist.
	if rounds==0 and reserve>0 and reload_clock==0:reload_clock=spec.reload
	# Mounted gunners stay put in their arcs.
	if mounted:
		state="mounted"
		stance="stand"
		# Mounted guns stay in their fortified arcs. No roaming beach gunner swarm.
		# Mounted guns stay in their fortified arcs. No roaming beach gunner swarm.
		return
	# Wait while throwing a grenade.
	if grenade_throw_time>0:return
	# Flee from live grenades that are about to go off (more than 2.2 s of fuse is ignored).
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
	# Throw a grenade at a target 8-29 m away if it is safe for friends and a lob is possible; knife anything within 2.2 m.
	if target!=null:
		var d=eye().distance_to(last_known)
		if grenades>0 and grenade_clock==0 and d>8 and d<29:
			if game.safe_explosive_target(self,last_known,6) and game.can_lob(eye(),last_known):
				begin_grenade(last_known)
				return
		if d<2.2 and knife_clock<=0:
			game.hurt_actor(target,35,position,"melee")
			knife_clock=1.1
	# Germans hold: return to the home position if too far from it, otherwise fire or watch with a stance chosen from the threat.
	if team==0:
		order="hold"
		if flat_distance(position,home)>guard_radius-1:
			state="relocate"
			set_destination(home)
		else:
			state="fire" if target!=null else "watch"
			stance="stand" if entrenched else ("prone" if threat_pressure>3 else "crouch")
		return
	# Americans assault: first finish any post-charge retreat.
	order="assault"
	if retreat_until>now:
		state="withdraw"
		stance="stand"
		set_destination(charge_retreat)
		return
	# Wire in the lane: use a nearby gap (within 72 m of the lane, or any if there are no charges), wait out a burning charge, or place a charge when carrying one.
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
		# No charge available: cross to a staging point just short of the wire, then try to recover a charge from a fallen engineer.
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
	# Past the wire: follow the route supplied by the controller. About one in eight soldiers pauses to fire at any time, except flamethrowers who keep moving.
	var goal=game.assault_goal(self)
	var moving=(int(now/3.0)+index)%4!=0 or target==null or weapon_kind=="flamethrower"
	state="advance" if moving else "fire"
	stance="crouch" if not moving and threat_pressure>2 else "stand"
	if moving:set_destination(goal)
	# No ammunition left but a target: go knife it.
	if rounds+reserve==0 and target!=null:
		state="melee"
		set_destination(last_known)

## Move in bounds: one soldier in ten covers while the others advance.
## @param goal World destination. @param now Mission time.
func bound_toward(goal:Vector3,now:float):
	# Suppression creates a short covered pause, then another bound. It must not
	# trap a whole assault wave in an indefinitely refreshed exposed prone state.
	var cover_slot=(int(now/2.4)+index)%4==0 and target!=null and position.z<0
	state="fire" if cover_slot else "advance"
	stance="prone" if cover_slot and threat_pressure>3 else ("crouch" if cover_slot else "stand")
	if not cover_slot:set_destination(goal)

## Fire the weapon, with American assault rifles allowed an inaccurate shot on the move.
func try_fire():
	if role=="driver" or staged:return
	var previous=shots
	super.try_fire()
	# A shot makes noise for detection.
	if shots>previous:
		last_fired=game.elapsed
		# Sustained defensive belts with visible traversing bursts and cooling pauses.
		# Sustained defensive belts with visible traversing bursts and cooling pauses.
		if mounted and weapon_kind in ["mg42","m1919"] and burst_pause>0:
			burst_pause=randf_range(0.25,0.55)
			burst_left=randi_range(9,18)

## Leave the landing craft after it beached; places the soldier on the ground at his seat and starts him moving.
func dismount():
	# Only possible once the boat has arrived.
	if truck==null or not truck.arrived:return
	var craft=truck
	var p=craft.seat_transform(seat).origin
	truck=null
	boat=null
	# Dormant boat state ends: collision layer 8 = friendly infantry.
	staged=false
	position=game.world.on_ground(p)+Vector3(0,0.15,0)
	collision_layer=8
	# Remember where he landed as the home position.
	home=position
	state="advance"
	stance="stand"
	# Force the posture to be recomputed, reset legs to standing and the collider to a standing capsule (1.76 m).
	posture_revision=-1
	for leg in model.legs:leg.rotation.x=0
	shape.shape.height=1.76
	shape.position.y=0.88
	# Small kick forward off the ramp.
	velocity=Vector3(0,0,-2)

## React to a noise (shots, footsteps).
## @param point World position. @param radius Audible range in metres. @param source_team Team that made it. @param kind Noise type string.
func hear_noise(point:Vector3,radius:float,source_team:int,kind:String):
	if not alive or staged or source_team==team:return
	# A sound creates a search direction, never visibility through a wall.
	# A sound creates a search direction, never visibility through a wall.
	if global_position.distance_to(point)>radius:return
	if kind=="footstep" and global_position.distance_to(point)>radius:return
	# Only update the search point if the soldier has no fresh contact (older than 1.2 s).
	if contact_age>1.2:
		last_known=point
		contact_age=3.0

## Ignore damage while dormant (staged); otherwise use the base class.
func take_damage(amount:float,source:Vector3=Vector3.ZERO,kind:String="rifle"):
	if staged:return
	super.take_damage(amount,source,kind)
