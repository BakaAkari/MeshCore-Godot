extends SceneTree
## Incremental-sync regression: applying a transform-only / subset next-tick set
## over an existing full scene must NOT double-convert the leaf's local position,
## must NOT destroy the applied mesh, and must NOT create duplicate nodes.
## Uses committed fixtures (tests/fixtures/incremental.bin), no /tmp prerequisite.
##
## Run:  godot --headless --path . --script tests/test_incremental_fixture.gd

const ImporterScript := preload("res://addons/meshcore/importer.gd")
const ProtocolScript := preload("res://addons/meshcore/protocol.gd")
const FIXTURE := "res://tests/fixtures"

var importer = ImporterScript.new()
var root3d := Node3D.new()
var failing := 0
var ran := false

func _init() -> void:
	root3d.name = "Root"
	root.add_child(root3d)

func _process(_d: float) -> bool:
	if not ran:
		ran = true
		_run()
	quit(1 if failing > 0 else 0)
	return false

func _fail(s: String) -> void: failing += 1; print("[INC] FAIL: " + s)

func _run() -> void:
	var full: Dictionary = ProtocolScript.decode_set(FileAccess.get_file_as_bytes(FIXTURE + "/scene.bin"))
	var inc: Dictionary = ProtocolScript.decode_set(FileAccess.get_file_as_bytes(FIXTURE + "/incremental.bin"))
	if (inc.get("entities", []) as Array).is_empty():
		_fail("incremental.bin empty — regenerate via tests/tools/generate_fixture.py"); return
	importer.apply_entities(full.entities, root3d)
	importer.apply_entities(inc.entities, root3d)
	# full-scene Wedge must still exist with its mesh, unmodified
	var w := root3d.get_node_or_null("Root/Arm/Wedge")
	if w == null:
		_fail("Wedge missing after incremental"); return
	# incremental leaf WedgeE is a distinct leaf; incremental emitted ancestor
	# transforms (Root, Arm) and the seed leaf 'Wedge' — but our incremental.bin
	# used only_paths={"/Root/Arm/Wedge"} so the leaf is 'Wedge' itself.
	var mi := w.get_node_or_null("Mesh") as MeshInstance3D
	if mi == null or mi.mesh == null or mi.mesh.get_faces().size() == 0:
		_fail("Wedge mesh missing/destroyed after incremental"); return
	# no duplicate leaf children under Arm
	var arm := root3d.get_node_or_null("Root/Arm")
	if arm == null: _fail("Arm missing after incremental"); return
	var leaves := 0
	for c in arm.get_children():
		if c.name.begins_with("Wedge"): leaves += 1
	if leaves != 1:
		_fail("Arm has %d Wedge* leaves, expected 1 (no duplication)" % leaves); return
	# incremental re-applied Root/Arm/Wedge transform-idempotently: local pos of
	# Wedge should equal its single-mapped value, not a compounded/mirrored one.
	# Wedge local location was (0.1,0.2,0.0) -> C-mapped (x,z,-y) = (0.1,0.0,-0.2).
	if w.position.distance_to(Vector3(0.1, 0.0, -0.2)) > 0.002:
		_fail("Wedge local pos after incremental got %s, expected (0.1,0,-0.2)" % w.position); return
	print("[INC] PASS: incremental over full — no double-convert, mesh survived, no duplication")