# ==============================================================================
# Program: ardennes_review.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for ardennes_review.gd.
# ==============================================================================
## Screenshot review script for the Ardennes mission.
##
## Plays the scene in an off-screen 1440x900 viewport (4x MSAA) and saves PNGs to
## reviews/ardennes-*.png: title, truck interior and exterior, the defences, rifle sights,
## prone view and the grenade wind-up. It checks nothing automatically; a person
## looks at the images. Run: `godot --path . --script res://tests/ardennes_review.gd` (needs a display).
extends SceneTree

# Mission instance and capture viewport.
var g
var view:SubViewport
func _initialize():call_deferred("run")

## Wait n physics ticks.
func ticks(n):
	for i in range(n):await physics_frame

## Save the viewport image as reviews/ardennes-<label>.png and print the label.
func capture(label):
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://reviews/ardennes-"+label+".png")
	print("CAPTURE ",label)
func run():
	# Deterministic test mode and muted audio.
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
	# Wait for the scene to settle before the title screenshot.
	await ticks(45)
	await capture("title")
	# Start and pause immediately so the camera poses can be set without the simulation moving.
	g.begin()
	await ticks(8)
	g.pause_game("paused")
	# Hide the HUD so screenshots show the 3D scene only.
	g.hud.hide()
	g.player.camera.current=true
	# Look slightly downward from inside the truck bed.
	g.player.head.rotation.x=-0.06
	g.player.update_view(0.2)
	await ticks(4)
	await capture("truck")
	# Walk out of the truck to a spot with a view of the first enemy position.
	g.player.truck=null
	g.player.position=g.world.on_ground(Vector3(-38,0,83))+Vector3(0,0.08,0)
	g.player.camera.look_at(g.world.anchors[0]+Vector3(0,0.8,0))
	g.player.aiming=false
	# update_view() advances the camera smoothing, so 20 small steps converge to the final pose.
	for i in range(20):g.player.update_view(0.016)
	await ticks(8)
	await capture("defenses")
	# Aiming through the BAR sights.
	g.player.aiming=true
	g.player.recoil=0
	for i in range(20):g.player.update_view(0.016)
	await ticks(4)
	await capture("bar-sights")
	# Clean shutdown.
	g.phase="title"
	g.queue_free()
	await ticks(4)
	quit()
