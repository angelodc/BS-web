extends Reference

# The playmat is the artwork behind the whole board. It is a local preference:
# each player sees their own choice, so it never travels through the relay.

const PLAYMAT_SETTING := "playmat_id"
const NONE_ID := "nenhum"
const CUSTOM_ID := "custom"
const CUSTOM_NAME := "Meu playmat"
const DEFAULT_ID := "bs_web"
# The same artwork is the main menu backdrop and the default playmat. It ships
# as the original WebP: no re-encode touches the art, Godot 3.4 decodes it in
# Image.load(), and the file costs 114 KB instead of a one-megabyte PNG.
const BACKDROP_PATH := "res://assets/brand/bs_web_backdrop.webp"

# The web export ships without the bundled artwork to keep the download small, so
# each player uploads their own. It lives in user://, which the browser keeps in
# IndexedDB, and it stays on that machine: nothing here goes through the relay.
const CUSTOM_DIR := "user://playmats"
const CUSTOM_PATH := "user://playmats/meu_playmat.png"
# The board draws the playmat inside a 16:9 rectangle, so an upload is centred,
# trimmed to that ratio and capped at this size. Godot 3.4 encodes PNG only, so
# the result is a lossless file of a couple of megabytes at most.
const UPLOAD_MAX_SIZE := Vector2(1920, 1080)

const PLAYMATS := [
	{
		"id": "bs_web",
		"name": "BS Web",
		"path": BACKDROP_PATH,
	},
	{
		"id": "battle_scenes_fit",
		"name": "Battle Scenes Inteira",
		"path": "res://assets/playmats/battle_scenes_fit.png",
	},
	{
		"id": "battle_scenes_open",
		"name": "Battle Scenes Aberto",
		"path": "res://assets/playmats/battle_scenes_open.png",
	},
	{
		"id": "battle_scenes",
		"name": "Battle Scenes",
		"path": "res://assets/playmats/battle_scenes.png",
	},
]


# Entries offered by the selector: the plain board, the artwork the player
# uploaded, then every bundled one that is actually present in this build.
static func list() -> Array:
	var entries := [{"id": NONE_ID, "name": "Sem playmat", "path": ""}]
	if has_custom():
		entries.append(custom_entry())
	for playmat in PLAYMATS:
		if texture_for_path(str(playmat.get("path", ""))) == null:
			continue
		entries.append(playmat)
	return entries


static func custom_entry() -> Dictionary:
	return {"id": CUSTOM_ID, "name": CUSTOM_NAME, "path": CUSTOM_PATH}


static func has_custom() -> bool:
	return file_exists(CUSTOM_PATH)


static func entry(id: String) -> Dictionary:
	if id == CUSTOM_ID:
		return custom_entry()
	for playmat in PLAYMATS:
		if str(playmat.get("id", "")) == id:
			return playmat
	return {"id": NONE_ID, "name": "Sem playmat", "path": ""}


static func display_name(id: String) -> String:
	return str(entry(id).get("name", "Sem playmat"))


static func selected_id() -> String:
	var saved := str(cfc.game_settings.get(PLAYMAT_SETTING, ""))
	if saved.empty():
		return DEFAULT_ID
	return saved


static func remember_id(id: String) -> void:
	if id.empty() or selected_id() == id:
		return
	cfc.set_setting(PLAYMAT_SETTING, id)


static func texture_for_id(id: String) -> Texture:
	return texture_for_path(str(entry(id).get("path", "")))


# Loaded instead of preloaded so a missing artwork leaves the plain board
# working rather than breaking every script that references this catalog.
static func texture_for_path(path: String) -> Texture:
	if path.empty():
		return null
	# Asking for the file first keeps a missing artwork silent: the web export
	# drops the bundled playmats and load() would log an error for each one.
	if not file_exists(path):
		return null
	if ResourceLoader.exists(path):
		var resource = load(path)
		if resource is Texture:
			return resource
	# The editor only imports new art when its window gets focus, and a playmat
	# the player uploaded has no importer at all; decoding the file directly
	# keeps both working.
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return texture_from_image(image)


static func texture_from_image(image: Image,
		flags := Texture.FLAGS_DEFAULT) -> Texture:
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.new()
	# The artwork is smaller than the board and the menu, so the default flags
	# matter: without the filter it would be stretched with hard pixels.
	texture.create_from_image(image, flags)
	return texture


static func file_exists(path: String) -> bool:
	if path.empty():
		return false
	var probe := File.new()
	return probe.file_exists(path)


# Keeps the uploaded artwork for this machine only. The image is trimmed to the
# ratio the board draws and capped at UPLOAD_MAX_SIZE, so a phone photo and a 4K
# wallpaper both end up as the same 1920x1080 file.
static func save_custom(image: Image, path := CUSTOM_PATH) -> Dictionary:
	if image == null or image.is_empty():
		return {"ok": false, "reason": "A imagem escolhida está vazia."}
	var ratio := UPLOAD_MAX_SIZE.x / UPLOAD_MAX_SIZE.y
	var prepared := _cropped_to_ratio(image, ratio)
	_within_cap(prepared)
	if not _ensure_custom_dir(path):
		return {"ok": false,
				"reason": "Não foi possível criar a pasta do playmat."}
	if prepared.save_png(path) != OK:
		return {"ok": false, "reason": "Não foi possível salvar o playmat."}
	return {"ok": true, "size": prepared.get_size(), "path": path}


# The caller's image is converted in place: every caller hands over a picture it
# has just read from disk or from the browser and does not reuse it afterwards.
static func _cropped_to_ratio(image: Image, ratio: float) -> Image:
	var size := image.get_size()
	if size.x <= 0 or size.y <= 0:
		return image
	var target := size
	if float(size.x) / float(size.y) > ratio:
		target.x = int(round(float(size.y) * ratio))
	else:
		target.y = int(round(float(size.x) / ratio))
	if target == size:
		return image
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var offset := Vector2(int((size.x - target.x) * 0.5),
			int((size.y - target.y) * 0.5))
	var cropped := Image.new()
	# create() and blit_rect() answer nothing in Godot 3.4, so the crop is
	# confirmed by the size the new image ended up with.
	cropped.create(target.x, target.y, false, Image.FORMAT_RGBA8)
	cropped.blit_rect(image, Rect2(offset, Vector2(target)), Vector2.ZERO)
	if cropped.is_empty() or cropped.get_size() != target:
		return image
	return cropped


static func _within_cap(image: Image) -> void:
	var size := image.get_size()
	if size.x <= int(UPLOAD_MAX_SIZE.x) and size.y <= int(UPLOAD_MAX_SIZE.y):
		return
	# The crop already fixed the ratio, so the cap is the exact target and a big
	# wallpaper always lands on the suggested 1920x1080.
	image.resize(int(UPLOAD_MAX_SIZE.x), int(UPLOAD_MAX_SIZE.y),
			Image.INTERPOLATE_LANCZOS)


static func _ensure_custom_dir(path: String) -> bool:
	var directory := Directory.new()
	var folder := path.get_base_dir()
	if folder.empty() or directory.dir_exists(folder):
		return true
	return directory.make_dir_recursive(folder) == OK
