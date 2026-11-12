extends "res://tests/UTcommon.gd"

const RenderResolution = preload("res://src/custom/RenderResolution.gd")
const FocusScript = preload("res://src/core/ViewportCardFocus.gd")

var cards := []

func before_each():
	await setup_main()
	cards = draw_test_cards(5)
	# The hand lays the drawn cards out with a tween; aim after it settles or
	# the hover targets a stale position.
	await yield_for(0.6)

func test_single_card_focus():
	var card : Card = cards[0]
	await move_mouse(card.global_position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	var focus_dupe = main._previously_focused_cards[card]
	assert_eq(main.card_focus.get_node('SubViewport').get_child_count(),2,
			"Duplicate card has been added for viewport focus")
	assert_eq(focus_dupe.scale,Vector2(1,1),
			"Duplicate card is scaled correctly")
	assert_eq(focus_dupe.get_node("Control").rotation,0.0,
			"Duplicate card is rotated correctly")
	assert_false(focus_dupe.is_in_group("cards"),
			"Duplicate card does not belong to the 'cards' group")
	assert_false(focus_dupe.highlight.visible,
			"Duplicate card does not have visible highlight")
	assert_not_null(focus_dupe.card_back, "card_back variable is populated")
	assert_eq(focus_dupe.get_node("Control/Back").get_child_count(), 1,
			"Duplicate card does not have duplicate card backs")
	assert_eq(focus_dupe.card_back.modulate.a, 1,
			"Duplicate card does not have visible highlight")
	assert_eq(focus_dupe.card_size, CFConst.CARD_SIZE * CFConst.FOCUSED_SCALE,
			"Duplicate resized correctly")
	assert_eq(focus_dupe._control.size, CFConst.CARD_SIZE * CFConst.FOCUSED_SCALE,
			"Duplicate's control resized correctly")

	await move_mouse(Vector2(0,0))
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	assert_eq(2,main.card_focus.get_node('SubViewport').get_child_count(),
			"Duplicate card object still remains")
	assert_false(main._previously_focused_cards[card].visible,
			"Duplicate is hidden")

func test_for_leftover_focus_objects():
	var card : Card = cards[2]
	await drag_drop(card,cfc.NMAP.discard.position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	await yield_for(0.5)
	assert_eq(2,main.card_focus.get_node('SubViewport').get_child_count(),
			"The top face-up card of the deck is now in focus")
	await move_mouse(Vector2(0,0), 'slow')
	assert_eq(2,main.card_focus.get_node('SubViewport').get_child_count(),
			"Duplicate card object still remains")
	assert_false(main._previously_focused_cards[card].visible,
			"Duplicate is hidden")

func test_card_back_focus():
	var card : Card = cards[0]
	card.is_faceup = false
	await move_mouse(card.global_position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	var focus_dupe = main._previously_focused_cards[card]
	assert_eq(focus_dupe.card_back.modulate.a, 1,
			"Duplicate card back does not modulate out")
	await move_mouse(Vector2(0,0))
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	assert_eq(2,main.card_focus.get_node('SubViewport').get_child_count(),
			"Duplicate card object still remains")

func test_deck_pile_hover_is_disabled():
	# The deck pile only shows card backs, so hovering it must not preview.
	var card : Card = deck.get_top_card()
	card.is_viewed = true
	await move_mouse(deck.global_position)
	await yield_for(0.3)
	assert_null(main._current_focus_source,
			"Hovering the deck does not focus any card")

func test_viewed_card_in_discard():
	var card : Card = cards[0]
	await drag_drop(card, cfc.NMAP.discard.position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	await move_mouse(Vector2(0, 0), "slow")
	await move_mouse(cfc.NMAP.discard.global_position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	assert_eq(2,main.card_focus.get_node('SubViewport').get_child_count(),
			"Duplicate card has been added for viewport focus")

func test_retain_properties():
	var card : Card = cards[0]
	# warning-ignore:return_value_discarded
	card.modify_property("Cost", 100, false, ["Init"])
	await move_mouse(card.global_position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	var focus_dupe = main._previously_focused_cards[card]
	assert_eq(focus_dupe.get_property("Cost"), 100,
			"Focus retains modified property values from original")

func test_FocusInfoPanel():
	var card : Card = cards[0]
	var card2 : Card = cards[2]
	var card3 : Card = cards[4]
	card2.properties["_illustration"] = "GUT"
	card.properties["_illustration"] = null
	card3.properties["_illustration"] = null
	card3.properties["Tags"] = []
	card3.properties["_keywords"] = ["Clarification A"]
	await move_mouse(card2.global_position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	# warning-ignore:unused_variable
	var focus_dupe = main._previously_focused_cards[card2]
	assert_eq(main.focus_info.modulate.a, 1.0,
			"FocusInfoPanel visible when illustration exists")
	assert_true(main.focus_info.existing_details['illustration'].visible,
			"Illustration label visible")
	await move_mouse(Vector2(0,0), "slow")
	await move_mouse(card.global_position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	focus_dupe = main._previously_focused_cards[card]
	assert_eq(main.focus_info.modulate.a, 1.0,
			"FocusInfoPanel visible through the card text panel")
	assert_false(main.focus_info.existing_details['illustration'].visible,
			"Illustration label invisible")
	assert_true(main.focus_info.existing_details['card_text'].visible,
			"Card text panel visible for cards with abilities")
	assert_eq(main.focus_info.existing_details['card_text']\
			.get_node("Header").text, card.canonical_name,
			"Card text header shows the card name")
	await move_mouse(Vector2(0,0), "slow")
	await move_mouse(card3.global_position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	focus_dupe = main._previously_focused_cards[card3]
	assert_eq(main.focus_info.modulate.a, 1.0,
			"FocusInfoPanel visible")
	assert_false(main.focus_info.existing_details['illustration'].visible,
			"Illustration label invisible")
	assert_not_null(main.focus_info.existing_details['Tag 1'])
	if main.focus_info.existing_details.get('Tag 1'):
		assert_false(main.focus_info.existing_details['Tag 1'].visible,
				"Tag 1 label invisible")
	assert_not_null(main.focus_info.existing_details["Clarification A"])
	if main.focus_info.existing_details.get("Clarification A"):
		assert_true(main.focus_info.existing_details["Clarification A"].visible,
				"Clarification visible")

func test_card_text_panel_shows_each_action_as_its_own_block():
	var card : Card = cards[0]
	card.properties["Abilities"] = "Texto impresso."
	card.properties["_actions"] = [{
		"name": "SOCO DEMOLIDOR",
		"text": "SOCO DEMOLIDOR causa 4 pontos de dano no alvo.",
		"power": "Super Força",
		"cost": "1",
		"type": "Normal",
	}]
	await move_mouse(card.global_position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	var panel: Control = main.focus_info.existing_details['card_text']
	assert_true(panel.visible, "Card text panel visible")
	var details: RichTextLabel = panel.get_node("Details")
	assert_eq(details.text,
			"Texto impresso.\n\n"
			+ "[color=#f0c96a][b]SOCO DEMOLIDOR[/b][/color]\n"
			+ "[color=#8f97a8][font_size=11]Normal • Custo 1 • Super Força"
			+ "[/font_size][/color]\n"
			+ "SOCO DEMOLIDOR causa 4 pontos de dano no alvo.",
			"Each action has its name, metadata and text in its own block")


func test_card_text_panel_keeps_errata_out_of_the_hover():
	var card : Card = cards[0]
	card.properties["Abilities"] = "Texto impresso."
	card.properties["_errata"] = "Texto oficial da errata."
	await move_mouse(card.global_position)
	await yield_to(main._focus_tween, "tween_all_completed", 1)
	var panel: Control = main.focus_info.existing_details['card_text']
	assert_true(panel.visible, "Card text panel visible")
	var details: RichTextLabel = panel.get_node("Details")
	assert_eq(details.text, "Texto impresso.",
			"Errata waits in its own menu instead of replacing the text")


func test_faq_button_only_shows_where_the_card_can_be_read():
	var card : Card = cards[0]
	card.properties["_faq"] = "Pergunta? R. Resposta."
	var faq_button: Button = card.get_node("Control/FaqButton")
	card._refresh_faq_button()
	assert_false(faq_button.visible, "The button stays hidden in the hand")
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	assert_true(faq_button.visible, "The button appears on the field")
	card.set_state(Card.CardState.DRAGGED)
	assert_false(faq_button.visible, "The button hides while the card is dragged")
	card.set_state(Card.CardState.IN_POPUP)
	assert_true(faq_button.visible, "The button appears in the pile inspection")
	card.properties.erase("_faq")
	card._refresh_faq_button()
	assert_false(faq_button.visible, "A card without FAQ or errata has no button")

func test_faq_dialog_opens_with_the_card_text():
	var card : Card = cards[0]
	card.canonical_name = "Abutre"
	card.properties["Name"] = "Abutre"
	card.properties["_faq"] = "Pergunta? R. Resposta."
	card.properties["_errata"] = "Texto oficial da errata."
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	card._open_faq_dialog()
	var dialog = main.get_node_or_null("CardFaqDialog")
	assert_not_null(dialog, "The single dialog is hosted by the game main")
	assert_true(dialog.get_node("Root").visible, "The dialog covers the screen")
	var title: Label = dialog.get_node("Root/Center/Box/VBox/Header/Title")
	assert_eq(title.text, "Abutre", "The title names the card")
	var body: RichTextLabel = dialog.get_node(
			"Root/Center/Box/VBox/Scroll/Body")
	assert_true(body.text.contains("Pergunta? R. Resposta."),
			"FAQ text is shown")
	assert_true(body.text.contains("Texto oficial da errata."),
			"Errata text is shown")
	dialog.close()
	assert_false(dialog.get_node("Root").visible, "Closing hides the dialog")


func test_preview_centers_on_screen():
	var card: Card = cards[0]
	hand.remove_child(card)
	board.add_child(card)
	card.network_mirror = true
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	card.preview_locked = true
	main.focus_card(card)
	await yield_for(0.5)
	var vbc: Control = main.get_node("VBC")
	var expected: Vector2 = (main.get_viewport().get_visible_rect().size - vbc.size) / 2
	assert_true(abs(vbc.position.x - expected.x) <= 2.0
			and abs(vbc.position.y - expected.y) <= 2.0,
			"The preview centers on the screen")

# The preview and the table rasterise at the chosen density but keep the
# 1280x720 (and 300x450) design coordinates. The containers must keep `stretch`
# off: with it on, the engine forces the SubViewport back to the container size
# and the chosen density never reaches the screen.
func test_full_hd_density_reaches_the_viewports():
	cfc.game_settings[RenderResolution.SETTING] = RenderResolution.FULL_HD
	main._apply_render_density()
	await yield_for(0.2)
	assert_false(main._board_host.stretch,
			"The board container must not force its SubViewport size")
	assert_false(main.card_focus.stretch,
			"The preview container must not force its SubViewport size")
	assert_eq(main._board_viewport.size, Vector2i(1920, 1080),
			"The board rasterises at Full HD")
	assert_eq(main._board_viewport.size_2d_override, RenderResolution.DESIGN_SIZE,
			"The board keeps the 1280x720 design coordinates")
	assert_true(main._board_viewport.size_2d_override_stretch,
			"The board content fills the Full HD raster")
	assert_eq(main._board_host.size, Vector2(1920, 1080),
			"The board host covers the Full HD raster unscaled")
	assert_almost_eq(main._board_host.scale.x, 2.0 / 3.0, 0.001,
			"The board host is scaled back into the design rectangle")
	assert_eq(main._focus_viewport.size, Vector2i(450, 675),
			"The preview rasterises at Full HD density")
	assert_eq(main._focus_viewport.size_2d_override,
			RenderResolution.FOCUS_DESIGN_SIZE,
			"The preview keeps the 300x450 design coordinates")
	assert_eq(main.card_focus.size, Vector2(450, 675),
			"The preview host covers the dense raster unscaled")
	assert_almost_eq(main.card_focus.scale.x, 2.0 / 3.0, 0.001,
			"The preview host is scaled back into the 300x450 box")
	cfc.game_settings[RenderResolution.SETTING] = RenderResolution.HD


func test_hand_panel_opens_beside_the_cursor():
	var pos := FocusScript.hand_panel_position(
			Vector2(400, 300), Vector2(200, 120), Vector2(1280, 720))
	assert_eq(pos, Vector2(460, 240),
			"The hand text panel opens to the right of the cursor, vertically centered")


func test_hand_panel_flips_side_near_the_right_edge():
	var pos := FocusScript.hand_panel_position(
			Vector2(1200, 300), Vector2(200, 120), Vector2(1280, 720))
	assert_eq(pos, Vector2(940, 240),
			"Near the right edge the panel flips to the left of the cursor")


func test_hand_panel_stays_inside_the_screen():
	var bottom := FocusScript.hand_panel_position(
			Vector2(400, 700), Vector2(200, 120), Vector2(1280, 720))
	assert_eq(bottom, Vector2(460, 600),
			"The panel never hangs below the screen")
	var tiny := FocusScript.hand_panel_position(
			Vector2(10, 10), Vector2(800, 600), Vector2(640, 480))
	assert_eq(tiny, Vector2.ZERO,
			"A panel wider and taller than the screen is pinned to its corner")


# The mirrored cards of the opponent run the state machine every frame, and its
# ON_PLAY_BOARD branch used to unfocus the closeup right after the hover showed
# it, which is why the mirrored zones previewed nothing at all.
func test_locked_mirror_preview_survives_the_state_machine():
	var card: Card = cards[0]
	hand.remove_child(card)
	board.add_child(card)
	card.network_mirror = true
	card.set_state(Card.CardState.ON_PLAY_BOARD)

	card.preview_locked = true
	main.focus_card(card)
	await yield_for(0.5)
	assert_eq(main._current_focus_source, card,
			"The previewed mirror keeps the closeup")
	assert_true(main.card_focus.visible, "The closeup stays on screen")
	assert_true(main._previously_focused_cards[card].visible,
			"The duplicate of the mirror is shown")

	card.preview_locked = false
	await yield_for(0.5)
	assert_null(main._current_focus_source,
			"Releasing the lock lets the mirror clear the closeup again")

# The log names a card, and the table can hold another copy of it face down
# inside a pile. The preview has to read a copy the player is allowed to see.
func test_log_preview_reads_a_copy_the_player_can_see():
	var hud = add_child_autofree(load("res://src/custom/MatchHUD.tscn").instantiate())
	await yield_for(0.2)
	var hidden: Card = cards[1]
	var shown: Card = cards[2]
	hidden.canonical_name = "Carta Gêmea"
	shown.canonical_name = "Carta Gêmea"
	hidden.visible = false
	hidden.is_faceup = false
	hidden.was_public = false
	shown.visible = true
	shown.is_faceup = true
	# The hidden copy stays first in the group, which is the order that used to
	# win and preview the back of a card nobody was allowed to read.
	shown.remove_from_group("cards")
	shown.add_to_group("cards")

	assert_eq(hud._find_preview_card("Carta Gêmea"), shown,
			"The preview skips the copy the player cannot read")

	# A copy that went back to a hand is face down again, but both players
	# already saw it, so the log may still show its front.
	shown.visible = false
	hidden.visible = true
	hidden.was_public = true
	assert_eq(hud._find_preview_card("Carta Gêmea"), hidden,
			"A copy that was already public can be previewed face up")
