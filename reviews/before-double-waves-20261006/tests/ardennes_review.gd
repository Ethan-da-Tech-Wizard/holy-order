extends SceneTree
var g
var view:SubViewport
func _initialize():call_deferred("run")
func ticks(n):
	for i in range(n):await physics_frame
func capture(label):
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://reviews/ardennes-"+label+".png")
	print("CAPTURE ",label)
func run():
	set_meta("battle_test",true)
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new()
	view.size=Vector2i(1440,900)
	view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.msaa_3d=Viewport.MSAA_4X
	root.add_child(view)
	g=load("res://scenes/ardennes.tscn").instantiate()
	view.add_child(g)
	await ticks(45)
	await capture("title")
	g.begin()
	await ticks(8)
	g.pause_game("paused")
	g.hud.hide()
	g.player.camera.current=true
	g.player.head.rotation.x=-0.06
	g.player.update_view(0.2)
	await ticks(4)
	await capture("truck")
	g.player.rotation.y+=PI
	await ticks(4)
	await capture("truck-covered-front")
	g.player.truck=null
	g.player.position=g.world.on_ground(Vector3(-35,0,186))+Vector3(0,0.08,0)
	g.player.camera.look_at(g.world.anchors[0]+Vector3(0,0.8,0))
	g.player.aiming=false
	for i in range(20):g.player.update_view(0.016)
	await ticks(8)
	await capture("defenses")
	g.player.aiming=true
	g.player.recoil=0
	for i in range(20):g.player.update_view(0.016)
	await ticks(4)
	await capture("bar-sights")
	g.player.aiming=false
	g.player.prone=true
	g.player.head.position.y=0.51
	for i in range(20):g.player.update_view(0.016)
	await ticks(4)
	await capture("prone")
	g.player.prone=false
	g.player.head.position.y=1.68
	g.player.begin_grenade()
	g.player.step_grenade(0.4)
	g.player.update_view(0.016)
	await ticks(4)
	await capture("grenade-windup")
	g.phase="title"
	g.queue_free()
	await ticks(4)
	quit()
