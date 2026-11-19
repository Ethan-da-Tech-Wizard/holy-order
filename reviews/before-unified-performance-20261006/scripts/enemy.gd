## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/enemy.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Soldier AI for the desert mission: one controller used by both sides (Italian
## defenders team 0, British patrol team 1).
##
## Role: instantiated by game.gd (which sets `game`, `team`, `role`, `index`,
## `sentry`). Each physics tick it perceives, decides, moves and fires. It
## builds its own capsule collider and an Art.soldier() model in _ready.
## Design rules (keep them when changing it):
##   - SIGHT versus SOUND: a gunshot or footstep is only a search clue
##     (hear_noise sets `last_known` with deliberate error); only a clear sight
##     ray (can_see) authorises an aimed shot at a living target.
##   - State machine in `state` (strings): idle, searching, investigating,
##     taking_cover, peeking, holding, covering, advancing, firing,
##     reloading, digging, knife_assault, manning_mg.
##   - Roles: sentry (guard post, fires first with a deliberately missed
##     shot), hold (defend and dig in), assault (advance with the squad), mg
##     (crew the machine gun nest).
## Collision layers: team 0 on layer 4, team 1 on layer 8; masks include
## world (1), player (2) and both teams (4|8).
## Interfaces used: game.hostile_targets/squad/share_contact/assault_can_move,
## game.world.navigation (pathing), game.world.village.covers, game.fire_projectile,
## game.emit_noise, game.sounds.
extends CharacterBody3D

# One perception / cover / ammunition controller for both sides. A sound is a
# search clue; only a sight ray can authorize an aimed shot at a live target.
const Art=preload("res://scripts/art.gd")
const Equipment=preload("res://scripts/equipment_hitbox.gd")

## The Game node (game.gd); provides targets, projectiles, sounds and world.
var game

## Dictionary returned by Art.soldier(): root, body, legs, gun.
var model: Dictionary

## Hit points; death at <= 0 (headshots count double).
var health: float=100

## False once die() has run; most methods return immediately when dead.
var alive: bool=true

## True for the lone forward guard, who is slower to fire and aims badly on his first shot.
var sentry: bool=false

## Position in the squad; staggers timers and seeds the RNG so soldiers do not act in lockstep.
var index: int=0

## 0 = Italian defenders (hunt the player), 1 = British allies (hunt Italians).
var team: int=0

## Tactical role: "hold", "assault", "mg".
var role: String="hold"

## Hit points of the rifle itself; at 0 the soldier switches to a knife.
var weapon_health: float=100

## Cartridges loaded in the rifle.
var rounds: int=6

## Cartridges carried; a reload moves ammunition from here to `rounds`.
var reserve_rounds: int=18

## Magazine size: 6 for Italians, 10 for the British (see _ready).
var capacity: int=6

## Home position the soldier returns to when idle and keeps cover choices near.
var anchor: Vector3

## Seconds this actor has been simulated; drives walking and digging animation.
var clock: float=0

## Seconds until another shot may start (random 2.7-4.1 s after each shot).
var cooldown: float=3

## Remaining aim time before the shot is released (0.42-0.52 s) so enemies
## give the player a visible tell.
var windup: float=0

## True once the soldier has seen or heard something; unalerted ones stand
## guard, look about slowly and have reduced vision range.
var alerted: bool=false

## Seconds of flinch after being hit; blocks movement and firing.
var stagger: float=0

## Total shots fired (used by the sentry's first-shot miss and by tests).
var shots_fired: int=0

## Muzzle-flash sphere on the gun.
var muzzle: MeshInstance3D

## Equipment hit area on the gun so bullets can ruin it.
var weapon_hitbox

## Knife model, used when the rifle is ruined or out of ammunition.
var knife: Node3D

## Shovel model, shown while digging in.
var shovel: Node3D

## Collision capsule; shrinks while crouched.
var capsule: CollisionShape3D

## Per-actor seeded generator, so behaviour is reproducible.
var rng=RandomNumberGenerator.new()

