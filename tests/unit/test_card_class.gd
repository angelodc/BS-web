extends "res://tests/UTcommon.gd"

var card: Card
var cards := []

func before_all():
	cfc.game_settings.fancy_movement = false

func after_all():
	cfc.game_settings.fancy_movement = true

func before_each():
	await setup_board()
	card = cfc.NMAP.deck.get_top_card()
	
	
func test_methods():
	assert_eq('Card',card.get_card_class(), 'class name returns correct value')

func test_focus_setget():
	card.set_focus(true)
	card.state = Card.CardState.FOCUSED_IN_HAND
	assert_true(card.highlight.visible,
			'Highlight is set correctly to visible')
	assert_true(card.get_focus(),
			'get_focus returns true correct value correctly')
	card.set_focus(false)
	card.state = Card.CardState.IN_HAND
	assert_false(card.highlight.visible,
			'Highlight is set correctly to invisible')
	assert_false(card.get_focus(),
			'get_focus returns false correct value correctly')

func test_move_to():
	var discard : Pile = cfc.NMAP.discard
	var card2 = cfc.NMAP.deck.get_card(1)
	var card3 = cfc.NMAP.deck.get_card(2)
	var card4 = cfc.NMAP.deck.get_card(3)
	var card5 = cfc.NMAP.deck.get_card(4)
	var card6 = cfc.NMAP.deck.get_card(5)
	card.move_to(discard)
	card2.move_to(discard)
	assert_eq(1,discard.get_card_index(card2),
			'move_to without arguments puts card at the end')
	card3.move_to(discard, 0)
	assert_eq(0,discard.get_card_index(card3),
			'move_to can move card to the top')
	card4.move_to(discard, 2)
	assert_eq(2,discard.get_card_index(card4),
			'move_to can move card between others')
	card5.move_to(discard,2)
	card6.move_to(discard,2)
	assert_eq(2,discard.get_card_index(card6),
			'move_to can takeover/push index spots of other cards')
	assert_eq(3,discard.get_card_index(card5),
			'move_to can takeover/push index spots of other cards')
	assert_eq(4,discard.get_card_index(card4),
			'move_to can takeover/push index spots of other cards')

func test_init_card_name():
	# We need a yield to allow the richtextlabel setup complete
	await wait_process_frames(1)
	# We know which are the last 3 card types of the test cards
	var test3 = cfc.NMAP.deck.get_card(15)
	var test2 = cfc.NMAP.deck.get_card(14)
	var test1 = cfc.NMAP.deck.get_card(13)
	assert_eq("Test Card 1",test1.canonical_name,
			'card_name variable is set correctly')
	# Godot 4 renumbers duplicate sibling names ("Test Card 8"), so only the
	# card name prefix is guaranteed.
	assert_true(str(test1.name).begins_with("Test Card"))
	assert_eq("Test Card 1",test1.card_front.card_labels["Name"].text,
			'Name Label text is set correctly')
	assert_eq("Test Card 2",test2.canonical_name,
			'card_name variable is set correctly')
	assert_true(str(test2.name).begins_with("Test Card"))
	assert_eq("Test Card 2",test2.card_front.card_labels["Name"].text,
			'Name Label text is set correctly')
	assert_eq("Test Card 3",test3.canonical_name,
			'card_name variable is set correctly')
	assert_true(str(test3.name).begins_with("Test Card"))
	assert_eq("Test Card 3",test3.card_front.card_labels["Name"].text,
			'Name Label text is set correctly')

func test_card_name_setget():
	await wait_process_frames(1)
	card.set_card_name("Testing Name Change 1")
	# The label resize awaits a frame before it writes the text
	await wait_process_frames(1)
	assert_eq("Testing Name Change 1",card.canonical_name,
			'card_name variable is set correctly')
	assert_string_contains(str(card.name), "Testing Name Change 1")
	assert_eq("Testing Name Change 1",card.card_front.card_labels["Name"].text,
			'Name Label text is set correctly')
	card.canonical_name = "Testing Name Change 2"
	await wait_process_frames(1)
	assert_eq("Testing Name Change 2",card.canonical_name,
			'card_name variable is set correctly')
	assert_string_contains(str(card.name), "Testing Name Change 2")
	assert_eq("Testing Name Change 2",card.card_front.card_labels["Name"].text,
			'Name Label text is set correctly')

