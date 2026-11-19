## One bazooka team on the American side at Omaha: a launcher with six rockets
## shared by a carrier (fires), a loader (reloads, 6.8 s) and a recoverer
## who picks up the launcher if the carrier dies.
##
## Role: created by omaha/battle.gd, which calls tick() every physics step. The
## team does not spawn soldiers: it recruits eligible friendly infantry,
## dynamically, by setting their `bazooka_team` / `loader_for` fields, and
## commands them through command(), which the actor's think() consults.
## Rules (from the file's design note): one owner and one exclusive helper
## per finite launcher; no remote or automatic reloads (the loader must stand within 2.8 m); a dropped launcher
## stays on the ground until another soldier walks to it.
## Targets are Panzer IVs (`game.tanks`) between 12 and 185 m.
extends Node3D
# A single owner and a single exclusive helper lease per finite launcher.
const Kit=preload("res://scripts/ardennes/weapons.gd")

## The Omaha battle controller.
var game

## Team number (identifies the loader/recoverer links on actors).
var index:int=0

## The soldier carrying and firing the launcher, or null.
var carrier

## Helper who reloads, or null.
var loader

## Soldier walking to pick up a dropped launcher, or null.
var recoverer

## The bazooka model.
var launcher:Node3D

## Ground position of the launcher after its carrier died; INF when carried.
var dropped_at=Vector3.INF

## Rockets left (6, finite).
var rockets:int=6

## Whether a rocket is in the launcher.
var loaded:bool=true

## Seconds of the current reload (completes at 6.8).
var reload_progress:float=0

## Countdown to the next decision (0.40-0.50 s).
var decision_clock:float=0

## Tank currently chosen.
var target

## True while the launcher is shouldered (1.25 s after choosing a shot).
var aiming:bool=false

## Time at which aiming ends.
var aim_until:float=0

## Position the carrier should move to for a clear and safe shot, or INF.
var firing_position=Vector3.INF

## Rockets fired (statistic).
var shots:int=0

## Times a new carrier picked up the launcher.
var recoveries:int=0

## Times a loader was recruited.
var loader_changes:int=0

## Godot lifecycle hook: builds the bazooka model and slings it on the carrier; physics processing is off because the controller calls tick().
func _ready():
	launcher=Kit.weapon(self,"bazooka")
	attach_launcher()
	set_physics_process(false)

## True if `actor` is alive, in play, not in a truck or boat.
func active(actor)->bool:
	return is_instance_valid(actor) and actor.alive and not actor.staged and actor.truck==null and actor.boat==null

## True if `actor` can join: an active US soldier who is not an engineer still carrying a bangalore (unless already past z = -186), not already in a team, and not a driver or gunner.
func eligible(actor)->bool:
	return active(actor) and actor.team==1 and (actor.bangalores==0 or actor.position.z< -186) and actor.bazooka_team<0 and actor.loader_for<0 and actor.role not in ["driver","gunner"]

## Attaches the launcher model to the carrier (slung on the back) and clears the dropped position.
func attach_launcher():
	if carrier==null:return
	launcher.reparent(carrier,false)
	launcher.position=Vector3(-0.30,1.03,0.30)
	launcher.rotation=Vector3(-1.23,0,-0.12)
	launcher.scale=Vector3.ONE
	dropped_at=Vector3.INF

## Frees the loader's link to this team.
func release_loader():
	if is_instance_valid(loader) and loader.loader_for==index:loader.loader_for=-1
	loader=null

## When the carrier dies: leaves the launcher on the ground where he fell, clears the aim state and frees the loader.
func lose_carrier():
	if carrier==null:return
	dropped_at=game.world.on_ground(carrier.position)+Vector3(0,0.15,0)
	carrier.bazooka_team=-1
	launcher.reparent(game,false)
	launcher.position=dropped_at
	launcher.rotation=Vector3(0,carrier.rotation.y,0.13)
	carrier=null
	target=null
	aiming=false
	reload_progress=0
	release_loader()

## Returns the nearest eligible friendly soldier to `point` within `radius`, or null.
func nearest_eligible(point:Vector3,radius:float):
	var nearest=null
	var best=radius*radius
	for actor in game.friendlies:
		if not eligible(actor):continue
		var d=actor.position.distance_squared_to(point)
		if d<best:
			best=d
			nearest=actor
	return nearest