## Current behaviour label (see class comment).
var state: String="idle"

## Where the soldier believes the target is (seen position or noisy guess).
var last_known=Vector3.ZERO

## Seconds the last_known position stays trusted; counts down.
var memory: float=0

## Seconds since the last sound heard.
var heard_age: float=999

## Countdown to the next perception check (about every 0.18 s).
var sense_timer: float=0

## True when a clear line of sight to target_actor was just confirmed.
var visible_target: bool=false

## The enemy actor this soldier is aiming at, or null.
var target_actor

## Seconds of "pinned down" time left after bullets pass close (near_miss).
var suppressed: float=0

## Count of close shots received, for statistics.
var near_misses: int=0

## Seconds left on the current reload (3 s).
var reload_time: float=0

## 0 standing .. 1 crouched; smoothed by animate().
var stance: float=0

## World point the movement code is walking toward.
var destination=Vector3.ZERO

## Chosen cover position (see choose_cover).
var cover_point=Vector3.ZERO

## Nearby spot from which the threat is visible; used to lean out of cover.
var peek_point=Vector3.ZERO

## True when cover_point is valid for the current threat.
var has_cover: bool=false

## Navigation revision the cover was chosen for; cover is re-chosen if the map changed.
var cover_revision: int=-1

## Countdown to the next call to decide() (0.7-1.0 s).
var decision_timer: float=0

## Current waypoints from the navigation graph.
var path=PackedVector3Array()

## Index of the waypoint being approached.
var path_cursor: int=0

## Countdown to recompute the path (about every 1.1 s).
var path_timer: float=0

## Navigation revision the path was computed for.
var path_revision: int=-1

## True when horizontal speed exceeds 0.5 m/s.
var moving: bool=false

## Seconds of digging left (5.5 s) while scraping a foxhole.
var digging: float=0

## True after a foxhole has been dug; no further digging attempts.
var entrenched: bool=false

## Ensures each soldier digs at most once.
var dig_attempted: bool=false

## True if a recent noise was close; interrupts digging.
var close_sound: bool=false

## True while operating the machine gun.
var mounted: bool=false

## Cooldown (3.5 s) between contact reports shared with squad mates.
var shared_timer: float=0

## Reserved timer for investigating; not used by the current logic.
var investigate_timer: float=0

## Metres walked since the last footstep sound.
var step_distance: float=0

## Godot lifecycle hook: seeds the RNG, joins group "tactical_actor",
## configures collision layers, builds the capsule, model, knife, shovel and
## muzzle flash, and sets team-specific ammunition (British 10/30 versus
## Italian 6/18).
func _ready():
	# Seed depends on index and team so squad members behave differently but
	# identically on every run.
	rng.seed=740+index*39+team*19
	add_to_group("tactical_actor")

	# Team layers let each side raycast the other (see can_see) without
	# every body blocking every other.
	collision_layer=4 if team==0 else 8
	collision_mask=1|2|4|8
	floor_snap_length=0.35
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

	# Until a threat is found, the "last known" point is 20 m straight ahead.
	last_known=position-global_basis.z*20

	# Stagger the first shot per soldier so a squad does not open fire in unison.
	cooldown=2.5+index*0.43
	if team==1:
		capacity=10
		rounds=10
		reserve_rounds=30
	weapon_hitbox=Equipment.new()
	weapon_hitbox.wielder=self
	model.gun.add_child(weapon_hitbox)
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
	var mat=Art.material(Color("ffe2a1")).duplicate()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle=Art.sphere(model.gun,0.06,model.gun.get_node("Muzzle").position,mat)
	muzzle.hide()

