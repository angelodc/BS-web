# The single menu for FAQ and errata. It is hosted by the game main, outside
# the board SubViewport, so it covers the whole screen and the text scrolls the
# same way wherever the card is being read from.
extends CanvasLayer

const TITLE_COLOUR := "f0c96a"
const HEADING_COLOUR := "8f97a8"

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Center/Box/VBox/Header/Title
@onready var _scroll: ScrollContainer = $Root/Center/Box/VBox/Scroll
@onready var _body: RichTextLabel = $Root/Center/Box/VBox/Scroll/Body


func _ready() -> void:
	_root.visible = false
	$Root/Dim.gui_input.connect(_on_Dim_gui_input)
	$Root/Center/Box/VBox/Header/Close.pressed.connect(close)


func show_card(card) -> void:
	_title.text = str(card.get_property("Name"))
	_body.text = build_body(card.properties)
	_root.visible = true
	_scroll.scroll_vertical = 0


func close() -> void:
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_Dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		close()


# Public so tests can build the text without instancing the whole scene.
static func build_body(properties: Dictionary) -> String:
	var faq := str(properties.get("_faq", "")).strip_edges()
	var errata := str(properties.get("_errata", "")).strip_edges()
	var blocks: Array[String] = []
	if not faq.is_empty():
		blocks.append(_section("FAQ", faq))
	if not errata.is_empty():
		blocks.append(_section("Errata", errata))
	return "\n\n".join(blocks)


static func _section(heading: String, text: String) -> String:
	return "[color=#" + TITLE_COLOUR + "][font_size=15][b]" + heading \
			+ "[/b][/font_size][/color]\n\n" + _escape(text)


static func _escape(text: String) -> String:
	# Both brackets have to be replaced in one pass: `[lb]` and `[rb]` contain
	# the opposite bracket, so two sequential replaces would escape the escapes.
	var escaped := ""
	for index in text.length():
		var character := text[index]
		if character == "[":
			escaped += "[lb]"
		elif character == "]":
			escaped += "[rb]"
		else:
			escaped += character
	return escaped