func test_CardDefinition_properties():
	cfc.card_definitions["GUT Card"] = {
		"Type": "Red",
		"Tags": ["Tag 1","Tag 2","GUT Tag"],
		"Requirements": "",
		"Abilities": "Gut Test",
		"_meta": "This is a meta property",
		"_meta2": "They are not displayed on the card",
		"Cost": 10,
		"ENERGIA": 10,
		"Power": 0,
	}
	var new_card = cfc.instance_card("GUT Card")
	board.add_child(new_card)
	new_card._determine_idle_state()
	# We need a yield to allow the richtextlabel setup complete
	await wait_process_frames(1)
	assert_eq(new_card.card_front.card_labels["Tags"].text,"Tag 1 - Tag 2 - GUT Tag",
			"Array property uses the separator")
	# The BS card front shows ENERGIA in the energy slot; the framework Cost
	# property is not displayed (see CardConfig.PROPERTIES_NOT_DISPLAYED).
	assert_eq(new_card.card_front.card_labels["ENERGIA"].text, "10",
			"Integer properties are converted into strings")

func test_font_size():
	var text_node = card.card_front.card_labels["Abilities"]
	var labels_rect = card.card_front._card_text.size
	var lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed vitae laoreet nunc. Etiam vitae tempus ligula. Vestibulum pellentesque mauris vel ultricies pharetra. Curabitur iaculis dolor vitae leo aliquet viverra sit amet vitae eros. Nulla eros turpis, mollis non elit eget, iaculis porta magna. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Nulla sem dui, consectetur ut nulla ut, vestibulum venenatis dui. Fusce sollicitudin bibendum quam, at scelerisque risus fringilla eu. Curabitur elementum sem sed nisi malesuada molestie. Nulla finibus, eros quis volutpat vehicula, dui mauris dictum metus, quis pellentesque sem quam eget mi. Vivamus convallis massa non ex laoreet pharetra. Proin sed leo at dui varius dapibus sit amet ac purus."
	card.card_front.set_rich_label_text(text_node, lorem)
	assert_eq(card.card_front._card_text.size,labels_rect)


# The fitting loop used to shrink past its own minimum check: when the first
# adjustment landed below 6 it never reached the "reached minimum size" branch
# and kept decrementing against a height it could not trust. On the web build
# that ended in a DynamicFont cache error and a frozen engine.
func test_rich_text_stops_at_the_minimum_font_size():
	var text_node: RichTextLabel = card.card_front.card_labels["Abilities"]
	# A narrow, short label and a long text force the first adjustment past the
	# floor, which is the case that used to slip under the minimum check.
	text_node.custom_minimum_size = Vector2(24, 12)
	var long_text := "Fitting floor check. ".repeat(40)
	await card.card_front.set_rich_label_text(text_node, long_text)
	_assert_rtl_fonts_at_least_minimum(text_node)


# A size cached by an earlier build could sit below the floor; the cached
# branch has to raise it instead of handing it to the font.
func test_cached_rich_text_size_respects_the_minimum():
	var text_node: RichTextLabel = card.card_front.card_labels["Abilities"]
	var text := "Cached floor check."
	var cache: Dictionary = cfc.font_size_cache.get(str(1), {})
	if not cache.has("Abilities"):
		cache["Abilities"] = {}
	cache["Abilities"][text.md5_text()] = -4
	cfc.font_size_cache[str(1)] = cache
	card.card_front.set_rich_label_text(text_node, text)
	_assert_rtl_fonts_at_least_minimum(text_node)


func _assert_rtl_fonts_at_least_minimum(text_node: RichTextLabel) -> void:
	for font_type in ["normal_font", "italics_font", "bold_font",
			"bold_italics_font", "title_font", "mono_font"]:
		var size := text_node.get_theme_font_size(font_type + "_size")
		assert_true(size >= CardFront.MIN_RTL_FONT_SIZE,
				"%s stays at or above the minimum (got %s)"
				% [font_type, size])

