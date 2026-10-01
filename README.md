# Brew Recipes — iOS beer recipe builder

A SwiftUI app for iPhone and iPad to design beer recipes, see live brewing numbers
(OG, FG, ABV, IBU, color, water volumes…), store recipes on the device, and export them as
**PDF**, **Word (.docx)** or **BeerXML**.

## Features

- **Recipes stored locally.** Each recipe is saved as JSON in the app's `Documents/Recipes`
  folder, so recipes stay on the device and are included in device backups. Exports go to
  `Documents/Exports`, which shows up in the Files app (*On My iPhone › Brew Recipes*).
- **Live calculations** that update as you type:
  - Original & final gravity (SG and °Plato), pre-boil gravity
  - ABV (standard and high-gravity formulas), apparent & real attenuation
  - IBU with a choice of **Tinseth** or **Rager**, including first-wort, whirlpool/hop-stand
    (temperature-aware), mash and dry hops, plus a per-addition breakdown
  - Color in SRM and EBC (Morey), with a beer-colored swatch
  - BU:GU balance ratio and calories per 12 oz
  - Brew day water: strike volume and temperature, sparge, total water, pre- and post-boil volume
  - Yeast cells needed and suggested packs; priming sugar (corn or table sugar) for bottling
  - Lactose/maltodextrin are treated as unfermentable, simple sugars as fully fermentable
- **Recipe scaling.** Resize to any batch size (with ½×, 2× and 3× shortcuts) or a different
  efficiency, and preview the before and after numbers. Grain is adjusted for the efficiency
  change so OG stays the same, kettle hops are re-balanced to keep the same IBU, and dry hops
  scale with volume. Save the result as a new recipe or replace the original.
- **Brew day log.** Start a brew day from any recipe and record what you measured: mash
  temperature and pH, pre- and post-boil volume and gravity, OG, and the volume into the
  fermenter. Log fermentation gravity readings, which are charted over time, then record FG,
  packaging and a tasting rating and notes. The app shows your real ABV, attenuation,
  brewhouse and kettle efficiency and boil-off rate next to the recipe's predictions. One tap
  feeds the measured efficiency or boil-off rate back into the recipe (re-balancing grain to keep
  the target OG) or into your default equipment. Brew logs are included in PDF and Word exports.
- **Brew day checklist and timers.** Opened from a brew log entry, the app builds a step-by-step
  plan from the recipe: sanitize, weigh out, mill, heat the strike water (with volume and
  temperature), each mash step, sparge, collect the pre-boil volume, boil, hop stand, chill,
  transfer, measure OG, pitch, then dry hop days, FG and packaging. Mash, steep, boil and hop-stand
  steps have countdown timers, and the boil shows a schedule of hop and ingredient additions,
  grouped by time and highlighted when due. Timers store their end time, so they keep running when
  the app is closed, and local notifications announce each addition and the end of every timer.
  Checked-off steps are saved with the brew session, and the screen can stay awake while you
  brew.
- **Water chemistry.** Start from your tap water report (saved once as "My Water"), distilled/RO, or a
  historical city profile (Pilsen, Munich, Burton, Dublin and others), with optional RO dilution.
  Add brewing salts (gypsum, calcium chloride, Epsom, table salt, baking soda, chalk, magnesium
  chloride) and see the resulting calcium, magnesium, sodium, chloride, sulfate and bicarbonate,
  the sulfate:chloride balance and residual alkalinity. Pick a style target (Pale & Soft, Pale
  Hoppy, Hazy, Amber, Dark and others) and **Match Target Automatically** works out the salt
  amounts. The app estimates mash pH from the grist and water, including acidulated malt, and
  suggests the lactic or phosphoric acid (or baking soda for dark beers) needed to reach pH 5.4.
  The water plan appears on the brew-day checklist and in PDF and Word exports, and scales
  with the recipe.
- **Tilt hydrometer** (Brewing Tools › Tilt Hydrometer). Shows live gravity and temperature from any
  Tilt or Tilt Pro in Bluetooth range, with per-color calibration offsets. While a brew is fermenting,
  its brew log has a **Log Tilt Reading** button that adds the reading to the fermentation chart.
  Tilts broadcast iBeacons, which iOS only exposes to apps with location permission, so the app asks
  for "While Using" location access. Location itself is never stored or sent anywhere. Readings
  come in while the app is open.
- **Equipment profiles** (Settings › Equipment Profiles). Save your brewing systems and load them into
  any recipe; the recipe keeps its own batch size and boil time. Presets cover a three-vessel setup,
  brew in a bag, Grainfather G30, BrewZilla 35 L and Anvil Foundry. **Full-volume (BIAB / no-sparge)**
  mashing puts all the water in the mash, so the strike temperature, water volumes and brew-day
  checklist match how those systems are brewed.
