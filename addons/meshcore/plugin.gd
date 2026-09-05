@tool
extends EditorPlugin

var server: MeshCoreServer
var importer := MeshCoreImporter.new()
var _updater := MeshCoreUpdater.new()
var _update_btn: Button

func _enter_tree() -> void:
	server = MeshCoreServer.new()
	server.entities_received.connect(_on_entities)
	server.deletes_received.connect(_on_deletes)
	server.start()
	_setup_updater_ui()

func _exit_tree() -> void:
	if server: server.stop()
	if _update_btn:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _update_btn)
		_update_btn.queue_free()

func _setup_updater_ui() -> void:
	_update_btn = Button.new()
	_update_btn.text = "MeshCore"
	_update_btn.tooltip_text = "MeshCore live-link — click to check for updates"
	_update_btn.pressed.connect(_on_update_pressed)
	_updater.check_finished.connect(_on_check_finished)
	_updater.update_finished.connect(_on_update_finished)
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _update_btn)
	_updater.check_async()  # silent startup check

func _on_update_pressed() -> void:
	_update_btn.text = "MeshCore: checking…"
	_update_btn.disabled = true
	_updater.check_async()

func _on_check_finished(latest: String, has_update: bool) -> void:
	_update_btn.disabled = false
	var local := MeshCoreUpdater.local_version()
	if latest.is_empty():
		_update_btn.text = "MeshCore v%s" % local
		return
	if has_update:
		_update_btn.text = "MeshCore v%s → %s (update)" % [local, latest]
		_update_btn.tooltip_text = "Click again to download and apply %s" % latest
		_update_btn.pressed.disconnect(_on_update_pressed)
		_update_btn.pressed.connect(_on_apply_update.bind(latest))
	else:
		_update_btn.text = "MeshCore v%s (latest)" % local

func _on_apply_update(tag: String) -> void:
	_update_btn.text = "MeshCore: updating…"
	_update_btn.disabled = true
	_updater.apply_update(tag)

func _on_update_finished(ok: bool, message: String) -> void:
	_update_btn.disabled = false
	if _update_btn.pressed.is_connected(_on_apply_update):
		_update_btn.pressed.disconnect(_on_apply_update)
	if not _update_btn.pressed.is_connected(_on_update_pressed):
		_update_btn.pressed.connect(_on_update_pressed)
	if ok:
		_update_btn.text = "MeshCore: restart editor"
		print("[MeshCore] update applied: %s" % message)
	else:
		_update_btn.text = "MeshCore: update failed"
		push_warning("[MeshCore] self-update failed: %s" % message)

func _process(_delta: float) -> void:
	if server: server.poll()

func _on_entities(entities: Array) -> void:
	# Per-entity/per-connection logging was removed: with live auto-sync
	# (one TCP connection per message, 4 messages per sync pass) it printed
	# thousands of lines per second and froze the editor Output panel.
	# One summary line per batch is kept; failures still push_warning.
	print("[MeshCore] received %d entities" % entities.size())
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

func _on_deletes(paths: Array) -> void:
	print("[MeshCore] received %d deletes" % paths.size())
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		push_warning("[MeshCore] NO SCENE OPEN in the editor — %d deletes DISCARDED." % paths.size())
		return
	importer.apply_deletes(paths, root)
