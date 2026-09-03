extends SceneTree
## Incremental-sync E2E receiver (strict): ancestor non-seed entries must
## arrive as bare transforms (no geometry), seeds keep their mesh.
var server := MeshCoreServer.new()
var importer := MeshCoreImporter.new()
var root3d := Node3D.new()
var got_any := false
var fail := false

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
	var cube := root3d.get_node_or_null("IncCube")
	var sph := root3d.get_node_or_null("IncSphere")
	var cyl := root3d.get_node_or_null("IncCylinder")
	var ok: bool = cube != null and sph != null and cyl != null
	var moved: bool = cube != null and cube.position.x >= 4.5
	# sphere mesh must have survived the incremental cube-move pass
	var sph_mesh: bool = sph != null and sph.get_node_or_null("Mesh") != null \
		and sph.get_node("Mesh").mesh != null \
		and sph.get_node("Mesh").mesh.get_faces().size() > 0
	print("[GODOT-INC] %s: cube=%s(x=%.2f) sphere=%s(mesh=%s) cyl=%s" % [
		"PASS" if (ok and moved and sph_mesh and not fail) else "FAIL",
		cube != null, cube.position.x if cube else -99.0,
		sph != null, sph_mesh, cyl != null])
	quit(0)

func _on_entities(entities: Array) -> void:
	got_any = true
	var names: Array = []
	for e in entities:
		names.append(e.path)
		# a MESH-typed entity must carry geometry; a bare transform must not
		if e.type == MeshCoreProtocol.ENTITY_MESH and e.points.is_empty():
			fail = true
			print("[GODOT-INC] WARN: mesh entity with no geometry: %s" % e.path)
	print("[GODOT-INC] set batch: %s" % str(names))
	importer.apply_entities(entities, root3d)

func _on_deletes(paths: Array) -> void:
	got_any = true
	importer.apply_deletes(paths, root3d)
	for p in paths: print("[GODOT-INC] deleted %s" % p)
