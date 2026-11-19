## Audio service for the Ardennes and Omaha missions: adds a bounded pool of
## 3D voices to the desert version (scripts/audio.gd).
##
## Why a pool: these battles have hundreds of simultaneous gunshots; creating
## and freeing a player node per sound (as the base class does) would be too
## slow. Here 32 players are created once and reused, and at most 5 new sounds
## may start per rendered frame, which keeps the mixer load predictable.
extends "res://scripts/audio.gd"

## Sounds started in the current frame (limit 5).
var frame_voices:int=0

## Engine process-frame number that frame_voices refers to.
var voice_frame:int=0

## The reusable pool of 32 AudioStreamPlayer3D nodes.
var voices:Array[AudioStreamPlayer3D]=[]

## Where the next free-slot search starts, so voices are used round-robin.
var next_voice:int=0

## Godot lifecycle hook: runs the base loader, then creates the voice pool and
## loads the extra "engine" and "explosion" sounds. Skips everything in
## headless runs (enabled == false).
func _ready():
	super._ready()
	if not enabled:return
	for i in range(32):
		var voice=AudioStreamPlayer3D.new()
		add_child(voice)
		voices.append(voice)
	for key in ["engine","explosion"]:
		streams[key]=load("res://assets/audio/"+key+".wav")

## Plays `sound` at world position `pos` through a free pooled voice.
## [param sound] stream key; unknown keys are ignored. [param volume] dB
## offset (+4 dB is added to compensate for distance falloff). [param pitch]
## playback speed.
## Dropped silently if 5 sounds already started this frame or all 32 voices are busy.
## Rifles and explosions can be heard from 900 m, others from 100 m.
func at(sound:String,pos:Vector3,volume:float=0,pitch:float=1.0):
	if not enabled or not streams.has(sound):return
	if voice_frame!=Engine.get_process_frames():
		voice_frame=Engine.get_process_frames()
		frame_voices=0

	# Frame budget: during a volley only the first five sounds play, the rest
	# would be inaudible among the others anyway.
	if frame_voices>=5:return
	frame_voices+=1
	var p:AudioStreamPlayer3D

	# Round-robin search for an idle voice starting after the last one used.
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
