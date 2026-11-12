extends "res://tests/UTcommon.gd"

const REPO_MAIN := "https://raw.githubusercontent.com/inimig0r/bsdb-imagens/refs/heads/main"


func test_official_cards_use_the_oficial_root():
	assert_eq(
			CFControl.bsdb_image_url("/bsca/BSCA_006.png"),
			REPO_MAIN + "/cards/oficial/bsca/BSCA_006.png")


func test_fan_made_cards_use_the_excelsior_root():
	assert_eq(
			CFControl.bsdb_image_url("/fmbspi/FMBSPI_042.png"),
			REPO_MAIN + "/cards/excelsior/fmbspi/FMBSPI_042.png")


func test_full_catalog_paths_keep_the_repository_root():
	assert_eq(
			CFControl.bsdb_image_url("/cards/excelsior/fmbsui/FMBSUI_130.png"),
			REPO_MAIN + "/cards/excelsior/fmbsui/FMBSUI_130.png")
