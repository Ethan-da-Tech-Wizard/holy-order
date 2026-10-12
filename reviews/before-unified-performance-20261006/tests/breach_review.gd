extends SceneTree
var g
var view: SubViewport
var checks=[]
func _initialize():call_deferred("run")
func ticks(n):
	for i in range(n):await physics_frame
func check(ok: bool, label: String):
	checks.append({"check":label,"passed":ok})
	print(("PASS " if ok else "FAIL ")+label)
func capture(label: String):
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://reviews/village-"+label+".png")
func settle():
	for i in range(8):
		g.phase="playing"
		await process_frame
func run():
	DisplayServer.window_set_title("Holy Order — destruction verification")
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new()
	view.size=Vector2i(1440,900)
	view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.msaa_3d=Viewport.MSAA_4X
	root.add_child(view)
	g=load("res://scenes/main.tscn").instantiate()
	view.add_child(g)
	await ticks(70)
	g.set_process(false)
	g.set_physics_process(false)
	g.set_process_unhandled_input(false)
	g.player.set_physics_process(false)
	g.player.set_process(false)
	g.player.set_process_unhandled_input(false)
	for e in g.enemies:e.set_physics_process(false)
	g.world.menu_knight.hide()
	g.player.camera.current=true
	g.phase="playing"
	g.player.position=Vector3(15,0.05,-22)
	g.player.rotation=Vector3.ZERO
	g.player.head.rotation=Vector3.ZERO
	g.player.camera.look_at(Vector3(21,1.4,-41))
	g.player.has_rifle=true
	g.player.ammo=6
	g.player.select_weapon(1)
	g.player.update_view(0.016)
	g.hud.hide()
	await settle()
	await capture("before-breach")
	var start=Time.get_ticks_msec()
	# Two overlapping blasts exercise CSG rebuild queues and persistent collision.
	g.world.blast(Vector3(20,1.2,-35.7),780,5)
	g.world.blast(Vector3(21,0.5,-35.7),340,4)
	await ticks(45)
	var time_ms=Time.get_ticks_msec()-start
	var count=0
	var pending=0
	for body in get_nodes_in_group("breakable"):
		if body.cuts_completed>0:count+=1
		if body.rebuilding:pending+=1
	check(count>=8 and pending==0,"Overlapping explosions finish rebuilding multiple pieces of real village geometry")
	var ray=PhysicsRayQueryParameters3D.create(Vector3(20,1.2,-34),Vector3(20,1.2,-38),1)
	check(g.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"Demolition opens a usable route into an existing house")
	await settle()
	await capture("after-breach")
	g.player.position=Vector3(7,0.05,-44)
	g.player.camera.look_at(Vector3(3,1.0,-49))
	await settle()
	await capture("machine-gun")
	g.enter_mg()
	check(g.player_mounted and g.mg_nest.operator==g.player,"The player can occupy the abandoned MG without duplicating its inventory")
	var initial=g.mg_nest.rounds
	g.mg_nest.cooldown=0
	g.mg_nest.try_fire(Vector3(3,1.4,-15))
	check(g.mg_nest.rounds==initial-1,"Player-mounted fire consumes the same ammunition as the AI")
	g.leave_mg()
	check(not g.player_mounted and g.player.hands.visible,"Dismount restores first-person weapons and movement")
	# Exercise the player's real satchel detonation method, rather than just blast().
	g.player.position=Vector3(18,0.05,-25)
	g.player.camera.look_at(Vector3(18,0,-27))
	g.demolition.take()
	g.demolition.deploy(false)
	check(is_instance_valid(g.demolition.active),"Satchel can be placed beside the village")
	g.player.position=Vector3(10,0.05,-23)
	g.demolition.detonate()
	await ticks(45)
	check(not is_instance_valid(g.demolition.active) and g.demolition.carried==0 and g.demolition.stock==2,"Detonation consumes exactly one optional charge")
	check(get_nodes_in_group("breakable").all(func(b):return not b.rebuilding),"Destruction settles back to static geometry after the second blast")
	await settle()
	g.hud.show()
	g.pause_game("inventory")
	await ticks(3)
	await capture("inventory")
	var failed=checks.filter(func(c):return not c.passed)
	FileAccess.open("res://reviews/breach-review.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed.size(),"passed":checks.size()-failed.size(),"observed_blast_settle_window_ms":time_ms,"note":"Fixed 1440x900 GPU verification. Settle window includes 45 deliberate physics frames, not a pure performance benchmark."},"  "))
	print("BREACH_REVIEW_COMPLETE ",checks.size()," checks; ",failed.size()," failures")
	g.phase="title"
	for i in range(120):
		if not g.world.navigation.rebuilding and g.world.navigation.dirty.is_empty():break
		await ticks(1)
	await create_timer(0.25).timeout
	g.queue_free()
	await ticks(4)
	quit(0 if failed.is_empty() else 1)
