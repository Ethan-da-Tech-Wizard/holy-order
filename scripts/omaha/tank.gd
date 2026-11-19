## A German Panzer IV defending the Omaha village: procedural model, patrol and
## pursuit AI, cannon and machine gun, and a damage model of two tracks and a hull.
##
## Role: three are created by omaha/battle.gd (`game`, `index` set before
## _ready), which calls tick() each physics step once the town is active
## (`game.town_active`). The tank moves along the town streets using
## game.world.tank_route, picks targets with line of sight, turns its turret,
## fires an HE shell every 7.8 s (32 rounds) and a coaxial MG34 in 10-round bursts.
## Damage: bullets cannot hurt the hull (damage_at only dents the tracks), blasts
## damage tracks (receive_blast), bazooka rockets hurt the hull (hit_rocket:
## 92 frontal, 150 side, 180 rear of 420 hit points) and can knock out tracks (240 of 460).
## A tank with a broken track can no longer move (mobile()). Collapsing houses hurt it too (hull_damage).
## Layers: 1 (world) + 128 (vehicles); collision mask 1.
extends CharacterBody3D
const Art=preload("res://scripts/art.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")
const Part=preload("res://scripts/omaha/tank_part.gd")
const Layout=preload("res://scripts/omaha/layout.gd")

## The Omaha battle controller.
var game

## Tank number 0..2; staggers timers and picks a patrol column.
var index:int=0

## 0, German.
var team:int=0

## False once the hull is destroyed.
var alive:bool=true

## Points to itself so shared "owner" lookups on hit parts work for tanks too.
var tank_owner

## Hull hit points (420).
var health:float=420

## Hit points of the left and right tracks (460 each); either at 0 immobilises the tank.
var tracks:Array[float]=[460,460]

## Turret node; rotates independently of the hull.
var turret:Node3D

## Marker at the gun muzzle where shells and bullets start.
var muzzle:Marker3D

## Placeholder hit area so shared code that expects `equipment` works; no collision.
var equipment:Area3D

## Current enemy actor, or null.
var target

## Last place a target was seen (INF if none).
var remembered:Vector3=Vector3.INF

## Time until which `remembered` is trusted (8 s).
var memory_until:float=0

## Game time of the last cannon shot.
var last_fired:float=-999

## Seconds until the cannon can fire again.
var cannon_clock:float=2

## Shells left (32).
var cannon_rounds:int=32

## Seconds until the machine gun can fire again.
var mg_clock:float=0

## MG rounds left (1600).
var mg_rounds:int=1600

## Rounds fired in the current burst.
var mg_burst:int=0

## Countdown to the next target and route decision (0.8 s plus a stagger).
var decision_clock:float=0

## Route waypoints along streets.
var route:PackedVector3Array=[]

## Index of the waypoint being approached.
var route_cursor:int=0

## Goal the route was planned for.
var route_goal:Vector3=Vector3.INF

## Physics RIDs of the tank and its parts, excluded from the tank's own rays.
var rids:Array[RID]=[]

## Hull visual node.
var model:Node3D

## Seconds until a new patrol destination is picked (18).
var patrol_clock:float=0

## Cannon shots fired (statistic).
var shots:int=0

## Weapon spec used by shared AI helpers: range 290 m.
var spec={"range":290.0}

## Actor instance id -> time until which that actor stays remembered.
var memory:Dictionary={}

## Always false (so shared code treats a tank as not manning a gun).
var mounted:bool=false

## Unused facing for shared code.
var mount_facing=Vector3.BACK

## Unused traverse arc for shared code.
var mount_arc:float=PI

