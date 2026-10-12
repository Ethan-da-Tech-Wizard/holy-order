extends SceneTree
var g
var checks=[]
func _initialize():call_deferred("run")
func check(label:String,ok:bool,data=null):
	checks.append({"check":label,"ok":ok,"data":data})
	print("PASS " if ok else "FAIL ",label," ",data if data!=null else "")
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for a in g.actors:a.set_physics_process(false)
	var reserve=g.friendlies.filter(func(a):return a.wave==1)
	check("All 600 reserves sleep with disabled collision until release",reserve.size()==600 and reserve.all(func(a):return a.staged and a.shape.disabled and a.collision_layer==0 and not a.is_physics_processing()))
	check("Every boat has three engineers spread through its file",g.boats.all(func(b):return b.occupants.filter(func(a):return a.bangalores==3).size()==3))
	var lanes={}
	for a in g.friendlies:
		if a.truck!=null:lanes[a.lane]=true
	check("Twenty separate breach lanes within a 228-metre landing front",lanes.size()==20 and is_equal_approx(g.boats[19].lane_x-g.boats[0].lane_x,228))
	var reserve_separation=INF
	for t in range(0,120,2):
		for boat in g.boats.slice(20):boat.update_course(t)
		for i in range(20,39):reserve_separation=minf(reserve_separation,g.boats[i].position.distance_to(g.boats[i+1].position))
	check("Circling reserves keep hulls separated",reserve_separation>=11.99,reserve_separation)
	var terrain_matches=0
	var error=0.0
	for x in range(-270,271,17):
		for z in range(-510,100,23):
			var p=Vector3(x+0.37,g.world.surface_height(x+0.37,z+0.69),z+0.69)
			var hit=g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3(0,3,0),p-Vector3(0,3,0),1))
			if not hit.is_empty() and hit.collider.get("material_kind")=="soil":
				terrain_matches+=1
				error=maxf(error,absf(hit.position.y-p.y))
	check("Terrain collision agrees with rendered height",terrain_matches>600 and error<0.02,{"samples":terrain_matches,"max_error":error})
	# Keep enemy fire and grenade avoidance out of this routing fixture.
	for a in g.actors:
		a.staged=true
		a.collision_layer=0
		a.equipment.collision_layer=0
	g.player.collision_layer=0
	g.player.position=Vector3(1100,80,0)
	g.rebuild_spatial()
	var carrier=g.friendlies.filter(func(a):return a.bangalores>0)[0]
	carrier.staged=false
	carrier.truck=null
	carrier.boat=null
	carrier.lane=-90
	carrier.position=g.world.on_ground(Vector3(carrier.lane,0,-89))
	carrier.grenades=0
	var wire=g.world.blocking_wire(carrier.position,carrier.lane)
	var distant=g.world.blocking_wire(carrier.position,carrier.lane+64)
	distant.breach()
	carrier.think(10)
	check("Engineer approaches intact wire ahead despite an existing distant gap",absf(carrier.destination.x-wire.position.x)<0.1 and carrier.destination.z>wire.position.z and carrier.state=="advance")
	var near=g.world.blocking_wire(carrier.position,carrier.lane+12)
	near.breach()
	carrier.think(11)
	check("Engineer still breaches its own file even when a nearby file is open",absf(carrier.destination.x-wire.position.x)<0.1)
	carrier.position=g.world.on_ground(wire.position+Vector3(0,0,3))
	carrier.think(12)
	check("Engineer plants and retreats immediately",wire.charge and carrier.bangalores==2 and carrier.state=="withdraw" and carrier.retreat_until>12)
	var follower=g.friendlies[8]
	follower.staged=false
	follower.truck=null
	follower.boat=null
	follower.lane=60
	follower.bangalores=0
	follower.position=g.world.on_ground(Vector3(60,0,-89))
	follower.destination=follower.position
	follower.think(15)
	check("Rifleman does not cross the entire beach to a distant gap",absf(follower.destination.x-60)<4 and follower.state in ["fire","cover"])
	var wall_routes=true
	for boat in g.boats.slice(0,20):
		var a=g.world.on_ground(Vector3(boat.lane_x,0,-105))
		var b=g.world.on_ground(Vector3(boat.lane_x,0,-135))
		var route=g.world.path_between(a,b)
		wall_routes=wall_routes and route.size()==4 and absf(route[1].x-a.x)<=6.1
		var hit=g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(route[1]+Vector3(0,0.65,0),route[2]+Vector3(0,0.65,0),1))
		wall_routes=wall_routes and hit.is_empty()
	check("Each file has a physically clear short route through the seawall",wall_routes)
	g.phase="playing"
	var wall=g.world.strong(Vector3(8,3,1),g.world.on_ground(Vector3(250,0,-60))+Vector3(0,1.5,0),g.world.concrete)
	follower.position=g.world.on_ground(Vector3(250,0,-50))+Vector3(0,0.025,0)
	follower.destination=g.world.on_ground(Vector3(250,0,-75))
	follower.path=PackedVector3Array()
	follower.state="advance"
	follower.stance="stand"
	follower.target=null
	follower.velocity=Vector3.ZERO
	await move_for(follower,3.0)
	check("Low-mode swept infantry capsule stops at solid concrete",follower.position.z> -59.3 and follower.position.z< -56,follower.position)
	wall.demolish()
	follower.path=PackedVector3Array()
	follower.destination=g.world.on_ground(Vector3(250,0,-75))
	await move_for(follower,2.0)
	check("Infantry moves through the opening after cover is destroyed",follower.position.z< -66,follower.position)
	var closed=g.world.wires_by_row[0][-2]
	follower.position=g.world.on_ground(closed.position+Vector3(0,0,10))+Vector3(0,0.025,0)
	follower.destination=g.world.on_ground(closed.position+Vector3(0,0,-10))
	follower.path=PackedVector3Array()
	follower.velocity=Vector3.ZERO
	follower.stuck=0
	await move_for(follower,2.8)
	check("Low-mode infantry cannot walk through intact wire",follower.position.z>closed.position.z+0.8,follower.position)
	closed.breach()
	follower.destination=g.world.on_ground(closed.position+Vector3(0,0,-10))
	follower.path=PackedVector3Array()
	follower.stuck=0
	await move_for(follower,2.0)
	check("Opening the wire admits the full-speed infantry capsule",follower.position.z<closed.position.z-4,follower.position)
	var victim=g.enemies[6]
	victim.staged=false
	victim.position=g.world.on_ground(Vector3(252,0,-80))
	victim.take_damage(1000,Vector3.ZERO,"rifle")
	var remains=get_nodes_in_group("winter_corpses").back()
	var part=remains.parts[0]
	check("Instanced remains keep all six damageable physical parts",remains.parts.size()==6 and remains.parts.all(func(p):return p.collision_layer==32 and not p.visual_batch.is_empty()))
	var old_part_position=part.global_position
	part.detach(Vector3(8,24,0))
	for i in range(12):await physics_frame
	await process_frame
	# The headless renderer returns identity for every MultiMesh readback. Check
	# the physical motion and running updater here; actual GPU pixels need playtest.
	check("Detached body keeps physical motion and its instancing updater",part.detached and not part.freeze and part.is_physics_processing() and part.global_position.distance_to(old_part_position)>0.02,{"updater":part.is_physics_processing(),"sleeping":part.sleeping,"moved":part.global_position.distance_to(old_part_position),"velocity":str(part.linear_velocity)})
	var drop=get_nodes_in_group("dropped_weapons").back()
	var drop_batch=drop.visual_batch
	check("Instanced dropped weapons retain finite ammunition and collision",drop.rounds>0 and drop.collision_layer==32 and not drop_batch.is_empty())
	var dropped_kind=drop.kind
	var dropped_rounds=drop.rounds
	drop.take(g.player)
	await process_frame
	await process_frame
	check("Picking up a batched weapon transfers ammunition and frees the drop",not is_instance_valid(drop) and g.player.gun_kind==dropped_kind and g.player.ammo==dropped_rounds)
	g.elapsed=119.99
	g.step_battle(0.02)
	await physics_frame
	check("Wave two activates all 600 soldiers at two minutes",reserve.all(func(a):return not a.staged and not a.shape.disabled and a.collision_layer==8) and g.wave_two_released)
	var result={"passed":checks.filter(func(c):return c.ok).size(),"total":checks.size(),"checks":checks}
	var file=FileAccess.open("res://reviews/omaha/double-wave-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit(0 if result.passed==result.total else 1)

func move_for(actor,seconds:float):
	for i in range(roundi(seconds*Engine.physics_ticks_per_second)):
		await physics_frame
		g.elapsed+=1.0/Engine.physics_ticks_per_second
		actor._physics_process(1.0/Engine.physics_ticks_per_second)
