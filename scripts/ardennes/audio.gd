extends "res://scripts/audio.gd"

var frame_voices:int=0
var voice_frame:int=0
var voices:Array[AudioStreamPlayer3D]=[]
var next_voice:int=0

func _ready():
	super._ready()
	if not enabled:return
	for i in range(32):
		var voice=AudioStreamPlayer3D.new()
		add_child(voice)
		voices.append(voice)
	for key in ["engine","explosion"]:
		streams[key]=load("res://assets/audio/"+key+".wav")

func at(sound:String,pos:Vector3,volume:float=0,pitch:float=1.0):
	if not enabled or not streams.has(sound):return
	if voice_frame!=Engine.get_process_frames():
		voice_frame=Engine.get_process_frames()
		frame_voices=0
	if frame_voices>=5:return
	frame_voices+=1
	var p:AudioStreamPlayer3D
	for i in range(voices.size()):
		var slot=(next_voice+i)%voices.size()
		if not voices[slot].playing:
			p=voices[slot]
			next_voice=(slot+1)%voices.size()
			break
	if p==null:return
	p.position=pos
	p.stream=streams[sound]
	p.volume_db=volume+4
	p.pitch_scale=pitch
	p.max_distance=900 if sound in ["rifle","explosion"] else 100
	p.unit_size=30 if sound=="rifle" else 18
	p.play()
