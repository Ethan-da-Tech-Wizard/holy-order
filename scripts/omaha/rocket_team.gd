extends Node3D
# A single owner and a single exclusive helper lease per finite launcher.
const Kit=preload("res://scripts/ardennes/weapons.gd")
var game
var index:int=0
var carrier
var loader
var recoverer
var launcher:Node3D
var dropped_at=Vector3.INF
var rockets:int=6
var loaded:bool=true
var reload_progress:float=0
var decision_clock:float=0
var target
var aiming:bool=false
var aim_until:float=0
var firing_position=Vector3.INF
var shots:int=0
var recoveries:int=0
var loader_changes:int=0

func _ready():
	launcher=Kit.weapon(self,"bazooka")
	attach_launcher()
	set_physics_process(false)

func active(actor)->bool:
	return is_instance_valid(actor) and actor.alive and not actor.staged and actor.truck==null and actor.boat==null

func eligible(actor)->bool:
	return active(actor) and actor.team==1 and (actor.bangalores==0 or actor.position.z< -186) and actor.bazooka_team<0 and actor.loader_for<0 and actor.role not in ["driver","gunner"]

func attach_launcher():
	if carrier==null:return
	launcher.reparent(carrier,false)
	launcher.position=Vector3(-0.30,1.03,0.30)
	launcher.rotation=Vector3(-1.23,0,-0.12)
	launcher.scale=Vector3.ONE
	dropped_at=Vector3.INF

func release_loader():
	if is_instance_valid(loader) and loader.loader_for==index:loader.loader_for=-1
	loader=null

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

func sees_tank(from:Vector3,tank,exclude:Array[RID])->bool:
	var q=PhysicsRayQueryParameters3D.create(from,tank.aim_point(),1|2|4|8)
	q.exclude=exclude
	var hit=get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider.get("tank_owner")==tank

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

func safe_backblast(from:Vector3,direction:Vector3)->bool:
	for actor in game.friendlies+[game.player]:
		if actor==carrier or not game.actor_alive(actor) or actor.position.distance_squared_to(from)>42:continue
		var offset=game.actor_aim(actor)-from
		if offset.length()>0.1 and offset.normalized().dot(-direction)>0.86:return false
	var q=PhysicsRayQueryParameters3D.create(from,from-direction*3.0,1)
	q.exclude=[carrier.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

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

func _exit_tree():
	if is_instance_valid(launcher):launcher.queue_free()