## Per-physics-step update: cleans up dead helpers, advances the reload when the loader stands at the carrier, poses the launcher (shouldered or slung) and, on a 0.4 s timer, makes decisions: recover a dropped launcher, recruit a loader, pick a tank, check a clear and safe line, then fire through game.launch_heavy with 90 m/s lead on the target.
## [param delta] physics step in seconds.
func tick(delta:float):
	if carrier!=null and not carrier.alive:lose_carrier()
	if loader!=null and (not active(loader) or loader.loader_for!=index):release_loader()
	if recoverer!=null and not active(recoverer):
		if recoverer.bazooka_team==index:recoverer.bazooka_team=-1
		recoverer=null
	if carrier!=null and active(carrier):
		# A loader must actually reach the carrier; no remote or automatic reloads.
		if not loaded and rockets>0 and active(loader) and loader.position.distance_to(carrier.position)<2.8:
			reload_progress+=delta
			if reload_progress>=6.8:
				loaded=true
				reload_progress=0
		if aiming and game.elapsed>aim_until:aiming=false
		launcher.position=Vector3(-0.22,1.43,-0.02) if aiming else Vector3(-0.30,1.03,0.30)
		launcher.rotation=Vector3.ZERO if aiming else Vector3(-1.23,0,-0.12)
		if aiming and is_instance_valid(target):launcher.look_at(target.aim_point(),Vector3.UP)
	decision_clock-=delta
	if decision_clock>0:return
	decision_clock=0.4+float(index%3)*0.05
	if carrier==null:
		if rockets<=0 or dropped_at==Vector3.INF:return
		if recoverer==null:
			recoverer=nearest_eligible(dropped_at,45)
			if recoverer!=null:recoverer.bazooka_team=index
		if recoverer!=null and recoverer.position.distance_squared_to(dropped_at)<3:
			carrier=recoverer
			recoverer=null
			recoveries+=1
			attach_launcher()
		return
	if not active(carrier):return
	if loader==null and rockets>0:
		loader=nearest_eligible(carrier.position,32)
		if loader!=null:
			loader.loader_for=index
			loader_changes+=1
	target=select_tank()
	firing_position=Vector3.INF
	if target==null or not loaded or rockets<=0 or carrier.grenade_throw_time>0:return
	var aim=target.aim_point()
	var from=carrier.position+Vector3(0,1.42,0)
	var direction=(aim-from).normalized()

	# If the carrier's back-blast would hit a friend or a wall, move to another position instead of firing.
	if not safe_backblast(from,direction):
		firing_position=find_firing_position(target)
		return
	var q=PhysicsRayQueryParameters3D.create(from+direction*0.7,aim,1|2|4|8)
	q.exclude=[carrier.get_rid()]
	var hit=get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.collider.get("tank_owner")!=target:
		firing_position=find_firing_position(target)
		return
	carrier.rotation.y=atan2(-direction.x,-direction.z)
	carrier.state="fire"
	carrier.stance="stand"
	carrier.velocity=Vector3.ZERO
	aiming=true
	aim_until=game.elapsed+1.25
	launcher.position=Vector3(-0.22,1.43,-0.02)
	launcher.look_at(aim,Vector3.UP)
	var muzzle=launcher.get_node("Muzzle").global_position
	game.launch_heavy(carrier,muzzle,aim+target.velocity*(from.distance_to(aim)/90.0),"bazooka")
	carrier.last_fired=game.elapsed
	carrier.shot_clock=maxf(carrier.shot_clock,1.3)
	shots+=1
	rockets-=1
	loaded=false
	reload_progress=0

## Chooses the nearest tank (between 12 m and 185 m) that the carrier or the loader can see; a helper may spot armour while the carrier is behind cover.
func select_tank():
	var chosen=null
	var best=185.0*185.0
	for tank in game.tanks:
		if not tank.alive:continue
		var d=carrier.position.distance_squared_to(tank.position)
		if d>=best or d<12*12:continue
		# The helper can spot armour while the carrier is behind nearby cover.
		for observer in [carrier,loader]:
			if not active(observer):continue
			if sees_tank(observer.eye(),tank,[observer.get_rid()]):
				chosen=tank
				best=d
				break
	return chosen

## True if a ray from `from` to the tank's aim point hits the tank first.
func sees_tank(from:Vector3,tank,exclude:Array[RID])->bool:
	var q=PhysicsRayQueryParameters3D.create(from,tank.aim_point(),1|2|4|8)
	q.exclude=exclude
	var hit=get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider.get("tank_owner")==tank

## Searches 3, 6 and 10 m to either side of the carrier for a position that is outside houses, has a clear view of the tank and a safe back-blast; returns INF when none.
func find_firing_position(tank)->Vector3:
	var toward=tank.position-carrier.position
	toward.y=0
	toward=toward.normalized()
	var side=toward.cross(Vector3.UP)
	for distance in [3.0,-3.0,6.0,-6.0,10.0,-10.0]:
		var candidate=game.world.on_ground(carrier.position+side*distance)
		if game.world.houses.any(func(h):return not h.collapsed and h.contains(candidate,0.6)):continue
		var from=candidate+Vector3(0,1.42,0)
		var direction=(tank.aim_point()-from).normalized()
		if sees_tank(from,tank,[carrier.get_rid()]) and safe_backblast(from,direction):return candidate
	return Vector3.INF

## True if nobody within about 6.5 m stands behind the launcher (dot of their direction with the back-blast axis above 0.86) and the rear is not blocked by a wall within 3 m.
func safe_backblast(from:Vector3,direction:Vector3)->bool:
	for actor in game.friendlies+[game.player]:
		if actor==carrier or not game.actor_alive(actor) or actor.position.distance_squared_to(from)>42:continue
		var offset=game.actor_aim(actor)-from
		if offset.length()>0.1 and offset.normalized().dot(-direction)>0.86:return false
	var q=PhysicsRayQueryParameters3D.create(from,from-direction*3.0,1)
	q.exclude=[carrier.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Called by an actor's think() to see whether the team wants to control it: sends the recoverer to the launcher, positions the loader beside the carrier, moves the carrier to the firing position, or keeps it aiming. Returns true if it took control.
func command(actor)->bool:
	if actor==recoverer:
		actor.state="advance"
		actor.stance="stand"
		actor.set_destination(dropped_at)
		return true
	if actor==loader and active(carrier):
		var side=carrier.global_basis.x*1.85+carrier.global_basis.z*0.6
		var point=carrier.position+side
		if actor.position.distance_to(point)>0.6:
			actor.state="advance"
			actor.stance="stand"
			actor.set_destination(point)
		else:
			actor.state="fire" if actor.target!=null else "cover"
			actor.stance=carrier.stance
		return true
	if actor==carrier and firing_position!=Vector3.INF:
		actor.state="advance"
		actor.stance="stand"
		actor.set_destination(firing_position)
		return true
	if actor==carrier and (aiming or (target!=null and not loaded and rockets>0)):
		actor.state="fire" if actor.target!=null else "cover"
		actor.stance="stand" if aiming else "crouch"
		return true
	return false

## Frees the launcher model.
func _exit_tree():
	if is_instance_valid(launcher):launcher.queue_free()
