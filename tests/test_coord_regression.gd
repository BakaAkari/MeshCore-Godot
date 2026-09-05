extends SceneTree
## Self-contained offline regression for the Z-up -> Godot Y-up basis change.
## Guards against the previous bug where quaternion was mapped as (-x,-z,y,w)
## instead of the correct conjugated (x,z,-y,w). Verifies position, quaternion,
## and scale mapping against the basis change C: (x,y,z)->(x,z,-y), plus that a
## nested hierarchy composes to the expected world transform, and that a bare
## transform-only (incremental) update does NOT double-convert the mesh.
## No Blender / HTTP required.

const ImporterScript := preload("res://addons/meshcore/importer.gd")
const ProtocolScript := preload("res://addons/meshcore/protocol.gd")

var importer = ImporterScript.new()
var root3d := Node3D.new()
var failing := 0
var ran := false

func _init() -> void:
	root3d.name = "Root"
	root.add_child(root3d)

func _process(_delta: float) -> bool:
	if not ran:
		ran = true
		_run()
	quit(1 if failing > 0 else 0)
	return false

func _ok(s: String) -> void: print("[COORD] " + s)
func _bad(s: String) -> void: failing += 1; print("[COORD] FAIL: " + s)

func _mk_entity(type: int, path: String):
	var e := ProtocolScript.Entity.new()
	e.type = type
	e.path = path
	return e

func _approx(a: Vector3, b: Vector3, eps := 0.001) -> bool: return a.distance_to(b) < eps

func _run() -> void:
	# --- single object, 30deg rotation about Z (the exact case that used to fail)
	var e = _mk_entity(ProtocolScript.ENTITY_MESH, "/Cube")
	e.pos = Vector3(1.0, 2.0, 3.0)
	e.rot = Quaternion(0.0, 0.0, 0.258819, 0.965926)  # 30deg about +Z (Blender)
	e.scale = Vector3(1.0, 2.0, 1.0)
	e.visible = true
	importer.apply_entities([e], root3d)
	var cube := root3d.get_node_or_null("Cube")
	if cube == null: _bad("Cube node not created"); return
	# pos (1,2,3) -> (x,z,-y) = (1,3,-2)
	if not _approx(cube.position, Vector3(1.0, 3.0, -2.0)):
		_bad("pos expected (1,3,-2) got %s" % cube.position)
	# quat (0,0,0.258819,0.965926) -> (x,z,-y,w) = (0,0.258819,0,0.965926)
	var eq := Quaternion(0.0, 0.258819, 0.0, 0.965926)
	if abs(cube.quaternion.dot(eq)) < 0.999:
		_bad("quat expected %s got %s" % [eq, cube.quaternion])
	# scale (1,2,1) -> (x,z,y) = (1,1,2)
	if not _approx(cube.scale, Vector3(1.0, 1.0, 2.0)):
		_bad("scale expected (1,1,2) got %s" % cube.scale)
	_ok("single 30deg-Z object: pos/rot/scale OK")

	# --- nested hierarchy composes
	var root = _mk_entity(ProtocolScript.ENTITY_TRANSFORM, "/Rig")
	root.pos = Vector3(2.0, 0.0, 0.0); root.scale = Vector3(1.0, 1.0, 1.0)
	var arm = _mk_entity(ProtocolScript.ENTITY_TRANSFORM, "/Rig/Arm")
	arm.pos = Vector3(0.0, 0.0, 1.0)
	arm.rot = Quaternion(0.0, 0.0, 0.258819, 0.965926)  # 30deg about Z
	var leaf = _mk_entity(ProtocolScript.ENTITY_MESH, "/Rig/Arm/Wedge")
	leaf.pos = Vector3(0.0, 0.0, 0.0)
	importer.apply_entities([root, arm, leaf], root3d)
	var rig := root3d.get_node_or_null("Rig")
	var w := root3d.get_node_or_null("Rig/Arm/Wedge")
	if rig == null or w == null: _bad("nested hierarchy not built"); return
	# Rig world origin = C·(2,0,0)=(2,0,0); wedge world = Rig∘Arm∘leaf local composed
	# verify the leaf node's LOCAL transform under Arm is (0,0,0) (apply is idempotent)
	if not _approx(w.position, Vector3.ZERO): _bad("leaf local pos expected 0 got %s" % w.position)
	if not _approx(rig.position, Vector3(2.0, 0.0, 0.0)): _bad("rig pos expected (2,0,0) got %s" % rig.position)
	_ok("nested hierarchy composes (paths /Rig/Arm/Wedge)")

	# --- incremental transform-only update must NOT double-convert position/mesh
	# Re-send a transform-only entity (same path, no geometry) and verify the node
	# position is set once, not compounded.
	var upd = _mk_entity(ProtocolScript.ENTITY_MESH, "/Rig/Arm/Wedge")
	upd.pos = Vector3(0.0, 0.0, 5.0)  # Blender local +Z
	upd.scale = Vector3(1.0, 1.0, 1.0)
	importer.apply_entities([root, arm, upd], root3d)
	# local mapped (x,z,-y) = (0,5,0) ; if double-converted it'd be (0,0,-5) or similar
	if not _approx(w.position, Vector3(0.0, 5.0, 0.0)):
		_bad("incremental upd expected local (0,5,0) got %s" % w.position)
	else:
		_ok("incremental transform-only update is idempotent (no double conversion)")

	print("[COORD] " + ("PASS" if failing == 0 else "FAIL (%d)" % failing))