## Godot lifecycle hook: builds the tank from boxes and cylinders (hull, tracks with road wheels and cleats, schurzen side skirts, turret with long gun and muzzle brake, hatch), track hit parts and the turret hit part, then bakes the visuals into one mesh per node.
func _ready():
	tank_owner=self
	collision_layer=1|128
	collision_mask=1
	floor_snap_length=0.5
	rotation.y=PI
	model=Node3D.new()
	add_child(model)
	var tan=Art.material(Color("8c8658"),0.25,0.8)
	var dark=Art.material(Color("34382f"),0.4,0.8)
	var green=Art.material(Color("5e6449"),0.1,0.9)
	var brown=Art.material(Color("665246"),0.1,0.9)
	var rubber=Art.material(Color("242823"))
	Art.box(model,Vector3(2.7,0.95,5.5),Vector3(0,1.03,0),tan)
	Art.box(model,Vector3(2.6,0.55,3.7),Vector3(0,1.75,0.25),tan)
	for side in [-1,1]:
		Art.box(model,Vector3(0.56,0.92,5.8),Vector3(side*1.43,0.57,0),dark)
		for i in range(8):
			var wheel=Art.cylinder(model,0.34,0.60,Vector3(side*1.43,0.60,-2.25+i*0.64),rubber,-1,10)
			wheel.rotation.z=PI/2
			var hub=Art.cylinder(model,0.18,0.64,Vector3(side*1.43,0.60,-2.25+i*0.64),tan,-1,8)
			hub.rotation.z=PI/2
		for i in range(5):
			Art.box(model,Vector3(0.055,0.98,1.0),Vector3(side*1.83,1.24,-2.05+i*1.03),green if i%3==0 else tan)
		for i in range(19):
			Art.box(model,Vector3(0.62,0.09,0.14),Vector3(side*1.43,1.055,-2.75+i*0.3),dark)
		Art.segment(model,Vector3(side*1.6,1.6,-2.6),Vector3(side*1.6,1.6,2.6),0.06,tan)
		part_shape(self,Vector3(side*1.43,0.57,0),Vector3(0.6,1.0,5.8),0 if side<0 else 1)
	for i in range(9):
		Art.box(model,Vector3(0.07,0.32,0.72),Vector3(1.36,1.35,-2.2+i*0.55),green if i%2 else brown)
		Art.box(model,Vector3(0.07,0.3,0.72),Vector3(-1.36,1.35,-2.1+i*0.54),brown if i%2 else green)
	for x in [-0.7,0.7]:
		Art.box(model,Vector3(0.8,0.10,1.0),Vector3(x,2.05,1.9),dark)
		Art.cylinder(model,0.12,0.18,Vector3(x,1.62,-2.8),dark,-1,8).rotation.x=PI/2
	Art.cylinder(model,0.16,1.5,Vector3(0,0.9,2.9),dark,-1,10).rotation.z=PI/2
	var shape=CollisionShape3D.new()
	shape.shape=BoxShape3D.new()
	shape.shape.size=Vector3(2.65,1.35,5.5)
	shape.position=Vector3(0,1.28,0)
	add_child(shape)
	turret=Node3D.new()
	add_child(turret)
	turret.position=Vector3(0,1.92,-0.25)
	Art.cylinder(turret,1.0,0.82,Vector3(0,0.38,0),tan,0.84,8)
	Art.box(turret,Vector3(1.25,0.7,1.3),Vector3(0,0.40,0.05),tan)
	for side in [-1,1]:
		Art.box(turret,Vector3(0.05,0.62,1.8),Vector3(side*1.08,0.48,0.10),green if side<0 else tan)
		Art.box(turret,Vector3(0.015,0.25,0.08),Vector3(side*1.12,0.48,0),dark)
		Art.box(turret,Vector3(0.015,0.08,0.3),Vector3(side*1.12,0.48,0),dark)
	Art.cylinder(turret,0.35,0.35,Vector3(-0.28,0.97,0.42),tan,-1,10)
	Art.box(turret,Vector3(0.78,0.52,0.35),Vector3(0,0.4,-0.98),tan)
	Art.cylinder(turret,0.072,3.6,Vector3(0,0.43,-2.65),tan,-1,10).rotation.x=PI/2
	Art.cylinder(turret,0.12,0.26,Vector3(0,0.43,-4.48),dark,-1,10).rotation.x=PI/2
	for side in [-1,1]:Art.box(turret,Vector3(0.015,0.12,0.09),Vector3(side*0.12,0.43,-4.48),rubber)
	Art.cylinder(turret,0.023,0.55,Vector3(0.44,0.35,-1.22),dark,-1,8).rotation.x=PI/2
	part_shape(turret,Vector3(0,0.40,0),Vector3(1.85,0.88,1.9),-1)
	muzzle=Marker3D.new()
	turret.add_child(muzzle)
	muzzle.position=Vector3(0,0.43,-4.67)
	equipment=Area3D.new()
	equipment.collision_layer=0
	add_child(equipment)
	bake_visuals(model)
	bake_visuals(turret)
	rids.append(get_rid())
	set_physics_process(false)

## Adds a collision part (tank_part.gd) to `parent`: a box of `size` at `p`. `side` is 0 or 1 for a track, -1 for armour. The tank and part ignore each other's collision.
func part_shape(parent:Node3D,p:Vector3,size:Vector3,side:int):
	var part=Part.new()
	part.tank_owner=self
	part.track_side=side
	part.collision_layer=1|128
	parent.add_child(part)
	part.position=p
	var shape=CollisionShape3D.new()
	shape.shape=BoxShape3D.new()
	shape.shape.size=size
	part.add_child(shape)
	rids.append(part.get_rid())
	add_collision_exception_with(part)
	part.add_collision_exception_with(self)

