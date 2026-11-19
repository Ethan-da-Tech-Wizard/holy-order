# ==============================================================================
# Program: enemy.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for enemy.gd.
# ==============================================================================
## Desert-mission soldier AI (defenders and, in tests, friendly soldiers): perception, cover, firing.
##
## One controller for both sides, driven by `_physics_process`. The soldier perceives with sight
## rays (a sound alone only gives a rough search point, never an aimed shot), chooses cover on the
## village's navigation graph, moves along A* paths, shoots with ammunition limits and spread,
## digs in, mans the Breda MG when ordered, uses a knife when dry, and dies with a ragdoll-like fall.
## Created by the mission script (`game`) which sets `index`, `team` (0 defenders, 1 friendly),
## `role` ("hold", "assault", "mg"), `sentry` and the start position. Behaviour is verified
## by tests/tactics_test.gd and tests/ai_simulation.gd. Later theaters extend ardennes/actor.gd instead.
extends CharacterBody3D

# One perception / cover / ammunition controller for both sides. A sound is a
# search clue; only a sight ray can authorize an aimed shot at a live target.
# Art helpers and the equipment hitbox script (lets bullets hit and ruin the held rifle).
# One perception / cover / ammunition controller for both sides. A sound is a
# search clue; only a sight ray can authorize an aimed shot at a live target.
const Art=preload("res://scripts/art.gd")
const Equipment=preload("res://scripts/equipment_hitbox.gd")

# Mission controller (world, navigation, sounds, projectiles, noise events).
var game

# Dictionary from Art.soldier(): root, body, legs, gun.
var model: Dictionary

# Health points (defeat at 0) and whether the soldier lives.
var health: float=100
var alive: bool=true

# True for the isolated first guard, who is slower to fire and misses his first shot.
var sentry: bool=false

# Identity: index in the roster (seeds random numbers and staggers timers), team (0 defender, 1 friendly) and role.
var index: int=0
var team: int=0
var role: String="hold"

# Rifle condition 0..100; at 0 the rifle is ruined and the soldier falls back to the knife.
var weapon_health: float=100

# Loaded rounds, spare rounds and magazine capacity (6 for defenders, 10 for friendlies).
var rounds: int=6
var reserve_rounds: int=18
var capacity: int=6

# Home position used when idle.
var anchor: Vector3

# Local clock (seconds) driving the walk and shovel animations.
var clock: float=0

# Seconds until the soldier may take the next shot.
var cooldown: float=3

# Aim delay: time left before the shot is released after the soldier decides to fire.
var windup: float=0

# True once the soldier knows something is wrong (heard or saw something); an unalerted soldier is idle and short-sighted.
var alerted: bool=false

# Time left of the hit stagger (stops shooting and tilts the body).
var stagger: float=0

# Shots fired, for statistics and tests.
var shots_fired: int=0

# Muzzle flash mesh, the hitbox on the gun, the knife and shovel visuals, and the collider capsule.
var muzzle: MeshInstance3D
var weapon_hitbox
var knife: Node3D
var shovel: Node3D
var capsule: CollisionShape3D

# Per-soldier random generator with a fixed seed, so AI behaviour is repeatable.
var rng=RandomNumberGenerator.new()

# Behaviour state name ("idle", "firing", "taking_cover", "advancing", ...) used by tests and animation.
var state: String="idle"

# Best guess of the enemy's position, and how many seconds of memory are left.
var last_known=Vector3.ZERO
var memory: float=0

# Seconds since the last heard sound, and the timer for the next perception update.
var heard_age: float=999
var sense_timer: float=0

# True when a sight ray currently reaches `target_actor`.
var visible_target: bool=false
var target_actor

# Seconds left of suppression from near misses, and how many bullets have passed close.
var suppressed: float=0
var near_misses: int=0

# Seconds left of the reload.
var reload_time: float=0

# Crouch amount 0..1 (0 standing).
var stance: float=0

