## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script tests/weapon_review.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Screenshot review of the first-person rifle in the desert mission: renders
## hip, aiming, bolt-cycle, reload and other poses to reviews/rifle-<label>-<pose>.png
## and writes a short render timing report.
##
## Needs a real renderer. Never drives the user's own game: it builds its own
## SubViewport (1440 x 900, own world, 4x MSAA) because a tiled test window may be
## much smaller than requested. Pass `--label=<name>` after `--` to name the set (default
## "after"); with "before" the aiming FOV is 49 instead of 58 so old and new weapon
## builds can be compared. The report reviews/rifle-render-check.json holds median and 95th
## percentile of a stationary preview's frame times and is explicitly not a gameplay benchmark.
## Run: godot --path <repo> --script res://tests/weapon_review.gd -- --label=after
extends SceneTree

# Separate, noninteractive render review. Never drives or closes the user's game.

## The desert Game node.
var game

## Fixed-size viewport that renders the review.
var review_viewport: SubViewport

## Name used in the output file names.
var label: String = "after"

## SceneTree entry point: reads --label= and defers to run().
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	call_deferred("run")

## Lets the view model finish its animation (100 manual updates, 0.6 s, a few frames) and the frame finish drawing before a capture; keeps the phase on "playing" because pause logic would stop it.
func settle():
	game.phase = "playing"
	for i in range(100): game.player.update_view(1.0 / 60.0)
	await create_timer(0.6).timeout
	for i in range(3):
		game.phase = "playing"
		await process_frame
	await RenderingServer.frame_post_draw

## Saves the viewport as reviews/rifle-<label>-<suffix>.png and prints WEAPON_CAPTURE.
## [param suffix] pose name.
func snap(suffix: String):
	var path = "res://reviews/rifle-" + label + "-" + suffix + ".png"
	review_viewport.get_texture().get_image().save_png(path)
	print("WEAPON_CAPTURE ", path)

## Sets up the scene (everything frozen except the view model), puts the player in the village and captures each pose, then writes the report.
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
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	snap("title")
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.player.set_physics_process(false)
	game.player.set_process(false)
	game.player.set_process_unhandled_input(false)
	for enemy in game.enemies:
		enemy.set_physics_process(false)
		enemy.set_process(false)
	game.world.menu_knight.hide()
	game.player.position = Vector3(0, 0.04, -17)
	game.player.rotation = Vector3.ZERO
	game.player.head.rotation = Vector3.ZERO
	game.player.camera.rotation = Vector3.ZERO
	game.player.camera.current = true

	# Arm the player with a loaded rifle at the outpost position so the view shows real sights and weapons.
	game.player.has_rifle = true
	game.player.ammo = 6
	game.player.select_weapon(1)
	game.quest = "outpost"
	game.player.aiming = false
	game.player.camera.fov = 83
	await settle()
	snap("hip")
	game.player.aiming = true
	game.player.camera.fov = 58 if label != "before" else 49
	await settle()
	snap("sights")
	game.player.recoil = 0.2
	game.player.cooldown = 0.55
	await settle()
	snap("bolt")
	game.player.recoil = 0
	game.player.cooldown = 0
	game.player.aiming = false
	game.player.reload_time = 1.35
	await settle()
	snap("reload")
	game.player.reload_time = 0
	await settle()
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
