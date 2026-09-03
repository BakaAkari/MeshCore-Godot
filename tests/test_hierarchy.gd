extends SceneTree
## Hierarchy incremental E2E: after child move, child mesh must survive,
## child position must reflect the move.
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
	var par := root3d.get_node_or_null("Par")
	var chi: Node3D = root3d.get_node_or_null("Par/Chi") if par != null else null
	print("[GODOT-HIER-DBG] par=%s chi=%s" % [par, chi])
	var chi_mesh: bool = false
	if chi != null:
		var mi = chi.get_node_or_null("Mesh")
		print("[GODOT-HIER-DBG] mi=%s mesh=%s" % [mi, mi.mesh if mi else null])
		if mi != null and mi.mesh != null:
			chi_mesh = mi.mesh.get_faces().size() > 0
	var moved: bool = chi != null and chi.position.x >= 4.5
	print("[GODOT-HIER] %s: par=%s chi=%s(x=%.2f) chi_mesh=%s" % [
		"PASS" if (par != null and chi != null and chi_mesh and moved) else "FAIL",
		par != null, chi != null, chi.position.x if chi else -99.0, chi_mesh])
	quit(0)

func _on_entities(entities: Array) -> void:
	got_any = true
	var names: Array = []
	for e in entities:
		var tag := ""
		if e.type == MeshCoreProtocol.ENTITY_MESH:
			tag = " mesh(pts=%d)" % (e.points.size() / 3)
		names.append(e.path + tag)
	print("[GODOT-HIER] set batch: %s" % str(names))
	importer.apply_entities(entities, root3d)

func _on_deletes(paths: Array) -> void:
	got_any = true
	importer.apply_deletes(paths, root3d)
	for p in paths: print("[GODOT-HIER] deleted %s" % p)