# Movement goal, chosen cover point, and a nearby spot from which the target can be seen.
var destination=Vector3.ZERO
var cover_point=Vector3.ZERO
var peek_point=Vector3.ZERO

# Whether a cover point is currently selected, and which navigation revision it was chosen on (so it is re-chosen after the world changed).
var has_cover: bool=false
var cover_revision: int=-1

# Time until the next decision.
var decision_timer: float=0

# Current path (points), index of the next point, time until it is re-planned and the navigation revision it came from.
var path=PackedVector3Array()
var path_cursor: int=0
var path_timer: float=0
var path_revision: int=-1

# True while moving.
var moving: bool=false

# Seconds of digging left; entrenched means a shallow trench already exists; dig_attempted prevents repeated digging.
var digging: float=0
var entrenched: bool=false
var dig_attempted: bool=false

# True when a close sound was just heard; used to cancel digging and tighten the search.
var close_sound: bool=false

# True while manning the MG nest.
var mounted: bool=false

# Timers for sharing contact with squad mates, for investigating, and the distance walked since the last footstep sound.
var shared_timer: float=0
var investigate_timer: float=0
var step_distance: float=0

## Create the collider, model, knife, shovel, gun hitbox and muzzle flash.
func _ready():
	# Seed from index and team so every soldier behaves differently but repeatably.
	rng.seed=740+index*39+team*19
	add_to_group("tactical_actor")
	# Team 0 is on layer 4 and team 1 on layer 8; the mask 1|2|4|8 collides with world, props, and both teams.
	collision_layer=4 if team==0 else 8
	collision_mask=1|2|4|8
	# Snap to the ground over small steps.
	floor_snap_length=0.35
	# Capsule 0.32 m radius, 1.85 m tall, matching Art soldiers.
	capsule=CollisionShape3D.new()
	var shape=CapsuleShape3D.new()
	shape.radius=0.32
	shape.height=1.85
	capsule.shape=shape
	capsule.position.y=0.93
	add_child(capsule)
	model=Art.soldier(self,team==1)
	anchor=position
	destination=position
	last_known=position-global_basis.z*20
	# Staggered first-shot cooldown so a group never fires in one volley.
	cooldown=2.5+index*0.43
	# Friendly soldiers carry a ten-round clip and 30 spare rounds.
	if team==1:
		capacity=10
		rounds=10
		reserve_rounds=30
	weapon_hitbox=Equipment.new()
	weapon_hitbox.wielder=self
	model.gun.add_child(weapon_hitbox)
	# Knife (hidden until needed) and shovel (shown while digging) are held on the body.
	knife=Node3D.new()
	model.body.add_child(knife)
	knife.position=Vector3(0.23,1.18,-0.38)
	Art.beveled_box(knife,Vector3(0.034,0.23,0.018),Vector3(0,0.15,0),Art.material(Color("a5aaa3"),0.85),0.004)
	Art.cylinder(knife,0.025,0.13,Vector3.ZERO,Art.material(Color("433b2e")))
	knife.hide()
	shovel=Art.shovel(model.body)
	shovel.position=Vector3(0.28,0.65,-0.45)
	shovel.scale=Vector3.ONE*0.75
	shovel.hide()
	# Muzzle flash is an unshaded warm sphere on the gun.
	var mat=Art.material(Color("ffe2a1")).duplicate()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle=Art.sphere(model.gun,0.06,model.gun.get_node("Muzzle").position,mat)
	muzzle.hide()

