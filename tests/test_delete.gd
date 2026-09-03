extends SceneTree
## Delete-sync E2E: create entities, delete one in Blender, verify removal.
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
	while t < 120000:
		server.poll()
		OS.delay_msec(8)
		t += 8
		idle += 8
		if got_any and idle > 8000:
			break
	# verify final tree state
	var keep := root3d.get_node_or_null("KeepCube")
	var gone := root3d.get_node_or_null("ByeCube")
	if keep != null and gone == null:
		print("[GODOT-DEL] PASS: KeepCube exists, ByeCube removed")
	else:
		print("[GODOT-DEL] FAIL: keep=%s gone=%s" % [keep, gone])
	quit(0)

func _on_entities(entities: Array) -> void:
	got_any = true
	importer.apply_entities(entities, root3d)
	for e in entities: print("[GODOT-DEL] set %s" % e.path)

func _on_deletes(paths: Array) -> void:
	got_any = true
	importer.apply_deletes(paths, root3d)
	for p in paths: print("[GODOT-DEL] deleted %s" % p)
