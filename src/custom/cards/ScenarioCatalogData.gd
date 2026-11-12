# Catálogo completo dos cenários do BS.
#
# Gerado do cards.json do BSDB por `.run/gen_scenario_catalog.js`. A chave é
# o `_bsdb_id` da definição. Cada entrada traz o nome impresso, as ações
# simples que a mesa executa sozinha (`enter`/`leave`), as opções A/B/C da
# carta e os trechos que continuam na mão do jogador (`pending`, mostrados no
# log em amarelo). `negation` marca o cenário que pede um pin X.
#
# Formato das ações: {"op": "comprar"|"mandar_topo_para_recursos", "quantity":
# N, "if": {condição}}. Condições checadas hoje:
#   {"type": "characters", "min": N}
#   {"type": "affiliation", "value": "X", "min": N}
#   {"type": "all_affiliation", "value": "X", "min": N}
#   {"type": "shared_affiliation", "min": N}
# Opções: timing "entry" (na entrada) ou "affiliation" (quando um personagem
# com a afiliação entra em cena sob seu controle), "before": "recursos" quando
# a carta manda colocar o cenário nos recursos antes de resolver a escolha.
#
# NÃO EDITE À MÃO: rode o gerador de novo.

const BY_ID := {
	"BSIV_058": {
		"name": "A Era de Ultron",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode incapacitar em 1 qualquer número de personagens que você controla e cujo alter ego seja ULTRON.",
			"Se o fizer, cada um dos personagens incapacitados desta forma causa 1 ponto de dano penetrante em um personagem ou suporte a sua escolha (os danos poderão ser atribuídos a diferentes personagens e suportes)."
		]
	},
	"BSET_048": {
		"name": "À Espreita",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando À ESPREITA sair de cena, se À ESPREITA tiver sido substituído por um novo cenário, o jogador que tiver colocado o novo cenário em cena escolhe um oponente.",
			"O oponente escolhido compra um card.",
			"Sempre que um vilão fosse causar dano, ele causará aquela quantidade de dano +1."
		]
	},
	"BSPO_044": {
		"name": "A Essência do Medo",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que uma ação de Antecipar causar dano, ela causará metade do dano, arredondado para baixo."
		]
	},
	"BSDS_051": {
		"name": "Aberrações Extraplanares",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Os jogadores podem colocar em cena personagens com Predador com o mesmo alter ego (ou nome, se não houver alter ego) de personagens sem Predador que estiverem em cena, desde que não controlem personagens com aquele mesmo alter ego (ou nome, se não houver alter ego)."
		]
	},
	"BSMI_053": {
		"name": "Ação Dupla",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, escolha um personagem em cena.",
			"Quando aquele personagem usar uma ação descrita em seu próprio card, você pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, aquele personagem poderá usar aquela ação outra vez neste turno (os custos da ação devem ser pagos a cada vez que ela é usada; o personagem não pode usar desta forma ações de nenhum dos cards que estiver carregando)."
		]
	},
	"BSCA_067": {
		"name": "Agroglifos",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com Poder Cósmico entrar em cena sob seu controle, você pode incapacitar aquele personagem em 1, colocar dois cards dos seus recursos na base do deck de seu dono e colocar este cenário em seus recursos.",
			"Se o fizer, olhe os quatro cards do topo de seu deck e coloque dois deles nos seus recursos e dois deles em sua mão."
		]
	},
	"BSPO_045": {
		"name": "Aguardar a Vez",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando AGUARDAR A VEZ entrar em cena, escolha um personagem que você não controla.",
			"Enquanto o controlador do personagem escolhido controlar mais personagens do que você, o personagem escolhido não poderá usar ações."
		]
	},
	"BSMI_054": {
		"name": "Ameaça Extremis",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, escolha um personagem que você controla com Energia Inicial 1 e então carregue um card de habilidade de seus recursos naquele personagem.",
			"O personagem escolhido tem os poderes dos cards de habilidade que ele estiver carregando."
		]
	},
	"BSCA_068": {
		"name": "Aparatos Exclusivos",
		"enter": [],
		"leave": [],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "Compre um card.",
					"action": {
						"op": "comprar",
						"quantity": 1
					}
				},
				{
					"label": "B",
					"text": "Você pode colocar em cena um suporte com uma afiliação em comum com ao menos dois personagens que você controla como se ele tivesse Materializar.",
					"manual": "colocar em cena um suporte com uma afiliação em comum com ao menos dois personagens que você controla como se ele tivesse Materializar."
				}
			]
		},
		"negation": false
	},
	"BSCA_069": {
		"name": "Aranhaverso",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {
			"timing": "affiliation",
			"items": [
				{
					"label": "A",
					"text": "coloque os dois cards do topo de seu deck em seus recursos.",
					"action": {
						"op": "mandar_topo_para_recursos",
						"quantity": 2
					}
				},
				{
					"label": "B",
					"text": "você pode procurar em seu deck por um card de personagem com a afiliação Aliados do Homem-Aranha.",
					"manual": "procurar em seu deck por um card de personagem com a afiliação Aliados do Homem-Aranha."
				}
			],
			"affiliation": "Aliados do Homem-Aranha",
			"timing_if": {
				"type": "affiliation",
				"value": "Aliados do Homem-Aranha",
				"min": 1
			},
			"before": "recursos"
		},
		"negation": false
	},
	"BSGC_053": {
		"name": "Artefato Falso",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se um personagem ou suporte que você não controla estiver carregando algum card de habilidade de Item Único, você pode escolher um daqueles cards e colocá-lo na base do deck de seu controlador.",
			"Se não o fizer, compre um card."
		]
	},
	"BSMI_055": {
		"name": "Assaltos nas Vizinhanças",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando você colocar um vilão em cena, se você controla um personagem com a afiliação Sexteto Sinistro desde o início do turno, coloque um número de cards do topo de seu deck em seus recursos igual à Energia Inicial daquele vilão.",
			"Então, coloque este cenário nos recursos de seu dono."
		]
	},
	"BSMI_056": {
		"name": "Atacar até Derrubar",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com a afiliação Mestres do Terror que você controla causar dano em um personagem ou suporte que não tenha a afiliação Mestres do Terror, você pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, este cenário causa 4 pontos de dano naquele personagem ou suporte."
		]
	},
	"BSET_049": {
		"name": "Ataque Surpresa",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Sempre que você colocar um personagem em cena, você pode capacitá-lo em 1."
		]
	},
	"BSAQ_063": {
		"name": "Atrasos e Problemas",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um efeito controlado por um oponente for colocar cards do topo de um deck nos recursos, se este card estiver em cena ou em seus recursos, você pode colocá-lo na base do seu deck.",
			"Se o fizer, compre um card e, até o final do turno, toda vez que um efeito colocar cards do topo de um deck nos recursos, aqueles cards são colocados na base do deck de seus donos ao invés disso."
		]
	},
	"BSUM_043": {
		"name": "Avante, Vingadores!",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Enquanto você controlar um personagem chamado Capitão América, cada um dos personagens Vingadores que você controla pode usar ações de qualquer um dos cards de habilidades que estiver carregando, mesmo que não tenha os poderes daquelas ações."
		]
	},
	"BSUM_044": {
		"name": "Batalha em Área Povoada",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Sempre que um herói fosse causar dano, ele causará aquela quantidade de dano -1."
		]
	},
	"BSOS_057": {
		"name": "Batalha Exaustiva",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Os personagens não podem ser capacitados mais de uma vez por turno."
		]
	},
	"BSIC_053": {
		"name": "Batalha nos Céus",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Personagens com Voo não podem ser alvos de ações de personagens sem Voo.",
			"Personagens sem Voo não podem ser alvos de ações de personagens com Voo."
		]
	},
	"BSGC_054": {
		"name": "Batedor Avançado",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se um de seus oponentes não controlar nenhum personagem, você pode incapacitar em 1 um personagem que você controla desde o início do turno.",
			"Se o fizer, olhe os cards da mão daquele jogador, escolha um deles e aquele jogador descarta o card escolhido."
		]
	},
	"BSGC_055": {
		"name": "Bater em Retirada",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, descarregue um personagem ou suporte que você controla desde o início do turno e devolva-o para sua mão."
		]
	},
	"BSPO_046": {
		"name": "Ben Urich Investiga",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Seus oponentes jogam com as mãos abertas (enquanto este card estiver em cena, seus oponentes devem deixar revelados os cards de suas mãos)."
		]
	},
	"BSAQ_064": {
		"name": "Ben Urich Investiga",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um personagem (ou mais de um), olhe a mão de um jogador.",
			"Você pode escolher um card que não seja de personagem dali e colocá-lo na base do deck de seu dono.",
			"Se o fizer, aquele jogador compra um card."
		]
	},
	"BSET_050": {
		"name": "Busca e Apreensão",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Sempre que um card de suporte em cena controlado por um de seus oponentes for colocado nos recursos daquele jogador, você pode colocar aquele card em seus prêmios.",
			"(Cada suporte em seus prêmios valerá uma quantidade de pontos igual à sua Energia Inicial até o final da partida.)"
		]
	},
	"BSGC_056": {
		"name": "Caça aos Renegados",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, ele causa 2 pontos de dano em um personagem sem a afiliação Aliados do Homem de Ferro ou você pode procurar por um card de personagem chamado HOMEM DE FERRO com alter ego ANTHONY EDWARD STARK em seu deck ou recursos, revele-o, coloque-o em sua mão e embaralhe seu deck se tiver procurado ali."
		]
	},
	"BSPO_047": {
		"name": "Calmaria",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"options": {},
		"negation": false
	},
	"BSGC_057": {
		"name": "Câmeras de Vigilância",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Enquanto este cenário estiver em cena ou em seus recursos, toda vez que uma ação for usada por um personagem no turno em que aquele personagem entrou em cena, você pode colocar este cenário na base do deck de seu dono.",
			"Se o fizer, coloque aquele personagem no estágio 2 e aquela ação não tem efeito."
		]
	},
	"BSDS_053": {
		"name": "Checagem Rápida",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Você pode incapacitar em 1 um personagem que você controla.",
			"Se o fizer, descarte um card e compre um card."
		]
	},
	"BSMI_057": {
		"name": "Chegada Antecipada",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Cards de personagens com Energia Inicial maior ou igual a 6 podem ser carregados com um card a menos ao serem colocados em cena (por exemplo, um personagem com Energia Inicial 8 pode ser colocado em cena com 7 cards dos seus recursos)."
		]
	},
	"BSIV_059": {
		"name": "Cidade Fantasma",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se um jogador fosse procurar um ou mais cards em seu deck, ele deverá comprar aquela mesma quantidade de cards do topo de seu deck ao invés disso."
		]
	},
	"BSUM_045": {
		"name": "Combate ao Crime",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Sempre que um herói fosse causar dano a um vilão, ele causará aquela quantidade de dano +1."
		]
	},
	"BSIC_054": {
		"name": "Combate ao Crime?",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem com a afiliação Vingadores Sombrios ou Thunderbolts causar dano a um personagem vilão, ele causa aquela quantidade de dano +1."
		]
	},
	"BSIV_060": {
		"name": "Combate às Cegas",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Toda vez que um personagem usar uma ação, aquela ação ganha “Ação Única” até o final do turno (aquele personagem não pode usar ações com o mesmo nome da ação usada neste turno)."
		]
	},
	"BSIC_055": {
		"name": "Combate em Campo Aberto",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Toda vez que uma ação que não seja de Antecipação nem Improvista causar dano, ela causa aquela quantidade de dano +1."
		]
	},
	"BSPO_048": {
		"name": "Conflito Generalizado",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Todos os personagens que não estiverem carregando cards de habilidades têm a ação de BRIGAR."
		]
	},
	"BSPO_049": {
		"name": "Confronto Anunciado",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Cada jogador que controlar algum personagem pode comprar um card extra durante a própria Fase de Compra."
		]
	},
	"BSPO_050": {
		"name": "Contra-Espionagem",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se algum jogador comprar cards durante sua própria Fase de Combate, cada outro jogador poderá comprar um card (cada jogador poderá comprar um único card desta forma por turno)."
		]
	},
	"BSPO_DECK_031": {
		"name": "Convocar Mercenários",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Os vilões que você controla ganham a afiliação H.I.D.R.A.",
			"Durante sua Fase de Preparação, uma vez por turno, você pode capacitar em 1 um personagem da H.I.D.R.A.",
			"que você controla.",
			"Se o fizer, coloque este cenário em seus recursos."
		]
	},
	"BSUM_046": {
		"name": "Convocar Reforços",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se você não tiver nenhum card em sua mão, coloque CONVOCAR REFORÇOS em seus recursos e procure em seu deck por até dois cards de personagens, revele-os e coloque-os em sua mão.",
			"Embaralhe seu deck a seguir."
		]
	},
	"BSGC_058": {
		"name": "Da Prática à Perfeição",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Todos os personagens sem a característica Aprimoramento ganham “Aprimoramento (durante sua Fase de Preparação, uma vez por turno, você pode carregar neste personagem um card de personagem de seus recursos que tenha um alter ego igual ao dele ou um nome, se não houver alter ego; se o fizer, descarregue um card deste personagem).”"
		]
	},
	"BSCA_071": {
		"name": "De Volta No Tempo",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um efeito controlado por um oponente fizer com que um ou mais cards carregados em um personagem e/ou suporte sejam colocados na base do seu deck, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Quando este cenário entrar em cena desta forma, coloque os dois cards da base do seu deck nos seus recursos, você pode carregar um card dos seus recursos em um personagem que você controla."
		]
	},
	"BATTLE_BOX_014": {
		"name": "Decisão Extrema",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode descarregar um personagem que você controla e colocá-lo em seus recursos.",
			"Se o fizer, este cenário causa 2 pontos de dano em um personagem ou suporte, ou este cenário causa 4 pontos de dano em um personagem ou suporte se o personagem colocado nos recursos desta forma tiver a afiliação Illuminati."
		]
	},
	"BSPO_051": {
		"name": "Deflagrar o Caos",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um card for colocado na base do deck de um jogador, aquele jogador coloca um card do topo do próprio deck nos próprios recursos."
		]
	},
	"BSGC_059": {
		"name": "Descobertas Infindáveis",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando você colocar um personagem com Genialidade em cena, você pode incapacitar aquele personagem em 1 e colocar este cenário em seus recursos.",
			"Se o fizer, compre três cards."
		]
	},
	"BSOS_058": {
		"name": "Desfechos Paralelos",
		"enter": [
			{
				"op": "mandar_topo_para_recursos",
				"quantity": 2
			}
		],
		"leave": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"options": {},
		"negation": false
	},
	"BSPO_052": {
		"name": "Desmaterialização Impossível",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando DESMATERIALIZAÇÃO IMPOSSÍVEL entrar em cena, se você controlar um personagem com Telecinesia, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, escolha um card de habilidade que um personagem estiver carregando.",
			"Coloque aquele card na mão de seu dono."
		]
	},
	"BSCA_MASTERBOX_004": {
		"name": "Desmaterializar",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem ou suporte controlado por um oponente for Materializado, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Quando este cenário entrar em cena desta forma, coloque aquele personagem ou suporte e todos os cards carregados nele na base do deck do seu dono em qualquer ordem."
		]
	},
	"BSIC_056": {
		"name": "Despertar do Destruidor",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Este cenário só pode ser colocado em cena se você controlar um personagem chamado GALACTUS, LOKI, ODIN ou THOR.",
			"Se você controlar um personagem com o alter ego DESTRUIDOR, ele ganha Super Força e Lâminas.",
			"Toda vez que ele usar a ação RAJADA DEVASTADORA, o dano daquela ação é penetrante."
		]
	},
	"BSPO_053": {
		"name": "Destruir e Dizimar",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se uma ação tiver um ou mais suportes como alvos, o jogador que controla aquela ação pode fazer com que ela tenha um ou mais personagens como alvos ao invés, e vice-versa (todas as palavras “suporte” no texto daquela ação serão tratadas como sendo as palavras “personagem” e vice-versa)."
		]
	},
	"BSFE_062": {
		"name": "Detonador Remoto",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode fazer com que ele cause 3 pontos de dano penetrante em um suporte.",
			"Se não o fizer, compre um card."
		]
	},
	"BSAQ_065": {
		"name": "Doença e Cura",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um personagem com Regeneração, você pode carregar um card de seus recursos em um personagem com Regeneração que você controla e/ou descarregar um card de um personagem sem Regeneração."
		]
	},
	"BSOS_059": {
		"name": "Em Meio à Multidão",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um personagem com a afiliação Fugitivos, você pode procurar em seu deck por um personagem sem a afiliação Fugitivos.",
			"Se o fizer, revele aquele card, coloque-o em sua mão e embaralhe seu deck.",
			"Enquanto você controlar um número de personagens sem a afiliação Fugitivos maior ou igual ao número de personagens com a afiliação Fugitivos que você controla, os personagens com a afiliação Fugitivos que você controla não podem ser alvos de ações."
		]
	},
	"BSAQ_066": {
		"name": "Emboscada Interplanetária",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem ou suporte com a afiliação Ordem Negra entrar em cena sob seu controle, você pode colocar este cenário em seus recursos.",
			"Se o fizer, coloque os quatro cards do topo de seu deck em seus recursos e procure em seu deck por um card de personagem chamado Thanos ou por um card de suporte chamado O Santuário, revele aquele card, coloque-o em sua mão e embaralhe seu deck."
		]
	},
	"BSIV_061": {
		"name": "Energia Estática",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando você colocar um personagem com Ataque energético em cena, você pode incapacitar aquele personagem em 1 e colocar este card em seus recursos.",
			"Se o fizer, aquele personagem causa 2 pontos de dano em um personagem ou suporte alvo que você não controla."
		]
	},
	"BSIV_062": {
		"name": "Ênfase no Foco",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Ações que não têm alvo não podem ser usadas."
		]
	},
	"BSOS_060": {
		"name": "Entrando de Cabeça",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode descarregar um personagem que você controla desde o início do turno e colocá-lo nos prêmios de seus oponentes.",
			"Se o fizer, olhe os cards da mão de um oponente, escolha um deles e coloque-o nos recursos de seu dono."
		]
	},
	"BSPO_054": {
		"name": "Entrave Temporal",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"O próximo personagem que for colocado em cena deve ser descarregado e colocado no topo do deck de seu dono.",
			"Então, coloque ENTRAVE TEMPORAL nos recursos de seu dono."
		]
	},
	"BSIV_063": {
		"name": "Entrega Especial",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se um jogador colocar um personagem em cena, aquele jogador pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, aquele jogador compra um card."
		]
	},
	"BSGC_060": {
		"name": "Entrincheirados",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Todo o dano que seria causado em personagens durante a Fase de Preparação é reduzido a 0.",
			"Se este cenário sair de cena durante a Fase de Preparação, todo o dano que seria causado em personagens até o final daquela Fase de Preparação é reduzido a 0."
		]
	},
	"BSCA_072": {
		"name": "Éramos Seis",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se você controlar sete ou mais personagens com a afiliação Sexteto Sinistro, até o final da partida, os personagens com a afiliação Sexteto Sinistro que você controla podem usar ações sem pagar seus custos de incapacitação e as ações deles tornam-se ações de antecipar e ganham Ação Única."
		]
	},
	"PROMO_008": {
		"name": "Erro de Cálculo",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se um jogador usar uma ação de antecipar durante a Fase de Combate de um oponente, aquela ação não terá efeito.",
			"Coloque ERRO DE CÁLCULO nos recursos de seu dono."
		]
	},
	"BSDS_054": {
		"name": "Escolta Armada",
		"enter": [
			{
				"op": "mandar_topo_para_recursos",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Toda vez que você colocar em cena um personagem com a afiliação Maggia e que não seja chamado Valentão, você pode procurar em seu deck ou recursos por um card de personagem chamado Valentão.",
			"Se o fizer, revele aquele card, coloque-o em sua mão e embaralhe seu deck se tiver procurado ali."
		]
	},
	"BSET_051": {
		"name": "Estratagema Infalível",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando ESTRATAGEMA INFALÍVEL entrar em cena, se você controlar um personagem com Genialidade, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, escolha um oponente.",
			"Você compra um card e aquele oponente descarta um card."
		]
	},
	"BSDS_055": {
		"name": "Estratagema Vil",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Enquanto este card estiver em seus recursos, personagens sem afiliação (N/A) e que não sejam heróis que você controla ganham a afiliação Alienígenas.",
			"No início da Etapa de Antecipação do turno de um oponente, se este card estiver em sua mão, você pode revelá-lo e descartá-lo.",
			"Se o fizer, você pode descarregar um personagem com a afiliação Alienígenas que você controla e colocá-lo em seus recursos."
		]
	},
	"BSOS_061": {
		"name": "Estratégia de Guerrilha",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, coloque o card do topo do seu deck nos seus recursos.",
			"Você pode devolver um card de habilidade dos seus recursos para sua mão."
		]
	},
	"BSPO_055": {
		"name": "Estudos Místicos",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Sempre que um personagem usar uma ação com Clarividência, o controlador daquele personagem pode comprar um card após aquela ação."
		]
	},
	"BSOS_062": {
		"name": "Evocação das Trevas",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Durante sua Fase de Preparação, se você controlar um personagem com Magia cujo alter ego não seja SHUMA-GORATH, você pode incapacitá-lo em 1 e descartar X cards de personagem cujos alter egos não sejam SHUMA-GORATH.",
			"Se o fizer, procure em seu deck e/ou recursos por até X cards de personagens chamados SHUMA-GORATH e/ou TENTÁCULOS DA ESCURIDÃO, revele-os, coloque-os em sua mão e embaralhe seu deck se tiver procurado ali."
		]
	},
	"BSPO_056": {
		"name": "Exaustão",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Sempre que um personagem usar uma ação, o controlador daquele personagem deve descarregar um card que aquele personagem estiver carregando (o card será descarregado daquele personagem antes do efeito da ação)."
		]
	},
	"BSPO_057": {
		"name": "Expandir Infinito",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando EXPANDIR INFINITO entrar em cena, se você controlar um personagem com Poder Cósmico, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, escolha um personagem.",
			"Aquele personagem não poderá usar ações de antecipar neste turno."
		]
	},
	"BSGC_061": {
		"name": "Experiência Acumulada",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que você colocar um personagem em cena durante sua Fase de Preparação, você pode procurar em seu deck por um card com o mesmo alter ego (ou nome, se não houver alter ego) daquele personagem.",
			"Se o fizer, revele aquele card, carregue-o naquele personagem e embaralhe o seu deck."
		]
	},
	"PROMO_020": {
		"name": "Expiar",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e, se todos os jogadores controlarem personagens, cada jogador escolhe e descarrega um card de habilidade de um personagem que ele próprio controla."
		]
	},
	"BSET_052": {
		"name": "Explosão Certeira",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando EXPLOSÃO CERTEIRA entrar em cena, EXPLOSÃO CERTEIRA causa 1 ponto de dano penetrante em um personagem ou suporte.",
			"O controlador daquele personagem ou suporte pode comprar um card."
		]
	},
	"BSPO_058": {
		"name": "Explosão Errática",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando EXPLOSÃO ERRÁTICA entrar em cena, EXPLOSÃO ERRÁTICA causa 2 pontos de dano em um personagem ou suporte.",
			"O controlador daquele personagem ou suporte pode comprar um card."
		]
	},
	"BSMI_058": {
		"name": "Extrapolar os Limites",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem usar uma ação de um card de personagem que ele estiver carregando, aquele personagem pode usar uma outra ação de nome diferente naquele mesmo turno."
		]
	},
	"BSMI_059": {
		"name": "Família Unida",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando você colocar um personagem com a afiliação Quarteto Futuro em cena, você pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, procure em seu deck ou recursos por um card de personagem com a afiliação Quarteto Futuro, revele-o, coloque-o em sua mão e embaralhe seu deck se tiver procurado ali."
		]
	},
	"BSIC_057": {
		"name": "Flores e Espinhos",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Ações de Super Força cujos efeitos reduzam o valor de Escudo causam aquela mesma quantidade de dano em vez disso (ex.: uma ação com efeito “o alvo ganha Escudo -3” causa 3 pontos de dano naquele mesmo alvo em vez de reduzir o valor de Escudo)."
		]
	},
	"BSUM_047": {
		"name": "Fogo Cruzado",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Ações de Antecipação não podem ter como alvos personagens com Ataque à distância."
		]
	},
	"BSOS_063": {
		"name": "Fôlego Renovado",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem que você controla for incapacitado em 1 ou 2 por um efeito controlado por um oponente, você pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, compre um card e capacite aquele personagem em 1 ou 2."
		]
	},
	"BSIV_064": {
		"name": "Força Enigma",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar menos personagens que um oponente, você pode comprar um card.",
			"Enquanto você controlar menos personagens que um oponente, você pode colocar em cena o personagem EV chamado CAPITÃO UNIVERSO da sua mão, independente do seu alinhamento.",
			"Ações chamadas UNIPODER de personagens que você controla são ações imprevistas."
		]
	},
	"BSOS_064": {
		"name": "Frenesi de Batalha",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que uma ação de Lâminas fosse causar dano em um ou mais alvos, ela causa aquela quantidade de dano +1 em cada um de seus alvos."
		]
	},
	"BSET_053": {
		"name": "Garras Imoladoras",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando GARRAS IMOLADORAS entrar em cena, se você controlar um personagem com Lâminas, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, aquele personagem causa 3 pontos de dano distribuídos entre um, dois ou três personagens e/ou suportes."
		]
	},
	"BSIV_065": {
		"name": "Gerenciar Informações",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem usar uma ação de Genialidade, o controlador daquele personagem pode descartar um card.",
			"Se o fizer, aquele jogador pode comprar um card."
		]
	},
	"BSMI_060": {
		"name": "Guerra Civil",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um herói controlado por um jogador fosse causar dano em um herói controlado por outro jogador, ele causará aquela quantidade de dano +1."
		]
	},
	"BSGC_062": {
		"name": "Guerra Civil",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem fosse causar dano em um personagem com a afiliação Aliados do Homem de Ferro ou Aliados do Capitão América, ele causará aquela quantidade de dano +1."
		]
	},
	"BSFE_063": {
		"name": "Guerra Kree-Skrull",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem sem a afiliação Kree e sem a afiliação Skrulls fosse causar dano, ele causará aquela quantidade de dano -1."
		]
	},
	"BSAQ_067": {
		"name": "Heróis de Aluguel",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar ou sair de cena, se você controlar um personagem com a afiliação Heróis de Aluguel, procure em seu deck por um card de personagem com a afiliação Heróis de Aluguel, revele-o, coloque-o em sua mão e embaralhe seu deck."
		]
	},
	"BSAQ_068": {
		"name": "Iluminação Inumana",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem com a afiliação Inumanos entrar em cena sob seu controle, você pode capacitar em 1 aquele personagem ou outro personagem com a afiliação Inumanos que você controla e colocar um card do topo de seu deck em seus recursos."
		]
	},
	"BSET_DECK_033": {
		"name": "Imagem Falsa",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando uma Réplica de Loki for nocauteada, se você controlar Loki, coloque-a nos recursos de seu dono ao invés de nos prêmios de seus oponentes.",
			"Coloque este cenário nos recursos de seu dono."
		]
	},
	"BSET_054": {
		"name": "Imortalidade Insólita",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando IMORTALIDADE INSÓLITA entrar em cena, se você controlar um personagem com Regeneração, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, você pode carregar este cenário e até um card de seus recursos naquele personagem."
		]
	},
	"BSMI_061": {
		"name": "Impermeabilidade",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se um personagem com Regeneração receber dano de uma ação de antecipar, o controlador daquele personagem pode carregar um card de seus próprios recursos naquele personagem (o card só poderá ser carregado se aquele personagem ainda estiver em cena)."
		]
	},
	"BSIV_066": {
		"name": "Impetuosidade",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"As ações dos personagens que você controla e que estão em cena desde o início do turno tornam-se ações imprevistas.",
			"Se um personagem que você controla usar uma ação durante sua Fase de Preparação, nocauteie o personagem que usou a ação e coloque IMPETUOSIDADE nos recursos de seu dono.",
			"(Descarregue o personagem nocauteado e coloque-o nos prêmios de seu oponente antes da ação.)"
		]
	},
	"BSDS_058": {
		"name": "Implodir",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Você pode descarregar um suporte que você controla desde o início do turno e colocá-lo em seus recursos."
		]
	},
	"BSMI_062": {
		"name": "Imposição Estratégica",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"No início do turno de cada jogador, cada um dos jogadores escolhe uma afiliação.",
			"Até o final do turno, cada jogador só pode usar ações de personagens que sejam da afiliação escolhida por ele."
		]
	},
	"BSGC_063": {
		"name": "Informações Privilegiadas",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre dois cards e coloque um card de sua mão na base de seu deck."
		]
	},
	"BSAQ_069": {
		"name": "Inimigo Íntimo",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode escolher um personagem e descarregar todos os cards de personagens com alter ego igual ao dele que ele estiver carregando (ou nome igual, se não houver alter ego).",
			"Se não o fizer, compre um card."
		]
	},
	"BSDS_059": {
		"name": "Inspiração Cármica",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com Magia entrar em cena sob seu controle, você pode incapacitar aquele personagem em 1 e colocar este cenário em seus recursos.",
			"Se o fizer, olhe os cinco cards do topo de seu deck e coloque-os no topo e/ou na base de seu deck em qualquer ordem.",
			"Compre dois cards."
		]
	},
	"BSFE_064": {
		"name": "Insultos e Provocações",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Você pode incapacitar em 1 um personagem controlado por um oponente que esteja no estágio 0 ou 1 de capacitação.",
			"Se o fizer, você pode capacitar em 1 até dois personagens diferentes que você controla."
		]
	},
	"BSIC_058": {
		"name": "Invasão Cósmica",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um jogador usar uma ação de Poder Cósmico, após o efeito daquela ação, aquele jogador pode colocar os dois cards do topo de seu próprio deck em seus recursos."
		]
	},
	"BSDS_060": {
		"name": "Invasão de Alienígenas",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante sua Fase de Preparação, uma vez por turno, você pode colocar um card de personagem com a afiliação Alienígenas dos seus recursos em sua mão.",
			"Toda vez que um personagem com a afiliação Alienígenas que você controla usar uma ação, você pode colocar os dois cards do topo de seu deck em seus recursos (isso ocorre antes do efeito da ação)."
		]
	},
	"BSIC_DECK_034": {
		"name": "Invasão Kree",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando você colocar este cenário em cena, se um oponente não controlar nenhum personagem, procure por um card de personagem ou suporte com a afiliação Kree em seu deck ou recursos, revele-o, coloque-o em sua mão.",
			"Embaralhe seu deck se tiver procurado ali.",
			"Toda vez que um personagem com a afiliação Kree que você controla causar dano, ele causa aquela quantidade de dano +1."
		]
	},
	"PROMO_001": {
		"name": "Invasão Secreta",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Você pode colocar em cena um card de personagem com o mesmo nome ou alter ego de um personagem que seu oponente controla.",
			"Se o fizer, coloque INVASÃO SECRETA nos recursos de seu dono.",
			"Se INVASÃO SECRETA estiver em seus recursos, você pode colocar em cena um card de personagem com o mesmo nome ou alter ego de um personagem que seu oponente controla.",
			"Se o fizer, coloque INVASÃO SECRETA na base de seu deck."
		]
	},
	"BSAQ_070": {
		"name": "Invasão Secreta",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Todos os personagens que você controla ganham a afiliação Skrulls.",
			"Durante sua Fase de Preparação, uma vez por turno, você pode descarregar todos os cards de um personagem que você controla desde o início do turno e colocá-lo em seus recursos.",
			"Se o fizer, você pode colocar em cena um card de personagem com o mesmo nome ou alter ego de um personagem que seu oponente controla."
		]
	},
	"BSOS_065": {
		"name": "Investida Tática",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"A primeira ação de dano com alvos que cada jogador usar em um turno causa +1 ponto de dano em cada um dos seus alvos."
		]
	},
	"BSIC_059": {
		"name": "Investigar Arredores",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um jogador comprar um ou mais cards de habilidade durante sua própria Fase de Compra, aquele jogador pode revelar um daqueles cards.",
			"Se o fizer, aquele jogador pode colocar o card revelado em seus recursos e comprar um card."
		]
	},
	"BSPO_060": {
		"name": "Investigar Ruínas",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando INVESTIGAR RUÍNAS entrar em cena, procure por um card de habilidade de Item Único em seu deck, revele-o e coloque-o em sua mão.",
			"Então embaralhe seu deck."
		]
	},
	"PROMO_019": {
		"name": "Invocar o Relâmpago",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, olhe a mão de um oponente.",
			"Você pode escolher um card de cenário dali e colocá-lo nos recursos de seu dono.",
			"Se algum personagem estiver carregando um card de habilidade chamado MJÖLNIR, aquele personagem não pode ser alvo de ações."
		]
	},
	"BSIV_067": {
		"name": "Lâminas Encantadas",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, coloque-o em seus recursos a não ser que você incapacite em 1 um personagem com Magia que você controla.",
			"Os personagens com Lâminas que você controla não podem ser alvos de ações de antecipar ou imprevistas."
		]
	},
	"BSMI_063": {
		"name": "Lavagem de Dinheiro",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode escolher um personagem vilão que você controla.",
			"Se o fizer, coloque um card do topo de seu deck em seus recursos para cada personagem vilão que você controla que tenha uma afiliação em comum com as afiliações do personagem escolhido (isso inclui o personagem escolhido)."
		]
	},
	"BSOS_066": {
		"name": "Lei Anti-Mutante",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Todo o dano causado a personagens com a afiliação X-Men ou Irmandade de Mutantes é penetrante."
		]
	},
	"PROMO_012": {
		"name": "Manchete do Clarim",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, escolha um personagem controlado por um oponente.",
			"Toda vez que uma ação de um herói que você controla causar dano no personagem escolhido, aquela ação causa +2 pontos de dano naquele personagem."
		]
	},
	"BSDS_061": {
		"name": "Massacre Impiedoso",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem com Predador fosse causar dano a um personagem sem Predador, aquele personagem causará aquela quantidade de dano +1."
		]
	},
	"BSDS_062": {
		"name": "Meditar",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"A começar por você, cada jogador pode escolher um card de habilidade dos próprios recursos e carregá-lo em um personagem que aquele jogador controla."
		]
	},
	"BSPO_061": {
		"name": "Mercado Negro",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante sua Fase de Contagem Regressiva, coloque um card do topo de seu deck em seus recursos.",
			"Então, coloque mais um card do topo de seu deck em seus recursos se houver um ou mais cards de cenário chamados MERCADO NEGRO em seus recursos (você deve colocar estes cards em seus recursos mesmo que não tenha personagens em cena)."
		]
	},
	"BSIC_060": {
		"name": "Missão S.H.I.E.L.D.",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Enquanto este cenário estiver em cena ou em seus recursos, os personagens com a afiliação Vingadores que você controla ganham a afiliação S.H.I.E.L.D."
		]
	},
	"BSET_056": {
		"name": "Momento de Hesitação",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Ações de antecipar que não sejam de cards de habilidades não podem ser usadas."
		]
	},
	"BSCA_073": {
		"name": "Momento De Precipitação",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Ações imprevistas que não sejam de cards de habilidades não podem ser usadas.",
			"Quando este cenário sair de cena, as ações imprevistas que não sejam de cards de habilidades não podem ser usadas até o final do turno."
		]
	},
	"BSET_057": {
		"name": "Movimento Imprevisível",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando MOVIMENTO IMPREVISÍVEL entrar em cena, se você controlar um personagem com Elasticidade, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, escolha um personagem em cena.",
			"Incapacite aquele personagem em 1 ou 2."
		]
	},
	"BSIV_068": {
		"name": "Movimentos Característicos",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante a Fase de Preparação de cada jogador, uma vez por turno, aquele jogador pode carregar um card de personagem de seus recursos em um personagem que ele controla com o mesmo alter ego (ou com o mesmo nome, se não houver alter ego)."
		]
	},
	"BSMI_064": {
		"name": "Múltiplas Identidades",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode incapacitar em 1 um personagem que você controla.",
			"Se o fizer, procure em seu deck por um card de personagem com o mesmo alter ego que o personagem incapacitado, revele-o, coloque-o em sua mão e embaralhe seu deck."
		]
	},
	"BSET_058": {
		"name": "Múltiplas Opções",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Sempre que um personagem que você controla usar uma ação de Genialidade, você pode comprar um card."
		]
	},
	"BSMI_DECK_036": {
		"name": "Nano-Sentinelas",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, você pode incapacitar em 1 um personagem que não seja herói nem vilão.",
			"Se o fizer, escolha um personagem.",
			"Este cenário causa 2 pontos de dano naquele personagem.",
			"Se o personagem escolhido tiver a afiliação X-Men ou Irmandade de Mutantes, o dano causado será penetrante."
		]
	},
	"BSCA_074": {
		"name": "Não Era Bem Isso...",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um efeito controlado por um oponente fizer com que ele procure por um ou mais cards no próprio deck, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Quando este cenário entrar em cena desta forma, aquele jogador não pode procurar por aqueles cards."
		]
	},
	"BSIC_061": {
		"name": "No Lugar Errado",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"No início do turno de cada jogador, cada um dos jogadores escolhe uma afiliação.",
			"Até o final do turno, os jogadores não poderão usar ações de personagens das afiliações escolhidas (este efeito permanece até o final do turno mesmo que este cenário saia de cena)."
		]
	},
	"BSAQ_071": {
		"name": "Novos Horizontes",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante sua Fase de Preparação, uma vez por turno, se você controlar um personagem (ou mais de um), você pode procurar em seu deck por um card de cenário.",
			"Se o fizer, revele aquele card, coloque-o em sua mão e embaralhe seu deck."
		]
	},
	"BSAQ_072": {
		"name": "Objetivos Iguais",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se você controlar três ou mais personagens com alguma afiliação em comum entre si, você pode comprar mais dois cards."
		]
	},
	"BSUM_048": {
		"name": "Onda de Assaltos",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se você controlar dois ou mais vilões, compre um card extra durante sua Etapa de Compra."
		]
	},
	"BSGC_064": {
		"name": "Onda de Boatos",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Todos os personagens ganham as afiliações Aliados do Capitão América e Aliados do Homem de Ferro."
		]
	},
	"BSUM_049": {
		"name": "Onda de Pânico",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Enquanto ONDA DE PÂNICO estiver em cena, cada jogador coloca um card a mais de seu próprio deck em seus próprios recursos durante a Contagem Regressiva do turno daquele jogador.",
			"(Se um jogador possuir algum personagem em cena, mesmo assim ele deverá colocar um card do deck nos recursos durante a sua própria Contagem Regressiva)."
		]
	},
	"BSGC_065": {
		"name": "Oposição ao Registro",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, ele causa 2 pontos de dano em um personagem sem a afiliação Aliados do Capitão América ou você pode procurar por um card de personagem chamado CAPITÃO AMÉRICA com alter ego STEVE ROGERS em seu deck ou recursos, revele-o, coloque-o em sua mão e embaralhe seu deck se tiver procurado ali."
		]
	},
	"BSCA_075": {
		"name": "Paradoxo Abrasador",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário fosse ser substituído por outro cenário, o controlador daquele cenário pode descarregar um card do personagem com menor Energia atual que ele próprio controla.",
			"Se não o fizer, aquele cenário não entra em cena e é colocado nos recursos daquele jogador ao invés disso (este cenário sairá de cena mesmo que aquele cenário não entre em cena)."
		]
	},
	"BSCA_076": {
		"name": "Paradoxo Enigmático",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário fosse ser substituído por outro cenário, o controlador daquele cenário pode incapacitar um personagem que ele próprio controla em 2.",
			"Se não o fizer, aquele cenário não entra em cena e é colocado nos recursos daquele jogador ao invés disso (este cenário sairá de cena mesmo que aquele cenário não entre em cena)."
		]
	},
	"BSCA_077": {
		"name": "Paradoxo Enlouquecedor",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário fosse ser substituído por outro cenário, o controlador daquele cenário pode colocar exatamente dois cards da mão na base do próprio deck e então comprar dois cards.",
			"Se não o fizer, aquele cenário não entra em cena e é colocado nos recursos daquele jogador ao invés disso (este cenário sairá de cena mesmo que aquele cenário não entre em cena)."
		]
	},
	"BSCA_078": {
		"name": "Paradoxo Temporal",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário fosse ser substituído por outro cenário, o controlador daquele cenário pode colocar um card dos próprios recursos na base do próprio deck.",
			"Se não o fizer, aquele cenário não entra em cena e é colocado nos recursos daquele jogador ao invés disso (este cenário sairá de cena mesmo que aquele cenário não entre em cena)."
		]
	},
	"BSIV_069": {
		"name": "Parede Holográfica",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Enquanto você controlar algum personagem com a afiliação H.I.D.R.A.",
			"ou I.M.A., os jogadores não podem colocar cenários em cena.",
			"Durante a Fase de Preparação de cada jogador, aquele jogador pode descartar um card de cenário ou dois outros cards.",
			"Se o fizer, coloque este cenário nos recursos de seu dono.",
			"Se um personagem com a afiliação H.I.D.R.A.",
			"ou I.M.A.",
			"que você controla receber dano enquanto este cenário estiver em cena, coloque este cenário nos recursos de seu dono.",
			"Se o fizer, aquele dano é reduzido a 0."
		]
	},
	"BSOS_067": {
		"name": "Passado Sombrio",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, escolha um personagem herói em cena.",
			"O personagem escolhido não pode usar ações.",
			"Quando o personagem escolhido for alvo de alguma ação ou sofrer dano, coloque este cenário nos recursos de seu dono."
		]
	},
	"BSFE_066": {
		"name": "Patrulhamento Galáctico",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se o fizer, compre um card.",
			"Quando um personagem com a afiliação Tropa Nova entrar em cena sob seu controle, se este card estiver em seus recursos, você pode colocar este card na base do seu deck."
		]
	},
	"BSOS_068": {
		"name": "Pesquisa Solitária",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode incapacitar um personagem que você controla em X.",
			"Se o fizer, compre X cards."
		]
	},
	"BSFE_067": {
		"name": "Plágio",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Você pode colocar em cena um card de suporte com o mesmo nome de um suporte que seu oponente controla.",
			"Se o fizer, coloque este cenário nos recursos de seu dono.",
			"Se este card estiver em seus recursos, você pode colocar em cena um card de suporte com o mesmo nome de um suporte que seu oponente controla.",
			"Se o fizer, coloque este card na base de seu deck."
		]
	},
	"BSET_059": {
		"name": "Planar Invisível",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando PLANAR INVISÍVEL entrar em cena, se você controlar um personagem com Voo, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, escolha um personagem em cena.",
			"Aquele personagem não poderá ser alvo de ações de antecipar neste turno."
		]
	},
	"BSET_060": {
		"name": "Plano Magistral - Estratégia",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando PLANO MAGISTRAL - ESTRATÉGIA entrar em cena, se PLANO MAGISTRAL - OBJETIVO estava em cena, compre 3 cards."
		]
	},
	"BSET_061": {
		"name": "Plano Magistral - Execução",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando PLANO MAGISTRAL - EXECUÇÃO entrar em cena, se PLANO MAGISTRAL - ESTRATÉGIA estava em cena, compre 3 cards."
		]
	},
	"BSET_062": {
		"name": "Plano Magistral - Objetivo",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando PLANO MAGISTRAL - OBJETIVO entrar em cena, se PLANO MAGISTRAL - EXECUÇÃO estava em cena, compre 3 cards."
		]
	},
	"BSPO_DECK_036": {
		"name": "Plano Magistral - Preparação",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando você colocar PLANO MAGISTRAL - PREPARAÇÃO em cena, você pode procurar em seus recursos por um card chamado PLANO MAGISTRAL - ESTRATÉGIA, um card chamado PLANO MAGISTRAL - OBJETIVO e um card chamado PLANO MAGISTRAL - EXECUÇÃO, e colocar aqueles cards em sua mão."
		]
	},
	"BSOS_069": {
		"name": "Planos Expostos",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, olhe a mão de um oponente.",
			"Você pode escolher um card de habilidade dali e colocá-lo nos recursos de seu dono."
		]
	},
	"BSAQ_073": {
		"name": "Planos Frustrados",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Os jogadores não podem procurar cards nos decks.",
			"Quando este cenário sair de cena, os jogadores não podem procurar cards nos decks até o final do turno."
		]
	},
	"BSIC_062": {
		"name": "Posicionamento Estratégico",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode incapacitar um personagem em 1.",
			"Se um oponente colocar um cenário em cena substituindo este cenário, você pode incapacitar em 1 um personagem que aquele jogador controla."
		]
	},
	"BSMI_065": {
		"name": "Possessão Sinistra",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, escolha um personagem em cena.",
			"Toda vez que o personagem escolhido usar uma ação, você escolhe e descarrega um card que ele estiver carregando (o card será descarregado daquele personagem antes do efeito da ação)."
		]
	},
	"BSPO_062": {
		"name": "Potência Incomparável",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando POTÊNCIA INCOMPARÁVEL entrar em cena, se você controlar um personagem com Super Força, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, a próxima ação que aquele personagem usar neste turno custará 1 a menos para ser usada (ela não poderá custar menos que 0; este efeito permanece mesmo que este cenário tenha saído de cena)."
		]
	},
	"BSPO_063": {
		"name": "Poucas Opções",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Os personagens não podem usar ações com os mesmos nomes de ações que já tiverem sido usadas neste turno."
		]
	},
	"BSFE_068": {
		"name": "Presença Estarrecedora",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com Telecinesia entrar em cena sob seu controle, você pode incapacitar aquele personagem em 1 e colocar este cenário em seus recursos.",
			"Se o fizer, coloque os cinco cards do topo de um deck nos recursos de seus donos."
		]
	},
	"BSMI_066": {
		"name": "Programação Defeituosa",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Enquanto houver em cena um personagem cujo alter ego seja SENTINELA, os personagens cujas afiliações não sejam Sentinelas ganham as afiliações X-Men e Irmandade de Mutantes."
		]
	},
	"BSPO_064": {
		"name": "Projétil Inesperado",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando PROJÉTIL INESPERADO entrar em cena, se você controlar um personagem com Genialidade, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, aquele personagem causa 1 ponto de dano penetrante em um outro personagem."
		]
	},
	"BSET_063": {
		"name": "Proteger os Inocentes",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Sempre que um personagem que você controla e não for herói nem vilão for alvo de uma ação, você pode escolher um herói que você controla como alvo daquela ação."
		]
	},
	"BSIC_063": {
		"name": "Pulso Eletromagnético",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e ele causa 2 pontos de dano em cada suporte."
		]
	},
	"BSAQ_074": {
		"name": "Pulso Iônico",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e ele causa 1 ponto de dano penetrante a cada suporte."
		]
	},
	"BSDS_063": {
		"name": "Quando o Mal Definha",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Os personagens com Predador perdem Predador e ganham: “Quando este personagem usar uma ação, descarregue um card dele.”"
		]
	},
	"BSGC_066": {
		"name": "Quebrar com Tudo",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando você colocar um personagem com Regeneração em cena, você pode incapacitar aquele personagem em 1 e colocar este cenário em seus recursos.",
			"Se o fizer, aquele personagem causa 4 pontos de dano em um suporte ou em um personagem alvo com Regeneração."
		]
	},
	"BSET_064": {
		"name": "Rajada Implacável",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando RAJADA IMPLACÁVEL entrar em cena, se você controlar um personagem com Ataque Energético, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, aquele personagem causa 3 pontos de dano penetrante em um suporte alvo."
		]
	},
	"BSIC_064": {
		"name": "Recrutar Mutantes",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um personagem com a afiliação Irmandade de Mutantes, pode procurar em seu deck por um card de personagem com a afiliação Irmandade de Mutantes, revelá-lo, colocá-lo em sua mão e embaralhar seu deck.",
			"Quando você colocar um personagem com a afiliação Irmandade de Mutantes em cena, pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, procure em seu deck por um card de personagem com a afiliação Irmandade de Mutantes, revele-o, coloque-o em sua mão e embaralhe seu deck."
		]
	},
	"BSMI_067": {
		"name": "Reflexos Rápidos",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Você pode usar uma ação de Agilidade de um personagem que você controla como se fosse uma ação imprevista.",
			"Se o fizer, coloque este cenário nos recursos de seu dono."
		]
	},
	"BSCA_079": {
		"name": "Reforços Aliados",
		"enter": [],
		"leave": [],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "Compre um card.",
					"action": {
						"op": "comprar",
						"quantity": 1
					}
				},
				{
					"label": "B",
					"text": "Se você controlar três ou mais personagens e todos os personagens que você controla tiverem uma afiliação em comum, você pode procurar em seu deck por até dois cards de personagem com aquela afiliação. Se o fizer, revele aqueles cards, coloque-os em sua mão e embaralhe o seu deck.",
					"manual": "procurar em seu deck por até dois cards de personagem com aquela afiliação. Se o fizer, revele aqueles cards, coloque-os em sua mão e embaralhe o seu deck."
				}
			]
		},
		"negation": false
	},
	"BSIV_070": {
		"name": "Resistência Extrema",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem com Energia Inicial 6 ou maior receber dano, aquele personagem receberá -1 ponto de dano."
		]
	},
	"BSDS_064": {
		"name": "Resposta à Ameaça",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um personagem com a afiliação Defensores e/ou se um outro jogador controlar um vilão, você pode procurar em seu deck por um personagem com a afiliação Defensores.",
			"Se o fizer, revele aquele card, coloque-o em sua mão e embaralhe seu deck.",
			"Toda vez que uma ação de um personagem com a afiliação Defensores que você controla fosse causar dano em um alvo, aquela ação causará aquela quantidade de dano +1."
		]
	},
	"BSUM_050": {
		"name": "Retirada Estratégica",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, descarregue um personagem ou suporte que você controla e devolva-o para sua mão."
		]
	},
	"BSAQ_075": {
		"name": "Reunião de Guerreiros",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um personagem (ou mais de um) com a afiliação Os Três Guerreiros, você pode procurar em seu deck por até dois cards de personagens com a afiliação Os Três Guerreiros.",
			"Se o fizer, revele aqueles cards, coloque-os em sua mão e embaralhe seu deck."
		]
	},
	"PROMO_010": {
		"name": "Reunião de Intelectos",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando REUNIÃO DE INTELECTOS for substituído por um outro cenário, cada jogador compra um card para cada um dos personagens com Genialidade que ele controlar."
		]
	},
	"BSIC_065": {
		"name": "Reunir a Gangue",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um personagem com a afiliação Gangue da Demolição, pode procurar em seu deck por um card de personagem com a afiliação Gangue da Demolição, revelá-lo, colocá-lo em sua mão e embaralhar seu deck.",
			"Quando você colocar um personagem com a afiliação Gangue da Demolição em cena, pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, coloque os três cards do topo de seu deck em seus recursos."
		]
	},
	"BSET_065": {
		"name": "Revigoramento Incrível",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando REVIGORAMENTO INCRÍVEL entrar em cena, se você controlar um personagem com Telepatia, você poderá incapacitar aquele personagem em 1.",
			"Se o fizer, escolha até dois personagens em cena sob seu controle.",
			"Capacite aqueles personagens em 1."
		]
	},
	"BSET_066": {
		"name": "Revisitar o Passado",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante a Fase de Compra, em seu próprio turno, você pode escolher um card de seus recursos e colocá-lo em sua mão.",
			"Se o fizer, coloque REVISITAR O PASSADO em seus recursos."
		]
	},
	"BSGC_067": {
		"name": "Revista Minuciosa",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Cada jogador deve colocar um card do topo do próprio deck nos recursos."
		]
	},
	"BSDS_065": {
		"name": "Revolta dos Inocentes",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem com Predador fosse causar dano a um personagem sem Predador, aquele personagem causará aquela quantidade de dano +1."
		]
	},
	"BSOS_070": {
		"name": "Ruínas Suspeitas",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"No início da Fase de Contagem Regressiva do jogador que controlar menos personagens em cena, se aquele jogador controlar ao menos um personagem e nenhum outro jogador controlar o mesmo número de personagens que ele, aquele jogador pode colocar os dois cards do topo do seu próprio deck em seus próprios recursos."
		]
	},
	"BSFE_069": {
		"name": "Sabotador Infiltrado",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar algum personagem com a afiliação H.I.D.R.A., você pode procurar em seu deck por um card de personagem com a afiliação H.I.D.R.A.",
			"Se o fizer, revele aquele card, coloque-o em sua mão e embaralhe o seu deck.",
			"Durante sua Fase de Preparação, se houver dois ou mais cards com a afiliação H.I.D.R.A.",
			"nos prêmios dos seus oponentes, você pode colocar este cenário nos seus recursos e procurar em seu deck por um card de personagem com a afiliação H.I.D.R.A."
		]
	},
	"BSMI_068": {
		"name": "Sabotagem",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"No final da próxima Fase de Contagem Regressiva, conte o número de cards que o jogador que controla o turno colocou do topo do deck nos recursos dele próprio.",
			"Você coloca aquele mesmo número de cards do topo de seu próprio deck em seus recursos e então coloca este cenário nos recursos de seu dono."
		]
	},
	"BSCA_080": {
		"name": "Segurança Pessoal",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem entrar em cena sob seu controle, você pode colocar este cenário em seus recursos.",
			"Se o fizer, aquele personagem ganha Escudo +1 até o final do turno e você pode descarregar um personagem que você controla desde o início do turno e devolvê-lo para sua mão."
		]
	},
	"BSUM_052": {
		"name": "Sem Trégua",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando SEM TRÉGUA entrar em cena, escolha um personagem herói ou vilão que você controla e um personagem herói ou vilão que você não controla.",
			"Enquanto SEM TRÉGUA e ambos os personagens escolhidos estiverem em cena, os personagens escolhidos só podem ser alvos das ações um do outro.",
			"Se um dos personagens escolhidos sair de cena, coloque SEM TRÉGUA nos recursos de seu dono."
		]
	},
	"BSFE_070": {
		"name": "Solidão Inabalável",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um personagem ou suporte fosse receber dano que não seja de uma ação, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Quando este cenário entrar em cena desta forma, aquele dano torna-se 0."
		]
	},
	"BSUM_053": {
		"name": "Sucessão de Eventos",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Cada jogador compra um card extra durante sua respectiva Etapa de Compra."
		]
	},
	"BSUM_054": {
		"name": "Super Plano de Dominação",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Cada vilão ganha Genialidade e Escudo +1."
		]
	},
	"BSFE_071": {
		"name": "Surpresa Inesperada",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante sua Fase de Preparação, uma vez por turno, você pode colocar um card dos recursos de um oponente na mão daquele jogador.",
			"Se o fizer, cada jogador compra um card."
		]
	},
	"BSIC_066": {
		"name": "Teletransporte",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode revelar um card de personagem com a afiliação Guardiões da Galáxia de sua mão.",
			"Se o fizer, revele cards do topo de seu deck em número igual à Energia Inicial daquele personagem e coloque-o em cena carregando aqueles cards como cards voltados para baixo de seus recursos."
		]
	},
	"BSET_067": {
		"name": "Terreno Acidentado",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se um jogador usar uma ação de antecipar de um personagem durante a Fase de Combate de um oponente, TERRENO ACIDENTADO causa 1 ponto de dano penetrante naquele personagem.",
			"Coloque TERRENO ACIDENTADO nos recursos de seu dono."
		]
	},
	"BSGC_068": {
		"name": "Titã Descontrolado",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante sua Fase de Preparação, você pode colocar em cena um card de personagem com Energia Inicial 7 ou maior carregando cards do topo do seu deck ao invés de cards dos seus recursos.",
			"Se o fizer, coloque este cenário em seus recursos."
		]
	},
	"BSCA_081": {
		"name": "Traição",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem usar uma ação, se este card estiver em sua mão e outro personagem com o mesmo controlador e sem afiliações em comum com aquele personagem já tiver usado uma ação neste turno, você pode colocar este card em cena.",
			"Quando este cenário entrar em cena desta forma, aquela ação não tem efeito."
		]
	},
	"BSIC_067": {
		"name": "Traidor",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, escolha um personagem que um oponente controla.",
			"Este cenário causa 1 ponto de dano no personagem escolhido, ou causa 1 ponto de dano penetrante nele se ele tiver alguma afiliação em comum com as afiliações dos personagens que você controla."
		]
	},
	"BSUM_055": {
		"name": "Treinamento Mental",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante sua Fase de Preparação, uma vez por turno, você pode capacitar em 1 um dos personagens com Telepatia que você controla."
		]
	},
	"BSUM_056": {
		"name": "Treino na Sala de Perigo",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante cada Fase de Preparação, uma vez por turno, você pode escolher um card que um personagem ou suporte X-Men que você controla estiver carregando e permutá-lo por outro card que outro personagem ou suporte X-Men que você controla estiver carregando."
		]
	},
	"BSDS_066": {
		"name": "Troca-Troca",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante a Fase de Preparação de cada jogador, uma vez por turno, aquele jogador pode permutar um card que um personagem que ele controla estiver carregando por um card que outro personagem que ele controla estiver carregando, se ele controlar estes dois personagens e ambos os personagens tiverem uma afiliação em comum."
		]
	},
	"PROMO_028": {
		"name": "União Inabalável",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um personagem fosse receber dano que não seja de uma ação, se este card estiver em sua mão, você pode colocá-lo em cena (este cenário pode ser colocado em cena desta forma mesmo que outro cenário já tenha sido colocado em cena neste turno).",
			"Quando este cenário entrar em cena, compre um card e escolha uma afiliação.",
			"Até o final do turno, todo o dano que não seja de ação que for causado a personagens com a afiliação escolhida é reduzido a 0."
		]
	},
	"PROMO_016": {
		"name": "Unidos, Venceremos!",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, escolha uma afiliação e capacite em 1 cada personagem daquela afiliação que você controla e que esteja no estágio 0 ou 1 de capacitação."
		]
	},
	"BSET_068": {
		"name": "Universo Paralelo",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Os jogadores podem colocar em cena personagens com nomes iguais aos dos personagens controlados por outros jogadores.",
			"(Um jogador não poderá colocar em cena personagens com o mesmo nome de outros personagens que ele próprio controle.)"
		]
	},
	"BSFE_073": {
		"name": "Vazio Temporal",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um personagem usar uma ação, se aquela não for a primeira ação que aquele personagem usou neste turno e este card estiver em sua mão, você pode colocá-lo em cena.",
			"Se o fizer, aquela ação não tem efeito (este cenário pode ser colocado em cena desta forma mesmo que outro cenário já tenha sido colocado em cena neste turno).",
			"Quando este cenário entrar em cena, compre um card e, até o final do turno, os personagens não podem usar ações caso já tenham usado alguma ação neste turno."
		]
	},
	"BSCA_082": {
		"name": "Venomverso",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {
			"timing": "affiliation",
			"items": [
				{
					"label": "A",
					"text": "coloque os dois cards do topo de seu deck em seus recursos.",
					"action": {
						"op": "mandar_topo_para_recursos",
						"quantity": 2
					}
				},
				{
					"label": "B",
					"text": "você pode procurar em seu deck por um card de personagem com a afiliação Simbiontes.",
					"manual": "procurar em seu deck por um card de personagem com a afiliação Simbiontes."
				}
			],
			"affiliation": "Simbiontes",
			"timing_if": {
				"type": "affiliation",
				"value": "Simbiontes",
				"min": 1
			},
			"before": "recursos"
		},
		"negation": false
	},
	"BSIC_068": {
		"name": "Véspera do Julgamento",
		"enter": [
			{
				"op": "mandar_topo_para_recursos",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se você não controlar nenhum personagem com a afiliação Arautos de Galactus, pode procurar em seu deck ou recursos por um personagem com essa afiliação, revelá-lo e colocá-lo em sua mão.",
			"Embaralhe seu deck se tiver procurado ali."
		]
	},
	"BSFE_074": {
		"name": "Vitalidade Mortífera",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante sua Fase de Preparação, se este card estiver em cena ou em seus recursos, você pode colocá-lo na base do seu deck.",
			"Se o fizer, você pode capacitar em 1 ou 2 um personagem com a afiliação Tentáculo que você controla."
		]
	},
	"BSFE_075": {
		"name": "Voltar Com Tudo",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante sua Fase de Preparação, os seus cards de personagens com a afiliação Guardiões da Galáxia podem ser colocados em cena como se fossem cards de Personagem-EV com Energia Extra +0 e requisito de evolução “EV - personagem com o mesmo alter ego deste card e que ainda não tenha usado ações neste turno”."
		]
	},
	"FMBSEI_068": {
		"name": "Atirar Primeiro",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com [Prontidão] entrar em cena sob seu controle, você pode incapacitar aquele personagem em [Preparação] e colocar este cenário em seus recursos.",
			"Se o fizer, aquele personagem causa 2 pontos de dano penetrante distribuídos da forma como você escolher entre até dois alvos diferentes."
		]
	},
	"FMBSEI_069": {
		"name": "Colheita Celestial",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, se cada personagem que você controlar tiver a afiliação Celestiais, carregue qualquer número de cards que não sejam de habilidade dos seus recursos em personagens com a afiliação Celestiais que você controla e então coloque todos os cards dos seus recursos que não sejam de habilidade na base do deck do seu dono em qualquer ordem e embaralhe o seu deck.",
			"Compre dois cards."
		]
	},
	"FMBSEI_070": {
		"name": "Conflito Interno",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Enquanto este cenário estiver em cena ou em seus recursos, quando um personagem sem afiliação [N/A], sem alinhamento [N/A] e Energia Inicial 1 que você controla for nocauteado por uma ação que cause dano, você pode colocar este cenário na base do deck de seu dono.",
			"Se o fizer, você pode colocar os 3-X cards do topo de seu deck em seus recursos.",
			"X é igual ao número de outros cards de cenário chamados CONFLITO INTERNO que você controla e que tiveram seus efeitos ativados e/ou desencadeados neste turno."
		]
	},
	"FMBSEI_071": {
		"name": "Dimensão Distorcida",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com a afiliação Zona Negativa entrar em cena sob seu controle, você pode incapacitar aquele personagem em 1 e colocar este card nos recursos de seu dono.",
			"Se o fizer, revele os cinco cards do topo de seu deck e escolha um oponente.",
			"O oponente separa os cards revelados em dois montes.",
			"Escolha um dos montes e coloque-o em sua mão e então coloque os demais cards na base do seu deck em qualquer ordem."
		]
	},
	"FMBSEI_072": {
		"name": "Evitar Catástrofe",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"No início da Etapa de Ataque do turno de um oponente, se este Cenário estiver em sua mão, você pode colocá-lo em cena.",
			"Se o fizer, descarregue qualquer número de cards com o nome JOIA DO INFINITO de um personagem controlado por um oponente, descarregue o mesmo número de cards descarregados daquele personagem de um personagem que você controla e então você pode carregar um card com o nome JOIA DO INFINITO dos seus recursos em um personagem que você controla."
		]
	},
	"FMBSEI_073": {
		"name": "Homo Immortalis",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com a afiliação Eternos que você controla for nocauteado por uma ação de um personagem controlado por um oponente, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Se o fizer, você pode procurar em seu deck por um personagem com o mesmo alter ego daquele personagem, revelá-lo, colocá-lo em sua mão e embaralhar seu deck.",
			"Quando um personagem com a afiliação Eternos que você controla for nocauteado por uma ação de um personagem controlado por um oponente, se este card estiver em cena ou nos seus recursos, você pode colocá-lo na base do seu deck."
		]
	},
	"FMBSEI_074": {
		"name": "Mundo Bélico",
		"enter": [],
		"leave": [],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "compre um card.",
					"action": {
						"op": "comprar",
						"quantity": 1
					}
				},
				{
					"label": "B",
					"text": "procure em seu deck por um card de suporte com a afiliação Mundo Bélico, revele-o, coloque-o em sua mão e embaralhe seu deck.",
					"manual": "procure em seu deck por um card de suporte com a afiliação Mundo Bélico, revele-o, coloque-o em sua mão e embaralhe seu deck."
				}
			]
		},
		"negation": false
	},
	"FMBSEI_075": {
		"name": "Panteão do Olimpo",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com a afiliação Deuses do Olimpo entrar em cena sob seu controle, você pode colocar o card do topo de seu deck em seus recursos.",
			"Quando este cenário sair de cena, você pode carregar um card de habilidade com Item Único de seus recursos em um personagem com a afiliação Deuses do Olimpo que você controla."
		]
	},
	"FMBSEI_076": {
		"name": "Posso Fazer Isso o Dia Todo",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando todos os cards que um personagem que você controla forem descarregados daquele personagem por uma ação que cause dano de um personagem controlado por um oponente e aquele personagem fosse ser nocauteado, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Se o fizer, carregue um card dos seus recursos naquele personagem."
		]
	},
	"FMBSEI_077": {
		"name": "Unimente",
		"enter": [],
		"leave": [],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "cada um dos personagens que foi incapacitado desta forma causa 1 ponto de dano penetrante em um personagem ou suporte a sua escolha.",
					"manual": "cada um dos personagens que foi incapacitado desta forma causa 1 ponto de dano penetrante em um personagem ou suporte a sua escolha."
				},
				{
					"label": "B",
					"text": "os personagens escolhidos ganham 'prontidão - ações de ✶ que não sejam imprevistas ◷'.",
					"manual": "os personagens escolhidos ganham 'prontidão - ações de ✶ que não sejam imprevistas ◷'."
				}
			]
		},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, você pode incapacitar em ◷ três personagens com a afiliação Eternos que você controla e então colocar os três cards do topo de seu deck em seus recursos."
		]
	},
	"FMBSEI_078": {
		"name": "Véspera do Julgamento",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena e no início de cada turno, cada jogador coloca o card do topo de seus decks em seus recursos.",
			"Enquanto este cenário estiver em cena, quando um efeito fizer com que este card seja colocado na base do seu deck, você pode colocá-lo na sua mão ao invés disso.",
			"No início de cada Fase de Combate, você pode escolher qualquer número de personagens com a afiliação Arautos de Galactus que você controla.",
			"Até o final do turno, os personagens escolhidos perdem suas afiliações, os textos permanentes daqueles personagens não têm efeito e as ações que eles usarem ganham Ação Única."
		]
	},
	"FMBSESPECIAL_004": {
		"name": "Inimigo Secreto",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, cada jogador descarta todos os cards da mão e então compra aquela mesma quantidade de cards."
		]
	},
	"FMBSEXTRA_003": {
		"name": "Provas Incriminadoras",
		"enter": [],
		"leave": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "os textos permanentes de cards de habilidade com Item Único não têm efeito até o final do turno.",
					"manual": "os textos permanentes de cards de habilidade com Item Único não têm efeito até o final do turno."
				},
				{
					"label": "B",
					"text": "ações de cards de habilidade com Item Único não podem ser usadas até o final do turno.",
					"manual": "ações de cards de habilidade com Item Único não podem ser usadas até o final do turno."
				}
			]
		},
		"negation": true
	},
	"FMBSFA_082": {
		"name": "Anarquizar",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar ou sair de cena, compre um card e você pode incapacitar um personagem que você controla em 1.",
			"Se um personagem foi incapacitado desta forma, aquele personagem pode causar 1 ponto de dano penetrante em um suporte.",
			"Se o fizer, os textos permanentes daquele suporte não têm efeito até o final do turno."
		]
	},
	"FMBSFA_083": {
		"name": "Arma-Viva de Vingança",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você não controlar um personagem com o alter ego YURIKO OYAMA, você pode procurar em seu deck, mão ou recursos por um card de personagem chamado LADY LETAL e alter ego YURIKO OYAMA e colocá-lo em cena como se ele tivesse Materializar.",
			"Se o fizer, aquele personagem ganha 'Prontidão - todas as ações'.",
			"Toda vez que um personagem com a afiliação Carniceiros usar uma ação que cause dano, você pode carregar um card de seus recursos naquele personagem.",
			"Se o alvo daquela ação for um personagem com Lâminas, você pode capacitar o personagem que usou aquela ação em 1."
		]
	},
	"FMBSFA_084": {
		"name": "Armadilha Mortal",
		"enter": [],
		"leave": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "procure em seu deck ou recursos por um card de personagem com o nome ARCADE e alter ego ARCADE, revele aquele card e coloque-o em sua mão.",
					"manual": "procure em seu deck ou recursos por um card de personagem com o nome ARCADE e alter ego ARCADE, revele aquele card e coloque-o em sua mão."
				},
				{
					"label": "B",
					"text": "coloque em cena um card de suporte com a afiliação Mundo Assassino diretamente de seus recursos.",
					"manual": "coloque em cena um card de suporte com a afiliação Mundo Assassino diretamente de seus recursos."
				}
			]
		},
		"negation": false
	},
	"FMBSFA_085": {
		"name": "Armadilha Mortal",
		"enter": [],
		"leave": [
			{
				"op": "mandar_topo_para_recursos",
				"quantity": 1
			}
		],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário for colocado em seus recursos vindo de sua mão ou deck, se você controlar um personagem com o nome ARCADE e alter ego ARCADE, você pode escolher uma opção, Ⓐ procure em seu deck ou recursos por um card de suporte com a afiliação Mundo Assassino, revele aquele card e coloque-o em sua mão; Ⓑ cada jogador pode incapacitar em 1 cada personagem que ele controla.",
			"Descarregue um card de cada personagem que não foi incapacitado desta forma."
		]
	},
	"FMBSFA_086": {
		"name": "Aventurar-Se No Espaço",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar ou sair de cena você pode carregar um card de habilidade dos seus recursos em um personagem com a afiliação Piratas Siderais que você controla.",
			"Se o fizer, compre um card.",
			"Toda vez que um personagem que você controla com a afiliação Piratas Siderais fosse receber dano de uma fonte, aquela fonte causará aquela quantidade de dano -1."
		]
	},
	"FMBSFA_087": {
		"name": "Barganha",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um efeito controlado por um oponente colocar um card da mão, deck, cena ou recursos daquele jogador nos seus prêmios e este card estiver em sua mão, você pode colocá-lo em cena.",
			"Se o fizer, compre três cards.",
			"Quando um personagem ou suporte controlado por um oponente entrar em cena, se este card estiver em sua mão, você pode colocá-lo em cena, descarregar um personagem com Energia Inicial 3 ou maior que você controla desde o início do turno e colocá-lo nos prêmios de seus oponentes."
		]
	},
	"FMBSFA_088": {
		"name": "Beco Escuro",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário sair de cena, até o final do turno, toda vez que um personagem controlado por um oponente usar uma ação, aquela ação ganha Ação Única.",
			"Os personagens com Agilidade não podem ser alvos de ações que causem 3 ou mais pontos de dano."
		]
	},
	"FMBSFA_090": {
		"name": "Convocar a Tropa",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar ou sair de cena, compre um card e você pode capacitar em 1 um personagem com a afiliação Tropa Alfa que você controla.",
			"Se o fizer, procure em seu deck ou recursos por um card de personagem com a afiliação Tropa Alfa, revele aquele card e coloque-o em sua mão."
		]
	},
	"FMBSFA_089": {
		"name": "Clones de Restos",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "procure em seu deck ou recursos por um card de habilidade chamado SINTETIZADOR DE CARBONÁDIO e carregue-o em um personagem com o alter ego ARKADY ROSSOVICH ou com a afiliação Clã Ômega que você controla.",
					"manual": "procure em seu deck ou recursos por um card de habilidade chamado SINTETIZADOR DE CARBONÁDIO e carregue-o em um personagem com o alter ego ARKADY ROSSOVICH ou com a afiliação Clã Ômega que você controla."
				},
				{
					"label": "B",
					"text": "os cards de personagens com a afiliação Clã Ômega em seus recursos têm Reviver até o final da Fase de Preparação deste turno.",
					"manual": "os cards de personagens com a afiliação Clã Ômega em seus recursos têm Reviver até o final da Fase de Preparação deste turno."
				},
				{
					"label": "C",
					"text": "descarregue um personagem com o alter ego ARKADY ROSSOVICH ou com a afiliação Clã Ômega que você controla desde o início do turno e devolva-o para sua mão.",
					"manual": "descarregue um personagem com o alter ego ARKADY ROSSOVICH ou com a afiliação Clã Ômega que você controla desde o início do turno e devolva-o para sua mão."
				}
			]
		},
		"negation": false
	},
	"FMBSFA_091": {
		"name": "Deu Branco",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode embaralhar três cards de habilidade dos seus recursos em seu deck.",
			"Se o fizer, um oponente descarta um card."
		]
	},
	"FMBSFA_092": {
		"name": "Emergir dos Túneis",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando esse cenário entrar em cena, compre um card e você pode procurar em seu deck ou recursos por um card de personagem com a afiliação Morlocks.",
			"Se o fizer, coloque-o em sua mão.",
			"Você pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, até o final desta Fase de Preparação, você pode colocar em cena um card de personagem com a afiliação Morlocks como se ele tivesse Materializar."
		]
	},
	"FMBSFA_093": {
		"name": "Infestação Descontrolada",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um card de personagem com a afiliação Ninhada entrar em cena sob seu controle, você pode incapacitar aquele personagem em 1 e colocar este cenário nos recursos de seu dono.",
			"Se o fizer, coloque os dois cards do topo de seu deck em seus recursos e então procure em seu deck ou recursos por um card de personagem com a afiliação Ninhada, revele aquele card e coloque-o em sua mão."
		]
	},
	"FMBSFA_094": {
		"name": "Massacrar Mutantes",
		"enter": [],
		"leave": [],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "procure em seu deck ou recursos por um card de personagem com a afiliação Carrascos, revele aquele card e coloque-o no topo de seu deck.",
					"manual": "procure em seu deck ou recursos por um card de personagem com a afiliação Carrascos, revele aquele card e coloque-o no topo de seu deck."
				},
				{
					"label": "B",
					"text": "incapacite um personagem que você controla em 1.",
					"manual": "incapacite um personagem que você controla em 1."
				}
			]
		},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena ou quando este card for colocado nos seus recursos vindo do seu deck, se cada personagem que você controlar tiver a afiliação Carrascos, compre um card"
		]
	},
	"FMBSFA_095": {
		"name": "Pesquisa Avançada",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "procure em seu deck por um card de personagem com a afiliação Arma X com Energia Inicial 2 ou menor, revele aquele card e coloque-o em sua mão.",
					"manual": "procure em seu deck por um card de personagem com a afiliação Arma X com Energia Inicial 2 ou menor, revele aquele card e coloque-o em sua mão."
				},
				{
					"label": "B",
					"text": "embaralhe até cinco cards de seus recursos em seu deck.",
					"manual": "embaralhe até cinco cards de seus recursos em seu deck."
				}
			]
		},
		"negation": false
	},
	"FMBSFA_096": {
		"name": "Protocolo de Investigação",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando esse cenário entrar em cena, um oponente revela a própria mão e os dois cards do topo do próprio deck.",
			"Escolha dois que não sejam de personagem dentre os cards revelados e coloque-os no topo do deck daquele jogador e devolva os cards restantes para a mão dele.",
			"Cada jogador comprar um card."
		]
	},
	"FMBSFA_097": {
		"name": "Protocolo de Ressurreição",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando esse cenário entrar em cena, compre um card e escolha um card de personagem em seus recursos com mesmo alter ego de um personagem nos prêmios de seus oponentes.",
			"O card escolhido ganha Reviver até o final da Fase de Preparação."
		]
	},
	"FMBSFA_098": {
		"name": "Reunião do Coven",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar três ou mais personagens com Magia, compre dois cards e, até o final do turno, toda vez que um personagem que você controla usar uma ação com Clarividência, aquela ação tem Clarividência +1 e aquele personagem ganha Escudo +1."
		]
	},
	"FMBSFA_099": {
		"name": "X-Factor Investigações",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se o fizer, carregue o card do topo de seu deck naquele personagem e então descarregue um card daquele personagem.",
			"Quando um personagem com a afiliação X-Factor entrar em cena sob seu controle, se este card estiver em seus recursos, você pode embaralhar este card no seu deck.",
			"Se o fizer, compre um card."
		]
	},
	"FMBSID_088": {
		"name": "Agentes da Destruição",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar ou sair de cena, se você controlar um personagem com a afiliação Dignos, você pode colocar um card de personagem ou de habilidade que estiver em seus recursos na sua mão.",
			"Enquanto este card estiver em cena ou em seus recursos, toda vez que um personagem com a afiliação Dignos sofrer dano de ações, você pode escolher quais cards serão descarregados dele."
		]
	},
	"FMBSID_089": {
		"name": "Convocar Martelo",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e então você pode procurar em seu deck por um card de habilidade chamado MAÇA TROVEJANTE, MJÖLNIR ou ROMPE TORMENTAS, revelar aquele card e colocá-lo em seus recursos.",
			"Se o fizer, você pode colocar este card nos recursos de seu dono.",
			"Quando este card sair de cena, se você controlar um ou mais personagens com a afiliação Tropa Thor, coloque os três cards do topo de seu deck em seus recursos."
		]
	},
	"FMBSID_090": {
		"name": "Dez Reinos",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Uma vez por turno, quando um personagem com Energia Inicial 3 ou menor e com a afiliação Asgardianos e/ou Inimigos do Thor entrar em cena, você pode comprar um card e colocar o card do topo de seu deck em seus recursos.",
			"Uma vez por turno, quando um personagem com Energia Inicial 4, 5 ou 6 e com a afiliação Asgardianos e/ou Inimigos do Thor entrar em cena, você pode comprar um card e colocar os dois cards do topo de seu deck em seus recursos.",
			"Uma vez por turno, quando um personagem com Energia Inicial 7 ou maior e afiliação Asgardianos e/ou Inimigos do Thor entrar em cena, você pode comprar um card e colocar os três cards do topo de seu deck em seus recursos."
		]
	},
	"FMBSID_091": {
		"name": "Exceder Limites",
		"enter": [
			{
				"op": "mandar_topo_para_recursos",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante sua Fase de Preparação, se este card estiver em cena ou em seus recursos, você pode colocá-lo na base do seu deck.",
			"Se o fizer, até o final do turno os cards de Personagem-EV de sua mão ou recursos podem ser colocados em cena como um card de personagem não EV."
		]
	},
	"FMBSID_092": {
		"name": "Glorioso Propósito",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Enquanto este cenário estiver em cena ou em seus recursos, os personagens chamados RÉPLICA DE LOKI têm Materializar e 'Prontidão - ação ATAQUE FANTASMA'.",
			"Enquanto este cenário estiver em cena ou em seus recursos, no início de cada turno, você pode colocar este card no topo de seu deck e então embaralhar o seu deck.",
			"Se o fizer, você pode colocar um card de cenário chamado IMAGEM FALSA de seus recursos em cena."
		]
	},
	"FMBSID_093": {
		"name": "Intervenção Divina",
		"enter": [
			{
				"op": "comprar",
				"quantity": 2,
				"if": {
					"type": "affiliation",
					"value": "conselho dos pais celestiais e/ou deuses do egito",
					"min": 1
				}
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Se não, procure em seu deck por um card de personagem com a afiliação Conselho dos Pais Celestiais e/ou Deuses do Egito, revele aquele card e coloque-o em sua mão.",
			"Enquanto este cenário estiver em cena ou em seus recursos, os personagens com alter ego ATHENA PARTHENOS, HERA ARGEIA, HERACLES, THOR ODINSON e/ou ZEUS PANHELLENIOS que estiverem em cena, em seu deck, em sua mão, em seus recursos ou nos prêmios de seus oponentes ganham a afiliação Conselho dos Pais Celestiais."
		]
	},
	"FMBSID_094": {
		"name": "Invocar o Relâmpago",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Enquanto um ou mais personagens que você controla estiverem carregando um card de habilidade chamado MAÇA TROVEJANTE, MJÖLNIR e/ou ROMPE TORMENTAS, os outros personagens com a afiliação Tropa Thor que você controla ganham Escudo +1, Ataque a Distância, Ataque Energético e Voo.",
			"Os personagens com alter ego THOR ODINSON que você controla ganham Pelotão e afiliação Tropa Thor."
		]
	},
	"FMBSID_095": {
		"name": "Rumo À Guerra",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Durante a sua Fase de preparação, você pode colocar este card nos recursos de seu dono.",
			"Se o fizer, pule a sua Fase de Combate e, até o final da partida, outros cards chamados RUMO À GUERRA não tem efeito.",
			"Durante sua Fase de preparação, se você não controlar nenhum personagem, você pode devolver este card dos seus recursos para sua mão.",
			"Se o fizer, compre 1-X cards.",
			"X é igual ao número de outros cenários chamados RUMO À GUERRA que tiveram seus efeitos ativados neste turno."
		]
	},
	"FMBSID_096": {
		"name": "Sair de Fininho",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, procure em seu deck por um card de personagem, coloque-o nos prêmios de seus oponentes e então coloque um card de personagem com a mesma Energia Inicial e um nome diferente daquele card dos prêmios de seus oponentes na sua mão."
		]
	},
	"FMBSID_097": {
		"name": "Ser Digno",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, escolha um personagem herói que você controla e carregue um card chamado MJÖLNIR dos seus recursos naquele personagem.",
			"Compre um card.",
			"O personagem escolhido ganha o nome THOR."
		]
	},
	"FMBSID_098": {
		"name": "Todas as Cores",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre dois cards, coloque um card da sua mão na base de seu deck.",
			"Enquanto você controlar quatro ou mais personagens e cada personagem que você controlar tiver a afiliação Jovens Vingadores, eles podem usar ações dos cards de habilidade que estiverem carregando, mesmo que não tenham os poderes daquelas ações."
		]
	},
	"FMBSLAM_012": {
		"name": "Programação Defeituosa",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, você pode procurar em seu deck e/ou recursos por um card de personagem com a afiliação Sentinelas e/ou por um card de habilidade chamado CAPTURAR MUTANTE.",
			"Se o fizer, revele aqueles cards e coloque-os em sua mão.",
			"Quando este cenário sair de cena, até o final do turno, enquanto houver em cena um personagem com alter ego Sentinela, os personagens cujas afiliações não sejam Sentinelas ganham as afiliações X-Men e Irmandade de Mutantes."
		]
	},
	"FMBSMP_010": {
		"name": "Disputa Pelo Título",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"No início do turno de cada jogador, se cada jogador controlar um ou mais personagens e você controlar um ou mais personagens com a afiliação Sociedade das Cinco Armas, o jogador que controlar menos personagens escolhe cada personagem que ele controla e então cada outro jogador escolhe aquele mesmo número de personagens que ele próprio controla.",
			"Até o final do turno, os personagens que não foram escolhidos não podem ser alvos de ações e não podem usar ações.",
			"Enquanto este cenário estiver em seus recursos, no final do turno de cada jogador, se você controlar um ou mais personagens com a afiliação Sociedade das Cinco Armas e nenhum cenário chamado DISPUTA PELO TÍTULO estiver em cena, você pode colocar este cenário em cena."
		]
	},
	"FMBSPE_033": {
		"name": "Plano de Contingência",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar ou sair de cena, se você controlar um personagem com a afiliação Jovens Vingadores, você pode olhar os cinco cards do topo do seu deck, revelar um card de personagem com a afiliação jovens vingadores dali, colocá-lo em cena e colocar os demais cards de volta no topo de seu deck em qualquer ordem."
		]
	},
	"FMBSPI_098": {
		"name": "Arquitetar Plano",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e você pode colocar em cena um suporte com a Energia Inicial 5 ou maior e sem afiliação (N/A) como se ele tivesse Materializar."
		]
	},
	"FMBSPI_099": {
		"name": "Degeneração Induzida",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um efeito fizer com que um ou mais cards dos recursos ou do topo do deck de um oponente sejam carregados em um personagem que aquele oponente controla, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Quando este cenário entrar em cena desta forma, aqueles cards são descarregados e colocados nos recursos de seu dono e outros cards não podem ser carregados ou descarregados daquele personagem até o final desta etapa ou fase do turno."
		]
	},
	"FMBSPI_100": {
		"name": "Entrar No Microverso",
		"enter": [],
		"leave": [],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "carregue um card chamado PARTÍCULAS PYM dos seus recursos em um personagem que você controla.",
					"manual": "carregue um card chamado PARTÍCULAS PYM dos seus recursos em um personagem que você controla."
				},
				{
					"label": "B",
					"text": "Descarregue um card chamado PARTÍCULAS PYM de um personagem.",
					"manual": "Descarregue um card chamado PARTÍCULAS PYM de um personagem."
				}
			],
			"before": "recursos"
		},
		"negation": false
	},
	"FMBSPI_101": {
		"name": "Família Real",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {
			"timing": "affiliation",
			"items": [
				{
					"label": "A",
					"text": "compre um card e coloque o card do topo de seu deck em seus recursos.",
					"action": {
						"op": "multi",
						"actions": [
							{
								"op": "comprar",
								"quantity": 1
							},
							{
								"op": "mandar_topo_para_recursos",
								"quantity": 1
							}
						]
					}
				},
				{
					"label": "B",
					"text": "você pode procurar em seu deck por um card de personagem com a afiliação Inumanos.",
					"manual": "procurar em seu deck por um card de personagem com a afiliação Inumanos."
				}
			],
			"affiliation": "Inumanos",
			"timing_if": {
				"type": "affiliation",
				"value": "Inumanos",
				"min": 1
			},
			"before": "recursos"
		},
		"negation": false
	},
	"FMBSPI_102": {
		"name": "Informações Secretas",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com a afiliação S.H.I.E.L.D.",
			"entrar em cena sob seu controle, você pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, olhe os dois cards do topo do seu deck, coloque um deles na sua mão e carregue o outro em um personagem com a afiliação S.H.I.E.L.D.",
			"que você controla.",
			"entrar em cena sob seu controle, se este card estiver em seus recursos, você pode colocar este card na base do seu deck.",
			"Se o fizer, você pode procurar em seu deck por um card de personagem chamado AGENTE S.H.I.E.L.D..",
			"Se o fizer, revele aquele card, coloque-o em sua mão e embaralhe o seu deck."
		]
	},
	"FMBSPI_103": {
		"name": "Invasão Skrull",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com a afiliação Skrulls entrar em cena sob seu controle sem ser materializado, se este card estiver em cena ou em seus recursos, você pode colocar este card na base do seu deck.",
			"Se o fizer, compre um card, você pode colocar em cena um card de personagem ou suporte com a afiliação Skrulls da sua mão como se ele tivesse Materializar e outros cenários chamados INVASÃO SKRULL não têm efeito até o final do turno."
		]
	},
	"FMBSPI_104": {
		"name": "Legado",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {
			"timing": "entry",
			"items": [
				{
					"label": "A",
					"text": "Se você controlar um personagem com a afiliação Invasores, coloque este card nos recursos de seu dono e então coloque os dois cards do topo de seu deck em seus recursos.",
					"manual": "coloque este card nos recursos de seu dono e então coloque os dois cards do topo de seu deck em seus recursos."
				},
				{
					"label": "B",
					"text": "Se houver um personagem chamado CAPITÃO AMÉRICA nos prêmios de seu oponente, você pode procurar por até três personagens chamados CAPITÃO AMÉRICA com alter egos diferentes em seu deck ou recursos.",
					"manual": "procurar por até três personagens chamados CAPITÃO AMÉRICA com alter egos diferentes em seu deck ou recursos."
				}
			]
		},
		"negation": false
	},
	"FMBSPI_105": {
		"name": "Nação Duende",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem controlado por um oponente usar uma ação que cause dano tendo como alvo um ou mais personagens com a afiliação Nação Duende que você controla, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Quando este cenário entrar em cena desta forma, aquela ação não tem efeito.",
			"Enquanto este cenário estiver em cena ou em seus recursos, os personagens Vilões com Pelotão, ➡️ e que tenham alguma afiliação que estiverem em cena, em seu deck ou em seus recursos, perdem suas afiliações e ganham a afiliação Nação Duende."
		]
	},
	"FMBSPI_106": {
		"name": "Nova Ordem Mundial",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e você pode colocar este card nos recursos de seu dono e então procurar em seu deck por um card de personagem com a afiliação I.M.A..",
			"Se o fizer, revele aquele card, coloque-o em sua mão e embaralhe o seu deck.",
			"Quando um personagem com a afiliação I.M.A.",
			"entrar em cena sob seu controle, se este card estiver em seus recursos, você pode colocar este card na base do seu deck.",
			"Se o fizer, você pode colocar um card de personagem ou suporte com a afiliação I.M.A.",
			"que estiver em seus recursos na sua mão."
		]
	},
	"FMBSPI_107": {
		"name": "Passado, Presente e Futuro",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com a afiliação Fugitivos entrar em cena, você pode escolher um card dos seus recursos e colocá-lo em sua mão.",
			"Se o fizer, compre um card, depois coloque um card do topo de seu deck em seus recursos, e então, coloque este card na base de seu deck."
		]
	},
	"FMBSPI_108": {
		"name": "Planejamentos Nefastos",
		"enter": [],
		"leave": [],
		"options": {
			"timing": "affiliation",
			"items": [
				{
					"label": "A",
					"text": "coloque os quatro cards do topo do deck de um jogador nos recursos de seu dono.",
					"manual": "coloque os quatro cards do topo do deck de um jogador nos recursos de seu dono."
				},
				{
					"label": "B",
					"text": "você pode procurar em seu deck por um card de personagem com a afiliação Cabala.",
					"manual": "procurar em seu deck por um card de personagem com a afiliação Cabala."
				}
			],
			"affiliation": "Cabala",
			"timing_if": {
				"type": "affiliation",
				"value": "Cabala",
				"min": 1
			},
			"before": "recursos"
		},
		"negation": false,
		"pending": [
			"Quando um personagem com a afiliação Cabala entrar em cena sob seu controle, você pode incapacitar aquele personagem em 1 e colocar este card nos recursos de seu dono."
		]
	},
	"FMBSPI_109": {
		"name": "Planejar Investida",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Enquanto este cenário estiver em cena ou em seus recursos, durante a sua Etapa de Ataque, você pode escolher um personagem com a afiliação Excalibur que você controlar.",
			"Se o fizer, coloque este card na base de seu deck e aquele personagem ganha 'Prontidão - ações que não sejam de cards de habilidade'."
		]
	},
	"FMBSPI_110": {
		"name": "Procurar Ajuda",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e até o final do turno, as ações dos personagens com a afiliação Fugitivos que entraram em cena neste turno tem Singularidade e os personagens com a afiliação Fugitivos que entraram em cena neste turno não podem ser alvos de ações.",
			"Enquanto este card estiver em cena ou em seus recursos, personagens chamados MANTO e/ou ADAGA que estiverem em cena, em seu deck, em sua mão ou em seus recursos, ganham a afiliação Fugitivos e as ações deles que não sejam de cards de habilidade tornam-se ações de antecipar ⚠️ e imprevistas ◷."
		]
	},
	"FMBSPI_111": {
		"name": "Salto de Fé",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem com Voo entrar em cena sob seu controle, você pode incapacitar aquele personagem em 1 e colocar este cenário em seus recursos.",
			"Se o fizer olhe os três cards do topo de seu deck.",
			"Coloque dois daqueles cards no topo de seu deck e o outro em seus recursos.",
			"Compre dois cards."
		]
	},
	"FMBSPI_112": {
		"name": "Sem Opções",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um personagem usar uma ação que tiver o mesmo nome de outra ação que tenha sido usada neste turno e este card estiver em sua mão, você pode colocá-lo em cena.",
			"Se o fizer, aquela ação não tem efeito.",
			"Quando este cenário entrar em cena, compre um card e, até o final do turno, os personagens não podem usar ações com o mesmo nome de outra ação que tenha sido usada neste turno."
		]
	},
	"FMBSPI_113": {
		"name": "Vozes Na Cabeça - Cheguei!",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um personagem com alter ego WANDA WILSON e/ou WADE WILSON, você pode carregar um card de sua mão em um personagem com a afiliação Tropa Deadpool que você controla.",
			"Se o fizer, escolha e coloque um card que aquele personagem estiver carregando na mão de seu dono e então compre dois cards e coloque este cenário em seus recursos."
		]
	},
	"FMBSPI_114": {
		"name": "Vozes Na Cabeça - Essa Doeu",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode colocar os dois cards do topo do seu deck em seus recursos, e um card de personagem com alter ego WANDA WILSON ou WADE WILSON dos seus recursos ganha Reviver até o final do turno."
		]
	},
	"FMBSPI_115": {
		"name": "Vozes Na Cabeça - Hoje Não!",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um efeito controlado por um oponente fizer com que ele procure por um ou mais cards no próprio deck, se este card estiver em sua mão e você controlar um personagem com alter ego WANDA WILSON e/ou WADE WILSON, você pode colocá-lo em cena.",
			"Quando este cenário entrar em cena desta forma, aquele jogador não pode procurar por aqueles cards e você pode procurar em seu deck por um card de cenário com o nome VOZES NA CABEÇA, revelá-lo, colocá-lo em sua mão e embaralhar seu deck."
		]
	},
	"FMBSPI_116": {
		"name": "Vozes Na Cabeça - Tá Tranquilo",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um personagem fosse receber dano que não seja de uma ação, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Se você controlar um personagem com o alter ego WANDA WILSON e/ou WADE WILSON, até o final do turno, todo o dano que não seja de ações que for causado a personagens com a afiliação Tropa Deadpool torna-se 0."
		]
	},
	"FMBSPI_117": {
		"name": "Vozes Na Cabeça - Tá Zoando?",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um personagem usar uma ação, se aquela não for a primeira ação que aquele personagem usou neste turno e este card estiver em sua mão e você controlar um personagem com alter ego WANDA WILSON e/ou WADE WILSON, você pode colocá-lo em cena.",
			"Se o fizer, aquela ação não tem efeito.",
			"Quando este cenário entrar em cena, compre um card e, até o final do turno, os personagens sem o alter ego WANDA WILSON e/ou WADE WILSON não podem usar ações caso já tenham usado alguma ação neste turno."
		]
	},
	"FMBSPI_DECK_004": {
		"name": "Plano Ancestral",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode escolher um card de personagem com a afiliação Culto da Pantera e/ou Dora Milaje de seus recursos e colocá-lo em cena diretamente de seus recursos.",
			"Compre um card.",
			"Enquanto este cenário estiver em cena, toda vez que uma ação de um personagem controlado por um oponente fosse causar dano em um personagem com a afiliação Culto da Pantera que você controla, você pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, aquele dano torna-se 0."
		]
	},
	"FMBSUI_094": {
		"name": "Abandonar o Manto",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e escolha um personagem controlado por outro jogador.",
			"Enquanto este cenário estiver em cena, o personagem escolhido perde seus alinhamentos e afiliações e os textos permanentes do personagem escolhido não têm efeito."
		]
	},
	"FMBSUI_095": {
		"name": "Acabou?",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"No início do seu turno, se este cenário estiver em cena ou em seus recursos e você não controlar nenhum personagem, você pode colocá-lo na base de seu deck e descartar um card.",
			"Se o fizer, escolha um card de personagem dos seus recursos e coloque-o em cena."
		]
	},
	"FMBSUI_096": {
		"name": "Ajuda do Multiverso",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um ou mais personagens com a afiliação Esquadrão Supremo, coloque os quatro cards do topo de seu deck em seus recursos e então coloque três cards dos seus recursos na base de seu deck em qualquer ordem.",
			"Compre um card."
		]
	},
	"FMBSUI_097": {
		"name": "Aliados da Guilda",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, se você controlar um ou mais personagens com a afiliação Guilda dos Assassinos e/ou Guilda dos Ladrões com Energia Inicial 3, você pode colocar um card de personagem com a afiliação Guilda dos Assassinos e/ou Guilda dos Ladrões com Energia Inicial 3 dos prêmios de um oponente em cena.",
			"Se o fizer, descarregue um personagem ou suporte que você controla com a afiliação Guilda dos Assassinos e/ou Guilda dos Ladrões com Energia Inicial 3 e coloque-o no prêmios daquele oponente."
		]
	},
	"FMBSUI_098": {
		"name": "Barreira Invisível",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Enquanto este cenário estiver em cena ou em seus recursos, se cada personagem que você controlar tiver a afiliação Quarteto Fantástico, toda vez que uma ação fosse causar dano em um personagem que você controla, você pode colocar X+1 cards de habilidade dos seus recursos no topo de seu deck.",
			"Se o fizer, embaralhe seu deck e então aquele dano torna-se 0.",
			"X é igual ao valor do dano daquela ação."
		]
	},
	"FMBSUI_099": {
		"name": "Bloqueio Psiônico",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um efeito de uma ação de um personagem controlado por um oponente fosse descarregar um ou mais cards de um personagem que você controla, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Se o fizer, aquela ação não tem efeito e ações com mesmo nome não podem ser usadas até o final do turno."
		]
	},
	"FMBSUI_100": {
		"name": "Chamada À Caçada",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar ou sair de cena, se você controlar um personagem com Predador, procure em seu deck por um card de personagem com Predador, revele-o, coloque-o em sua mão e embaralhe seu deck."
		]
	},
	"FMBSUI_101": {
		"name": "Comprometer Operação",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Enquanto este cenário estiver em cena ou em seus recursos, toda vez que uma ação de antecipar usada por um personagem controlado por um oponente tiver como alvo um ou mais personagens que você controla, você pode colocar este cenário na base do deck de seu dono.",
			"Se o fizer, você pode escolher um personagem ou suporte que você controla como um dos alvos para aquela ação."
		]
	},
	"FMBSUI_102": {
		"name": "Evitar Tragédia",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem que você controla fosse ser nocauteado por uma ação de um personagem controlado por um oponente, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Quando este cenário entrar em cena desta forma, coloque um card de personagem dos seus recursos com Energia Inicial igual ou maior a daquele personagem nos pontos do seu oponente.",
			"Se o fizer, coloque aquele personagem (o personagem que seria nocauteado) em seus recursos."
		]
	},
	"FMBSUI_103": {
		"name": "Festa Lá Em Casa!",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, todo o dano que seria causado em personagens com a afiliação Novos Mutantes até o final deste turno fora da Etapa de Ataque torna-se 0.",
			"Se este cenário sair de cena, todo o dano que seria causado a personagens com a afiliação Novos Mutantes até o final deste turno fora da Etapa de Ataque torna-se 0 e você pode procurar em seu deck por um card de personagem com a afiliação Novos Mutantes.",
			"Se o fizer, revele aquele card, coloque-o em sua mão e embaralhe o seu deck."
		]
	},
	"FMBSUI_104": {
		"name": "Imprevisibilidade",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando você colocar um personagem com Agilidade em cena, você pode incapacitar aquele personagem em 1 e colocar este cenário em seus recursos.",
			"Se o fizer, carregue três cards do topo de seu deck naquele personagem.",
			"Descarregue três cards daquele personagem e então você pode capacitar em 1 outro personagem que você controla."
		]
	},
	"FMBSUI_105": {
		"name": "Invasão Cósmica",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena escolha um oponente.",
			"Coloque os dois cards do topo do deck daquele oponente nos recursos de seu dono.",
			"Se o fizer, coloque até três cards que não sejam de cenário dos recursos daquele oponente na base do deck de seu dono.",
			"Compre um card."
		]
	},
	"FMBSUI_106": {
		"name": "Legião de Ferro",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode colocar um card de personagem com a afiliação Legião de Ferro que estiver em seus recursos na sua mão.",
			"Enquanto este cenário estiver em cena ou em seus recursos, os personagens com alter ego ANTHONY EDWARD STARK, JAMES RUPERT RHODES, RIRI WILLIAMS, e/ou VIRGINIA POTTS-HOGAN que estiverem em cena, em seu deck, em sua mão ou em seus recursos, ganham a afiliação Legião de Ferro."
		]
	},
	"FMBSUI_107": {
		"name": "Lei Imperial",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Toda vez que um personagem com a afiliação Guarda Imperial entrar em cena sob seu controle, se cada personagem que você controlar tiver a afiliação Guarda Imperial, você pode capacitar em 1 um personagem que você controla.",
			"Se o fizer, coloque o card do topo de seu deck em seus recursos.",
			"Quando este cenário sair de cena, capacite em 1 cada personagem com a afiliação Guarda Imperial que você controla."
		]
	},
	"FMBSUI_108": {
		"name": "Múltiplas Identidades",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena compre um card e revele um card de personagem não EV da sua mão.",
			"Durante sua fase de preparação, o personagem revelado pode entrar em cena como se fosse um Personagem-EV com Energia Extra +0 e requisito de evolução 'EV - personagem com o mesmo alter ego deste card'."
		]
	},
	"FMBSUI_109": {
		"name": "Poderes Ocultos",
		"enter": [],
		"leave": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, olhe os três cards do topo de seu deck e coloque-os no topo e/ou na base de seu deck em qualquer ordem.",
			"Você pode revelar o card do topo do seu deck.",
			"Se o card revelado for uma habilidade, você pode carregar o card revelado em um personagem que você controla."
		]
	},
	"FMBSUI_110": {
		"name": "Quebra de Contrato",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando um personagem que você controla for incapacitado em 1 ou 2 por um efeito controlado por um oponente, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Se o fizer, capacite aquele personagem em 1 ou 2."
		]
	},
	"FMBSUI_111": {
		"name": "Rastro de Toupeira",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e coloque um card dos recursos de um oponente na base do deck do seu dono.",
			"Quando este cenário sair de cena, coloque um card dos recursos de um oponente na base do deck do seu dono.",
			"Quando este card for colocado nos seus recursos vindo da sua mão, coloque um card que não seja de cenário dos recursos de um oponente na base do deck do seu dono."
		]
	},
	"FMBSUI_112": {
		"name": "Resquícios da Batalha",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena você pode descarregar um card de cenário de um personagem que você controla e incapacitar aquele personagem em 1.",
			"Se o fizer, coloque o card descarregado por este efeito em cena e carregue um card de cenário dos seus recursos naquele personagem."
		]
	},
	"FMBSUI_113": {
		"name": "Sorte No Amor",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, compre um card e cada jogador pode colocar até dois cards de seus próprios recursos na base do deck de seu dono.",
			"Cada jogador que o fizer, embaralha o seu deck e compra aquela mesma quantidade de cards."
		]
	},
	"FMBSUI_114": {
		"name": "Tirar Proveito",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Quando um efeito controlado por um oponente fizer com que ele procure por um ou mais cards no próprio deck, se este card estiver em sua mão, você pode colocá-lo em cena.",
			"Quando este cenário entrar em cena desta forma, aquele jogador pode colocar exatamente dois cards da mão na base do próprio deck.",
			"Se não o fizer, aquele jogador não pode procurar por aqueles cards."
		]
	},
	"FMBSUI_115": {
		"name": "Trabalhando Para o Chefe",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Todos os personagens com Pelotão e sem a característica Espionar ganham Espionar."
		]
	},
	"FMBSUI_116": {
		"name": "Universo Marvel",
		"enter": [
			{
				"op": "comprar",
				"quantity": 1
			}
		],
		"leave": [],
		"options": {},
		"negation": true,
		"pending": [
			"Os textos permanentes de todos os personagens não têm efeito e ações imprevistas ◷ não podem ser usadas.",
			"Quando este cenário sair de cena, ações imprevistas ◷ não podem ser usadas até o final do turno."
		]
	},
	"FMBSUI_117": {
		"name": "Vamos Lá, Campeões!",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode capacitar em 1 um personagem com a afiliação Campeões que você controla.",
			"Se o fizer, coloque os dois cards do topo de seu deck em seus recursos e coloque um card de personagem com a afiliação Campeões que estiver em seus recursos na sua mão.",
			"Enquanto este cenário estiver em cena ou em seus recursos, os personagens com alter ego MILES MORALES, AMADEUS CHO, SAM ALEXANDER e/ou VICTOR ALVAREZ que estiverem em cena, em seu deck, em sua mão ou em seus recursos, perdem suas afiliações e ganham a afiliação Campeões."
		]
	},
	"FMBSUI_118": {
		"name": "Vestir o Manto",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar ou sair de cena, se você controlar um personagem com a afiliação Vingadores, procure em seu deck por um card de personagem com a afiliação Vingadores, revele-o, coloque-o em sua mão e embaralhe seu deck.",
			"Enquanto este card estiver em cena ou em seus recursos, os personagens com afiliação Vingadores que você controla sem a característica Aprimoramento ganham Aprimoramento."
		]
	},
	"FM_BATTLE_BOX_019": {
		"name": "Plano Ancestral",
		"enter": [],
		"leave": [],
		"options": {},
		"negation": false,
		"pending": [
			"Quando este cenário entrar em cena, você pode escolher um card de personagem com a afiliação Culto da Pantera e/ou Dora Milaje de seus recursos e colocá-lo em cena diretamente de seus recursos.",
			"Compre um card.",
			"Enquanto este cenário estiver em cena, toda vez que uma ação de um personagem controlado por um oponente fosse causar dano em um personagem com a afiliação Culto da Pantera que você controla, você pode colocar este cenário nos recursos de seu dono.",
			"Se o fizer, aquele dano torna-se 0."
		]
	}
}
