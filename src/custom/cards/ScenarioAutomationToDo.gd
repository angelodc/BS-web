# Pendências da automação de cenários.
#
# Todo cenário real usa só compras e topo→recursos como efeito automático. O
# restante do texto impresso fica aqui: entra no log em amarelo quando o
# cenário entra em cena e quando o jogador usa uma opção manual, para lembrar o
# que ainda precisa ser resolvido na mesa.
class_name ScenarioAutomationToDo
extends RefCounted

const Catalog = preload("res://src/custom/cards/ScenarioCatalog.gd")


static func pending_of(card) -> Array:
	return Catalog.pending_of(card)


static func has_pending(card) -> bool:
	return not Catalog.pending_of(card).is_empty()


# The printed fragments that still need the player, one per line, without the
# trigger noise. An empty list means the scenario is fully automated.
static func describe(card) -> String:
	return "\n".join(PackedStringArray(Catalog.pending_of(card)))


static func is_negation(card) -> bool:
	return Catalog.is_negation(card)
