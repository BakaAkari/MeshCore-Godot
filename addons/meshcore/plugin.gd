@tool
extends EditorPlugin

var server: MeshCoreServer
var importer := MeshCoreImporter.new()

func _enter_tree() -> void:
	server = MeshCoreServer.new()
	server.entities_received.connect(_on_entities)
	server.deletes_received.connect(_on_deletes)
	server.start()

func _exit_tree() -> void:
	if server: server.stop()

func _process(_delta: float) -> void:
	if server: server.poll()

func _on_entities(entities: Array) -> void:
	print("[MeshCore] received %d entities" % entities.size())
	for e in entities:
		print("[MeshCore]   decode: type=%d path=%s points=%d indices=%d" % [
			e.type, e.path, e.points.size(), e.indices.size()])
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		push_warning("[MeshCore] NO SCENE OPEN in the editor — %d entities DISCARDED. Open/create a scene in the editor, then sync again." % entities.size())
		return
	print("[MeshCore] applying to edited scene root: '%s'" % root.name)
	importer.apply_entities(entities, root)
	for e in entities:
		var rel: String = String(e.path).trim_prefix("/")
		var n: Node = root.get_node_or_null(rel)
		if n == null:
			push_warning("[MeshCore]   apply FAILED, node missing after import: %s" % e.path)
		else:
			var mi: Node = n.get_node_or_null("Mesh") if n is Node3D else null
			print("[MeshCore]   apply OK: %s (node=%s, mesh=%s)" % [
				e.path, n.get_class(), "yes" if mi else "no"])

func _on_deletes(paths: Array) -> void:
	print("[MeshCore] received %d deletes" % paths.size())
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		push_warning("[MeshCore] NO SCENE OPEN in the editor — %d deletes DISCARDED." % paths.size())
		return
	importer.apply_deletes(paths, root)
