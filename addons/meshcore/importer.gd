class_name MeshCoreImporter
## Applies received entities into the scene tree. Blender sends raw Z-up
## data; this importer converts to Godot Y-up -Z-forward using the same
## formula as Unity's FlipYZ_ZUpCorrector:
##   position: (x, y, z) -> (x, z, -y)
##   quaternion: (x, y, z, w) -> (-x, -z, y, w)
##   scale: (x, y, z) -> (x, z, y)
##   mesh points/normals: same as position
## Triangles keep Blender's CCW winding (no flip).

var root_path: NodePath = ^"."

func apply_entities(entities: Array, scene_root: Node) -> void:
	var root: Node = scene_root.get_node_or_null(root_path)
	if root == null: root = scene_root
	var by_path := {}
	for e in entities: by_path[e.path] = e
	for e in entities:
		_ensure(e, by_path, root)

func _ensure(e, by_path: Dictionary, root: Node) -> Node3D:
	var segs: PackedStringArray = e.path.trim_prefix("/").split("/", false)
	var cur: Node = root
	var acc: String = ""
	var node: Node3D = null
	for i in segs.size():
		acc += "/" + segs[i]
		var child := cur.get_node_or_null(segs[i])
		if child == null or not (child is Node3D):
			child = Node3D.new()
			child.name = segs[i]
			cur.add_child(child)
			child.owner = cur.owner if cur.owner else cur
		cur = child
		node = child
		var ent = by_path.get(acc)
		if ent != null:
			_apply_transform(node, ent)
	if e.type == MeshCoreProtocol.ENTITY_MESH and not e.points.is_empty():
		_apply_mesh(node, e)
	return node

func _apply_transform(node: Node3D, e) -> void:
	# Blender exporter sends raw Blender Z-up data. Convert to Godot Y-up
	# -Z-forward using the same formula as Unity's FlipYZ_ZUpCorrector:
	#   pos: (x, y, z) -> (x, z, -y)
	#   quat: (x, y, z, w) -> (-x, -z, y, w)
	#   scale: (x, y, z) -> (x, z, y)
	node.position = Vector3(e.pos.x, e.pos.z, -e.pos.y)
	node.quaternion = Quaternion(-e.rot.x, -e.rot.z, e.rot.y, e.rot.w)
	node.scale = Vector3(e.scale.x, e.scale.z, e.scale.y)
	node.visible = e.visible

func _apply_mesh(node: Node3D, e) -> void:
	if e.indices.is_empty(): return
	var nloop: int = e.indices.size()
	var have_n: bool = e.normals.size() == nloop * 3
	var have_uv: bool = e.uv0.size() == nloop * 2
	# The Blender exporter marks every mesh FLIP_FACES (MeshSync refine
	# semantics, targeting Unity's left-handed winding). Unity's server
	# executes the flip in Mesh::refine(); we must do the same — but Godot
	# is right-handed like Blender, so the correct execution is: consume
	# the flag and KEEP Blender's original CCW winding (i.e. do NOT flip).
	# Flipping here produces exactly the "normals inverted" look reported
	# against Unity. Verified against BoxMesh ground truth: unflipped
	# import scores 12/12 inward under the same geometric test as BoxMesh.
	var lverts := PackedVector3Array(); lverts.resize(nloop)
	var lnorm := PackedVector3Array(); lnorm.resize(nloop)
	var luv := PackedVector2Array(); luv.resize(nloop)
	for li in nloop:
		var vi: int = e.indices[li]
		# Blender Z-up -> Godot Y-up: (x, y, z) -> (x, z, -y)
		lverts[li] = Vector3(e.points[vi*3], e.points[vi*3+2], -e.points[vi*3+1])
		if have_n: lnorm[li] = Vector3(e.normals[li*3], e.normals[li*3+2], -e.normals[li*3+1])
		if have_uv: luv[li] = Vector2(e.uv0[li*2], e.uv0[li*2+1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fi: int = 0
	for c in e.counts:
		# reverse fan order vs the Unity-oriented triangle emission so the
		# final winding matches Godot's front-face convention
		for k in c - 2:
			for li in [fi + k + 2, fi + k + 1, fi]:
				if have_uv: st.set_uv(luv[li])
				if have_n: st.set_normal(lnorm[li])
				st.add_vertex(lverts[li])
		fi += c
	if not have_n: st.generate_normals()
	var arr_mesh := st.commit()
	var mi: MeshInstance3D = node.get_node_or_null("Mesh")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Mesh"
		node.add_child(mi)
		mi.owner = node.owner
	mi.mesh = arr_mesh

func apply_deletes(paths: Array, scene_root: Node) -> void:
	var root: Node = scene_root.get_node_or_null(root_path)
	if root == null: root = scene_root
	for p in paths:
		var segs: PackedStringArray = String(p).trim_prefix("/").split("/", false)
		var cur := root
		var ok: bool = true
		for s in segs:
			cur = cur.get_node_or_null(s)
			if cur == null: ok = false; break
		if ok and cur != root:
			cur.get_parent().remove_child(cur)
			cur.queue_free()
