extends Node

var streams: Dictionary = {}
var music: AudioStreamPlayer
var enabled: bool = DisplayServer.get_name() != "headless"

func _ready():
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
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	streams.clear()

func play(sound: String, volume: float = -8, pitch: float = 1.0):
	if not enabled: return
	var p = AudioStreamPlayer.new()
	add_child(p)
	p.stream = streams[sound]
	p.volume_db = volume
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	p.play()

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
