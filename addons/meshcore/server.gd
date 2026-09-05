class_name MeshCoreServer
extends RefCounted
## Minimal HTTP/1.1 server speaking the MeshSync wire protocol.
## Routes: GET /protocol_version, POST /set, POST /delete, POST /fence.
## Call poll() regularly (from _process or a manual loop).

signal entities_received(entities: Array)   # Array[MeshCoreProtocol.Entity]
signal deletes_received(paths: Array)
signal get_received()

const H_CONTINUE := "HTTP/1.1 100 Continue\r\n\r\n"
const H_OK := "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\nContent-Length: %d\r\n\r\n"

var host := "0.0.0.0"
var port := 18080
var protocol_version := 124

var _server := TCPServer.new()
var _peers: Array[Dictionary] = []  # {peer, buf, cont_sent}

func start() -> int:
	stop()
	var err := _server.listen(port, host)
	if err == OK:
		print("[MeshCore] listening on %s:%d" % [host, port])
	else:
		push_error("[MeshCore] listen failed: %s" % error_string(err))
	return err

func stop() -> void:
	for p in _peers: p.peer.disconnect_from_host()
	_peers.clear()
	if _server.is_listening(): _server.stop()

func is_listening() -> bool: return _server.is_listening()

func poll() -> void:
	if not _server.is_listening(): return
	while _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(),
			"buf": PackedByteArray(), "cont_sent": false})
	var keep: Array[Dictionary] = []
	for p in _peers:
		var peer: StreamPeerTCP = p.peer
		peer.poll()
		var st := peer.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			var n := peer.get_available_bytes()
			if n > 0:
				p.buf.append_array(peer.get_data(n)[1])
				if _try_handle(p):
					peer.disconnect_from_host()
					continue  # response sent, drop
			keep.append(p)
		elif st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
			pass  # disconnected, drop
		else:
			keep.append(p)
	_peers = keep

## Try to parse one complete HTTP request from p.buf.
## Returns true when the request was fully handled (peer can be closed).
func _try_handle(p: Dictionary) -> bool:
	var buf: PackedByteArray = p.buf
	# need full header block
	var h_end := _find_header_end(buf)
	if h_end < 0:
		return false
	var head := buf.slice(0, h_end).get_string_from_utf8()
	var lines := head.split("\r\n")
	if lines.is_empty(): return true
	var req := lines[0].split(" ")
	if req.size() < 2: return true
	var method := req[0]
	var path := req[1].trim_prefix("/")
	var content_len := 0
	var expect_continue := false
	for i in range(1, lines.size()):
		var l := lines[i]
		var low := l.to_lower()
		if low.begins_with("content-length:"):
			content_len = l.split(":")[1].strip_edges().to_int()
		elif low.begins_with("expect:") and low.contains("100"):
			expect_continue = true
	var body_start := h_end + 4
	if buf.size() < body_start + content_len:
		return false  # wait for the body
	if expect_continue and not p.cont_sent:
		# Only send 100-continue once the FULL BODY has arrived: Python's
		# http.client blocks in getresponse() until it sees either the 100
		# or the final response. Sending 100 while the body is still in
		# flight lets our final 200 cross with the client's body upload —
		# http.client raises ResponseNotReady, the client thinks the send
		# failed, retries forever (infinite re-import loop + UI lag).
		p.peer.put_data(H_CONTINUE.to_utf8_buffer())
		p.cont_sent = true
	var body := buf.slice(body_start, body_start + content_len)
	_respond(p.peer, method, path, body)
	return true

func _respond(peer: StreamPeerTCP, method: String, path: String, body: PackedByteArray) -> void:
	var payload := ""
	if method == "GET" and path == "protocol_version":
		payload = str(protocol_version)
	elif method == "POST":
		match path:
			"set":
				var scene := MeshCoreProtocol.decode_set(body)
				entities_received.emit(scene.entities)
			"delete":
				deletes_received.emit(MeshCoreProtocol.decode_delete(body))
			"fence":
				pass  # SceneBegin/SceneEnd: no payload needed for apply
	peer.put_data((H_OK % payload.length()).to_utf8_buffer() + payload.to_utf8_buffer())

func _find_header_end(buf: PackedByteArray) -> int:
	# search for \r\n\r\n
	for i in buf.size() - 3:
		if buf[i] == 13 and buf[i+1] == 10 and buf[i+2] == 13 and buf[i+3] == 10:
			return i
	return -1
