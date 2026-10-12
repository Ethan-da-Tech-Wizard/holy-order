extends "res://scripts/ardennes/audio.gd"
func at(sound:String,pos:Vector3,volume:float=0,pitch:float=1.0):
	if not enabled or get_child_count()>42:return
	if voice_frame!=Engine.get_process_frames():
		voice_frame=Engine.get_process_frames()
		frame_voices=0
	if frame_voices>=5:return
	frame_voices+=1
	var p=AudioStreamPlayer3D.new()
	add_child(p)
	p.position=pos
	p.stream=streams[sound]
	p.volume_db=volume+4
	p.pitch_scale=pitch
	p.max_distance=1400 if sound in ["rifle","explosion"] else 100
	p.unit_size=30 if sound=="rifle" else 18
	p.finished.connect(p.queue_free)
	p.play()
