## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/ardennes/audio.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
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

## Godot lifecycle hook: runs the base loader, then creates the voice pool and
## loads the extra "engine" and "explosion" sounds. Skips everything in
## headless runs (enabled == false).
func _ready():
	super._ready()
	if not enabled:return
	for key in ["engine","explosion"]:
		streams[key]=load("res://assets/audio/"+key+".wav")

## Plays `sound` at world position `pos` through a free pooled voice.
## [param sound] stream key; unknown keys are ignored. [param volume] dB
## offset (+4 dB is added to compensate for distance falloff). [param pitch]
## playback speed.
## Dropped silently if 5 sounds already started this frame or all 32 voices are busy.
## Rifles and explosions can be heard from 900 m, others from 100 m.
func at(sound:String,pos:Vector3,volume:float=0,pitch:float=1.0):
	if not enabled or get_child_count()>36:return
	if voice_frame!=Engine.get_process_frames():
		voice_frame=Engine.get_process_frames()
		frame_voices=0
	if frame_voices>=4:return
	frame_voices+=1
	super.at(sound,pos,volume,pitch)
