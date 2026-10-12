extends RefCounted
# Shared by all three missions. The 3D scene alone is scaled; text stays sharp.
const NAMES=["LOW / MAX FPS","STANDARD","HIGH"]
static func quality(tree:SceneTree)->int:
	return int(tree.get_meta("graphics_quality",0))

static func apply(game):
	var q=quality(game.get_tree())
	# The mass landing uses a lighter step in Low; camera and models interpolate.
	Engine.physics_ticks_per_second=20 if q==0 and game.get("boats")!=null else 30
	var viewport=game.get_viewport()
	viewport.scaling_3d_scale=0.40 if q==0 and game.get("boats")!=null else [0.50,0.75,1.0][q]
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	for light in game.find_children("*","Light3D",true,false):
		light.shadow_enabled=q==2 and light is DirectionalLight3D
		if light is DirectionalLight3D:light.directional_shadow_max_distance=60
	for environment in game.find_children("*","WorldEnvironment",true,false):
		var env=environment.environment
		env.ssao_enabled=false
		env.ssil_enabled=false
		env.ssr_enabled=false
		env.glow_enabled=false
		env.volumetric_fog_enabled=false
	for visual in game.find_children("*","GeometryInstance3D",true,false):
		if not visual.has_meta("original_shadow"):visual.set_meta("original_shadow",visual.cast_shadow)
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if q<2 else visual.get_meta("original_shadow")
	for camera in game.find_children("*","Camera3D",true,false):
		if not camera.has_meta("original_far"):camera.set_meta("original_far",camera.far)
		camera.far=minf(camera.get_meta("original_far"),[450.0,650.0,750.0][q])
	# Snapshot all spawn transforms before the first interpolated display frame.
	game.reset_physics_interpolation()

static func install(game):
	Engine.max_fps=60
	apply(game)
	var overlay=load("res://scripts/performance_overlay.gd").new()
	overlay.game=game
	game.add_child(overlay)

static func cycle(game):
	var q=(quality(game.get_tree())+1)%NAMES.size()
	game.get_tree().set_meta("graphics_quality",q)
	apply(game)
	if game.get("quality")!=null:game.quality=q
	if game.has_method("apply_quality"):game.apply_quality()
	game.toast("GRAPHICS: "+NAMES[q],3)

static func menu(game):
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.get_tree().change_scene_to_file("res://scenes/menu.tscn")
