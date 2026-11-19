# ==============================================================================
# Program: performance_overlay.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for performance_overlay.gd.
# ==============================================================================
## On-screen FPS counter with graphics-quality hotkeys.
##
## Created by the game script (which assigns `game`) as a top CanvasLayer. F6
## cycles the graphics quality through graphics.gd; F10 hides/shows the text.
extends CanvasLayer

# Graphics presets and the quality names displayed in the overlay.
const Graphics=preload("res://scripts/graphics.gd")

# The owning game object, passed to Graphics.cycle() so it can apply the new preset.
var game

# Single label that draws the FPS line in the top-left corner.
var label:Label

# Seconds left until the next text refresh.
var timer:float=0

## Build the label with a readable shadowed style above all other UI.
func _ready():
	# Layer 20 keeps the overlay above gameplay HUD layers.
	layer=20
	label=Label.new()
	# Ignore mouse so the overlay never steals clicks from the game.
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",14)
	# Shadow and light colour keep the text legible over both bright sky and dark interiors.
	label.add_theme_color_override("font_color",Color("c9d2cd"))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	add_child(label)
	label.position=Vector2(14,8)

## Handle the F6 / F10 hotkeys.
## @param event Input event; only fresh key presses (not echo repeats) count.
func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F6:Graphics.cycle(game)
		if event.keycode==KEY_F10:label.visible=not label.visible

## Refresh the FPS text twice a second.
## @param delta Seconds since last frame.
func _process(delta):
	timer-=delta
	# Updating every frame would churn string allocation for no readable benefit.
	if timer>0:return
	timer=0.5
	label.text="%d FPS  ·  %s  ·  F6 graphics / F10 hide"%[Engine.get_frames_per_second(),Graphics.NAMES[Graphics.quality(get_tree())]]
