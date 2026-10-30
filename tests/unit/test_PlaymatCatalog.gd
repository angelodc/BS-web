extends "res://tests/UTcommon.gd"

# The playmat each player uploads is trimmed to the ratio the board draws, capped
# at the suggested size and kept as a PNG in user://. It is the only artwork the
# web build ships, because the bundled playmats stay out of that export.

const PlaymatCatalog = preload("res://src/custom/PlaymatCatalog.gd")
const TEST_PATH := "user://tests/playmat_upload.png"


func after_each():
	var probe := File.new()
	if not probe.file_exists(TEST_PATH):
		return
	var directory := Directory.new()
	if directory.remove(TEST_PATH) != OK:
		gut.p("Could not remove " + TEST_PATH)


func _picture(width: int, height: int) -> Image:
	var image := Image.new()
	image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.8))
	return image


func test_big_upload_is_cropped_and_capped():
	var result := PlaymatCatalog.save_custom(_picture(3000, 2000), TEST_PATH)

	assert_true(result.get("ok", false), "The upload was saved")
	var saved := Image.new()
	assert_eq(saved.load(TEST_PATH), OK, "The saved PNG can be read back")
	assert_eq(saved.get_size(), Vector2(1920, 1080),
			"A big picture ends up at the suggested playmat size")


func test_small_upload_keeps_its_own_resolution():
	var result := PlaymatCatalog.save_custom(_picture(800, 600), TEST_PATH)

	assert_true(result.get("ok", false), "The upload was saved")
	assert_eq(result.get("size", Vector2.ZERO), Vector2(800, 450),
			"A small picture is only trimmed to 16:9, never enlarged")


func test_saved_playmat_is_readable_by_the_catalog():
	PlaymatCatalog.save_custom(_picture(1024, 1024), TEST_PATH)

	var texture = PlaymatCatalog.texture_for_path(TEST_PATH)

	assert_not_null(texture, "The catalog reads back what it saved")
	assert_eq(str(PlaymatCatalog.entry(
			PlaymatCatalog.CUSTOM_ID).get("path", "")),
			PlaymatCatalog.CUSTOM_PATH, "The custom entry points at user://")


func test_missing_artwork_yields_nothing():
	assert_null(PlaymatCatalog.texture_for_path(""),
			"An empty path has no texture")
	assert_null(PlaymatCatalog.texture_for_path("user://tests/nao_existe.jpg"),
			"A missing file has no texture")
	assert_eq(str(PlaymatCatalog.entry("inexistente").get("id", "")),
			PlaymatCatalog.NONE_ID, "An unknown id falls back to no playmat")
	assert_eq(str(PlaymatCatalog.list()[0].get("id", "")),
			PlaymatCatalog.NONE_ID, "The selector always offers the plain board")
