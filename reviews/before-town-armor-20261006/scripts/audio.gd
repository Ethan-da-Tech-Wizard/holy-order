# ==============================================================================
# Program: audio.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for audio.gd.
# ==============================================================================
## Global sound player (autoloaded or added as a child of the game).
##
## Owns the looping background wind track and two helpers: `play()` for flat UI /
## player sounds and `at()` for positional 3D sounds such as distant gunfire.
## Every one-shot spawns a temporary player node that frees itself when finished.
## In headless runs (tests, benchmarks) audio is disabled entirely, see `enabled`.
extends Node

# Name -> loaded AudioStreamWAV. Filled once in _ready from res://assets/audio/<name>.wav.
var streams: Dictionary = {}

# Looping ambient/music player; created even when audio is disabled so callers can touch it safely.
var music: AudioStreamPlayer

# Headless mode uses a dummy audio driver; skip all playback there.
var enabled: bool = DisplayServer.get_name() != "headless"

## Load every sound and start the looping wind ambience.
func _ready():
	# (existing note) The headless driver leaks voices, so tests get an empty music node instead of real playback.
	# The headless dummy audio driver does not release active WAV voices reliably.
	# Simulation tests do not need audio playback; normal desktop launches do.
	if not enabled:
		music=AudioStreamPlayer.new()
		add_child(music)
		return
	# The complete list of sound names callers may pass to play() / at(); a name missing here raises on lookup.
	for name in ["rifle","bolt","sword","hit","clang","step","reload","victory","wind"]:
		streams[name] = load("res://assets/audio/"+name+".wav")
	music = AudioStreamPlayer.new()
	# Wind is the quiet default bed under all missions; -10 dB keeps it below gunfire.
	music.stream = streams.wind
	music.volume_db = -10
	add_child(music)
	# Manual loop: restart on finish, guarded by is_inside_tree so quitting the scene does not replay a dead node.
	music.finished.connect(func(): if is_inside_tree(): music.play())
	music.play()

## Stop and release every voice on exit.
func _exit_tree():
	# Explicitly dropping streams lets the engine free WAV data and avoids leak warnings at shutdown.
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	streams.clear()

## Play a non-positional sound (UI, own weapon).
## @param sound Key from the `streams` table.
## @param volume Volume in dB (negative is quieter; default -8).
## @param pitch Playback speed multiplier, 1.0 is normal; vary it to avoid repetitive sounds.
func play(sound: String, volume: float = -8, pitch: float = 1.0):
	if not enabled: return
	var p = AudioStreamPlayer.new()
	add_child(p)
	p.stream = streams[sound]
	p.volume_db = volume
	p.pitch_scale = pitch
	# Self-cleaning one-shot: free the node when playback ends so voices do not pile up.
	p.finished.connect(p.queue_free)
	p.play()

## Play a sound at a world position with distance falloff.
## @param sound Key from the `streams` table.
## @param pos World position in metres.
## @param volume Gain in dB.
## @param pitch Playback speed multiplier.
func at(sound: String, pos: Vector3, volume: float = 0, pitch: float = 1.0):
	if not enabled: return
	var p = AudioStreamPlayer3D.new()
	add_child(p)
	p.position = pos
	p.stream = streams[sound]
	p.volume_db = volume
	p.pitch_scale = pitch
	# Rifle shots carry much further (210 m) than footsteps, clangs and hits (65 m).
	p.max_distance = 210 if sound=="rifle" else 65
	# unit_size sets how quickly volume drops with distance; louder sounds get a larger value.
	p.unit_size = 11 if sound=="rifle" else 7
	p.finished.connect(p.queue_free)
	p.play()