## Main per-tick update: timers, perception, reload, decisions, digging, movement and shooting.
## @param delta Seconds since the last physics tick.
func _physics_process(delta):
	# Inactive when dead or the game is not in the playing phase.
	if not alive or game.phase!="playing":return
	# Count down timers.
	clock+=delta
	cooldown=maxf(0,cooldown-delta)
	stagger=maxf(0,stagger-delta)
	suppressed=maxf(0,suppressed-delta)
	memory=maxf(0,memory-delta)
	heard_age+=delta
	shared_timer=maxf(0,shared_timer-delta)
	decision_timer-=delta
	path_timer-=delta
	sense_timer-=delta
	# Perceive about every 0.18 s, offset per soldier to spread the cost.
	if sense_timer<=0:
		sense_timer=0.18+index*0.006
		perceive()
	# Reload completes: move rounds from reserve into the magazine.
	if reload_time>0:
		reload_time=maxf(0,reload_time-delta)
		if reload_time==0:
			var added=mini(capacity-rounds,reserve_rounds)
			rounds+=added
			reserve_rounds-=added
	# The designated MG soldier operates the gun once alerted and while it is usable; others make decisions every 0.7-1.0 s.
	if alerted and role=="mg" and game.mg_nest and game.mg_nest.usable():
		operate_mg(delta)
	else:
		if mounted:dismount()
		if decision_timer<=0:
			decision_timer=0.7+rng.randf()*0.3
			decide()
		# Digging: a shallow scrape, interrupted by close sounds, suppression or a visible target within 23 m.
		if digging>0:
			state="digging"
			if close_sound or suppressed>0 or (visible_target and global_position.distance_to(last_known)<23):
				digging=0
				decision_timer=0
			else:
				digging-=delta
				shovel.rotation.x=-0.5+sin(clock*5)*0.6
				if digging<=0:
					# A shallow scrape behind cover, not an instant full-depth bunker.
					# A shallow scrape behind cover, not an instant full-depth bunker.
					game.world.dig(global_position+Vector3(0,0.1,0),0.42)
					entrenched=true
					has_cover=false
					decision_timer=0
		# Move, then show the right items: knife when out of ammunition, gun while armed, shovel while digging.
		move_tactically(delta)
		var has_ammo=weapon_health>0 and (rounds>0 or reserve_rounds>0)
		knife.visible=not has_ammo and digging<=0
		model.gun.visible=has_ammo and digging<=0
		shovel.visible=digging>0
		weapon_hitbox.set_active(model.gun.visible)
		# Start a 3 s reload when the magazine is empty and reserve rounds exist.
		if alerted and has_ammo and rounds==0 and reserve_rounds>0 and reload_time<=0:
			reload_time=3.0
			state="reloading"
			game.sounds.at("reload",global_position,-15)
		# Fire control: only when the target is visible and not staggered or digging.
		if visible_target and is_instance_valid(target_actor) and stagger==0 and digging<=0:
			var distance=global_position.distance_to(target_actor.global_position)
			# Out of ammunition and within 1.85 m: stab.
			if not has_ammo and distance<1.85 and cooldown<=0:
				melee()
			# Otherwise shoot only if standing, not suppressed under 1 s, not reloading or moving. Wind-up 0.52 s for the sentry, 0.42 s for the others, then the shot is released.
			elif has_ammo and reload_time==0 and suppressed<1.0 and not moving and stance<0.22:
				if windup>0:
					windup-=delta
					if windup<=0:shoot()
				elif cooldown<=0:
					windup=0.52 if sentry else 0.42
		else:windup=0
	# Animation (stance, legs, facing) and a safety kill if the soldier falls through the world (y < -25).
	animate(delta)
	if global_position.y< -25:take_damage(200)

## Whether an actor still exists and has health.
func target_is_alive(actor) -> bool:
	return is_instance_valid(actor) and actor.health>0

## World position of this soldier's eyes, lowered by crouching.
func eye_position() -> Vector3:
	return global_position+Vector3(0,1.53-stance*0.55,0)

## World position to aim at on a target: the player's head height or a fixed 1.3 m for soldiers.
func target_eye(actor) -> Vector3:
	return actor.global_position+Vector3(0,actor.eye_height*0.82 if actor==game.player else 1.3,0)

