# ==============================================================================
# Program: weapon_review.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Automated test script verifying runtime performance, physics stability, or behavior correctness for weapon_review.gd.
# ==============================================================================
## Screenshot review of the rifle model and animations (hip, sights, bolt, reload).
##
## Renders the desert mission into an off-screen 1440x900 viewport so the captures are the
## same size on any window manager, then saves reviews/rifle-<label>-{title,hip,sights,bolt,reload}.png
## and a short render-timing JSON (reviews/rifle-render-check.json). Pass `-- --label=before` to
## name the capture set (default "after") when comparing two versions of the model.
## It asserts nothing; a person looks at the images.
extends SceneTree

# Separate, noninteractive render review. Never drives or closes the user's game.
# Mission instance and its off-screen viewport.
# Separate, noninteractive render review. Never drives or closes the user's game.
var game
var review_viewport: SubViewport

# Prefix in the output file names, from the --label= argument.
var label: String = "after"

## Read the command line label, then start the review.
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	call_deferred("run")

## Let the view and animations settle before a screenshot.
func settle():
	game.phase = "playing"
	# 100 small updates let camera blending reach its final pose.
	for i in range(100): game.player.update_view(1.0 / 60.0)
	# Wait real time so animations and timers play out.
	await create_timer(0.6).timeout
	for i in range(3):
		game.phase = "playing"
		await process_frame
	# Make sure the frame is rendered before reading pixels.
	await RenderingServer.frame_post_draw

## Save the viewport as reviews/rifle-<label>-<suffix>.png.
func snap(suffix: String):
	var path = "res://reviews/rifle-" + label + "-" + suffix + ".png"
	review_viewport.get_texture().get_image().save_png(path)
	print("WEAPON_CAPTURE ", path)

## Run the review sequence.
func run():
	DisplayServer.window_set_title("Holy Order — weapon review")
	AudioServer.set_bus_mute(0,true)
	# Hyprland can tile a test window down to a fraction of the requested size.
	# Render to a fixed-size GPU viewport so the captures and timing are meaningful.
	# Hyprland can tile a test window down to a fraction of the requested size.
	# Render to a fixed-size GPU viewport so the captures and timing are meaningful.
	review_viewport = SubViewport.new()
	review_viewport.size = Vector2i(1440,900)
	review_viewport.own_world_3d = true
	review_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	review_viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(review_viewport)
	game = load("res://scenes/main.tscn").instantiate()
	review_viewport.add_child(game)
	# Title screenshot first, before freezing the game.
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	snap("title")
	# Freeze the game and enemies so the camera and rifle poses are fully controlled by the test.
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.player.set_physics_process(false)
	game.player.set_process(false)
	game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:
		enemy.set_physics_process(false)
		enemy.set_process(false)
	# Hide the menu knight and set up a clear view of the player's rifle in front of the outpost.
	game.world.menu_knight.hide()
	game.player.position = Vector3(0, 0.04, -17)
	game.player.rotation = Vector3.ZERO
	game.player.head.rotation = Vector3.ZERO
	game.player.camera.rotation = Vector3.ZERO
	game.player.camera.current = true
	game.player.has_rifle = true
	game.player.ammo = 6
	game.player.select_weapon(1)
	# Quest state "outpost" shows the in-game rifle HUD.
	game.quest = "outpost"
	game.player.aiming = false
	# Wide field of view (83) for hip fire; 58 when aiming, 49 on the older "before" model whose sights were different.
	game.player.camera.fov = 83
	await settle()
	snap("hip")
	game.player.aiming = true
	game.player.camera.fov = 58 if label != "before" else 49
	await settle()
	snap("sights")
	# Bolt cycle pose: recoil and cooldown set manually.
	game.player.recoil = 0.2
	game.player.cooldown = 0.55
	await settle()
	snap("bolt")
	game.player.recoil = 0
	game.player.cooldown = 0
	game.player.aiming = false
	# Reload pose: 1.35 s into the reload animation.
	game.player.reload_time = 1.35
	await settle()
	snap("reload")
	game.player.reload_time = 0
	await settle()
	# Measure 120 rendered frames to produce a median and p95 frame time (a static scene, not a benchmark).
	var frame_times: Array[float] = []
	var previous = Time.get_ticks_usec()
	for i in range(120):
		await RenderingServer.frame_post_draw
		var now = Time.get_ticks_usec()
		frame_times.append(float(now-previous)/1000.0)
		previous = now
	frame_times.sort()
	var report = {
		"resolution":str(review_viewport.get_texture().get_size()),
		"preview_median_frame_ms":frame_times[60],
		"preview_p95_frame_ms":frame_times[114],
		"msaa_samples":4,
		"note":"Stationary render preview; not a gameplay performance benchmark."
	}
	FileAccess.open("res://reviews/rifle-render-check.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("WEAPON_RENDER ",JSON.stringify(report))
	print("WEAPON_REVIEW_COMPLETE")
	quit()
