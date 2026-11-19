# ==============================================================================
# Program: audio.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for audio.gd.
# ==============================================================================
## Omaha-specific audio: same sounds as Ardennes but tuned for a very large, loud beach.
##
## Extends the Ardennes audio script. The difference is `at()`: with hundreds of
## soldiers firing, positional sounds create a fresh player per call (not the
## Ardennes voice pool) and are throttled by three limits (child count, per-frame
## count) so the mixer is not flooded.
extends "res://scripts/ardennes/audio.gd"

## Play a positional sound, dropping it if the mixer is already saturated.
## @param sound Key in `streams`.
## @param pos World position in metres.
## @param volume Gain in dB, raised by 4 dB internally to cut through the barrage.
## @param pitch Playback speed multiplier.
func at(sound:String,pos:Vector3,volume:float=0,pitch:float=1.0):
	# Hard cap: more than 42 child nodes means plenty of voices are already playing.
	if not enabled or get_child_count()>42:return
	# Reset the per-frame voice counter when a new render frame starts.
	if voice_frame!=Engine.get_process_frames():
		voice_frame=Engine.get_process_frames()
		frame_voices=0
	# At most 5 new voices per frame so a volley does not stack into a single loud spike.
	if frame_voices>=5:return
	frame_voices+=1
	var p=AudioStreamPlayer3D.new()
	add_child(p)
	p.position=pos
	p.stream=streams[sound]
	# +4 dB boost so distant gunfire stays audible against the noise floor.
	p.volume_db=volume+4
	p.pitch_scale=pitch
	# Rifle and explosion are audible up to 1.4 km across the beach; everything else only 100 m.
	p.max_distance=1400 if sound in ["rifle","explosion"] else 100
	# Larger unit_size = slower falloff; rifles are loudest.
	p.unit_size=30 if sound=="rifle" else 18
	# One-shot node frees itself when finished (this variant has no voice pool).
	p.finished.connect(p.queue_free)
	p.play()
