## Archived review snapshot (before-village-pass-20261005-205403): the code below is the script as it stood for that
## review. The documentation was carried over from the live script tests/aim_check.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Verification of rifle aiming accuracy and sight alignment in the desert mission.
##
## Checks (PASS/FAIL, also reviews/aim-checks.json; exit 1 on failure): for each
## stance (standing, crouched, prone, lean left, lean right) the front sight and rear
## notch both coincide with the screen centre to within 0.35 px while aiming, and an aimed
## shot hits a 28 mm target 25 m away. Also: recoil returns to the original alignment;
## a reload lowers the sights, shows the clip and keeps ammunition accounting right (2 loaded and 18 spare become 6 and 14);
## aim re-acquires after reload; and the aim transition settles to the same FOV and sight alignment at 30, 60 and 144 FPS.
## Why: iron sights are real geometry (carcano_model.gd), so camera and view-model maths must line
## up exactly or the weapon would be unusable.
## Run: godot --path <repo> --script res://tests/aim_check.gd
extends SceneTree

## A tiny static target that counts how many times it takes damage.
class AimTarget extends StaticBody3D:
	## Number of hits received.
	var hits: int = 0

	## Called by the player's shot; only counts.
	func take_damage(_amount: float, _head: bool = false): hits += 1

## The desert Game node.
var game

## Collected results {check, passed}.
var checks: Array = []

## SceneTree entry point: sets a 1440 x 900 window and defers to run().
func _initialize():
	root.size = Vector2i(1440,900)
	call_deferred("run")

## Records and prints one result. [param ok] pass/fail. [param description] text.
func check(ok: bool, description: String):
	checks.append({"check":description,"passed":ok})
	print(("PASS " if ok else "FAIL ")+description)

## Awaits `count` frames' worth of physics, scaled to the physics rate so 60 means one second at any rate.
func ticks(count: int):
	for i in range(count): await physics_frame

## Distance in screen pixels between a sight marker and the screen centre.
## [param p] the player. [param marker_name] "SightLine" (front sight) or "RearSightLine".
func sight_error(p, marker_name: String = "SightLine") -> float:
	var point = p.rifle.get_node(marker_name).global_position
	return p.camera.unproject_position(point).distance_to(p.camera.get_viewport().get_visible_rect().size*0.5)

## Runs all the checks (see the class comment).
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

	# Each stance is held for 60 ticks so the view settles, then the sight alignment and a real shot are checked.
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