## Merges the meshes under `root` into one baked mesh, so the tank is a couple of draw calls.
func bake_visuals(root:Node3D):
	var mesh=MeshInstance3D.new()
	mesh.mesh=Kit.bake(root)
	for child in root.get_children():
		if child is MeshInstance3D:child.free()
	root.add_child(mesh)

## World position of the commander's eyes (2.95 m up), where sight rays start.
func eye()->Vector3:return global_position+Vector3(0,2.95,0)

## World position enemies aim at (1.4 m up on the hull).
func aim_point()->Vector3:return global_position+Vector3(0,1.4,0)

## RIDs that the tank's own shots ignore.
func shot_exclusions()->Array[RID]:return rids

## True if the tank is alive and both tracks are working.
func mobile()->bool:return alive and tracks[0]>0 and tracks[1]>0

## Per-physics-step AI: every 0.8 s picks a target and plans a route (toward a
## remembered enemy within 50 m or a random street patrol point, then drives), then
## turns the turret at 0.85 rad/s and fires when aligned (within 0.08 rad) with a clear line:
## HE shell with a 160 m/s lead when the target is more than 15 m away, and the MG in 10-round bursts at 0.075 s intervals then a 1.2 s pause.
## [param delta] physics step in seconds.
func tick(delta:float):
	if not alive or not game.town_active:return
	cannon_clock=maxf(0,cannon_clock-delta)
	mg_clock=maxf(-delta,mg_clock-delta)
	decision_clock-=delta
	patrol_clock-=delta
	if decision_clock<=0:
		decision_clock=0.8+index*0.08
		choose_target()
		if target!=null:
			remembered=target.position
			memory_until=game.elapsed+8
			if position.distance_to(remembered)>50:
				plan_route(Vector3(game.world.closest_road_x(remembered.x),Layout.TOWN_GROUND,clampf(game.world.closest_road_z(remembered.z),Layout.TOWN_BACK,Layout.TOWN_FRONT-8)))
		elif patrol_clock<=0:
			patrol_clock=18
			var x=clampf((index-1)*76+[-38,0,38][randi()%3],-152,152)
			var z=[-498,-452,-408,-358][randi()%4]
			if memory_until>game.elapsed:
				x=game.world.closest_road_x(remembered.x)
				z=clampf(game.world.closest_road_z(remembered.z),-520,-358)
			plan_route(Vector3(x,Layout.TOWN_GROUND,z))
	move_tank(delta)
	if target==null or not game.actor_alive(target):return
	var aim=game.actor_aim(target)
	var offset=aim-turret.global_position
	var desired=atan2(-offset.x,-offset.z)
	turret.global_rotation.y=lerp_angle(turret.global_rotation.y,desired,delta*0.85)
	if absf(angle_difference(turret.global_rotation.y,desired))>0.08:return
	if not clear_shot(muzzle.global_position,aim,target):return
	if cannon_clock<=0 and cannon_rounds>0 and offset.length()>15:
		game.launch_heavy(self,muzzle.global_position,aim+target.velocity*(offset.length()/160.0),"tank_shell")
		cannon_clock=7.8
		cannon_rounds-=1
		shots+=1
		last_fired=game.elapsed
	if mg_clock<=0 and mg_rounds>0:
		game.shoot(self,muzzle.global_position,aim,0.021,46,"mg34")
		mg_rounds-=1
		mg_burst+=1
		mg_clock+=0.075
		if mg_burst>=10:
			mg_clock=1.2
			mg_burst=0

## Chooses the nearest of up to 12 candidate attackers (or the player) that lie north of z = -326, within 290 m, detected by game.can_detect and visible; remembers that target for 8 s.
func choose_target():
	target=null
	var candidates=[]
	for actor in game.active_attackers+[game.player]:
		if not game.actor_alive(actor) or actor.position.z> -326:continue
		if position.distance_squared_to(actor.position)>290*290:continue
		if not game.can_detect(self,actor):continue
		candidates.append(actor)
	candidates.sort_custom(func(a,b):return position.distance_squared_to(a.position)<position.distance_squared_to(b.position))
	for actor in candidates.slice(0,12):
		if clear_shot(eye(),game.actor_aim(actor),actor):
			target=actor
			memory[actor.get_instance_id()]=game.elapsed+8
			return

