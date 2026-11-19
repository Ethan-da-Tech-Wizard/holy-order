## Graphics quality presets shared by all three missions.
##
## Quality 0/1/2 (LOW / STANDARD / HIGH) is stored as SceneTree meta
## "graphics_quality" so it survives scene changes (menu -> mission -> menu).
## Only the 3D view is scaled (scaling_3d_scale); 2D UI text stays sharp.
## Expensive post effects are always off; the presets trade resolution scale,
## shadows and draw distance for frame rate on modest laptops.
extends RefCounted
# Shared by all three missions. The 3D scene alone is scaled; text stays sharp.

## Display names indexed by quality level; also used by menu.gd's dropdown.
const NAMES=["LOW / MAX FPS","STANDARD","HIGH"]

## Returns the current quality index (0 when never chosen).
## [param tree] the SceneTree that carries the meta value.
static func quality(tree:SceneTree)->int:
	return int(tree.get_meta("graphics_quality",0))

## Applies the current quality to a mission scene: 3D resolution scale,
## anti-aliasing, shadows, post effects and camera far plane.
## [param game] mission root node; its subtree is searched for lights,
## environments, meshes and cameras. Detects the Omaha mission by the
## presence of a `boats` property.
## Idempotent: original shadow settings and far planes are remembered in
## meta so cycling back to HIGH restores them.
static func apply(game):
	var q=quality(game.get_tree())
	# The mass landing uses a lighter step in Low; camera and models interpolate.
	# Omaha has hundreds of actors, so Low drops physics to 20 Hz there; the
	# view stays smooth because transforms and the camera interpolate.
	Engine.physics_ticks_per_second=20 if q==0 and game.get("boats")!=null else 30
	var viewport=game.get_viewport()

	# Render scale: 40% for Low on Omaha, otherwise 50/75/100%.
	viewport.scaling_3d_scale=0.40 if q==0 and game.get("boats")!=null else [0.50,0.75,1.0][q]

	# Anti-aliasing is off at every level: the resolution scale already costs
	# detail and MSAA is expensive on integrated GPUs.
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED

	# Only the sun casts real-time shadows, and only on HIGH.
	for light in game.find_children("*","Light3D",true,false):
		light.shadow_enabled=q==2 and light is DirectionalLight3D
		if light is DirectionalLight3D:light.directional_shadow_max_distance=60

	# Screen-space effects, glow and volumetric fog are the costliest options
	# and are disabled in every preset.
	for environment in game.find_children("*","WorldEnvironment",true,false):
		var env=environment.environment
		env.ssao_enabled=false
		env.ssil_enabled=false
		env.ssr_enabled=false
		env.glow_enabled=false
		env.volumetric_fog_enabled=false

	# Remember each mesh's authored shadow flag the first time, then turn
	# shadows off below HIGH and restore the authored flag on HIGH.
	for visual in game.find_children("*","GeometryInstance3D",true,false):
		if not visual.has_meta("original_shadow"):visual.set_meta("original_shadow",visual.cast_shadow)
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if q<2 else visual.get_meta("original_shadow")

	# Shorter far planes on lower presets cut the number of objects drawn.
	for camera in game.find_children("*","Camera3D",true,false):
		if not camera.has_meta("original_far"):camera.set_meta("original_far",camera.far)
		camera.far=minf(camera.get_meta("original_far"),[450.0,650.0,750.0][q])
	# Snapshot all spawn transforms before the first interpolated display frame.
	# Snapshot spawn transforms before the first interpolated frame so nodes do not glide in from the origin.
	game.reset_physics_interpolation()

## Called once by each mission at start-up: caps fps at 60, applies the quality
## and adds the performance overlay (F6/F10).
## [param game] mission root node.
static func install(game):
	Engine.max_fps=60
	apply(game)
	var overlay=load("res://scripts/performance_overlay.gd").new()
	overlay.game=game
	game.add_child(overlay)

## Advances to the next quality level (wraps), re-applies it, informs the game
## object if it keeps its own `quality`/`apply_quality`, and shows a toast.
## Bound to F6 by performance_overlay.gd.
## [param game] mission root; must provide toast(text, seconds).
static func cycle(game):
	var q=(quality(game.get_tree())+1)%NAMES.size()
	game.get_tree().set_meta("graphics_quality",q)
	apply(game)
	if game.get("quality")!=null:game.quality=q
	if game.has_method("apply_quality"):game.apply_quality()
	game.toast("GRAPHICS: "+NAMES[q],3)

## Returns to the main menu scene and frees the mouse (the "Mission Menu"
## route out of a mission).
static func menu(game):
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.get_tree().change_scene_to_file("res://scenes/menu.tscn")
