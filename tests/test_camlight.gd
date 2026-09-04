extends SceneTree

func _initialize() -> void:
	var data := FileAccess.get_file_as_bytes("/tmp/mcg_wire_cam_light.bin")
	var r := MeshCoreProtocol.Reader.new(data)
	var scene := MeshCoreProtocol.parse_set_body(r)
	var bad := 0
	for e in scene.entities:
		print("entity type=%d path=%s pos=%s points=%d consumed_ok=%s" % [
			e.type, e.path, str(e.pos), e.points.size(), str(r.remaining() >= 0)])
		if e.path.is_empty(): bad += 1
	print("remaining=%d total=%d" % [r.remaining(), data.size()])
	if scene.entities.size() != 4 or bad > 0 or r.remaining() != 0:
		print("CAMLIGHT TEST FAIL")
		quit(1)
	print("CAMLIGHT TEST PASS")
	quit(0)
