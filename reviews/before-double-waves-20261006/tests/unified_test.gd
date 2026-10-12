extends SceneTree
const Kit=preload("res://scripts/ardennes/weapons.gd")
const Soldier=preload("res://scripts/omaha/actor.gd")
var checks=[]
class GunRange extends Node3D:
	var elapsed:float=0
	var phase:String="playing"
	var vehicle_shots:int=0
	var profile_enabled:bool=false
	var bullets:int=0
	func actor_alive(_actor):return true
	func actor_aim(_actor):return Vector3(0,1.2,-20)
	func safe_fire_line(_actor,_from,_to):return true
	func shoot(_source,_from,_aim,_spread,_damage,_kind):bullets+=1
func _initialize():call_deferred("run")
func check(label:String,ok:bool,data=null):
	checks.append({"check":label,"ok":ok,"data":data})
	print("PASS " if ok else "FAIL ",label," ",data if data!=null else "")
func ticks(n:int):
	for i in range(n):await physics_frame
func run():
	set_meta("battle_test",true)
	var range_scene=GunRange.new()
	root.add_child(range_scene)
	for hz in [20,30,60,120]:
		for kind in ["bar","m1919","m2","mg34","mg42","mp40"]:
			var actor=Soldier.new()
			actor.game=range_scene
			actor.weapon_kind=kind
			actor.mounted=true
			range_scene.add_child(actor)
			actor.set_physics_process(false)
			actor.target=range_scene
			actor.shot_clock=0
			actor.burst_left=999
			var times=[]
			for tick in range(roundi(2.4*hz)):
				actor.contact_age=0
				var count=actor.shots
				range_scene.elapsed=float(tick)/hz
				actor._physics_process(1.0/hz)
				if actor.shots>count:times.append(range_scene.elapsed)
			var measured=60.0*(times.size()-1)/(times.back()-times[0])
			var expected=Kit.DATA[kind].cyclic_rpm
			check("%s cyclic rate at %d Hz"%[kind,hz],absf(measured-expected)/expected<0.025 and actor.rounds==actor.spec.capacity-times.size(),{"rpm":measured,"rounds":times.size()})
			actor.free()
	range_scene.free()
	check("Default physics uses 30 Hz plus interpolation",Engine.physics_ticks_per_second==30 and ProjectSettings.get_setting("physics/common/physics_interpolation"))
	check("Narrow battle widths",preload("res://scripts/ardennes/world.gd").LIMIT.x==90 and preload("res://scripts/omaha/layout.gd").WIDTH==288)
	# Actual mission menu transitions must release the old world and its soldiers.
	for id in ["desert","ardennes","omaha"]:
		change_scene_to_file("res://scenes/menu.tscn")
		await ticks(3)
		var menu=current_scene
		check("Menu offers all three missions",menu.choices.size()==3)
		menu.launch(id)
		await ticks(6)
		var game=current_scene
		Engine.max_fps=0
		check("Menu loads "+id,game!=menu and game.get("player")!=null and game.phase=="title")
		check(id+" retains 300 knight health and low rendering",game.player.health==300 and is_equal_approx(root.scaling_3d_scale,0.5) and root.msaa_3d==Viewport.MSAA_DISABLED)
		check(id+" owns exactly one battlefield",get_nodes_in_group("battle_world").size()==1)
		check(id+" camera keeps mouse look outside fixed interpolation",game.player.camera.physics_interpolation_mode==Node.PHYSICS_INTERPOLATION_MODE_OFF)
		if id=="desert":
			game.phase="playing"
			game.set_physics_process(false)
			game.player.set_physics_process(false)
			for enemy in game.enemies:enemy.set_physics_process(false)
			var nest=game.mg_nest
			nest.set_physics_process(false)
			nest.operator=game.player
			nest.position=Vector3(0,70,0)
			nest.spare_trays=0
			await ticks(2)
			for hz in [20,30,60,120]:
				nest.cooldown=0
				nest.rounds=20
				nest.reload_time=0
				nest.shots_fired=0
				var times=[]
				for tick in range(roundi(2.4*hz)):
					var shots=nest.shots_fired
					nest._physics_process(1.0/hz)
					nest.try_fire(Vector3(0,71,100))
					if nest.shots_fired>shots:times.append(float(tick)/hz)
				var rpm=60.0*(times.size()-1)/(times.back()-times[0])
				check("Breda M37 cyclic rate at %d Hz"%hz,absf(rpm-450)/450<0.03 and nest.rounds==20-times.size(),{"rpm":rpm,"rounds":times.size()})
			game.phase="title"
		if id=="omaha":
			var base=Vector3(250,25,-80)
			var wall=game.world.strong(Vector3(6,3.0,0.6),base,game.world.masonry)
			await ticks(2)
			var ray=PhysicsRayQueryParameters3D.create(base+Vector3(0,0,2),base-Vector3(0,0,2),1)
			check("Town wall blocks bullets before a grenade",not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty())
			game.world.blast(base,380,5)
			await ticks(15)
			check("Grenade opens a physical local hole without removing the wall",game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty() and not wall.destroyed and wall.cuts_completed==1 and wall.box_pieces.size()==4)
			ray.from+=Vector3(2,0,0)
			ray.to+=Vector3(2,0,0)
			check("Remaining wall still stops bullets",not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty())
			var bunker=game.world.strong(Vector3(6,3,1.2),base+Vector3(0,0,10),game.world.concrete)
			game.world.blast(bunker.position,380,5)
			await ticks(10)
			check("Thick bunker concrete survives a hand grenade",not bunker.destroyed and bunker.cuts_completed==0)
		var old_id=game.get_instance_id()
		preload("res://scripts/graphics.gd").menu(game)
		await ticks(5)
		check("Returning from "+id+" frees its actors and world",not is_instance_id_valid(old_id) and get_nodes_in_group("battle_world").is_empty() and get_nodes_in_group("winter_corpses").is_empty())
	var file=FileAccess.open("res://reviews/unified-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"passed":checks.filter(func(c):return c.ok).size(),"total":checks.size()},"  "))
	quit(0 if checks.all(func(c):return c.ok) else 1)
