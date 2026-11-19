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

## Build the pool and load the extra engine/explosion samples.
func _ready():
	# Base class loads the standard sound set and music.
	super._ready()
	# Nothing to prepare in headless mode.
	if not enabled:return
	# Vehicle and explosion sounds are specific to this theater and not in the base list.
	for key in ["engine","explosion"]:
		streams[key]=load("res://assets/audio/"+key+".wav")

## Play a positional sound using a free pooled voice.
## @param sound Key in `streams`; unknown names are ignored.
## @param pos World position in metres.
## @param volume Gain in dB (+4 dB is added to cut through battle noise).
## @param pitch Playback speed multiplier.
func at(sound:String,pos:Vector3,volume:float=0,pitch:float=1.0):
	if not enabled or get_child_count()>36:return
	# Reset the per-frame counter when a new frame starts.
	if voice_frame!=Engine.get_process_frames():
		voice_frame=Engine.get_process_frames()
		frame_voices=0
	if frame_voices>=4:return
	frame_voices+=1
	super.at(sound,pos,volume,pitch)
