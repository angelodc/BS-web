# This file contains just card definitions. See also `CardConfig.gd`

extends Reference

const SET = "Demo Set 2"
const CARDS := {
	"Test Card 3": {
		"Type": "Green",
		"_tipo": "Personagem",
		"ENERGIA": "3",
		"Tags": ["Tag 1","Tag 2"],
		"Requirements": "",
		"Abilities": "While on board, this card will flip face-down " \
				+ "and rotate 180 degrees a target." \
				+ "\n\nWhile on the hand, this card will remove " \
				+ "a target card from the game" \
				+ "\n\nAfter another card is rotated, gain a blood token.",
		"Cost": 0,
		"Power": 9001,
		"_keywords": ["Keyword 1","Clarification A"]
	},
	"Multiple Choices Test Card": {
		"Type": "Blue",
		"_tipo": "Personagem",
		"ENERGIA": "3",
		"Tags": ["Tag 2","Tag 3"],
		"Requirements": "",
		"Abilities": "While on board, either rotate 90, or flip face-down." \
				+ "\n\nWhile on hand, discard up to 5 cards " \
				+ "from the top of the deck",
		"Cost": 0,
		"Power": 0,
	},
	"Demo Scenario 2": {
		"Type": "Purple",
		"_tipo": "Cenário",
		"ENERGIA": "0",
		"Tags": [],
		"Requirements": "",
		"Abilities": "Use this card to test replacing the active scenario.",
		"Cost": 0,
		"Power": 0,
	},
	"Demo Support": {
		"Type": "Green",
		"_tipo": "Suporte",
		"ENERGIA": "3",
		"Tags": [],
		"Requirements": "",
		"Abilities": "Use this card to test resource attachments for Supports.",
		"Cost": 0,
		"Power": 0,
	},
}
