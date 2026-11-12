extends "res://tests/UTcommon.gd"

const CardText = preload("res://src/custom/BSOverridableUtils.gd")


# The hover panel reads better with one sentence per line, so every full stop
# that ends a sentence starts a new line.
func test_each_sentence_starts_a_new_line():
	assert_eq(CardText.break_sentences("Causa 2 de dano. Depois compre 1."),
			"Causa 2 de dano.\nDepois compre 1.")
	assert_eq(CardText.break_sentences("Um. Dois. Três."),
			"Um.\nDois.\nTrês.")


func test_decimal_numbers_stay_together():
	assert_eq(CardText.break_sentences("Custa 1.5 energia por turno."),
			"Custa 1.5 energia por turno.")
	assert_eq(CardText.break_sentences("Ganha 2.0 de escudo. Depois ataca."),
			"Ganha 2.0 de escudo.\nDepois ataca.")


func test_existing_lines_and_ellipses_are_kept():
	assert_eq(CardText.break_sentences("Primeira linha.\nSegunda linha."),
			"Primeira linha.\nSegunda linha.")
	assert_eq(CardText.break_sentences("Espere... Agora ataque."),
			"Espere...\nAgora ataque.")


# The breaks have to reach the panel through the bbcode assembly, not only the
# helper, or the hover text keeps coming as one paragraph.
func test_panel_breaks_the_printed_abilities():
	var details: String = CardText.new()._details_bbcode("Causa 2. Compre 1.", [])
	assert_eq(details, "Causa 2.\nCompre 1.")
