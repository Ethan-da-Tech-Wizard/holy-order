extends SceneTree
const Armor=preload("res://scripts/omaha/armor.gd")
var g
var checks:Array=[]
func _initialize():call_deferred("run")
func check(label:String,ok:bool,data=null):
	checks.append({"check":label,"ok":ok,"data":data})
	print("PASS " if ok else "FAIL ",label," ",data if data!=null else "")
func ticks(n:int):
	for i in range(n):await physics_frame
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await ticks(3)
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for a in g.actors:a.set_physics_process(false)
	check("600 Americans including player; 100 Germans",g.friendlies.size()==599 and g.enemies.size()==100)
	check("Two complete 300-person waves",g.friendlies.filter(func(a):return a.wave==0).size()==299 and g.friendlies.filter(func(a):return a.wave==1).size()==300)
	check("20 craft, 40 Brownings, 20 protected drivers",g.boats.size()==20 and g.friendlies.filter(func(a):return a.role=="gunner").size()==40 and g.friendlies.filter(func(a):return a.role=="driver" and a.health>=20000).size()==20)
	check("32 fortified MGs and 8 portable MG42s",g.enemies.filter(func(a):return a.mounted).size()==32 and g.enemies.filter(func(a):return a.weapon_kind=="mg42" and not a.mounted).size()==8)
	check("All soldiers carry finite ammunition and grenades",g.actors.all(func(a):return a.rounds>0 and a.grenades>=2))
	check("Scarce AI-only Bangalore carriers",g.friendlies.filter(func(a):return a.bangalores>0).size()==20 and g.player.get("bangalores")==null)
	check("Flamethrowers, BARs and carbines present",g.friendlies.any(func(a):return a.weapon_kind=="flamethrower") and g.friendlies.any(func(a):return a.weapon_kind=="bar") and g.friendlies.any(func(a):return a.weapon_kind=="carbine"))
	check("Player Garand, grenades, shovel, sword and fists",g.player.gun_kind=="garand" and g.player.ammo==8 and g.player.reserve==96 and g.player.has_shovel and g.player.grenades==4)
	check("Player starts in rear row of packed craft",g.player.seat==25 and g.player.truck.occupants.size()==26)
	var start=g.player.position
	Input.action_press("move_forward")
	g.begin()
	g.player._physics_process(1.0)
	Input.action_release("move_forward")
	check("Packed craft locks walking before ramp opens",g.player.position.distance_to(start)<0.2)
	var count=g.player.ammo
	g.player.attack()
	check("No weapon use while packed aboard",g.player.ammo==count)
	var circle=g.boats[12].position
	g.boats[12].update_course(20)
	check("Reserve craft circle offshore",circle.distance_to(g.boats[12].position)>5 and g.boats[12].position.z>350)
	g.elapsed=g.first_landing_at-0.1
	for b in g.boats:b.tick(0.1)
	check("Ramps stay up until beach arrival",g.boats.all(func(b):return not b.arrived))
	g.elapsed=g.first_landing_at
	for b in g.boats:b.tick(0.1)
	check("First wave arrives together; second still offshore",g.boats.slice(0,10).all(func(b):return b.arrived) and g.boats.slice(10).all(func(b):return not b.arrived))
	g.elapsed=g.first_landing_at+3
	for b in g.boats:b.tick(1)
	check("Front troops leave before player",g.player.truck!=null and g.boats[4].occupants.any(func(a):return a.truck==null))
	g.elapsed=g.first_landing_at+10
	for b in g.boats:b.tick(1)
	check("All assault passengers exit through ramps",g.player.truck==null and g.boats.slice(0,10).all(func(b):return not b.has_passengers()))
	check("Player exits into shallow water",g.player.position.z>0 and g.player.position.z<20)
	var min_separation=INF
	for t in range(int(g.first_landing_at)+25,241):
		g.elapsed=t
		for b in g.boats:b.tick(1)
		for a in g.boats.slice(0,10):
			if a.departed:continue
			for b in g.boats.slice(10):min_separation=minf(min_separation,Vector2(a.position.x-b.position.x,a.position.z-b.position.z).length())
	check("Returning wave uses separate clear lanes",min_separation>15,min_separation)
	check("First-wave craft leave scene before second approach",g.boats.slice(0,10).all(func(b):return b.departed and not b.visible) and g.boats.slice(10).all(func(b):return not b.arrived))
	g.elapsed=g.second_wave_at-0.1
	for b in g.boats:b.tick(1)
	check("Second wave does not land early",not g.second_wave_landed)
	g.elapsed=g.second_wave_at
	for b in g.boats:b.tick(1)
	check("Second landing exactly 240 seconds after first",g.second_wave_landed and g.second_wave_at-g.first_landing_at==240)
	var panel=g.boats[10].parts[1]
	panel.damage_at(10,panel.position)
	check("Fresh hull initially stops rifle rounds",not panel.penetrable)
	for i in range(14):panel.damage_at(40,panel.global_position)
	check("Sustained fire makes individual hull panel penetrable",panel.penetrable and not g.boats[10].parts[2].penetrable)
	var wire=g.world.wires[70]
	var engineer=g.friendlies.filter(func(a):return a.bangalores>0)[0]
	engineer.position=wire.position+Vector3(0,0,2)
	var carried=engineer.bangalores
	check("Engineer deploys one carried Bangalore",wire.deploy(engineer) and engineer.bangalores==carried-1)
	check("A second charge cannot duplicate an armed breach",not wire.deploy(engineer))
	wire.tick(1.9)
	check("Bangalore keeps its warning fuse",not wire.broken)
	wire.tick(0.11)
	check("Charge creates one local opening",wire.broken and g.world.wires.filter(func(w):return w.broken).size()==1 and g.breaches==1)
	check("Wire breach removes collision and registers its opening",wire.collision_layer==0 and not wire.bars.visible and wire in g.world.gaps_by_row[wire.row])
	check("Three wire lines, cover, trenches, town",g.world.wires.size()==258 and g.world.trench_segments.size()>170 and g.world.town_points.size()==36 and g.world.covers.size()>400)
	# Isolate actual physics / perception in an unobstructed flank of the map.
	for a in g.actors:
		a.staged=true
		a.collision_layer=0
		a.equipment.collision_layer=0
	var defender=g.enemies[6]
	var friendly=g.friendlies[8]
	defender.staged=false
	defender.mounted=false
	defender.position=g.world.on_ground(Vector3(500,0,-120))
	defender.rotation.y=PI
	defender.collision_layer=4
	defender.memory.clear()
	friendly.staged=false
	friendly.truck=null
	friendly.stance="stand"
	friendly.position=g.world.on_ground(Vector3(500,0,-95))
	friendly.collision_layer=8
	g.player.position=g.world.on_ground(Vector3(500,0,-80))
	g.player.truck=null
	g.player.crouched=false
	g.player.prone=false
	await ticks(3)
	check("Nearest detected AI selected ahead of player",g.acquire_target(defender)==friendly)
	friendly.staged=true
	friendly.collision_layer=0
	g.player.position=g.world.on_ground(Vector3(500,0,-140))
	g.player.prone=true
	g.player.last_fired=-999
	defender.memory.clear()
	await ticks(2)
	check("Quiet prone player can approach from behind",not g.can_detect(defender,g.player))
	g.player.last_fired=g.elapsed
	check("Firing gives away a hidden player",g.can_detect(defender,g.player))
	g.player.position=g.world.on_ground(Vector3(500,0,-80))
	g.player.prone=false
	var cover=g.world.strong(Vector3(7,5,1),g.world.on_ground(Vector3(500,0,-100))+Vector3(0,2.5,0),g.world.concrete)
	await ticks(2)
	check("Detection never sees through concrete",g.acquire_target(defender)==null)
	cover.queue_free()
	await ticks(2)
	var ports=0
	for nest in g.world.nests:
		var from=nest.position+Vector3(0,1.5,0)
		var to=from+nest.facing*20
		var q=PhysicsRayQueryParameters3D.create(from,to,1)
		if g.get_world_3d().direct_space_state.intersect_ray(q).is_empty():ports+=1
	check("Fortified guns have physically open firing ports",ports>=24,ports)
	var p=g.world.on_ground(Vector3(510,0,-90))
	var before=g.world.surface_height(p.x,p.z)
	g.world.dig(p,1.65,0.48)
	await ticks(10)
	check("Shovel changes collision terrain height",g.world.surface_height(p.x,p.z)<before-0.25)
	# Distant infantry must move at the same physical speed as nearby infantry.
	friendly.staged=false
	friendly.alive=true
	friendly.truck=null
	friendly.boat=null
	friendly.position=g.world.on_ground(Vector3(470,0,-80))+Vector3(0,0.03,0)
	friendly.state="advance"
	friendly.stance="stand"
	friendly.order="assault"
	friendly.target=null
	friendly.vehicle_target=null
	friendly.velocity=Vector3.ZERO
	friendly.set_destination(g.world.on_ground(Vector3(470,0,-110)))
	g.player.position=Vector3(0,60,0)
	var origin=friendly.position
	for i in range(60):
		await physics_frame
		friendly._physics_process(1.0/60.0)
	var advanced=origin.z-friendly.position.z
	check("Distant troops retain full movement speed",advanced>3.7,advanced)
	# Water must reduce intended speed, not repeatedly cancel acceleration.
	friendly.position=g.world.on_ground(Vector3(470,0,12))+Vector3(0,0.03,0)
	friendly.velocity=Vector3.ZERO
	friendly.path_refresh=0
	friendly.set_destination(g.world.on_ground(Vector3(470,0,-20)))
	origin=friendly.position
	for i in range(60):
		await physics_frame
		friendly._physics_process(1.0/60.0)
	advanced=origin.z-friendly.position.z
	check("Troops wade off the ramp at a useful pace",advanced>3.0,advanced)
	# Expired waiting time must never scatter a file towards the map boundary.
	friendly.position=g.world.on_ground(Vector3(120,0,g.Layout.WIRE_ROWS[0]+11))
	friendly.lane=120
	friendly.bangalores=0
	g.elapsed=g.first_landing_at+300
	friendly.destination=friendly.position
	friendly.think(g.elapsed)
	check("Infantry converges on an existing breach instead of a distant flank",not friendly.flanking_wire and absf(friendly.destination.x-wire.position.x)<3 and friendly.destination.z<wire.position.z)
	friendly.position=g.world.on_ground(Vector3(120,0,g.Layout.WIRE_ROWS[1]+11))
	friendly.destination=friendly.position
	friendly.think(g.elapsed)
	check("Infantry holds its lane while the next belt is closed",not friendly.flanking_wire and absf(friendly.destination.x-120)<3 and friendly.state in ["fire","cover"])
	var fleet_width=g.boats[9].lane_x-g.boats[0].lane_x
	check("Landing front and first wire crossing are compact",fleet_width<=400 and -g.Layout.WIRE_ROWS[0]<=110,{"frontage":fleet_width,"shore_to_wire":-g.Layout.WIRE_ROWS[0]})
	var wall=null
	for body in get_nodes_in_group("breakable"):
		if body is Armor and body.render_batch!=null and body.global_position.z<g.Layout.VILLAGE:
			wall=body
			break
	var shielded=false
	if wall!=null:
		var from=wall.global_position+Vector3(0,0,1)
		var to=wall.global_position-Vector3(0,0,1)
		var ray=PhysicsRayQueryParameters3D.create(from,to,1)
		var hit=g.get_world_3d().direct_space_state.intersect_ray(ray)
		shielded=hit.get("collider")==wall and wall.distance_to_surface(from)<1.1
		wall.demolish()
		await ticks(2)
		hit=g.get_world_3d().direct_space_state.intersect_ray(ray)
		shielded=shielded and hit.get("collider")!=wall
	check("Batched scenery preserves blast bounds and destructible cover",shielded)
	var result={"passed":checks.filter(func(c):return c.ok).size(),"total":checks.size(),"checks":checks}
	var f=FileAccess.open("res://reviews/omaha/tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"  "))
	f.close()
	g.phase="title"
	g.queue_free()
	await ticks(3)
	quit(0 if result.passed==result.total else 1)
