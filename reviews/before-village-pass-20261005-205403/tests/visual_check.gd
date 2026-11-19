## Archived review snapshot (before-village-pass-20261005-205403): the code below is the script as it stood for that
## review. The documentation was carried over from the live script tests/visual_check.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Scripted walk through the desert mission that saves screenshots to reviews/
## for a visual regression review (start screen, briefing, spawn, rifle pickup,
## outpost, patrol rendezvous, tea scene, end).
##
## Role: created and run by game.gd when started with `--visual-check` (see
## Game.run_visual_check); `g` is the Game node. It needs a real renderer (not
## --headless) because it reads viewport textures. Timings are wall-clock
## timers sized for the cutscene lengths in game.gd (pickup 1.8 s, tea scene about
## 5.6 s). It teleports the player and kills enemies to jump between stages.
extends Node

## Waits for the frame to finish drawing and saves the viewport as reviews/<name>.png.
## [param name] file name without extension.
func snap(name: String):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reviews/"+name+".png")

## Plays the staged walkthrough using timers, taking one screenshot per stage; prints VISUAL_CHECK_COMPLETE and quits.
## [param g] the Game node (game.gd).
func run(g):
	await get_tree().create_timer(1.5).timeout
	await snap("start-screen")
	g.begin()
	await get_tree().create_timer(0.3).timeout
	await snap("opening-briefing")

	# Keep the enemies from shooting during the screenshots.
	for enemy in g.enemies: enemy.cooldown=999
	g.resume_game()
	await get_tree().create_timer(0.8).timeout
	await snap("sheltered-spawn")
	g.player.position=Vector3(1.5,0.04,5.7)

	# Kill the sentry so his rifle drops and the pickup cutscene can play.
	g.enemies[0].take_damage(200)
	await get_tree().create_timer(1.8).timeout
	await snap("rifle-pickup")
	await get_tree().create_timer(2).timeout
	g.player.rotation=Vector3.ZERO
	g.player.head.rotation=Vector3.ZERO
	g.player.camera.rotation=Vector3.ZERO
	await get_tree().create_timer(0.35).timeout
	await snap("rifle-quip")
	g.player.position=Vector3(0,0.05,-17)
	await get_tree().create_timer(0.4).timeout
	await snap("outpost")
	for enemy in g.enemies:
		if enemy.alive: enemy.take_damage(200)
	g.player.position=Vector3(26,0.05,-40)
	g.player.look_at(g.patrol_point)
	await get_tree().create_timer(0.6).timeout
	await snap("patrol-rendezvous")
	g.player.position=g.patrol_point+Vector3(-3,0,5)
	await get_tree().create_timer(5.6).timeout
	await snap("tea-scene")
	await get_tree().create_timer(9).timeout
	await snap("test-complete")
	print("VISUAL_CHECK_COMPLETE")
	get_tree().quit()
