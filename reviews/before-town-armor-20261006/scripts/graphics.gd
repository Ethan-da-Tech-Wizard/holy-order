# ==============================================================================
# Program: graphics.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for graphics.gd.
# ==============================================================================
## Graphics quality presets shared by every mission scene.
##
## Quality is a number stored as metadata on the SceneTree (so it survives scene
## changes): 0 = LOW / MAX FPS, 1 = STANDARD, 2 = HIGH. `apply()` pushes the
## chosen preset into the viewport, lights, environments, meshes and cameras. The
## performance overlay calls `cycle()` on F6. All functions are static; nothing is instantiated.
extends RefCounted
# Shared by all three missions. The 3D scene alone is scaled; text stays sharp.
# Display names indexed by quality level.
const NAMES=["LOW / MAX FPS","STANDARD","HIGH"]

## Current quality level.
## @param tree The active SceneTree (holds the "graphics_quality" meta).
## @return 0, 1 or 2; defaults to 0 (fastest) when never set.
static func quality(tree:SceneTree)->int:
	return int(tree.get_meta("graphics_quality",0))

## Apply the current quality preset to everything under `game`.
##
## Re-runnable: original shadow and camera far values are stored as metadata the first
## time so switching back to a higher level restores them exactly.
## @param game Root node of the mission (Ardennes or Omaha).
static func apply(game):
	var q=quality(game.get_tree())
	# The mass landing uses a lighter step in Low; camera and models interpolate.
	# Omaha is recognised by its `boats` property; physics tick drops to 20 Hz there, else 30 Hz.
	# The mass landing uses a lighter step in Low; camera and models interpolate.
	Engine.physics_ticks_per_second=20 if q==0 and game.get("boats")!=null else 30
	# 3D resolution scale: 40% for Omaha Low, otherwise 50/75/100% by level. UI is drawn at native size.
	var viewport=game.get_viewport()
	viewport.scaling_3d_scale=0.40 if q==0 and game.get("boats")!=null else [0.50,0.75,1.0][q]
	# MSAA and screen-space AA are off at every level; they cost more than the visual gain at low scale.
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	# Only the sun casts shadows, and only on High; point lights never do (expensive).
	for light in game.find_children("*","Light3D",true,false):
		light.shadow_enabled=q==2 and light is DirectionalLight3D
		# Shorter shadow range concentrates shadow-map resolution near the player.
		if light is DirectionalLight3D:light.directional_shadow_max_distance=60
	# All costly environment effects are disabled at all levels to keep frame rate stable.
	for environment in game.find_children("*","WorldEnvironment",true,false):
		var env=environment.environment
		env.ssao_enabled=false
		env.ssil_enabled=false
		env.ssr_enabled=false
		env.glow_enabled=false
		env.volumetric_fog_enabled=false
	# Below High, no mesh casts shadows; the original setting is remembered so High can restore it.
	for visual in game.find_children("*","GeometryInstance3D",true,false):
		if not visual.has_meta("original_shadow"):visual.set_meta("original_shadow",visual.cast_shadow)
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if q<2 else visual.get_meta("original_shadow")
	# Cap view distance per quality (450/650/750 m) but never extend beyond the camera's original far plane.
	for camera in game.find_children("*","Camera3D",true,false):
		if not camera.has_meta("original_far"):camera.set_meta("original_far",camera.far)
		camera.far=minf(camera.get_meta("original_far"),[450.0,650.0,750.0][q])
	# Snapshot all spawn transforms before the first interpolated display frame.
	# Snapshot all spawn transforms before the first interpolated display frame.
	game.reset_physics_interpolation()

## One-time setup when a mission starts: cap FPS, apply the preset and attach the FPS overlay.
## @param game Mission root; receives the overlay as a child.
static func install(game):
	# 60 FPS cap saves power and keeps the 20/30 Hz physics interpolation smooth.
	Engine.max_fps=60
	apply(game)
	var overlay=load("res://scripts/performance_overlay.gd").new()
	overlay.game=game
	game.add_child(overlay)

## Step to the next quality level (wraps from High back to Low) and re-apply it.
## @param game Mission root; its `quality` property and `apply_quality()` method are updated when present.
static func cycle(game):
	var q=(quality(game.get_tree())+1)%NAMES.size()
	# Persist on the tree so the choice survives scene reloads.
	game.get_tree().set_meta("graphics_quality",q)
	apply(game)
	# Some missions keep their own copy of the level; keep it in sync.
	if game.get("quality")!=null:game.quality=q
	if game.has_method("apply_quality"):game.apply_quality()
	# Feedback so the player sees the level changed (3 s toast).
	game.toast("GRAPHICS: "+NAMES[q],3)

## Leave the mission and return to the main menu scene.
## @param game Mission root, used only to reach the SceneTree.
static func menu(game):
	# The mouse is captured during play; release it for the menu.
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.get_tree().change_scene_to_file("res://scenes/menu.tscn")
