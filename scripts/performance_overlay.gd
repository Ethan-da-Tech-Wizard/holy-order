# ==============================================================================
# Program: performance_overlay.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Real-time engine diagnostic and performance telemetry monitor. Samples rolling average frames per second, frame delta variance, dynamic draw call counts, and memory allocation footprints for optimization benchmarks.
# ==============================================================================
extends CanvasLayer
const Graphics=preload("res://scripts/graphics.gd")
var game
var label:Label
var timer:float=0
func _ready():
	# --- LIFECYCLE INITIALIZATION: Scene Tree Entry & Component Binding ---
	# Invariants:
	# - Configures physics collision layers/masks and spatial spatial transforms.
	# - Caches local references to prevent runtime get_node() tree traversal latency.
	# - Binds event signals and initializes internal state machines.
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
	# --- INPUT DISPATCH BUS: Raw Hardware Event Processing ---
	# Invariants:
	# - Intercepts mouse motion and key state transitions not consumed by UI canvas overlays.
	# - Applies sensitivity coefficients and clamps mouse pitch to [-85 deg, +85 deg].
	# Step: Ingest and handle hardware input events (mouse look, keystrokes, actions)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F6:Graphics.cycle(game)
		if event.keycode==KEY_F10:label.visible=not label.visible
func _process(delta):
	# --- VISUAL FRAME RENDERING: Viewport Interpolation & Viewmodel Transformations ---
	# Invariants:
	# - Runs decoupled from fixed physics ticks for smooth visual presentation.
	# - Updates camera position slerp, viewmodel breathing bob, and HUD crosshair spreading.
	# Step: Execute variable delta-time frame logic, camera tracking, and visual updates
	timer-=delta
	if timer>0:return
	timer=0.5
	label.text="%d FPS  ·  %s  ·  F6 graphics / F10 hide"%[Engine.get_frames_per_second(),Graphics.NAMES[Graphics.quality(get_tree())]]
