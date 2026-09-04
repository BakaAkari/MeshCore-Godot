class_name MeshCoreUpdater
extends RefCounted
## Self-update from GitHub Releases. Checks the latest tag against the
## local plugin.cfg version; downloads the release zip and overlays it on
## addons/meshcore/ via the system `unzip` (self-overwrite is safe on
## macOS/Linux; editor restart is required regardless).
## Requires the repo to be PUBLIC (no token available in a plugin).

signal check_finished(latest: String, has_update: bool)
signal update_finished(ok: bool, message: String)

const REPO := "BakaAkari/MeshCore-Godot"
const API_LATEST := "https://api.github.com/repos/%s/releases/latest" % REPO
const ADDON_DIR := "res://addons/meshcore"

static func local_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(ADDON_DIR + "/plugin.cfg") != OK:
		return ""
	return str(cfg.get_value("plugin", "version", ""))

static func _version_newer(latest: String, current: String) -> bool:
	var lp := latest.trim_prefix("v").split(".")
	var cp := current.trim_prefix("v").split(".")
	for i in maxi(lp.size(), cp.size()):
		var l := int(lp[i]) if i < lp.size() else 0
		var c := int(cp[i]) if i < cp.size() else 0
		if l != c:
			return l > c
	return false

func check_async() -> void:
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		http.queue_free()
		if code != 200:
			check_finished.emit("", false)
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			check_finished.emit("", false)
			return
		var latest := str(data.get("tag_name", ""))
		check_finished.emit(latest, _version_newer(latest, local_version()))
	)
	var err := http.request(API_LATEST, ["User-Agent: meshcore-godot"])
	if err != OK:
		http.queue_free()
		check_finished.emit("", false)

func apply_update(tag: String) -> void:
	var zip_name := "MeshCore-Godot-%s.zip" % tag.trim_prefix("v")
	var url := "https://github.com/%s/releases/download/%s/%s" % [REPO, tag, zip_name]
	var tmp := "/tmp/meshcore_update.zip"
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		if code != 200:
			update_finished.emit(false, "download failed (HTTP %d) — is the repo public?" % code)
			return
		var out := []
		var err := OS.execute("unzip", ["-o", tmp, "-d", ProjectSettings.globalize_path("res://")], out, true)
		DirAccess.remove_absolute(tmp)
		if err != 0:
			update_finished.emit(false, "unzip failed: %s" % "\n".join(out))
			return
		# stamp cfg version defensively (zip already stamped by CI)
		update_finished.emit(true, "updated to %s — restart the editor to load the new code" % tag)
	)
	http.download_file = tmp
	var err := http.request(url, ["User-Agent: meshcore-godot"])
	if err != OK:
		http.queue_free()
		update_finished.emit(false, "request failed: %s" % error_string(err))
