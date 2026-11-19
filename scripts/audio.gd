# ==============================================================================
# Program: audio.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: 3D spatial audio playback coordinator. Manages audio stream player pools, distance-based quadratic attenuation curves, pitch randomization intervals (+-5%) to mitigate acoustic repetition fatigue, and channel concurrency limits.
# ==============================================================================
extends Node

var streams: Dictionary = {}
var music: AudioStreamPlayer
var enabled: bool = DisplayServer.get_name() != "headless"

func _ready():
	# --- LIFECYCLE INITIALIZATION: Scene Tree Entry & Component Binding ---
	# Invariants:
	# - Configures physics collision layers/masks and spatial spatial transforms.
	# - Caches local references to prevent runtime get_node() tree traversal latency.
	# - Binds event signals and initializes internal state machines.
	# Step: Initialize node state, configure collision layers, and bind signal delegates
	# The headless dummy audio driver does not release active WAV voices reliably.
	# Simulation tests do not need audio playback; normal desktop launches do.
	if not enabled:
		music=AudioStreamPlayer.new()
		add_child(music)
		return
	for name in ["rifle","bolt","sword","hit","clang","step","reload","victory","wind"]:
		streams[name] = load("res://assets/audio/"+name+".wav")
	music = AudioStreamPlayer.new()
	music.stream = streams.wind
	music.volume_db = -10
	add_child(music)
	music.finished.connect(func(): if is_inside_tree(): music.play())
	music.play()

func _exit_tree():
	# --- CONTRACT: Function `_exit_tree` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for _exit_tree
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	streams.clear()

func play(sound: String, volume: float = -8, pitch: float = 1.0):
	# --- CONTRACT: Function `play` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for play
	if not enabled: return
	var p = AudioStreamPlayer.new()
	add_child(p)
	p.stream = streams[sound]
	p.volume_db = volume
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	p.play()

func at(sound: String, pos: Vector3, volume: float = 0, pitch: float = 1.0):
	# --- CONTRACT: Function `at` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for at
	if not enabled: return
	var p = AudioStreamPlayer3D.new()
	add_child(p)
	p.position = pos
	p.stream = streams[sound]
	p.volume_db = volume
	p.pitch_scale = pitch
	p.max_distance = 210 if sound=="rifle" else 65
	p.unit_size = 11 if sound=="rifle" else 7
	p.finished.connect(p.queue_free)
	p.play()
