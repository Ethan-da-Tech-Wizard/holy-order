# ==============================================================================
# Program: audio.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for audio.gd.
# ==============================================================================
## Ardennes audio: adds a pooled set of 3D voices for combat sound.
##
## Extends the global audio script. Instead of creating a new 3D player for every
## shot, `at()` reuses a ring of 32 pre-made players and limits new sounds per
## frame. This keeps CPU and memory stable during long firefights.
extends "res://scripts/audio.gd"

# Count of positional sounds already started this render frame.
var frame_voices:int=0

# The render frame number that `frame_voices` refers to.
var voice_frame:int=0

# Pre-built player nodes (the pool).
var voices:Array[AudioStreamPlayer3D]=[]

# Index where the next free-slot search starts, so voices are used round-robin.
var next_voice:int=0

## Build the pool and load the extra engine/explosion samples.
func _ready():
	# Base class loads the standard sound set and music.
	super._ready()
	# Nothing to prepare in headless mode.
	if not enabled:return
	# 32 voices is enough for the loudest firefights; extra sounds are simply dropped.
	for i in range(32):
		var voice=AudioStreamPlayer3D.new()
		add_child(voice)
		voices.append(voice)
	# Vehicle and explosion sounds are specific to this theater and not in the base list.
	for key in ["engine","explosion"]:
		streams[key]=load("res://assets/audio/"+key+".wav")

## Play a positional sound using a free pooled voice.
## @param sound Key in `streams`; unknown names are ignored.
## @param pos World position in metres.
## @param volume Gain in dB (+4 dB is added to cut through battle noise).
## @param pitch Playback speed multiplier.
func at(sound:String,pos:Vector3,volume:float=0,pitch:float=1.0):
	if not enabled or not streams.has(sound):return
	# Reset the per-frame counter when a new frame starts.
	if voice_frame!=Engine.get_process_frames():
		voice_frame=Engine.get_process_frames()
		frame_voices=0
	# At most 5 new sounds per frame, otherwise one volley of shots would use all voices.
	if frame_voices>=5:return
	frame_voices+=1
	var p:AudioStreamPlayer3D
	# Search round-robin from the last used slot so the oldest voices get reused fairly.
	for i in range(voices.size()):
		var slot=(next_voice+i)%voices.size()
		if not voices[slot].playing:
			p=voices[slot]
			next_voice=(slot+1)%voices.size()
			break
	# All voices busy: drop the sound rather than cut off one already playing.
	if p==null:return
	p.position=pos
	p.stream=streams[sound]
	p.volume_db=volume+4
	p.pitch_scale=pitch
	# Rifles and explosions carry 900 m; other sounds 100 m.
	p.max_distance=900 if sound in ["rifle","explosion"] else 100
	# Rifle falls off more slowly (unit_size 30) than other sounds (18).
	p.unit_size=30 if sound=="rifle" else 18
	p.play()
