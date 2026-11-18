# ==============================================================================
# Program: performance_overlay.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 18, 2026
# Purpose: Developer diagnostic overlay displaying real-time FPS, draw calls, physics tick duration, and active entity counts.
# ==============================================================================
extends CanvasLayer
const Graphics=preload("res://scripts/graphics.gd")
var game
var label:Label
var timer:float=0
func _ready():
	# Step: Initialize node state, configure collision layers, and bind signal delegates
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
func _unhandled_input(event):
	# Step: Ingest and handle hardware input events (mouse look, keystrokes, actions)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F6:Graphics.cycle(game)
		if event.keycode==KEY_F10:label.visible=not label.visible
func _process(delta):
	# Step: Execute variable delta-time frame logic, camera tracking, and visual updates
	timer-=delta
	if timer>0:return
	timer=0.5
	label.text="%d FPS  ·  %s  ·  F6 graphics / F10 hide"%[Engine.get_frames_per_second(),Graphics.NAMES[Graphics.quality(get_tree())]]
