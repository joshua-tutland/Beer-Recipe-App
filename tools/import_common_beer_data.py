#!/usr/bin/env python3
"""Merge Wall Brew Co's common-beer-data (MIT) into the app's bundled ingredient JSON.

Usage:
    git clone --depth 1 https://github.com/Wall-Brew-Co/common-beer-data /tmp/common-beer-data
    python3 tools/import_common_beer_data.py /tmp/common-beer-data

Entries already in the curated JSON (matched by normalized name, or lab + product id for yeast)
are kept as they are, so existing recipe and inventory ids never change. Only new ingredients
are appended, tagged with `"source": "common-beer-data"`.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "BrewCore", "Sources", "BrewCore", "Resources")
SOURCE_TAG = "common-beer-data"

FIELD = re.compile(r'cbf/([\w-]+)\s+("(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?|true|false|nil)', re.S)
ENTRY = re.compile(r'\((?:[\w-]+/)?build-[\w-]+\s+:([\w-]+)\s*\{(.*?)\}\)', re.S)


# Source entries that duplicate a curated ingredient under another name, or whose values look wrong.
SKIP_FERMENTABLES = {
    "Acid Malt",                     # = Acidulated Malt
    "Cara-Pils/Dextrine", "CaraFoam", "Dextrine",  # = Carapils / Carafoam
    "Caramel/Crystal Malt - 10L", "Caramel/Crystal Malt - 20L", "Caramel/Crystal Malt - 40L",
    "Caramel/Crystal Malt - 60L", "Caramel/Crystal Malt - 80L", "Caramel/Crystal Malt - 120L",
    "Corn Sugar", "Dextrose",        # = Corn Sugar (Dextrose)
    "Table Sugar", "Sucrose", "Cane Sugar",  # = Table Sugar (Sucrose)
    "Milk Sugar",                    # = Lactose (and the source marks it fermentable)
    "Maris Otter Pale Malt", "Melanoiden Malt", "Peat Smoked Malt", "Smoked Malt",
    "Munich Malt", "Munich Malt - 10L", "Munich Malt - 20L",
    "Pale Malt (2 Row) - USA", "Pilsner (2 Row) - Germany", "Wheat Malt - Germany",
    "Extra Light Dry Extract",       # source potential 1.036 is far below dry extract's ~1.044
}
SKIP_HOPS = {
    "Columbus", "CTZ",               # = Columbus (CTZ)
    "East Kent Golding",             # = East Kent Goldings
    "Mt. Hood",                      # = Mount Hood
    "Celeia",                        # = Styrian Golding (Celeia)
    "Spalt",                         # = Spalter
}
# Brewtek cultures were discontinued long ago and the source uses one placeholder attenuation for all.
SKIP_LABS = {"Brewtek"}


def parse_value(raw):
    if raw.startswith('"'):
        return re.sub(r"\s+", " ", raw[1:-1].replace('\\"', '"')).strip()
    if raw in ("true", "false"):
        return raw == "true"
    if raw == "nil":
        return None
    return float(raw)


def entries(path):
    text = open(path, encoding="utf-8").read()
    for match in ENTRY.finditer(text):
        fields = {k: parse_value(v) for k, v in FIELD.findall(match.group(2))}
        yield match.group(1), fields


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def norm(name):
    """Loose name key: 'Malt, Pale (2-Row)' and 'Pale 2-Row Malt' compare equal."""
    words = re.findall(r"[a-z0-9]+", name.lower())
    drop = {"malt", "the", "us", "uk", "de", "be", "american", "german", "english", "belgian"}
    return " ".join(sorted(w for w in words if w not in drop)) or name.lower()


def clean(d):
    return {k: v for k, v in d.items() if v not in (None, "")}


def load(name):
    with open(os.path.join(RESOURCES, name + ".json"), encoding="utf-8") as f:
        return json.load(f)


def save(name, data):
    with open(os.path.join(RESOURCES, name + ".json"), "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")


def merge_fermentables(src):
    existing = load("fermentables")
    existing = [e for e in existing if e.get("source") != SOURCE_TAG]
    seen = {norm(e["name"]) for e in existing}
    ids = {e["id"] for e in existing}
    file_types = {"grains": "grain", "adjuncts": "adjunct", "extracts": "extract",
                  "dry_extracts": "dryExtract", "sugars": "sugar"}
    added = []
    for file, kind in file_types.items():
        for key, f in entries(os.path.join(src, "fermentables", file + ".cljc")):
            name = f.get("name")
            potential = f.get("potential")
            if not name or not potential or name in SKIP_FERMENTABLES or norm(name) in seen:
                continue
            ppg = round((potential - 1) * 1000, 1)
            lower = name.lower()
            fermentability = None
            if "lactose" in lower or "milk sugar" in lower or "maltodextrin" in lower:
                fermentability = 0
            elif kind == "sugar":
                fermentability = 100
            entry_id = slug(name)
            if entry_id in ids:
                entry_id = "cbd-" + entry_id
            max_in_batch = f.get("max-in-batch")
            added.append(clean({
                "id": entry_id,
                "name": name,
                "type": kind,
                "colorLovibond": round(f.get("color", 0), 1),
                "potentialPPG": ppg,
                "fermentability": fermentability,
                "origin": f.get("origin"),
                "supplier": f.get("supplier"),
                "maxPercent": round(max_in_batch * 100) if max_in_batch else None,
                "notes": f.get("notes"),
                "source": SOURCE_TAG,
            }))
            seen.add(norm(name))
            ids.add(entry_id)
    save("fermentables", existing + sorted(added, key=lambda e: e["name"].lower()))
    return len(added)


def merge_hops(src):
    existing = [e for e in load("hops") if e.get("source") != SOURCE_TAG]
    seen = {norm(e["name"]) for e in existing}
    ids = {e["id"] for e in existing}
    purposes = {"Aroma": "aroma", "Bittering": "bittering", "Both": "dualPurpose"}
    added = []
    for file in ("aroma", "bittering", "both"):
        for key, f in entries(os.path.join(src, "hops", file + ".cljc")):
            name = f.get("name")
            if not name or f.get("alpha") is None or name in SKIP_HOPS or norm(name) in seen:
                continue
            entry_id = slug(name) if slug(name) not in ids else "cbd-" + slug(name)
            added.append(clean({
                "id": entry_id,
                "name": name,
                "origin": f.get("origin"),
                "alphaAcid": round(f["alpha"] * 100, 2),
                "betaAcid": round(f["beta"] * 100, 2) if f.get("beta") is not None else None,
                "purpose": purposes.get(f.get("type"), "dualPurpose"),
                "aroma": f.get("notes"),
                "substitutes": f.get("substitutes"),
                "source": SOURCE_TAG,
            }))
            seen.add(norm(name))
            ids.add(entry_id)
    save("hops", existing + sorted(added, key=lambda e: e["name"].lower()))
    return len(added)


def yeast_type(base_type, name, notes):
    text = f"{name} {notes}".lower()
    if any(w in text for w in ("brett", "lacto", "pedio", "sour")):
        return "wild"
    if "kveik" in text:
        return "kveik"
    if any(w in text for w in ("belgian", "saison", "abbey", "trappist", "farmhouse", "biere de garde")):
        return "belgian"
    return {"Ale": "ale", "Lager": "lager", "Wheat": "wheat", "Wine": "wine", "Champagne": "wine"}.get(base_type, "ale")


# The source uses 0.765 for every yeast, so it carries no real attenuation data. Use a typical range
# for the yeast type instead and say so in the notes.
PLACEHOLDER_ATTENUATION = 0.765
TYPICAL_ATTENUATION = {
    "ale": (72, 78), "lager": (73, 78), "wheat": (72, 77), "belgian": (75, 83),
    "kveik": (75, 82), "wild": (80, 90), "wine": (90, 98),
}


def merge_yeasts(src):
    existing = [e for e in load("yeasts") if e.get("source") != SOURCE_TAG]
    labs = {"DCL/Fermentis": "Fermentis"}

    def key_for(lab, product):
        return (lab or "").lower(), re.sub(r"[^a-z0-9]", "", (product or "").lower())

    seen = {key_for(e.get("laboratory"), e.get("productId")) for e in existing}
    ids = {e["id"] for e in existing}
    added = []
    for file in ("wyeast", "white_labs", "dcl_fermentis", "lallemand", "brewtek"):
        for key, f in entries(os.path.join(src, "yeasts", file + ".cljc")):
            name = f.get("name")
            lab = labs.get(f.get("laboratory"), f.get("laboratory"))
            product = f.get("product-id")
            attenuation = f.get("attenuation")
            if not name or attenuation is None or lab in SKIP_LABS or key_for(lab, product) in seen:
                continue
            # Names often repeat the product id ("1007 German Ale"); the app shows lab + id + name.
            if product and name.lower().startswith(product.lower()):
                name = name[len(product):].strip(" -")
            notes = f.get("notes") or ""
            if f.get("best-for"):
                notes = (notes + " Best for: " + f["best-for"].rstrip(". ") + ".").strip()
            entry_id = slug(f"{lab} {product or name}")
            if entry_id in ids:
                entry_id = "cbd-" + entry_id
            kind = yeast_type(f.get("type"), name, notes)
            if abs(attenuation - PLACEHOLDER_ATTENUATION) < 1e-9:
                low, high = TYPICAL_ATTENUATION[kind]
                notes = (notes + f" Attenuation not in source data; {low}–{high}% is typical for this type. Check the lab's spec.").strip()
            else:
                low = high = round(attenuation * 100, 1)
            added.append(clean({
                "id": entry_id,
                "name": name,
                "laboratory": lab,
                "productId": product,
                "type": kind,
                "form": "dry" if (f.get("form") or "").lower() == "dry" else "liquid",
                "attenuationMin": low,
                "attenuationMax": high,
                "tempMinC": round(f.get("min-temperature", 18), 1),
                "tempMaxC": round(f.get("max-temperature", 22), 1),
                "flocculation": f.get("flocculation"),
                "notes": notes,
                "source": SOURCE_TAG,
            }))
            seen.add(key_for(lab, product))
            ids.add(entry_id)
    save("yeasts", existing + sorted(added, key=lambda e: (e["laboratory"].lower(), e.get("productId") or "")))
    return len(added)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = os.path.join(sys.argv[1], "src", "common_beer_data")
    print("fermentables added:", merge_fermentables(src))
    print("hops added:", merge_hops(src))
    print("yeasts added:", merge_yeasts(src))
