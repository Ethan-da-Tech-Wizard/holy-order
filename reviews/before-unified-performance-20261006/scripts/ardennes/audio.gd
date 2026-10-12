extends "res://scripts/audio.gd"

var frame_voices:int=0
var voice_frame:int=0

func _ready():
	super._ready()
	if not enabled:return
	for key in ["engine","explosion"]:
		streams[key]=load("res://assets/audio/"+key+".wav")

func at(sound:String,pos:Vector3,volume:float=0,pitch:float=1.0):
	if not enabled or get_child_count()>36:return
	if voice_frame!=Engine.get_process_frames():
		voice_frame=Engine.get_process_frames()
		frame_voices=0
	if frame_voices>=4:return
	frame_voices+=1
	super.at(sound,pos,volume,pitch)
