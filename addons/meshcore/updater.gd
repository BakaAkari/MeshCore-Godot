class_name MeshCoreUpdater
extends RefCounted
## Self-update from GitHub Releases. Checks the latest tag against the
## local plugin.cfg version; downloads the release zip and overlays it on
## addons/meshcore/ using Godot's built-in ZIPReader (cross-platform —
## no system `unzip` dependency; editor restart is required regardless).
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
	var tmp := OS.get_cache_dir().path_join("meshcore_update.zip")
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		if code != 200:
			update_finished.emit(false, "download failed (HTTP %d) — is the repo public?" % code)
			return
		var msg := _extract_zip(tmp, ProjectSettings.globalize_path("res://"))
		DirAccess.remove_absolute(tmp)
		if msg != "":
			update_finished.emit(false, msg)
			return
		# stamp cfg version defensively (zip already stamped by CI)
		update_finished.emit(true, "updated to %s — restart the editor to load the new code" % tag)
	)
	http.download_file = tmp
	var err := http.request(url, ["User-Agent: meshcore-godot"])
	if err != OK:
		http.queue_free()
		update_finished.emit(false, "request failed: %s" % error_string(err))

## Extract `zip_path` over `dest_dir` (overlay, per-file replace).
## Returns "" on success or an error message. Skips directory entries.
static func _extract_zip(zip_path: String, dest_dir: String) -> String:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return "cannot open downloaded zip"
	var failed := 0
	for entry in zr.get_files():
		if entry.ends_with("/"):
			continue
		var target := dest_dir.path_join(entry)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
			failed += 1
			continue
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			failed += 1
			continue
		f.store_buffer(zr.read_file(entry))
		f.close()
	zr.close()
	if failed > 0:
		return "%d files failed to write (locked by editor? try updating after closing scenes)" % failed
	return ""
