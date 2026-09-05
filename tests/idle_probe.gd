extends SceneTree
## Headless: start MeshCoreServer (the plugin's per-frame polled piece),
## run N frames idle, count prints via a captured logger. We cannot capture
## engine print() directly, so we measure server behaviour (connections,
## emitted signals) instead and reason about prints from code paths.
const PORT := 18091

var server: MeshCoreServer
var batches := 0
var deletes := 0

func _init() -> void:
	server = MeshCoreServer.new()
	server.port = PORT
	server.entities_received.connect(func(_e): batches += 1)
	server.deletes_received.connect(func(_d): deletes += 1)
	var err := server.start()
	print("START err=%d listening=%s" % [err, server.is_listening()])
	# idle: 120 frames of pure poll() — no clients
	for i in 120:
		server.poll()
	print("IDLE120 frames done: batches=%d deletes=%d peers=%d" % [batches, deletes, server._peers.size()])
	quit()
