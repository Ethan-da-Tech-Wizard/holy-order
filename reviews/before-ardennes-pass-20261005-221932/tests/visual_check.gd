# ==============================================================================
# Program: visual_check.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for visual_check.gd.
# ==============================================================================
## Screenshot walkthrough of the desert mission (start to tea scene).
##
## Not a SceneTree script: a node that a test scene calls with `run(game)`. It waits real time
## with timers, teleports the player between story beats and saves PNGs to reviews/ (start-screen,
## opening-briefing, sheltered-spawn, rifle-pickup, rifle-quip, outpost, patrol-rendezvous,
## tea-scene, test-complete). Meant for a person to inspect the images.
extends Node

## Save the current viewport as reviews/<name>.png after the frame is drawn.
func snap(name: String):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reviews/"+name+".png")

## Drive the mission through its main beats.
## @param g The mission controller.
func run(g):
	# Give the title screen time to render.
	await get_tree().create_timer(1.5).timeout
	await snap("start-screen")
	g.begin()
	await get_tree().create_timer(0.3).timeout
	await snap("opening-briefing")
	# Cooldown 999 stops enemies from firing during the early shots.
	for enemy in g.enemies: enemy.cooldown=999
	g.resume_game()
	await get_tree().create_timer(0.8).timeout
	await snap("sheltered-spawn")
	# Move to the sentry and kill him so the rifle pickup and quip beats trigger.
	g.player.position=Vector3(1.5,0.04,5.7)
	g.enemies[0].take_damage(200)
	await get_tree().create_timer(1.8).timeout
	await snap("rifle-pickup")
	await get_tree().create_timer(2).timeout
	# Reset the aim so the quip screenshot is level.
	g.player.rotation=Vector3.ZERO
	g.player.head.rotation=Vector3.ZERO
	g.player.camera.rotation=Vector3.ZERO
	await get_tree().create_timer(0.35).timeout
	await snap("rifle-quip")
	# Outpost view; then kill all enemies so the patrol scene can proceed.
	g.player.position=Vector3(0,0.05,-17)
	await get_tree().create_timer(0.4).timeout
	await snap("outpost")
	for enemy in g.enemies:
		if enemy.alive: enemy.take_damage(200)
	# Patrol rendezvous and the tea scene, timed to the scripted cinematic (5.6 s and 9 s).
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
