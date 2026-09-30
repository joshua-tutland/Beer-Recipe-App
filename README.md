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
- **Brewing tools** (*More › Brewing Tools*):
  - Hydrometer temperature correction, with a remembered calibration temperature (60°F or 68°F)
  - Refractometer Brix → gravity for wort, plus calibration of your wort correction factor from
    a paired hydrometer reading
  - Refractometer during fermentation: corrects for alcohol from original and current Brix
    (Sean Terrill's cubic formula)
  - ABV calculator: standard and high-gravity ABV, apparent and real attenuation, calories
  - Brew log readings can be entered either way: hydrometer readings are temperature-corrected, and
    refractometer readings are alcohol-corrected against the batch's OG
- **Style check** against a subset of 58 BJCP 2021 styles, showing whether OG, FG, ABV, IBU
  and SRM are below, within or above each style's range.
- **Ingredient database** bundled with the app (66 fermentables, 58 hops, 44 yeasts,
  20 other ingredients such as water salts, finings and spices), plus your own custom ingredients.
- **Export & share** through the share sheet: PDF recipe sheet, Word document, or BeerXML.
  You can also save to Files, AirDrop, email or print.
- **BeerXML import** lets you bring in recipes from BeerSmith, Brewfather, Brewer's Friend,
  Brewtarget and others.
- **Metric or US units**, switchable at any time. Values are stored in metric internally.
- **Adaptive layout.** iPad gets a split view (recipe list, editor, and a live analysis panel beside the editor).
  iPhone gets a navigation stack with a summary strip and a full analysis page.

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
| Hydrometer | Reading × ρ(sample temp) / ρ(calibration temp), using the standard water-density polynomial |
| Refractometer | SG from Brix ÷ WCF (default 1.04); during fermentation, Terrill's cubic in original and current Brix |

## Open-source data and APIs for brewing ingredients

There is no single free, maintained, open REST API for brewing ingredients. For that
reason the app ships its own offline database, and it uses **BeerXML** so ingredients and
recipes can come from anywhere. Useful open sources for extending the data:

| Source | What it offers | Notes |
|---|---|---|
| [BeerXML 1.0](http://www.beerxml.com) | Open recipe and ingredient interchange format | Implemented here for import and export |
| [BeerJSON](https://github.com/beerjson/beerjson) | Newer JSON successor to BeerXML with schemas | A good next import/export target |
| [Wall-Brew-Co/common-beer-data](https://github.com/Wall-Brew-Co/common-beer-data) | Open data set of fermentables, hops, yeasts, waters and styles | Can be converted into this app's JSON resources |
| [Brewtarget](https://github.com/Brewtarget/brewtarget) / [Brewken](https://github.com/Brewken/brewken) | Open-source brewing apps with default ingredient databases | GPL licensed; check the license before bundling their data |
| [BJCP Style Guidelines](https://www.bjcp.org/beer-styles/) | Official style ranges | Source for `styles.json` |
| [Punk API](https://github.com/sammdec/punkapi) | BrewDog's 325 open "DIY Dog" recipes | MIT licensed data; the hosted API is deprecated, so use the dataset directly |
| [Microbrew.it API](https://github.com/Microbrewit/microbrew-it) | Fermentables, hops and yeast endpoints | Older open-source project; self-host |

To add or update ingredients, edit the JSON files in `BrewCore/Sources/BrewCore/Resources/`.
The fields match the Swift models in `Models/Ingredients.swift`. Users can also add their own
ingredients inside the app (Ingredient Library › +).

> Ingredient and style values are typical figures for guidance. Check your supplier's specs and
> the current BJCP guidelines for exact numbers.