## Main per-tick loop (fixed physics step): timers, perception, reloading,
## decision, digging, movement, firing and animation. Skipped when dead or when
## the game is not in the "playing" phase.
## [param delta] physics step in seconds.
func _physics_process(delta):
	if not alive or game.phase!="playing":return
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

	# Perception is polled about 5 times a second and staggered by index,
	# which is far cheaper than a ray every frame for every soldier.
	if sense_timer<=0:
		sense_timer=0.18+index*0.006
		perceive()
	if reload_time>0:
		reload_time=maxf(0,reload_time-delta)
		if reload_time==0:
			var added=mini(capacity-rounds,reserve_rounds)
			rounds+=added
			reserve_rounds-=added

	# Machine-gun crew override: go to and man the nest while it is usable;
	# otherwise fall through to normal infantry behaviour.
	if alerted and role=="mg" and game.mg_nest and game.mg_nest.usable():
		operate_mg(delta)
	else:
		if mounted:dismount()

		# Re-think roughly every 0.7-1.0 s with jitter so decisions are not synchronised.
		if decision_timer<=0:
			decision_timer=0.7+rng.randf()*0.3
			decide()

		# Digging aborts if a noise is close, the soldier is suppressed, or a
		# visible target is within 23 m; otherwise a shallow 0.42 m scrape is
		# carved at the end, not an instant full-depth bunker.
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
					game.world.dig(global_position+Vector3(0,0.1,0),0.42)
					entrenched=true
					has_cover=false
					decision_timer=0
		move_tactically(delta)

		# Weapon visibility: knife when the rifle is ruined or empty, gun
		# otherwise, shovel while digging.
		var has_ammo=weapon_health>0 and (rounds>0 or reserve_rounds>0)
		knife.visible=not has_ammo and digging<=0
		model.gun.visible=has_ammo and digging<=0
		shovel.visible=digging>0
		weapon_hitbox.set_active(model.gun.visible)

		# Automatic reload (3 s) when the magazine is empty and ammo remains.
		if alerted and has_ammo and rounds==0 and reserve_rounds>0 and reload_time<=0:
			reload_time=3.0
			state="reloading"
			game.sounds.at("reload",global_position,-15)

		# Fire control: knife attack when out of ammunition and within 1.85 m;
		# otherwise start a windup, then shoot(). The soldier must be standing
		# still (not moving, stance < 0.22), not suppressed, and not reloading.
		if visible_target and is_instance_valid(target_actor) and stagger==0 and digging<=0:
			var distance=global_position.distance_to(target_actor.global_position)
			if not has_ammo and distance<1.85 and cooldown<=0:
				melee()
			elif has_ammo and reload_time==0 and suppressed<1.0 and not moving and stance<0.22:
				if windup>0:
					windup-=delta
					if windup<=0:shoot()
				elif cooldown<=0:
					windup=0.52 if sentry else 0.42
		else:windup=0
	animate(delta)

	# Failsafe: anyone who falls out of the world dies instead of lingering.
	if global_position.y< -25:take_damage(200)

## True if `actor` is still a valid instance with positive health.
func target_is_alive(actor) -> bool:
	return is_instance_valid(actor) and actor.health>0

## World position of this soldier's eyes: 1.53 m standing, lowered up to
## 0.55 m when crouched. Origin of sight rays and shots.
func eye_position() -> Vector3:
	return global_position+Vector3(0,1.53-stance*0.55,0)

## World position of an actor's upper body to aim at: 82% of the player's
## eye height, or a fixed 1.3 m for AI soldiers.
func target_eye(actor) -> Vector3:
	return actor.global_position+Vector3(0,actor.eye_height*0.82 if actor==game.player else 1.3,0)

## Line-of-sight test: a ray from this soldier's eyes to the target hits that
## target first (layers world, player, both teams, excluding self).
## Returns false for dead targets.
func can_see(actor) -> bool:
	if not target_is_alive(actor):return false
	var q=PhysicsRayQueryParameters3D.create(eye_position(),target_eye(actor),1|2|4|8)
	q.exclude=[get_rid()]
	var hit=get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider==actor

## Convenience wrapper: can_see(game.player).
func can_see_player() -> bool:
	return can_see(game.player)

