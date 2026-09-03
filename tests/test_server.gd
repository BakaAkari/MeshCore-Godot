extends SceneTree
## E2E (headless-safe): _init blocks in a poll loop because headless
## --script mode does not drive _process.
var server := MeshCoreServer.new()
var importer := MeshCoreImporter.new()
var root3d := Node3D.new()
var got_any := false

func _init() -> void:
	root3d.name = "MeshCoreRoot"
	root.add_child(root3d)
	server.entities_received.connect(_on_entities)
	server.deletes_received.connect(_on_deletes)
	if server.start() != OK:
		quit(1)
		return
	var t := 0
	var idle := 0
	while t < 120000:  # 2 min max
		server.poll()
		OS.delay_msec(8)
		t += 8
		idle += 8
		if got_any and idle > 8000:
			break
	print("[GODOT-E2E] done")
	quit(0)

func _on_entities(entities: Array) -> void:
	got_any = true
	importer.apply_entities(entities, root3d)
	for e in entities:
		var info := "[GODOT-E2E] %s pos=(%.2f, %.2f, %.2f)" % [e.path, e.pos.x, e.pos.y, e.pos.z]
		if e.type == MeshCoreProtocol.ENTITY_MESH and not e.indices.is_empty():
			var nv: int = e.points.size() / 3
			info += " verts=%d n0=(%.2f, %.2f, %.2f) tris=%d,%d,%d" % [
				nv, e.normals[0], e.normals[1], e.normals[2],
				e.indices[0], e.indices[1], e.indices[2]]
			# face normal of first tri vs first loop normal (winding check)
			var p0: int = e.indices[0]
			var p1: int = e.indices[1]
			var p2: int = e.indices[2]
			var a := Vector3(e.points[p0*3], e.points[p0*3+1], e.points[p0*3+2])
			var b := Vector3(e.points[p1*3], e.points[p1*3+1], e.points[p1*3+2])
			var c := Vector3(e.points[p2*3], e.points[p2*3+1], e.points[p2*3+2])
			var fn := (b - a).cross(c - a).normalized()
			info += " faceN=(%.2f, %.2f, %.2f) dot=%.2f" % [fn.x, fn.y, fn.z,
				fn.dot(Vector3(e.normals[0], e.normals[1], e.normals[2]))]
		print(info)

func _on_deletes(paths: Array) -> void:
	got_any = true
	importer.apply_deletes(paths, root3d)
	for p in paths: print("[GODOT-E2E] deleted %s" % p)
