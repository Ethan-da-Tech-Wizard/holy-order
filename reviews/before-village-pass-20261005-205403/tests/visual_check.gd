extends Node

func snap(name: String):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reviews/"+name+".png")

func run(g):
	await get_tree().create_timer(1.5).timeout
	await snap("start-screen")
	g.begin()
	await get_tree().create_timer(0.3).timeout
	await snap("opening-briefing")
	for enemy in g.enemies: enemy.cooldown=999
	g.resume_game()
	await get_tree().create_timer(0.8).timeout
	await snap("sheltered-spawn")
	g.player.position=Vector3(1.5,0.04,5.7)
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
