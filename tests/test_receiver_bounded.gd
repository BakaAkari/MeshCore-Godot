extends SceneTree
## Isolated bounded Godot receiver measurement on a NON-DEFAULT port.
## Measures how many entity batches arrive and how many log lines the
## plugin-style _on_entities handler would emit, over:
##   (a) a fixed idle window (expect 0 batches / 0 lines),
##   (b) after one real scene POST (expect 1 batch, N lines),
##   (c) after a second identical POST (counts again — receiver has no dedup;
##       suppression is Blender-side).
##
## The receiver here ONLY sets server.port to the given port — never 18080 —
## so it cannot collide with another receiver or a stale harness.
##
## Run: godot --headless --path . --script tests/test_receiver_bounded.gd -- <port> <idle_ms>
##
## The scene body is POSTed by an EXTERNAL python client (bench_send.py) in the
## test flow to keep this a pure receiver.

const ONE := "res://tests/fixtures/scene.bin"

var server := MeshCoreServer.new()
var importer := MeshCoreImporter.new()
var root3d := Node3D.new()
var batches := 0
var entity_count := 0
var log_lines := 0
var port := 18082
var idle_ms := 3000

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1: port = int(args[0])
	if args.size() >= 2: idle_ms = int(args[1])
	root3d.name = "RecvRoot"
	root.add_child(root3d)
	server.port = port
	server.entities_received.connect(_on_entities)
	server.deletes_received.connect(_on_deletes)
	if server.start() != OK:
		push_error("[BOUNDED] listen failed")
		quit(2)
		return
	print("[BOUNDED] listening on 127.0.0.1:%d" % port)
	_run_loop()

func _process(_delta: float) -> bool:
	# Headless --script: drive polling in _init loop instead; _process not called.
	return false

func _on_entities(entities: Array) -> void:
	batches += 1
	entity_count += entities.size()
	# Mimic plugin.gd's _on_entities verbosity (the visible editor log spam).
	log_lines += 1  # "received N entities"
	for e in entities:
		log_lines += 1  # decode line
		log_lines += 1  # apply line (or warning)
	importer.apply_entities(entities, root3d)
	print("[BOUNDED] batch=%d entities=%d log_lines=%d" % [batches, entities.size(), log_lines])

func _on_deletes(_paths: Array) -> void:
	batches += 1

func _run_loop() -> void:
	var t := 0
	var logged_idle := false
	while t < 60000:
		server.poll()
		OS.delay_msec(10)
		t += 10
		# After the first batch, wait a settle window then record idle silence.
		if batches > 0 and not logged_idle and t > (idle_ms + 2000):
			logged_idle = true
			print("[BOUNDED] settle: batches=%d entity_count=%d log_lines=%d (idle over %dms)" % [batches, entity_count, log_lines, idle_ms])
		if logged_idle and t > idle_ms * 2 + 3000:
			break
	if logged_idle:
		print("[BOUNDED] RESULT batches=%d entity_count=%d log_lines=%d" % [batches, entity_count, log_lines])
	else:
		print("[BOUNDED] RESULT batches=%d entity_count=%d log_lines=%d (idle window never saw a batch)" % [batches, entity_count, log_lines])
	quit(0)