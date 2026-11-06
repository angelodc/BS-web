# Regenerates the CARDS dictionary of SetDefinition_ResgateAracnideo.gd from
# the bsdb-imagens cards.json, applying the same defaults as
# BSDBDeckImportDialog.make_card_properties. Run from the repo root:
#   python tools/fill_resgate_texts.py
import io
import json
import re
import sys

REPO_CARDS = r"D:\Projetos\bsdb-imagens\dados\cards.json"
SET_FILE = r"src\custom\cards\sets\SetDefinition_ResgateAracnideo.gd"

VALID_CARD_TYPES = ["Personagem", "Suporte", "Habilidade", "Cenário"]
ENERGY_CARD_TYPES = ["Personagem", "Suporte"]
TEMPLATE_FOR_CATEGORY = {
    "Personagem": "Blue",
    "Cenário": "Green",
    "Suporte": "Red",
    "Habilidade": "Purple",
}


def normalize_category(raw: str) -> str:
    category = raw.strip()
    if " - " in category:
        category = category.split(" - ")[0].strip()
    for valid in VALID_CARD_TYPES:
        if category.lower() == valid.lower():
            return valid
    return category


def string_or_default(data, key, default):
    value = data.get(key)
    if value is None or str(value) == "":
        return default
    return str(value)


# ERRATA/FAQ come as lists of paragraphs in the BSDB data.
def texts_or_default(data, key, default):
    value = data.get(key)
    if value is None:
        return default
    if isinstance(value, list):
        items = [str(item) for item in value if str(item).strip()]
        return "\n\n".join(items) if items else default
    return string_or_default(data, key, default)


def make_card_properties(record):
    category = normalize_category(str(record.get("TIPO", "")))
    ability = string_or_default(record, "TEXTO", "")
    for action in record.get("ACOES") or []:
        action_text = string_or_default(action, "TEXTO", "")
        if action_text:
            if ability:
                ability += "\n\n"
            ability += action_text
    evolution = string_or_default(record, "TEXTO_EV", "")
    if evolution:
        if ability:
            ability += "\n\n"
        ability += evolution
    energy_default = "" if category in ENERGY_CARD_TYPES else "0"
    return {
        "Type": TEMPLATE_FOR_CATEGORY[category],
        "_tipo": category,
        "ENERGIA": string_or_default(record, "ENERGIA", energy_default),
        "Tags": record.get("PODERES") or [],
        "Requirements": string_or_default(record, "AFILIACAO", ""),
        "Abilities": ability,
        "Cost": 0,
        "Power": 0,
        "_bsdb_id": str(record.get("ID_CARD", "")),
        "_bsdb_image_path": str(record.get("IMAGEM", "")),
        "_bsdb_shield": string_or_default(record, "ESCUDO", "0"),
        "_errata": texts_or_default(record, "ERRATA", ""),
        "_faq": texts_or_default(record, "FAQ", ""),
        "_illustration": string_or_default(record, "ILUSTRADORES", ""),
    }


def gd_string(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )
    return f'"{escaped}"'


def gd_value(value) -> str:
    if isinstance(value, str):
        return gd_string(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(gd_value(item) for item in value) + "]"
    raise TypeError(f"unsupported value: {value!r}")


def render_card(name, props):
    lines = [f"\t{gd_string(name)}: {{"]
    tags = gd_value(props.pop("Tags"))
    abilities = gd_value(props.pop("Abilities"))
    lines.append(
        f"\t\t\"Type\": {gd_value(props.pop('Type'))}, "
        f"\"_tipo\": {gd_value(props.pop('_tipo'))}, "
        f"\"ENERGIA\": {gd_value(props.pop('ENERGIA'))},"
    )
    lines.append(f"\t\t\"Tags\": {tags},")
    lines.append(
        f"\t\t\"Requirements\": {gd_value(props.pop('Requirements'))}, "
        f"\"Abilities\": {abilities},"
    )
    lines.append(
        f"\t\t\"Cost\": {props.pop('Cost')}, \"Power\": {props.pop('Power')},"
    )
    lines.append(
        f"\t\t\"_bsdb_id\": {gd_value(props.pop('_bsdb_id'))},"
    )
    lines.append(
        f"\t\t\"_bsdb_image_path\": {gd_value(props.pop('_bsdb_image_path'))},"
    )
    shield = props.pop("_bsdb_shield")
    errata = gd_value(props.pop("_errata"))
    faq = gd_value(props.pop("_faq"))
    illustration = gd_value(props.pop("_illustration"))
    if shield != "0":
        lines.append(f"\t\t\"_bsdb_shield\": {gd_value(shield)},")
    lines.append(f"\t\t\"_errata\": {errata},")
    lines.append(f"\t\t\"_faq\": {faq},")
    lines.append(f"\t\t\"_illustration\": {illustration},")
    if props:
        raise ValueError(f"unrendered fields: {props.keys()}")
    lines.append("\t},")
    return lines


def main():
    with io.open(REPO_CARDS, encoding="utf-8") as handle:
        repo_cards = json.load(handle)
    by_id = {str(card.get("ID_CARD")): card for card in repo_cards}

    with io.open(SET_FILE, encoding="utf-8") as handle:
        content = handle.read()

    header_match = re.search(r"const CARDS := \{", content)
    if not header_match:
        sys.exit("CARDS dictionary not found")
    names = re.findall(r'^\t"((?:[^"\\]|\\.)+)": \{', content, re.MULTILINE)
    entries = []
    for name in names:
        card_id = re.search(
            r'"%s": \{(?:(?!^\t\},?$).)*?"_bsdb_id": "([^"]+)"' % re.escape(name),
            content,
            re.DOTALL | re.MULTILINE,
        )
        if not card_id:
            sys.exit(f"_bsdb_id not found for {name}")
        record = by_id.get(card_id.group(1))
        if record is None:
            sys.exit(f"{name} ({card_id.group(1)}) missing from cards.json")
        entries.append(render_card(name, make_card_properties(record)))

    out = [content[: header_match.end()], ""]
    for entry in entries:
        out.extend(entry)
        out.append("")
    out.append("}")
    if not content.rstrip().endswith("}"):
        sys.exit("unexpected file ending")
    with io.open(SET_FILE, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(out))
    print(f"rewrote {len(entries)} cards")


if __name__ == "__main__":
    main()
