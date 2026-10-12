extends SceneTree

class AimTarget extends StaticBody3D:
	var hits: int = 0
	func take_damage(_amount: float, _head: bool = false): hits += 1

var game
var checks: Array = []

func _initialize():
	root.size = Vector2i(1440,900)
	call_deferred("run")

func check(ok: bool, description: String):
	checks.append({"check":description,"passed":ok})
	print(("PASS " if ok else "FAIL ")+description)

func ticks(count: int):
	for i in range(count): await physics_frame

func sight_error(p, marker_name: String = "SightLine") -> float:
	var point = p.rifle.get_node(marker_name).global_position
	return p.camera.unproject_position(point).distance_to(p.camera.get_viewport().get_visible_rect().size*0.5)

func run():
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for enemy in game.enemies:
		enemy.set_physics_process(false)
		enemy.set_process(false)
	game.phase = "playing"
	var p = game.player
	p.has_rifle = true
	p.select_weapon(1)
	p.camera.current = true
	Input.action_press("aim")
	for stance in ["standing","crouched","prone","lean left","lean right"]:
		for action in ["crouch","lean_left","lean_right"]: Input.action_release(action)
		p.prone = stance == "prone"
		if stance == "crouched": Input.action_press("crouch")
		if stance == "lean left": Input.action_press("lean_left")
		if stance == "lean right": Input.action_press("lean_right")
		# Clear air above the basin isolates the sight/ballistic check from level cover.
		p.position = Vector3(0,45,0)
		p.velocity = Vector3.ZERO
		p.rotation = Vector3.ZERO
		p.head.rotation = Vector3.ZERO
		p.recoil = 0
		p.cooldown = 0
		p.set_physics_process(true)
		p.set_process(true)
		await ticks(60)
		p.set_physics_process(false)
		p.set_process(false)
		check(p.aiming and sight_error(p)<0.35,"Front sight coincides with screen aim point while "+stance)
		check(sight_error(p,"RearSightLine")<0.35,"Rear notch and front blade share the sight line while "+stance)
		var target = AimTarget.new()
		target.collision_layer = 4
		target.collision_mask = 0
		var collision = CollisionShape3D.new()
		var shape = SphereShape3D.new()
		shape.radius = 0.014
		collision.shape = shape
		target.add_child(collision)
		game.add_child(target)
		target.global_position = p.camera.global_position-p.camera.global_basis.z*25
		await ticks(3)
		p.ammo = 6
		p.attack()
		check(target.hits==1 and p.ammo==5,"Aimed shot hits a 28 mm target at 25 m while "+stance)
		target.queue_free()
	for action in ["crouch","lean_left","lean_right"]: Input.action_release(action)
	p.prone = false
	p.position = Vector3(0,45,0)
	p.velocity = Vector3.ZERO
	p.set_physics_process(true)
	p.set_process(true)
	await ticks(95)
	check(sight_error(p)<0.35 and p.recoil==0,"Recoil returns to the original sight alignment")
	p.ammo=2
	p.reserve=18
	p.cooldown=0
	p.reload_weapon()
	await ticks(50)
	check(not p.aiming and p.rifle.get_node("ReloadClip").visible,"Reload lowers the sights and displays the en-bloc clip")
	await ticks(130)
	check(p.ammo==6 and p.reserve==14,"Animated reload preserves ammunition accounting")
	check(p.aiming and sight_error(p)<0.35 and not p.rifle.get_node("ReloadClip").visible,"Holding aim reacquires the sights after reloading")
	p.set_physics_process(false)
	p.set_process(false)
	for rate in [30,60,144]:
		p.aim_blend=0
		p.camera.fov=83
		p.cooldown=0
		for i in range(rate): p.update_view(1.0/rate)
		check(absf(p.camera.fov-58)<0.01 and sight_error(p)<0.35,"Aim transition settles consistently at "+str(rate)+" FPS")
	Input.action_release("aim")
	var failures = checks.filter(func(item): return not item.passed)
	var report={"passed":checks.size()-failures.size(),"failed":failures.size(),"checks":checks}
	FileAccess.open("res://reviews/aim-checks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("AIM_CHECK_COMPLETE ",report.passed," passed; ",report.failed," failed")
	quit(0 if failures.is_empty() else 1)
