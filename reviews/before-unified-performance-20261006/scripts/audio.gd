## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/audio.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Audio service for the desert mission: sound-effect loader, one-shot players
## and looping wind music.
##
## Role: created as a child of the game node (game.gd). Other scripts call
## play() for non-positional sounds (UI, the player's own weapon) and at() for
## world-positioned sounds that fall off with distance. The Ardennes and Omaha
## missions use scripts/ardennes/audio.gd, which has a bounded voice pool.
## Under the headless display driver audio is disabled so tests stay stable.
extends Node

## Sound name -> loaded WAV, from res://assets/audio/<name>.wav.
var streams: Dictionary = {}

## Looping ambient wind player.
var music: AudioStreamPlayer

## False when running headless (tests/CI); all play calls become no-ops.
var enabled: bool = DisplayServer.get_name() != "headless"

## Godot lifecycle hook: loads every sound and starts the wind loop.
func _ready():
	# The headless dummy audio driver does not release active WAV voices reliably.
	# Simulation tests do not need audio playback; normal desktop launches do.
	# Headless dummy audio driver does not release WAV voices reliably, so
	# tests get a silent placeholder player only.
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

	# Re-arm manually instead of using stream loop flags so the loop works with
	# any imported WAV settings; the is_inside_tree guard avoids restarting
	# during scene teardown.
	music.finished.connect(func(): if is_inside_tree(): music.play())
	music.play()

## Stops every voice and drops stream references on scene exit so the engine
## can release audio resources cleanly.
func _exit_tree():
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	streams.clear()

## Plays a non-positional one-shot sound.
## [param sound] key in `streams` ("rifle", "bolt", "sword", "hit", "clang",
## "step", "reload", "victory", "wind").
## [param volume] gain in dB (default -8). [param pitch] playback speed
## multiplier (1.0 normal) used for variation.
## A player node is created per call and frees itself when finished.
func play(sound: String, volume: float = -8, pitch: float = 1.0):
	if not enabled: return
	var p = AudioStreamPlayer.new()
	add_child(p)
	p.stream = streams[sound]
	p.volume_db = volume
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	p.play()

## Plays a 3D positioned one-shot sound.
## [param pos] world position. [param volume] dB. [param pitch] multiplier.
## Rifle shots carry farther (210 m, unit size 11) than other sounds (65 m, 7).
func at(sound: String, pos: Vector3, volume: float = 0, pitch: float = 1.0):
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
