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
	var root := get_editor_interface().get_edited_scene_root()
	if root == null: return
	importer.apply_entities(entities, root)

func _on_deletes(paths: Array) -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null: return
	importer.apply_deletes(paths, root)