- **Hop substitution.** The hop editor suggests substitutes from the database. Swapping a kettle hop
  re-weighs it for the new alpha acid so IBU stays the same; dry hops keep their weight.
- **Ingredient inventory** (*More › Inventory*). Track malts, hops (with lot alpha acid), yeast and
  other ingredients on hand, with optional best-before dates. Each recipe shows whether
  everything is in stock. It combines repeated ingredients (e.g. three Cascade additions) and
  lists what's short, with a shareable shopping list and a one-tap "mark as bought". From a brew
  log entry, **Deduct Ingredients from Inventory** removes what the brew used, oldest stock
  first, and records that it's done so it can't happen twice.
- **Brewing tools** (*More › Brewing Tools*):
  - Hydrometer temperature correction, with a remembered calibration temperature (60°F or 68°F)
  - Refractometer Brix → gravity for wort, plus calibration of your wort correction factor from
    a paired hydrometer reading
  - Refractometer during fermentation: corrects for alcohol from original and current Brix
    (Sean Terrill's cubic formula)
  - ABV calculator: standard and high-gravity ABV, apparent and real attenuation, calories
  - Yeast starter calculator: cells needed, liquid yeast viability by age, and up to three starter
    steps, with or without a stir plate (Braukaiser and Chris White growth models)
  - Keg carbonation: regulator pressure for a target CO₂ level, and a balanced serving line length
  - Brew log readings can be entered either way: hydrometer readings are temperature-corrected, and
    refractometer readings are alcohol-corrected against the batch's OG
- **Style check** against a subset of 58 BJCP 2021 styles, showing whether OG, FG, ABV, IBU
  and SRM are below, within or above each style's range.
- **Ingredient database** bundled with the app: 107 fermentables, 79 hops, 168 yeasts and 20 other
  ingredients (water salts, finings, spices), plus your own custom ingredients. Curated entries are
  extended with the open [common-beer-data](https://github.com/Wall-Brew-Co/common-beer-data) set
  (MIT; see `THIRD_PARTY_NOTICES.md`). That set has no real yeast attenuation figures, so those
  yeasts show a typical range for their type, flagged in their notes.
- **Export & share** through the share sheet: PDF recipe sheet, Word document, or BeerXML.
  You can also save to Files, AirDrop, email or print.
- **BeerXML and BeerJSON import/export** for exchanging recipes with BeerSmith, Brewfather, Brewer's Friend,
  Brewtarget and others. The format is detected automatically on import. BeerJSON exports are checked
  in CI against the [official schema](https://github.com/beerjson/beerjson); hop stands are written as
  end-of-boil additions with a steep time, and first-wort hops as full-boil additions.
- **Metric or US units**, switchable at any time. Values are stored in metric internally.
- **Adaptive layout.** iPad gets a split view (recipe list, editor, and a live analysis panel beside the editor).
  iPhone gets a navigation stack with a summary strip and a full analysis page.

## iCloud sync (optional)

Settings › **Sync with iCloud** keeps recipes, brew logs, water plans, inventory and custom
ingredients the same across your iPhone and iPad. Each recipe is a separate file in the app's
iCloud Drive container, so iOS syncs them individually. If two devices change the same recipe
while offline, the most recently edited copy wins. Turning sync on merges the device's existing
recipes into iCloud; turning it off copies the latest iCloud versions back to the device.

The iCloud capability is **not** enabled in the project by default, because Xcode can't sign apps
that use iCloud with a free (personal team) Apple account. To use sync you need a paid Apple
Developer account. Then:

1. In Xcode, select the **BeerRecipe** target › **Signing & Capabilities** › **+ Capability** › **iCloud**.
2. Tick **iCloud Documents**, then under Containers click **+** and add one, e.g. `iCloud.<your bundle id>`.
3. Run on a device (or simulator) signed in to iCloud with iCloud Drive turned on, and switch on
   **Sync with iCloud** in the app's Settings. Do the same on your other device.

Without the capability, or when the device isn't signed in to iCloud, the toggle explains why
sync isn't available and the app keeps working with local storage.

## Project layout

```
BeerRecipe.xcodeproj      Xcode project (iOS 17+, iPhone + iPad)
BeerRecipe/               SwiftUI app
  App/                    App entry point
  Store/                  RecipeStore – observable state + autosave
  Views/                  List, editor, pickers, stats panel, settings, library
  Export/                 PDF renderer and export file writer
BrewCore/                 Swift package with no UI dependencies (unit-tested)
  Sources/BrewCore/
    Models/               Recipe, fermentables, hops, yeast, misc, mash, equipment
    Calculations/         BrewMath formulas, BrewCalculator, unit conversions
    Catalog/              Ingredient & BJCP style catalogs
    Export/               RecipeReport, DocxWriter (+ zip writer), BeerXML import/export
    Persistence/          File-based recipe repository, sample recipes
    Resources/            fermentables/hops/yeasts/miscs/styles JSON data
  Tests/BrewCoreTests/    XCTest suite
```

## Building

1. Open `BeerRecipe.xcodeproj` in **Xcode 16 or later**.
2. Select the *BeerRecipe* target, then under **Signing & Capabilities** choose your team and
   change the bundle identifier (`com.example.BrewRecipes`) to one you own.
3. Pick an iPhone or iPad simulator (or a device) and press **Run**.

Run the calculation and export tests with:

```sh
cd BrewCore && swift test
```

or run them from Xcode by opening `BrewCore/Package.swift`. On each push, GitHub Actions runs
the package tests, checks the generated .docx with an independent reader (`python-docx`), and
builds the app for the iOS Simulator.

## Formulas

| Value | Method |
|---|---|
| OG | Σ(lb × PPG × efficiency) / gal. Extracts and sugars use 100% yield |
| FG | Unfermented points: yeast attenuation for malt sugars; per-ingredient fermentability for sugars, lactose and maltodextrin |
| ABV | (OG − FG) × 131.25; the alternate formula is 76.08 (OG − FG)/(1.775 − OG) × FG/0.794 |
| IBU | Tinseth or Rager at average boil gravity over post-boil volume; +10% for pellets; +10% for first-wort hops; whirlpool time scaled by the Malowicki isomerization rate at the stand temperature |
| Color | Morey: SRM = 1.4922 × MCU^0.6859; EBC = SRM × 1.97 |
| Strike temp | T = (0.41 / R)(T_mash − T_grain) + T_mash, R in L/kg |
| Priming | Residual CO₂ from beer temperature; dextrose g = 15.195 × gal × (vols − residual) |
| Calories | ASBC-style formula from OG and FG, per 12 oz |
| Water | Salt contributions from molecular weights; residual alkalinity (Kolbach) = HCO₃ − Ca/3.5 − Mg/7 in mEq/L |
| Mash pH | Linear malt-buffering model after Kai Troester: Σ m·BC·pHᵢ plus water alkalinity minus acid, divided by Σ m·BC. Base, crystal, roast, adjunct and acid malt each have their own distilled-water pH and buffer capacity |
| Hydrometer | Reading × ρ(sample temp) / ρ(calibration temp), using the standard water-density polynomial |
| Refractometer | SG from Brix ÷ WCF (default 1.04); during fermentation, Terrill's cubic in original and current Brix |

## Open-source data and APIs for brewing ingredients

There is no single free, maintained, open REST API for brewing ingredients. For that
reason the app ships its own offline database, and it uses **BeerXML** so ingredients and
recipes can come from anywhere. Useful open sources for extending the data:

| Source | What it offers | Notes |
|---|---|---|
| [BeerXML 1.0](http://www.beerxml.com) | Open recipe and ingredient interchange format | Implemented here for import and export |
| [BeerJSON](https://github.com/beerjson/beerjson) | Newer JSON successor to BeerXML with schemas | Implemented here for import and export |
| [Wall-Brew-Co/common-beer-data](https://github.com/Wall-Brew-Co/common-beer-data) | Open data set of fermentables, hops, yeasts and styles | **Merged into the bundled data** with `tools/import_common_beer_data.py` (MIT) |
| [Brewtarget](https://github.com/Brewtarget/brewtarget) / [Brewken](https://github.com/Brewken/brewken) | Open-source brewing apps with default ingredient databases | GPL licensed; check the license before bundling their data |
| [BJCP Style Guidelines](https://www.bjcp.org/beer-styles/) | Official style ranges | Source for `styles.json` |
| [Punk API](https://github.com/sammdec/punkapi) | BrewDog's 325 open "DIY Dog" recipes | MIT licensed data; the hosted API is deprecated, so use the dataset directly |
| [Microbrew.it API](https://github.com/Microbrewit/microbrew-it) | Fermentables, hops and yeast endpoints | Older open-source project; self-host |

To add or update ingredients, edit the JSON files in `BrewCore/Sources/BrewCore/Resources/`.
The fields match the Swift models in `Models/Ingredients.swift`. Users can also add their own
ingredients inside the app (Ingredient Library › +).

> Ingredient and style values are typical figures for guidance. Check your supplier's specs and
> the current BJCP guidelines for exact numbers.
