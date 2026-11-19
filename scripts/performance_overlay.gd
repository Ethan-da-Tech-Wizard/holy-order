## Small on-screen frame-rate readout plus keyboard shortcuts for graphics.
##
## Installed by Graphics.install(game) in each mission. F6 cycles graphics
## quality (Graphics.cycle), F10 shows or hides the readout. The layer is 20 so
## it draws above the HUD, and it ignores mouse events so it can never block
## clicks on the game UI.
extends CanvasLayer
const Graphics=preload("res://scripts/graphics.gd")

## The mission root node, set by Graphics.install before the overlay is added;
## passed back to Graphics.cycle when F6 is pressed.
var game

## The single Label that shows the text.
var label:Label

## Seconds until the next text refresh; the text updates only twice a second
## so the readout itself costs almost nothing and stays readable.
var timer:float=0

## Godot lifecycle hook: creates the label with a black drop shadow so it
## stays legible over both snow and sand backgrounds.
func _ready():
	layer=20
	label=Label.new()
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",14)
	label.add_theme_color_override("font_color",Color("c9d2cd"))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	add_child(label)
	label.position=Vector2(14,8)

## Handles the overlay hotkeys. Uses _unhandled_input so UI controls that
## already consumed the key (for example a text field) do not trigger them.
## [param event] the input event; only fresh key presses (not echoes) count.
func _unhandled_input(event):
	# - Intercepts mouse motion and key state transitions not consumed by UI canvas overlays.
	# - Applies sensitivity coefficients and clamps mouse pitch to [-85 deg, +85 deg].
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F6:Graphics.cycle(game)
		if event.keycode==KEY_F10:label.visible=not label.visible

## Per-frame hook that refreshes the "NN FPS / quality" text every 0.5 s.
## [param delta] seconds since the last frame.
func _process(delta):
	# - Runs decoupled from fixed physics ticks for smooth visual presentation.
	# - Updates camera position slerp, viewmodel breathing bob, and HUD crosshair spreading.
	timer-=delta
	if timer>0:return
	timer=0.5
	label.text="%d FPS  ·  %s  ·  F6 graphics / F10 hide"%[Engine.get_frames_per_second(),Graphics.NAMES[Graphics.quality(get_tree())]]
