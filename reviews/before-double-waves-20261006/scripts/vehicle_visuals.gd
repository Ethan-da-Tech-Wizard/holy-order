extends RefCounted
# Moving vehicles keep individual armor colliders, but draw same-material panels
# together in vehicle-local coordinates. Wheels, ramps and crew keep their motion.
static func batch_boxes(root:Node3D,excluded:Array=[]):
	var groups={}
	for visual in root.find_children("*","MeshInstance3D",true,false):
		if not visual.mesh is BoxMesh or not visual.visible or visual.is_queued_for_deletion():continue
		var skip=false
		for node in excluded:
			if node==visual or node.is_ancestor_of(visual):skip=true
		if skip or visual.material_override==null:continue
		var key=visual.material_override.get_instance_id()
		if not groups.has(key):groups[key]=[]
		groups[key].append(visual)
	var count=0
	for key in groups:
		var visuals=groups[key]
		if visuals.size()<2:continue
		var mesh=BoxMesh.new()
		mesh.size=Vector3.ONE
		mesh.material=visuals[0].material_override.duplicate()
		if mesh.material is StandardMaterial3D:mesh.material.vertex_color_use_as_albedo=true
		var batch=MultiMeshInstance3D.new()
		batch.multimesh=MultiMesh.new()
		batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		batch.multimesh.use_colors=true
		batch.multimesh.mesh=mesh
		batch.multimesh.instance_count=visuals.size()
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(batch)
		batch.set_meta("vehicle_panel_batch",true)
		for i in range(visuals.size()):
			var visual=visuals[i]
			var xf=root.global_transform.affine_inverse()*visual.global_transform*Transform3D(Basis.IDENTITY.scaled(visual.mesh.size),Vector3.ZERO)
			batch.multimesh.set_instance_transform(i,xf)
			batch.multimesh.set_instance_color(i,Color.WHITE)
			var body=visual.get_parent()
			if body.get("integrity")!=null and body.has_method("damage_at"):
				body.refresh_bounds()
				body.render_batch=batch.multimesh
				body.render_index=i
				body.render_origin=xf.origin
			visual.hide()
			count+=1
	root.set_meta("batched_panels",count)