## Vision scan: picks the nearest hostile actor that is within range, in the
## forward view cone (or within 3 m) and truly visible; updates visible_target,
## last_known, memory and shares the contact with the squad.
## Range: 100 m once alerted; 29 m for a sentry and 33 m for others otherwise;
## an unalerted soldier sees a prone player at 34% and a crouching one at
## 60% of that range. The view cone is a dot product > 0.15 (about 81 degrees
## half-angle).
func perceive():
	visible_target=false
	var candidates=game.hostile_targets(team)
	var nearest=INF
	for actor in candidates:
		if not target_is_alive(actor):continue
		var delta=actor.global_position-global_position
		var distance=delta.length()
		var range_limit=100.0 if alerted else (29.0 if sentry else 33.0)
		if actor==game.player and not alerted:
			range_limit*=0.34 if actor.prone else (0.60 if actor.crouched else 1.0)
		var in_view=(-global_basis.z).dot(delta.normalized())>0.15 or distance<3.0
		if distance<range_limit and distance<nearest and in_view and can_see(actor):
			nearest=distance
			target_actor=actor
			visible_target=true
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
		state="searching"
		close_sound=false

## Convenience: treat a gunshot at `point` as a "gunshot" noise.
func hear_shot(point: Vector3):
	hear_noise(point,"gunshot")

## Reacts to a sound at `point`: becomes alerted, notes the sound's age, and
## unless the target is in view, sets last_known to the point plus an error
## that grows with distance (9% of range, clamped to 0.65-7.5 m). Footsteps are
## "close" within 8 m, other sounds within 20 m. Assault soldiers switch to
## investigating, and the next decision is immediate.
## [param point] noise origin. [param kind] "gunshot", "footstep", "impact",
## "near_miss" (affects the closeness threshold).
func hear_noise(point: Vector3, kind: String="gunshot"):
	if not alive:return
	var distance=global_position.distance_to(point)
	alerted=true
	heard_age=0
	close_sound=distance<(8 if kind=="footstep" else 20)
	# Keep a recent visual fix. Distant sound locations carry deliberate uncertainty.
	if not visible_target:
		var uncertainty=clampf(distance*0.09,0.65,7.5)
		last_known=point+Vector3(rng.randf_range(-uncertainty,uncertainty),0,rng.randf_range(-uncertainty,uncertainty))
	memory=20
	if role=="assault":state="investigating"
	decision_timer=0
	if close_sound:digging=0

## Reacts to a squad mate's contact report: alerts and points the soldier
## at the reported position with a +-1.5 m error. Ignored when the soldier
## already has its own visual contact.
func hear_contact(point: Vector3):
	if not alive or visible_target:return
	alerted=true
	last_known=point+Vector3(rng.randf_range(-1.5,1.5),0,rng.randf_range(-1.5,1.5))
	memory=18
	decision_timer=0

## Called when a bullet passes close: pins the soldier down for 2.5 s,
## aborts digging, invalidates cover, and treats the shooter's direction as a noise.
## [param source] where the shot came from.
func near_miss(source: Vector3):
	if not alive:return
	near_misses+=1
	suppressed=2.5
	hear_noise(source,"near_miss")
	close_sound=true
	digging=0
	has_cover=false
	decision_timer=0