func test_number_properties_with_string_value():
	cfc.card_definitions["GUT Card"] = {
		"Type": "Red",
		"Tags": ["Tag 1","Tag 2","GUT Tag"],
		"Requirements": "",
		"Abilities": "Gut Test",
		"_meta": "This is a meta property",
		"_meta2": "They are not displayed on the card",
		"Cost": 'X',
		"ENERGIA": 'X',
		"Power": '1',
	}
	var new_card = cfc.instance_card("GUT Card")
	board.add_child(new_card)
	new_card._determine_idle_state()
	# We need a yield to allow the richtextlabel setup complete
	await wait_process_frames(1)
	assert_eq(new_card.card_front.card_labels["ENERGIA"].text,"X",
			"Numerical array allowed string value")
	assert_eq(new_card.card_front.card_labels["Power"].text, '1',
			"String number handled properly")
	assert_eq(new_card.properties.Power, 1,
			"Number property changed to integer")
	new_card.modify_property('Power', 'U')
	await wait_process_frames(1)
	assert_eq(new_card.card_front.card_labels["Power"].text,"U",
			"Numerical array allowed string value")


func test_number_properties_adjust():
	cfc.card_definitions["GUT Card"] = {
		"Type": "Red",
		"Tags": ["Tag 1","Tag 2","GUT Tag"],
		"Requirements": "",
		"Abilities": "Gut Test",
		"Cost": '1',
		"Power": '5',
	}
	var new_card = cfc.instance_card("GUT Card")
	board.add_child(new_card)
	new_card._determine_idle_state()
	# We need a yield to allow the richtextlabel setup complete
	await wait_process_frames(1)
	new_card.modify_property("Cost", "+3")
	new_card.modify_property("Power", "+3")
	await wait_process_frames(1)
	assert_eq(new_card.properties.Cost, 4,
			"Number property adjusted upwards")
	assert_eq(new_card.card_front.card_labels["Power"].text, '8',
			"Number property label adjusted upwards")
	new_card.modify_property("Power", "-3")
	await wait_process_frames(1)
	assert_eq(new_card.card_front.card_labels["Power"].text, '5',
			"Number property label adjusted downwards")
	assert_eq(new_card.properties.Power, 5,
			"Number property adjusted downwards")



func test_refresh_card_front():
	cfc.card_definitions["GUT Card"] = {
		"Type": "Red",
		"Tags": ["Tag 1","Tag 2","GUT Tag"],
		"Requirements": "",
		"Abilities": "Gut Test",
		"Cost": '1',
		"Power": '5',
	}
	var new_card = cfc.instance_card("GUT Card")
	board.add_child(new_card)
	new_card._determine_idle_state()
	# We need a yield to allow the richtextlabel setup complete
	await wait_process_frames(1)
	new_card.properties = {
		"Type": "Red",
		"Tags": ["Tag 3","Tag 4"],
		"Requirements": "",
		"Abilities": "Property Refreshed",
		"Cost": 'U',
		"ENERGIA": 'U',
		"Power": "+3",
	}
	# The rich text setter ignores requests while the label from setup is still
	# resizing, so let it settle first or the Abilities refresh is dropped.
	await wait_until(
			func(): return new_card.card_front.resizing_labels.is_empty(), 3)
	new_card.refresh_card_front()
	await wait_until(
			func(): return new_card.card_front.resizing_labels.is_empty(), 3)
	assert_eq(new_card.card_front.card_labels["ENERGIA"].text,"U",
			"Number Property refreshed as string")
	assert_eq(new_card.card_front.card_labels["Power"].text, '3',
			"String refreshed to int")
	assert_eq(new_card.card_front.card_labels["Tags"].text, "Tag 3 - Tag 4",
			"Tags refreshed")
	# Abilities is a RichTextLabel filled with append_text(), which leaves the
	# `text` property untouched; the drawn text is get_parsed_text().
	assert_eq(new_card.card_front.card_labels["Abilities"].get_parsed_text(),
			"Property Refreshed", "Abilities refreshed")