## Line-of-sight test using a physics ray on layers 1, 2, 4 and 8.
## @return true if the first thing the ray hits is exactly `actor`.
func can_see(actor) -> bool:
	if not target_is_alive(actor):return false
	var q=PhysicsRayQueryParameters3D.create(eye_position(),target_eye(actor),1|2|4|8)
	q.exclude=[get_rid()]
	var hit=get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider==actor

## Convenience wrapper: can this soldier see the player?
func can_see_player() -> bool:
	return can_see(game.player)

## Update `visible_target` by scanning hostile actors.
##
## Range is 100 m once alerted, otherwise 29 m (sentry) or 33 m (others), reduced to 34 % if the
## player is prone and 60 % if crouched. The target must be within a forward cone (dot > 0.15) or
## within 3 m, and a sight ray must reach it. The nearest visible actor wins.
func perceive():
	visible_target=false
	var candidates=game.hostile_targets(team)
	var nearest=INF
	for actor in candidates:
		if not target_is_alive(actor):continue
		var delta=actor.global_position-global_position
		var distance=delta.length()
		var range_limit=100.0 if alerted else (29.0 if sentry else 33.0)
		# Hiding makes the player harder to spot only while the soldier is unalerted.
		if actor==game.player and not alerted:
			range_limit*=0.34 if actor.prone else (0.60 if actor.crouched else 1.0)
		var in_view=(-global_basis.z).dot(delta.normalized())>0.15 or distance<3.0
		if distance<range_limit and distance<nearest and in_view and can_see(actor):
			nearest=distance
			target_actor=actor
			visible_target=true
	# On contact: become alerted, remember the position for 24 s and tell squad mates (at most every 3.5 s).
	if visible_target:
		alerted=true
		last_known=target_actor.global_position
		memory=24
		close_sound=nearest<15
		if sentry:game.has_seen_rifle=true
		if shared_timer<=0:
			shared_timer=3.5
			game.share_contact(self,last_known)
	elif memory<=0 and alerted:
		# Search around the last clue; never follow an unseen player's live position.
		# Search around the last clue; never follow an unseen player's live position.
		state="searching"
		close_sound=false

## Gunshot heard (compatibility wrapper for hear_noise).
func hear_shot(point: Vector3):
	hear_noise(point,"gunshot")

## Hear a noise at a point.
## @param point World position of the sound. @param kind "gunshot", "footstep", "melee", "impact", "near_miss"...
func hear_noise(point: Vector3, kind: String="gunshot"):
	if not alive:return
	var distance=global_position.distance_to(point)
	alerted=true
	heard_age=0
	# Footsteps count as close within 8 m, other sounds within 20 m.
	close_sound=distance<(8 if kind=="footstep" else 20)
	# Keep a recent visual fix. Distant sound locations carry deliberate uncertainty.
	# Keep a recent visual fix. Distant sound locations carry deliberate uncertainty.
	if not visible_target:
		var uncertainty=clampf(distance*0.09,0.65,7.5)
		last_known=point+Vector3(rng.randf_range(-uncertainty,uncertainty),0,rng.randf_range(-uncertainty,uncertainty))
	# Remember the clue for 20 s and force a new decision immediately; close sounds stop digging.
	memory=20
	if role=="assault":state="investigating"
	decision_timer=0
	if close_sound:digging=0

## Receive a position from a squad mate who saw an enemy; blurred by 1.5 m, ignored if this soldier already sees one.
func hear_contact(point: Vector3):
	if not alive or visible_target:return
	alerted=true
	last_known=point+Vector3(rng.randf_range(-1.5,1.5),0,rng.randf_range(-1.5,1.5))
	memory=18
	decision_timer=0

## A bullet passed close: suppress for 2.5 s, drop cover and treat it as a close noise.
## @param source World position the shot came from.
func near_miss(source: Vector3):
	if not alive:return
	near_misses+=1
	suppressed=2.5
	hear_noise(source,"near_miss")
	close_sound=true
	digging=0
	has_cover=false
	decision_timer=0