## Picks the best cover point and a "peek" spot to shoot from.
## [param advance] true for an assaulting soldier moving up (looks farther
## and must pick cover closer to the threat); false for defending.
## Candidate cover (game.world.village.covers) must be within 21 m (24 when advancing)
## of the soldier and within 26 m of the anchor (defence), have a floor on the
## nav graph, actually block a ray from the threat, be reachable, and not be
## taken by a squad mate (2.3 m). A peek spot within 4.1 m of walking distance
## that sees the threat is preferred.
## Score (lower is better) = route length + 15 if no peek spot, + 0.65 x distance
## to threat when advancing or + 0.22 x distance from the anchor when defending.
## Sets has_cover, cover_point, peek_point.
func choose_cover(advance: bool=false):
	var best_score=INF
	var chosen=global_position
	var chosen_peek=global_position
	var valid_cover=false
	var nav=game.world.navigation
	cover_revision=nav.revision

	# Rays aim at the threat's chest height, 1.45 m above the believed position.
	var threat=last_known+Vector3(0,1.45,0)
	var current_distance=global_position.distance_to(last_known)
	for candidate in game.world.village.covers:
		if candidate.distance_to(global_position)> (24 if advance else 21):continue
		if not advance and candidate.distance_to(anchor)>26:continue
		var floor=nav.floor_point(candidate)
		if floor.distance_to(candidate)>2.2:continue
		var ray=PhysicsRayQueryParameters3D.create(threat,floor+Vector3(0,0.72,0),1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
		var route=nav.path_between(global_position,floor)
		if route.is_empty() or route[-1].distance_to(floor)>1.0:continue
		var occupied=false
		for other in game.squad(team):
			if other!=self and other.alive and other.has_cover and other.cover_point.distance_to(floor)<2.3:occupied=true
		if occupied:continue
		var to_threat=(last_known-floor).normalized()
		var side=Vector3(-to_threat.z,0,to_threat.x)
		var peek=floor
		var can_peek=false

		# Try the cover itself, sidesteps of 1.3 and 2.3 m either side and a
		# step forward, looking for a position with a clear view of the threat.
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
		var distance=floor.distance_to(last_known)

		# An advancing soldier only takes cover that is at least 3 m closer to the threat.
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
	has_cover=valid_cover
	cover_point=chosen
	peek_point=chosen_peek

## Behavioural decision (called every 0.7-1.0 s): chooses `state` and
## `destination` from awareness, ammunition, suppression and role.
## Order of priority: unalerted idle -> out of ammunition (knife / search) ->
## sentry -> pinned or reloading (take cover) -> role behaviour:
## assault (advance, fire from the peek spot when within 13 m, or cover other
## squad members if not allowed to move), hold (stay in cover; dig in once,
## when far from the threat and quiet; peek periodically).
func decide():
	if not alerted:
		state="idle"
		destination=anchor
		return
	var dry=weapon_health<=0 or (rounds==0 and reserve_rounds==0)
	if dry:
		state="knife_assault" if visible_target else "searching"
		destination=last_known
		return

	# Cover chosen on an old nav graph may be invalid after destruction: re-pick.
	if cover_revision!=game.world.navigation.revision:has_cover=false
	if not has_cover:choose_cover(role=="assault" and suppressed==0)
	if sentry:
		state="firing" if visible_target else "investigating"
		destination=cover_point if suppressed>0 and has_cover else anchor
		return
	if suppressed>0 or reload_time>0:
		if not has_cover:choose_cover(false)
		state="taking_cover"
		destination=cover_point if has_cover else game.world.navigation.floor_point(global_position+global_basis.x*3)
		return
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

				# Flank offset: alternate soldiers shift 5 m to opposite sides of
				# the approach line, so assaulters do not queue behind one another.
				var approach=(last_known-global_position).normalized()
				var side=Vector3(-approach.z,0,approach.x)*(5 if index%2==0 else -5)
				destination=cover_point if has_cover else game.world.navigation.floor_point(last_known-approach*8+side)
		else:
			state="covering"
			destination=peek_point if has_cover and peek_point.distance_to(global_position)<3.5 else global_position
	else:
		state="holding"
		destination=cover_point if has_cover else anchor
		if has_cover and global_position.distance_to(cover_point)<1.6 and not dig_attempted and not close_sound and global_position.distance_to(last_known)>28:
			dig_attempted=true
			digging=5.5
		if visible_target or (memory>0 and int(clock*0.45+index)%3==0):
			state="peeking"
			destination=peek_point if has_cover else anchor

	# Lost the target: sweep a slowly rotating point around the last known position.
	if not visible_target and memory<=0 and role=="assault":
		state="searching"
		destination=game.world.navigation.floor_point(last_known+Vector3(sin(clock*0.3+index)*7,0,cos(clock*0.3+index)*7))

## Walks along the nav path toward `destination` with speed 3.7 m/s
## (assault/knife) or 2.9 m/s, jumps small ledges (steps over 0.22 m up),
## opens closed doors on the way, applies gravity and emits footstep sounds
## every 1.9 m of travel.
## [param delta] physics step in seconds.
func move_tactically(delta: float):
	var wanted=Vector3.ZERO
	var nav=game.world.navigation
	if digging<=0 and stagger==0 and destination.distance_to(global_position)>0.8:
		# Recompute at most every 1.1 s, or sooner when the world changed.
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
				# Horizontal-only steering toward the next waypoint (arrive within 0.5 m).
				wanted=flat.normalized()*(3.7 if role=="assault" or state=="knife_assault" else 2.9)
				if point.y-global_position.y>0.22 and is_on_floor():velocity.y=4.5
		if path_cursor>=path.size() and nav.line_clear(global_position,destination,0.7):
			var final_step=destination-global_position
			final_step.y=0
			if final_step.length()>0.8:wanted=final_step.normalized()*2.9
		var door=game.world.nearby_door(global_position+Vector3(0,1,0),2.5)
		if door and not door.opened:door.use()

	# Acceleration limit of 16 m/s^2 gives a quick but not instant start/stop.
	velocity.x=move_toward(velocity.x,wanted.x,16*delta)
	velocity.z=move_toward(velocity.z,wanted.z,16*delta)
	if not is_on_floor():velocity.y-=20*delta
	move_and_slide()
	moving=Vector2(velocity.x,velocity.z).length()>0.5
	if moving and is_on_floor():
		step_distance+=Vector2(velocity.x,velocity.z).length()*delta
		if step_distance>1.9:
			step_distance=0
			game.sounds.at("step",global_position,-10,0.95+index*0.018)

## Procedural animation: crouch (stance) in cover, leg swing while walking,
## flinch lean when staggered, turning toward the threat or direction of
## travel, and gun lowered when unalerted.
## [param delta] frame step in seconds.
func animate(delta: float):
	# Crouch when taking cover, digging, reloading or holding position unseen,
	# but only while not walking.
	var low=(state in ["taking_cover","digging","reloading"] or (state=="holding" and not visible_target)) and not moving
	stance=move_toward(stance,1.0 if low else 0.0,delta*5)
	capsule.shape.height=1.85-stance*0.50
	capsule.position.y=capsule.shape.height/2
	model.body.position.y=-stance*0.53
	for leg in model.legs:leg.rotation.x=stance*0.5
	if moving:
		model.legs[0].rotation.x=sin(clock*9)*0.5
		model.legs[1].rotation.x=-model.legs[0].rotation.x
	model.body.rotation.x=-stagger*0.4
	if alerted:
		var facing=last_known if not moving else global_position+Vector3(velocity.x,0,velocity.z)
		facing.y=global_position.y
		if facing.distance_to(global_position)>0.1:
			var desired=atan2(-(facing.x-global_position.x),-(facing.z-global_position.z))
			rotation.y=lerp_angle(rotation.y,desired,1-exp(-8*delta))

	# Unalerted soldiers slowly scan left and right (+-0.25 rad).
	else:rotation.y=PI+sin(clock*0.22+index)*0.25
	model.gun.rotation.x=lerpf(model.gun.rotation.x,0.0 if alerted else -0.48,delta*4)

## Fires one aimed round at target_actor if it is still visible.
## Spread (metres at the target): 0.12 + 0.007 per metre of range, x1.7 if the
## player is sprinting. The sentry's first shot is deliberately pushed 1.15 m
## sideways, a fair warning. Damage 12 (sentry) or 14 at 42 m/s; emits a
## 175 m noise that alerts everyone nearby; adds a visual recoil kick.
func shoot():
	if not alive or rounds<=0 or weapon_health<=0 or reload_time>0:return
	if not is_instance_valid(target_actor):target_actor=game.player if team==0 else null
	if not target_is_alive(target_actor) or not can_see(target_actor):return
	rounds-=1
	shots_fired+=1
	cooldown=rng.randf_range(2.7,4.1)
	var origin=eye_position()-Vector3(0,0.08,0)
	var target=target_eye(target_actor)-Vector3(0,0.17,0)
	var distance=origin.distance_to(target)
	var spread=0.12+distance*0.007
	if target_actor==game.player and target_actor.is_sprinting:spread*=1.7
	target+=Vector3(rng.randfn(0,spread),rng.randfn(0,spread*0.60),rng.randfn(0,spread))
	if sentry and shots_fired==1:target+=global_basis.x*1.15
	game.fire_projectile(origin,target,self,12 if sentry else 14,42)
	muzzle.show()
	get_tree().create_timer(0.06).timeout.connect(func():if is_instance_valid(muzzle):muzzle.hide())
	game.sounds.at("rifle",origin,-2)
	game.emit_noise(origin,175,team,"gunshot")
	model.gun.position.z=-0.38
	create_tween().tween_property(model.gun,"position:z",-0.43,0.28)

## Knife attack on target_actor (needs sight). 24 damage to the player, 35 to
## AI soldiers, with a 1.1 s cooldown and a stab animation.
func melee():
	if not target_is_alive(target_actor) or not can_see(target_actor):return
	cooldown=1.1
	game.sounds.at("sword",global_position,-12)
	knife.rotation.x=-1.3
	create_tween().tween_property(knife,"rotation:x",0,0.35)
	if target_actor==game.player:target_actor.take_damage(24,global_position,"melee")
	else:target_actor.take_damage(35)

## Machine-gun behaviour: walk to the gunner position, claim the nest, hide
## personal weapons, aim at the last known position and fire when a target is
## visible and not suppressed. Gives up the gun if the nest becomes unusable.
## [param delta] physics step in seconds.
func operate_mg(delta: float):
	var nest=game.mg_nest
	destination=nest.operator_position()
	state="manning_mg"
	if global_position.distance_to(destination)>1.0:
		move_tactically(delta)
		return
	if not nest.claim(self):
		role="hold"
		return
	mounted=true
	moving=false
	velocity=Vector3.ZERO
	model.gun.hide()
	weapon_hitbox.set_active(false)
	knife.hide()
	shovel.hide()
	nest.track(last_known)
	if visible_target and suppressed<1.6 and target_is_alive(target_actor):nest.try_fire(target_eye(target_actor))
	if not nest.usable():dismount()

## Leaves the machine gun: releases the nest, returns to the "hold" role at
## the current position and shows the rifle again.
func dismount():
	if game.mg_nest:game.mg_nest.release(self)
	mounted=false
	role="hold"
	anchor=global_position
	has_cover=false
	decision_timer=0
	model.gun.visible=weapon_health>0
	weapon_hitbox.set_active(model.gun.visible)

## Called by the rifle's Equipment hit area. At 0 weapon health the rifle is
## ruined: it is hidden, and loaded rounds are added to the reserve so that
## loot on the corpse remains correct.
## [param _item] always the rifle. [param amount] damage points.
func receive_equipment_damage(_item: String, amount: float):
	weapon_health=maxf(0,weapon_health-amount)
	if weapon_health<=0:
		model.gun.hide()
		weapon_hitbox.set_active(false)
		# Loaded cartridges stay with the corpse even when the rifle is ruined.
		reserve_rounds+=rounds
		rounds=0
		reload_time=0
		decision_timer=0
	game.sounds.at("clang",global_position,-8)

## Applies damage from the player or another AI.
## [param amount] hit points. [param headshot] true doubles the damage.
## Staggers 0.55 s, alerts the soldier, and plays the hit sound. Death at 0.
func take_damage(amount: float, headshot: bool=false):
	if not alive:return
	health-=amount*(2.0 if headshot else 1.0)
	stagger=0.55
	alerted=true
	game.sounds.at("hit",global_position,-7)
	if health<=0:die()
	else:
		# Impact direction is a clue, not a through-wall sight fix.
		hear_noise(game.player.global_position,"impact")

## Kills the soldier: disables collision, releases the machine gun if manning
## it, topples the model with a quad-eased 0.45 s fall and, for team 0, tells
## the game (enemy_down) so objectives and loot update.
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
