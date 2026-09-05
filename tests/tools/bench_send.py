#!/usr/bin/env python3
"""POST a pre-serialized MeshSync SetMessage (fixture scene.bin) to a live
Godot MeshCore receiver on a NON-DEFAULT port, exactly as the Blender client
does (Expect: 100-continue, octet-stream). Usage:
  python3 bench_send.py <port> <scene.bin> [count]
"""

import http.client
import sys

port = int(sys.argv[1])
path = sys.argv[2]
count = int(sys.argv[3]) if len(sys.argv) > 3 else 1
body = open(path, "rb").read()

for i in range(count):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10.0)
    try:
        conn.putrequest("POST", "/set")
        conn.putheader("Content-Type", "application/octet-stream")
        conn.putheader("Content-Length", str(len(body)))
        conn.putheader("Expect", "100-continue")
        conn.endheaders()
        conn.send(body)
        resp = conn.getresponse()
        resp.read()
        print(
            f"[send] POST /set #{i + 1} -> HTTP {resp.status} body={len(body)}B",
            flush=True,
        )
    finally:
        conn.close()
