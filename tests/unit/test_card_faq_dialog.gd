extends "res://tests/UTcommon.gd"

# The text of the single FAQ/Errata menu. Building it without the scene keeps
# the test independent from fonts and sizes.

const FaqDialog = preload("res://src/custom/CardFaqDialog.gd")


func test_body_keeps_faq_and_errata_in_separate_sections():
	var body: String = FaqDialog.build_body({
		"_faq": "Pergunta? R. Resposta.",
		"_errata": "Texto oficial da errata.",
	})
	assert_true(body.begins_with(
			"[color=#f0c96a][font_size=15][b]FAQ[/b][/font_size][/color]\n\n"
			+ "Pergunta? R. Resposta."),
			"FAQ opens the body")
	assert_true(body.ends_with(
			"[color=#f0c96a][font_size=15][b]Errata[/b][/font_size][/color]\n\n"
			+ "Texto oficial da errata."),
			"Errata follows as its own section")


func test_body_with_a_single_section():
	var faq_only: String = FaqDialog.build_body({"_faq": "Pergunta?"})
	assert_true(faq_only.begins_with("[color=#f0c96a]"), "FAQ heading present")
	assert_false(faq_only.contains("Errata"), "No empty errata section")
	var errata_only: String = FaqDialog.build_body({"_errata": "Errata."})
	assert_true(errata_only.contains("Errata"), "Errata heading present")
	assert_false(errata_only.contains("[b]FAQ[/b]"), "No empty FAQ section")


func test_body_escapes_bbcode():
	var body: String = FaqDialog.build_body({"_faq": "Use [X] aqui."})
	assert_true(body.contains("Use [lb]X[rb] aqui."),
			"Brackets in the catalog text are shown literally")


func test_body_is_empty_without_faq_or_errata():
	assert_eq(FaqDialog.build_body({}), "")
	assert_eq(FaqDialog.build_body({"_faq": "  ", "_errata": ""}), "")