## True if no obstacle lies between `from` and `to` except `actor` itself.
func clear_shot(from:Vector3,to:Vector3,actor)->bool:
	var q=PhysicsRayQueryParameters3D.create(from,to,1|2|4|8)
	q.exclude=rids
	var hit=get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider==actor

## Computes a street route to `goal` unless immobile or already heading to a goal within 2 m.
func plan_route(goal:Vector3):
	if not mobile() or route_goal.distance_squared_to(goal)<4:return
	route_goal=goal
	route=game.world.tank_route(position,goal)
	route_cursor=0

## Drives along the route: turns the hull at 1.1 rad/s, moves at 3.2 m/s when roughly facing the way (otherwise 0.5), applies gravity and sliding, and clamps to the town's boundaries and ground height. Does nothing if immobile.
## [param delta] physics step in seconds.
func move_tank(delta:float):
	if not mobile():
		velocity=Vector3.ZERO
		return
	while route_cursor<route.size() and Vector2(position.x-route[route_cursor].x,position.z-route[route_cursor].z).length()<0.9:route_cursor+=1
	var direction=Vector3.ZERO
	if route_cursor<route.size():
		direction=route[route_cursor]-position
		direction.y=0
		direction=direction.normalized()
	var desired=atan2(-direction.x,-direction.z)
	if direction.length_squared()>0.1:rotation.y=lerp_angle(rotation.y,desired,delta*1.1)
	var speed=3.2 if absf(angle_difference(rotation.y,desired))<0.25 else 0.5
	velocity.x=direction.x*speed
	velocity.z=direction.z*speed
	if not is_on_floor():velocity.y-=20*delta
	move_and_slide()
	position.x=clampf(position.x,-152,152)
	position.z=clampf(position.z,Layout.TOWN_BACK,Layout.TOWN_FRONT)
	position.y=maxf(position.y,game.world.surface_height(position.x,position.z)+0.03)

## Bullets and fragments: hits on the track area damage that track by 2.5% of the amount; everything else is stopped by the armour.
func damage_at(amount:float,point:Vector3,_radius:float=0.2,_explosive:bool=false)->bool:
	var p=to_local(point)
	if absf(p.x)>1.12 and p.y<1.04:hit_track(0 if p.x<0 else 1,amount*0.025)
	return true # Rifle fire stops at the armour; it cannot drain hull health.

## Reduces a track's hit points (clamped at 0).
## [param side] 0 left, 1 right. [param amount] damage.
func hit_track(side:int,amount:float):
	if not alive:return
	tracks[side]=maxf(0,tracks[side]-maxf(0,amount))

## Explosion damage to tracks: each track takes damage reduced by distance (power 1.2) and by kind (grenade and mine 55%, others 85%).
## [param point] blast centre. [param radius] blast radius. [param damage] damage at the centre. [param kind] blast kind.
func receive_blast(point:Vector3,radius:float,damage:float,kind:String):
	if not alive:return
	for side in range(2):
		var track_point=to_global(Vector3(-1.43 if side==0 else 1.43,0.55,clampf(to_local(point).z,-2.8,2.8)))
		var distance=point.distance_to(track_point)
		if distance<radius:
			var multiplier=0.55 if kind in ["grenade","mine"] else 0.85
			hit_track(side,damage*multiplier*pow(1-distance/radius,1.2))

## A bazooka rocket hit: hull damage depends on the angle (frontal 92, rear 180, side 150) and a track hit if the impact was low at the side (240).
func hit_rocket(point:Vector3):
	if not alive:return
	var local=to_local(point)
	var frontal=local.z< -1.8 and absf(local.x)<1.15
	var damage=92 if frontal else (180 if local.z>1.7 else 150)
	hull_damage(damage,point)
	if absf(local.x)>1.1 and local.y<1.2:hit_track(0 if local.x<0 else 1,240)

## Applies hull damage; at zero hit points the tank is destroyed: stops, is darkened as a burnt wreck, explodes (7 m / 170 damage) and shows a toast.
## [param amount] hit points. [param point] impact position.
func hull_damage(amount:float,point:Vector3):
	if not alive:return
	health=maxf(0,health-amount)
	if health>0:return
	alive=false
	velocity=Vector3.ZERO
	var burnt=Art.material(Color("30352e"),0.25,1)
	for visual in find_children("*","MeshInstance3D",true,false):visual.material_override=burnt
	game.explode(point,7,170,self,"tank_wreck")
	game.toast("PANZER IV DESTROYED",3)