## Pick the best cover point near the soldier.
##
## Candidates come from the village's cover list, must be reachable, hidden from the threat
## (a ray from the threat finds the cover blocking it), not claimed by another soldier and ideally
## have a peek spot within 4.1 m of path from which the threat can be seen. Score is route length plus
## a 15 point penalty for no peek spot, preferring cover near home (defence) or closer to the threat (advance).
## @param advance true when moving forward under fire; then only cover that gets nearer than the current position qualifies.
func choose_cover(advance: bool=false):
	var best_score=INF
	var chosen=global_position
	var chosen_peek=global_position
	var valid_cover=false
	# The cover list lives on the village; navigation provides ground points and paths.
	var nav=game.world.navigation
	cover_revision=nav.revision
	var threat=last_known+Vector3(0,1.45,0)
	var current_distance=global_position.distance_to(last_known)
	# Within 24 m when advancing, 21 m when defending (and 26 m of home).
	for candidate in game.world.village.covers:
		if candidate.distance_to(global_position)> (24 if advance else 21):continue
		if not advance and candidate.distance_to(anchor)>26:continue
		# The cover point must sit on the navigation graph (within 2.2 m of a ground point).
		var floor=nav.floor_point(candidate)
		if floor.distance_to(candidate)>2.2:continue
		# Skip cover that a bullet from the threat could pass over (no solid between threat and the soldier's chest).
		var ray=PhysicsRayQueryParameters3D.create(threat,floor+Vector3(0,0.72,0),1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		# A path to the cover must exist.
		var route=nav.path_between(global_position,floor)
		if route.is_empty() or route[-1].distance_to(floor)>1.0:continue
		# One soldier per cover spot (2.3 m separation).
		var occupied=false
		for other in game.squad(team):
			if other!=self and other.alive and other.has_cover and other.cover_point.distance_to(floor)<2.3:occupied=true
		if occupied:continue
		var to_threat=(last_known-floor).normalized()
		var side=Vector3(-to_threat.z,0,to_threat.x)
		var peek=floor
		var can_peek=false
		# Look for a peek position: beside the cover (1.3 m or 2.3 m to either side) or in front of it, within a short walk.
		for offset in [Vector3.ZERO,side*1.3,-side*1.3,side*2.3,-side*2.3,to_threat*1.7]:
			var test=nav.floor_point(floor+offset)
			if test.distance_to(floor+offset)>1.4:continue
			var peek_route=nav.path_between(floor,test)
			if peek_route.is_empty():continue
			var peek_distance=0.0
			for i in range(1,peek_route.size()):peek_distance+=peek_route[i-1].distance_to(peek_route[i])
			if peek_distance>4.1:continue
			var sight=PhysicsRayQueryParameters3D.create(test+Vector3(0,1.52,0),threat,1)
			if get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
				peek=test
				can_peek=true
				break
		# Distance gate for advancing, route cost and scoring.
		var distance=floor.distance_to(last_known)
		if advance and distance>current_distance-3:continue
		var route_distance=0.0
		for i in range(1,route.size()):route_distance+=route[i-1].distance_to(route[i])
		var score=route_distance+(0 if can_peek else 15)
		if advance:score+=distance*0.65
		else:score+=floor.distance_to(anchor)*0.22
		if score<best_score:
			best_score=score
			chosen=floor
			chosen_peek=peek
			valid_cover=true
	# Store the result (has_cover false if nothing qualified).
	has_cover=valid_cover
	cover_point=chosen
	peek_point=chosen_peek

## Choose a behaviour state and destination (called every 0.7-1.0 s).
##
## Priority: idle if unalerted, knife assault when dry, sentry behaviour, taking cover when
## suppressed or reloading, then assault (bound forward or cover each other) or hold (dig in, peek).
func decide():
	if not alerted:
		state="idle"
		destination=anchor
		return
	# Dry means the rifle is ruined or no rounds remain.
	var dry=weapon_health<=0 or (rounds==0 and reserve_rounds==0)
	if dry:
		state="knife_assault" if visible_target else "searching"
		destination=last_known
		return
	# Choose again when the world changed (a door opened or wall broke) since cover was selected.
	if cover_revision!=game.world.navigation.revision:has_cover=false
	if not has_cover:choose_cover(role=="assault" and suppressed==0)
	if sentry:
		state="firing" if visible_target else "investigating"
		destination=cover_point if suppressed>0 and has_cover else anchor
		return
	# Suppressed or reloading: go to cover.
	if suppressed>0 or reload_time>0:
		if not has_cover:choose_cover(false)
		state="taking_cover"
		destination=cover_point if has_cover else game.world.navigation.floor_point(global_position+global_basis.x*3)
		return
	# Assault soldiers alternate moving and covering with their partner (game.assault_can_move).
	if role=="assault":
		if game.assault_can_move(self):
			state="advancing" if visible_target else "investigating"
			if has_cover and global_position.distance_to(cover_point)>1.6:
				destination=cover_point
			elif visible_target and global_position.distance_to(last_known)<13:
				state="firing"
				destination=peek_point if has_cover and peek_point.distance_to(global_position)<3.5 else global_position
			else:
				choose_cover(true)
				var approach=(last_known-global_position).normalized()
				var side=Vector3(-approach.z,0,approach.x)*(5 if index%2==0 else -5)
				destination=cover_point if has_cover else game.world.navigation.floor_point(last_known-approach*8+side)
		else:
			state="covering"
			destination=peek_point if has_cover and peek_point.distance_to(global_position)<3.5 else global_position
	else:
		state="holding"
		destination=cover_point if has_cover else anchor
		# Defenders: dig in once if far (over 28 m) from the last clue and not under close sound.
		if has_cover and global_position.distance_to(cover_point)<1.6 and not dig_attempted and not close_sound and global_position.distance_to(last_known)>28:
			dig_attempted=true
			digging=5.5
		# Peek from cover when the target is visible, or periodically while remembering one.
		if visible_target or (memory>0 and int(clock*0.45+index)%3==0):
			state="peeking"
			destination=peek_point if has_cover else anchor
	# Assault soldiers who lost contact walk a slow circle of 7 m radius around the last known position.
	if not visible_target and memory<=0 and role=="assault":
		state="searching"
		destination=game.world.navigation.floor_point(last_known+Vector3(sin(clock*0.3+index)*7,0,cos(clock*0.3+index)*7))

## Follow the A* path to `destination`, open doors on the way and play footstep sounds.
## @param delta Seconds.
func move_tactically(delta: float):
	var wanted=Vector3.ZERO
	var nav=game.world.navigation
	# Walk only when not digging or staggered and further than 0.8 m from the goal.
	if digging<=0 and stagger==0 and destination.distance_to(global_position)>0.8:
		# Re-plan every 1.1 s or when the navigation graph changed.
		if path_timer<=0 or path_revision!=nav.revision:
			path=nav.path_between(global_position,destination)
			path_cursor=1 if path.size()>1 else 0
			path_timer=1.1
			path_revision=nav.revision
		if path_cursor<path.size():
			var point=path[path_cursor]
			var flat=Vector3(point.x-global_position.x,0,point.z-global_position.z)
			if flat.length()<0.5:path_cursor+=1
			else:
				# Assault soldiers and knife attackers run at 3.7 m/s, others walk at 2.9.
				wanted=flat.normalized()*(3.7 if role=="assault" or state=="knife_assault" else 2.9)
				# Hop (4.5 m/s upward) over steps higher than 0.22 m.
				if point.y-global_position.y>0.22 and is_on_floor():velocity.y=4.5
		# At the end of the path, walk straight to the goal if the line is clear.
		if path_cursor>=path.size() and nav.line_clear(global_position,destination,0.7):
			var final_step=destination-global_position
			final_step.y=0
			if final_step.length()>0.8:wanted=final_step.normalized()*2.9
		# Soldiers open doors within 2.5 m on their way.
		var door=game.world.nearby_door(global_position+Vector3(0,1,0),2.5)
		if door and not door.opened:door.use()
	# Smooth acceleration (16 m/s^2) and gravity (20 m/s^2).
	velocity.x=move_toward(velocity.x,wanted.x,16*delta)
	velocity.z=move_toward(velocity.z,wanted.z,16*delta)
	if not is_on_floor():velocity.y-=20*delta
	move_and_slide()
	moving=Vector2(velocity.x,velocity.z).length()>0.5
	# Footstep every 1.9 m walked.
	if moving and is_on_floor():
		step_distance+=Vector2(velocity.x,velocity.z).length()*delta
		if step_distance>1.9:
			step_distance=0
			game.sounds.at("step",global_position,-10,0.95+index*0.018)

## Update stance, leg swing, body tilt, facing and gun pose.
func animate(delta: float):
	# Crouch while taking cover, digging, reloading, or holding without a target.
	var low=(state in ["taking_cover","digging","reloading"] or (state=="holding" and not visible_target)) and not moving
	stance=move_toward(stance,1.0 if low else 0.0,delta*5)
	# Shrink the collider and lower the body with the stance (0.5 m lower when crouched).
	capsule.shape.height=1.85-stance*0.50
	capsule.position.y=capsule.shape.height/2
	model.body.position.y=-stance*0.53
	for leg in model.legs:leg.rotation.x=stance*0.5
	# Walk animation: legs swing at 9 rad/s while moving.
	if moving:
		model.legs[0].rotation.x=sin(clock*9)*0.5
		model.legs[1].rotation.x=-model.legs[0].rotation.x
	# Stagger tilts the body backwards.
	model.body.rotation.x=-stagger*0.4
	# Alerted soldiers face the last known position (or their movement direction); idle ones sweep slowly around their start direction.
	if alerted:
		var facing=last_known if not moving else global_position+Vector3(velocity.x,0,velocity.z)
		facing.y=global_position.y
		if facing.distance_to(global_position)>0.1:
			var desired=atan2(-(facing.x-global_position.x),-(facing.z-global_position.z))
			rotation.y=lerp_angle(rotation.y,desired,1-exp(-8*delta))
	else:rotation.y=PI+sin(clock*0.22+index)*0.25
	# Gun raised when alerted, lowered otherwise.
	model.gun.rotation.x=lerpf(model.gun.rotation.x,0.0 if alerted else -0.48,delta*4)

## Fire one rifle shot at the current target.
##
## Requires ammunition, a working rifle and a clear line of sight. Spread grows with distance
## (0.12 m plus 0.7 % of distance) and by 70 % when the player is sprinting; the sentry's first
## shot is deliberately wide. Spawns a projectile (damage 12 for the sentry, 14 otherwise, speed 42),
## muzzle flash, rifle sound and a 175 m gunshot noise that alerts others.
func shoot():
	if not alive or rounds<=0 or weapon_health<=0 or reload_time>0:return
	if not is_instance_valid(target_actor):target_actor=game.player if team==0 else null
	if not target_is_alive(target_actor) or not can_see(target_actor):return
	rounds-=1
	shots_fired+=1
	# Next shot in 2.7-4.1 s: deliberately slow so the player can survive.
	cooldown=rng.randf_range(2.7,4.1)
	var origin=eye_position()-Vector3(0,0.08,0)
	var target=target_eye(target_actor)-Vector3(0,0.17,0)
	var distance=origin.distance_to(target)
	var spread=0.12+distance*0.007
	if target_actor==game.player and target_actor.is_sprinting:spread*=1.7
	target+=Vector3(rng.randfn(0,spread),rng.randfn(0,spread*0.60),rng.randfn(0,spread))
	# The sentry misses the first shot by 1.15 m sideways, a warning shot.
	if sentry and shots_fired==1:target+=global_basis.x*1.15
	game.fire_projectile(origin,target,self,12 if sentry else 14,42)
	muzzle.show()
	get_tree().create_timer(0.06).timeout.connect(func():if is_instance_valid(muzzle):muzzle.hide())
	game.sounds.at("rifle",origin,-2)
	game.emit_noise(origin,175,team,"gunshot")
	# Recoil kick animation.
	model.gun.position.z=-0.38
	create_tween().tween_property(model.gun,"position:z",-0.43,0.28)

## Knife attack on an adjacent target (24 damage to the player, 35 to others).
func melee():
	if not target_is_alive(target_actor) or not can_see(target_actor):return
	cooldown=1.1
	game.sounds.at("sword",global_position,-12)
	knife.rotation.x=-1.3
	create_tween().tween_property(knife,"rotation:x",0,0.35)
	if target_actor==game.player:target_actor.take_damage(24,global_position,"melee")
	else:target_actor.take_damage(35)

## Man the machine-gun nest: walk to it, claim it, then track and fire while a target is visible.
func operate_mg(delta: float):
	var nest=game.mg_nest
	destination=nest.operator_position()
	state="manning_mg"
	if global_position.distance_to(destination)>1.0:
		move_tactically(delta)
		return
	# If someone else claimed the nest, go back to holding.
	if not nest.claim(self):
		role="hold"
		return
	# Hide the rifle, knife and shovel while mounted.
	mounted=true
	moving=false
	velocity=Vector3.ZERO
	model.gun.hide()
	weapon_hitbox.set_active(false)
	knife.hide()
	shovel.hide()
	nest.track(last_known)
	# Fire only when not suppressed (under 1.6 s) and the target is alive.
	if visible_target and suppressed<1.6 and target_is_alive(target_actor):nest.try_fire(target_eye(target_actor))
	# Leave when the nest is wrecked or out of ammunition.
	if not nest.usable():dismount()

## Leave the machine gun and become an ordinary defender at the current position.
func dismount():
	if game.mg_nest:game.mg_nest.release(self)
	mounted=false
	role="hold"
	anchor=global_position
	has_cover=false
	decision_timer=0
	model.gun.visible=weapon_health>0
	weapon_hitbox.set_active(model.gun.visible)

## Damage to the held rifle (from shots hitting the equipment hitbox).
## @param _item Unused. @param amount Damage points.
func receive_equipment_damage(_item: String, amount: float):
	weapon_health=maxf(0,weapon_health-amount)
	if weapon_health<=0:
		model.gun.hide()
		weapon_hitbox.set_active(false)
		# Loaded cartridges stay with the corpse even when the rifle is ruined.
		# Loaded cartridges stay with the corpse even when the rifle is ruined.
		reserve_rounds+=rounds
		rounds=0
		reload_time=0
		decision_timer=0
	game.sounds.at("clang",global_position,-8)

## Take damage.
## @param amount Damage points. @param headshot true doubles the damage.
func take_damage(amount: float, headshot: bool=false):
	if not alive:return
	health-=amount*(2.0 if headshot else 1.0)
	# Hit stagger of 0.55 s; the soldier is alerted by being hit.
	stagger=0.55
	alerted=true
	game.sounds.at("hit",global_position,-7)
	if health<=0:die()
	else:
		# Impact direction is a clue, not a through-wall sight fix.
		# Impact direction is a clue, not a through-wall sight fix.
		hear_noise(game.player.global_position,"impact")

## Die: stop collision, fall over with a tween and tell the game one defender is down.
func die():
	alive=false
	collision_layer=0
	collision_mask=0
	velocity=Vector3.ZERO
	muzzle.hide()
	shovel.hide()
	if mounted:game.mg_nest.release(self)
	mounted=false
	var tw=create_tween().set_parallel(true)
	tw.tween_property(model.root,"rotation:x",-PI/2,0.45).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(model.root,"position:y",0.18,0.45)
	if team==0:game.enemy_down(self)
