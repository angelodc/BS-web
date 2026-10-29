extends Reference

# The playmat is the artwork behind the whole board. It is a local preference:
# each player sees their own choice, so it never travels through the relay.

const PLAYMAT_SETTING := "playmat_id"
const NONE_ID := "nenhum"
const DEFAULT_ID := "battle_scenes"

const PLAYMATS := [
	{
		"id": "battle_scenes",
		"name": "Battle Scenes",
		"path": "res://assets/playmats/battle_scenes.png",
	},
]


# Entries offered by the selector: the plain board plus every artwork that is
# actually present in the project.
static func list() -> Array:
	var entries := [{"id": NONE_ID, "name": "Sem playmat", "path": ""}]
	for playmat in PLAYMATS:
		if texture_for_path(str(playmat.get("path", ""))) == null:
			continue
		entries.append(playmat)
	return entries


static func entry(id: String) -> Dictionary:
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
	var resource = load(path)
	if resource is Texture:
		return resource
	return null
