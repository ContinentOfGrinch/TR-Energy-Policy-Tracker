# SKDM_TURKIYE.md — Project Instructions

Persistent context for Claude Code working on this repository. Read fully before writing
any code. If a request conflicts with anything here, stop and ask rather than improvising.

This file is loaded automatically via a one-line `CLAUDE.md` pointer in the repository root.
Do not delete that pointer — without it these instructions are not loaded into new sessions.

Companion documents:
- `ROADMAP.md` — the authoritative record of scope decisions and deferred features
- `METHODOLOGY.md` — written by the author; do not generate its prose

---

## 1. What this project is

An open-source **R Shiny** dashboard that maps individual carbon-intensive industrial
installations in Türkiye and estimates their exposure to the **EU Carbon Border Adjustment
Mechanism** (CBAM / Turkish: *Sınırda Karbon Düzenleme Mekanizması*, SKDM) under
user-defined carbon price scenarios.

**Repository name:** `skdm-turkiye`

**Author:** an undergraduate economics researcher. This is a portfolio project intended to
be released with a Zenodo DOI and potentially submitted to the Journal of Open Source
Software (JOSS). It must therefore be reproducible, documented, and honest about its limits.

**Research positioning:** existing tools analyse CBAM exposure for Türkiye only at national
or sectoral resolution. Facility-level, spatially explicit, open-source treatment appears to
be unoccupied. That combination *is* the contribution — not the calculation formula, which
is commodity.

---

## 2. Audience and language

Target users are Turkish policymakers, researchers, journalists and regional development
agencies.

| Element | Language |
|---|---|
| Shiny UI labels, titles, buttons, tooltips, legends | **Turkish** |
| JSON content in `policies/` intended for display | **Turkish** |
| Code, variable names, function names, file names | **English** |
| Code comments | **English** |
| README, METHODOLOGY, ROADMAP | **English** (with a Turkish summary block in README) |

Use proper Turkish characters (ç, ğ, ı, İ, ö, ş, ü). Ensure UTF-8 encoding everywhere.

**Windows encoding rule.** Development happens on Windows, where the default encoding is
not UTF-8. All files must be written as **UTF-8 without BOM**. In PowerShell never rely on
`Set-Content` defaults — pass `-Encoding utf8` explicitly. In R, read with an explicit
locale (`readr::locale(encoding = "UTF-8")`) and set `options(encoding = "UTF-8")` in
`global.R`. `ui.R` must include `tags$meta(charset = "UTF-8")`. Verify Turkish characters
survive after writing any file containing them.

---

## 3. Directory structure — do not add top-level folders

```
app/
  global.R       libraries, data loading, constants shared by ui and server
  ui.R           interface definition (Turkish labels)
  server.R       reactive logic
  www/           CSS, static assets
data/
  raw/           downloaded source files — NOT tracked by git
  processed/     facilities.rds, facility_panel.rds, SOURCES.md
policies/
  cbam_phase_in.json
  carbon_price_scenarios.json
  tr_ets.json
scripts/
  00_coverage_audit.R
  01_fetch_climate_trace.R
  02_build_facilities.R
  03_build_panel.R
```

Root files: `README.md`, `SKDM_TURKIYE.md`, `CLAUDE.md` (pointer only), `METHODOLOGY.md`,
`ROADMAP.md`, `CITATION.cff`, `LICENSE`, `renv.lock`, `.gitignore`.

**Hard rules:**
- Never create new top-level directories without asking.
- Never merge `ui.R` and `server.R` into `app.R`. `global.R` is permitted and is not a merge.
- Scripts in `scripts/` are numbered and run in order. Preserve the numbering convention.

**Known outstanding item:** JOSS requires automated tests, which implies a `tests/`
directory. It has not been created — adding it requires the author's explicit approval
under the rule above. Tracked in `ROADMAP.md` under the release path.

---

## 4. Coding standards

- **Tidyverse first.** Use `dplyr`, `tidyr`, `purrr`, and the native pipe `|>` for data
  manipulation. Avoid base-R subsetting loops where a tidyverse verb is clearer.
- **Comment extensively in English.** Every reactive block and every pipeline step should
  explain *why*, not just *what*. This project's author must be able to defend every line.
- **Spatial:** `sf`. All geometry must be transformed to **EPSG:4326** before reaching
  `leaflet`. Turkish national CRS (e.g. EPSG:5254) causes silent misplacement — always
  `st_transform(4326)` explicitly.
- **Basemap:** CartoDB.Positron (light) or CartoDB.DarkMatter (dark). Clean, professional,
  makes facility points stand out.
- **Framework:** `shinydashboard`. Keep the layout responsive and cognitive load low.
- **Performance:** use `leafletOptions(preferCanvas = TRUE)`; update markers with
  `leafletProxy()` rather than re-rendering the map; `debounce()` the time slider; do heavy
  computation once in a `reactive()` and let observers consume it.
- **No browser storage APIs** (localStorage/sessionStorage). Use reactive values.
- **Environment:** `renv` for dependency pinning. Consider Docker if `sf`/GEOS deployment
  proves fragile.

**Local environment (confirmed):** R 4.5.1 and RStudio on Windows 11. Run scripts with
`Rscript`, not `R` — in PowerShell, `R` collides with the `Invoke-History` alias.

---

## 5. Scope of v1 — hold this line

**In scope:**

| Dimension | Decision |
|---|---|
| Sectors | Iron & steel, cement, aluminium (fertilisers dropped on evidence — see below) |
| Geography | Türkiye |
| Unit of analysis | Individual facility |
| Time | Historical panel only; `t₀` determined **empirically** by `00_coverage_audit.R`, not guessed |
| Policy | EU CBAM liability under user-set carbon price scenarios |
| Aggregation | Facility → province → national |
| Key UI control | **Time slider** — the most important control element, place it prominently |

**Scope decisions taken — see `ROADMAP.md` for full reasoning:**

1. **Three of the six CBAM goods categories.** Two distinct kinds of exclusion, and the
   distinction matters for how each is defended:
   - *By choice:* electricity and hydrogen. Türkiye's electricity exports to the EU are
     marginal and the indirect-emissions channel is deferred; hydrogen volumes are negligible.
   - *On evidence:* fertilisers. Climate TRACE has no fertiliser-**production** subsector
     (`synthetic-fertilizer-application` is agricultural N₂O from soils — a different
     emission source entirely, and must never be substituted), and GEM publishes no
     fertiliser tracker. The `chemicals` subsector returns 3 Turkish assets but is broader
     than fertilisers and must not be used as a proxy.

   Both restrictions must be stated explicitly in README and METHODOLOGY. The fertiliser
   exclusion is reported as an **empirical finding** of the coverage audit, not as an
   oversight — "not addressable at facility resolution with open data" is itself a result.
2. **EU export share is modelled, not assumed to be 100%.** CBAM liability arises only on
   goods actually exported to the EU. A sector-level `eu_export_share` derived from
   HS-code export statistics is applied within each sector and exposed as a user-adjustable
   UI control. Facility-level export shares are not public and must not be fabricated.
3. **Climate TRACE is the primary source; GEM is cross-validation only.** Reconnaissance
   showed Climate TRACE already carries the fields originally expected from GEM —
   `AssetType` (e.g. BF/BOF), `Capacity`, and `Activity` (production in tonnes of product).
   GEM is therefore not merged into the panel; it is used to independently check capacity
   and commissioning year, and the **disagreement rate is reported in METHODOLOGY** rather
   than silently reconciled. This keeps a single licence and attribution chain in the panel
   and avoids entity-resolution error entering the numbers.
4. **Estimated exposure is not a tax bill.** CBAM certificates are surrendered by the EU
   importer, not the Turkish producer. UI wording must use "maruziyet" and "maliyet
   baskısı" — never "vergi" or "ödeyeceği tutar".
5. **Forward years are retained but never rendered as observations.** Climate TRACE carries
   estimates beyond the last observed year (currently 2025–2026). These enter the panel with
   `value_type = projected` and must be drawn with a dashed line, desaturation and a visible
   badge. Showing 2026 matters — it is the year CBAM's definitive regime applies — but it
   must never be mistaken for a realised figure.

**Explicitly deferred to `ROADMAP.md` — do not build these in v1:**

- Electricity generation assets (thermal and renewable) and the indirect-emissions channel
- TR-ETS liability and the domestic-carbon-price offset engine
- Forward projection to 2035
- Endogenous grid emission factor
- Monte Carlo / uncertainty quantification
- EPİAŞ Transparency Platform integration (requires authentication; unsuitable for a public
  app without a scheduled ETL)
- Country-agnostic architecture

If asked to build a deferred feature, flag the scope decision before proceeding.

---

## 6. Data model — fix this before writing app code

**`data/processed/facilities.rds`** — time-invariant facility attributes, one row per facility:

```
facility_id, facility_name_tr, operator_name, sector, technology,
liability_class, lat, lon, province_code, nuts2_code,
country_iso3, regime_id, source, source_id, geocode_quality
```

**`data/processed/facility_panel.rds`** — long format, one row per facility × year:

```
facility_id, year, status, capacity_mw_or_capacity_t, production_activity,
co2_direct_t, co2_indirect_t, emission_intensity,
eu_export_share,
value_type, vintage, source
```

Notes:
- `liability_class` ∈ {`direct`, `indirect_driver`, `neutral`} — kept even though v1 is all
  `direct`, because v2 adds power assets.
- `value_type` ∈ {`observed`, `legislated`, `scenario`, `projected`, `assumption`}. These are
  epistemically different and must be encoded differently in the UI (solid vs dashed lines,
  desaturation, a "projection" badge). Never render a projection identically to an
  observation.
- `eu_export_share` ∈ [0, 1] — the share of a facility's output assumed to enter the EU.
  Sourced at **sector level** from HS-code export statistics and applied uniformly within
  the sector; it always carries `value_type = assumption` and must be visibly flagged as
  such. It is user-adjustable in the UI. The uniform-within-sector assumption is a known
  limitation and belongs in METHODOLOGY.
- `country_iso3` and `regime_id` are included **from day one** even though v1 is Türkiye
  only. Adding them later would break every downstream layer. Cost now: zero.
- Anything that changes over time (status, capacity, production) belongs in the **panel**,
  not the facilities table. Putting them in `facilities` breaks the panel structure.
- `status` uses Global Energy Monitor conventions: `planned`, `construction`, `operating`,
  `retired`, `cancelled`. Facilities entering and exiting over time is a **feature** — the
  time slider should animate fleet turnover.

---

## 7. Policy parameters — never hardcode

All regulatory parameters live in `policies/*.json` and are read at runtime. This is not a
style preference: TR-ETS secondary legislation was still being finalised through mid-2026,
the EU withdrew and is reissuing certain Turkish default values, and certificate prices
update quarterly. If maintenance requires editing R source, this project dies within two
years.

**`cbam_phase_in.json`** — year → phase-in factor. CBAM's financial obligation phases in
alongside the EU ETS free-allocation phase-out, reaching full application when free
allocation for CBAM sectors hits zero in **2034**.

**`carbon_price_scenarios.json`** — scenario name → year → EUR/tCO₂e. Provide at minimum:
- `low`: €75/tCO₂e (EBRD/Directorate of Climate Change study assumption)
- `high`: €150/tCO₂e (same study's upper scenario)
- `observed`: anchored on the actual first quarterly CBAM certificate price, set by the
  Commission at **€75.36/tCO₂e for Q1 2026**
- `custom`: user-defined via UI

**`tr_ets.json`** — scope, thresholds and allocation rules for the Turkish ETS. Populate but
do not wire into calculations in v1. Reference facts: pilot period **2026–2027**, threshold
**50,000 tCO₂e/year**, first compliance period **2028–2035**, 100% free allocation during
the pilot under a benchmark method, administered by the Directorate of Climate Change with
the market operated by EXIST/EPİAŞ.

**`grid_emission_factor.json`** — placeholder for v2.

Every parameter file must carry a `source_url` and a retrieval date. A regulatory number
without a citation is not usable in this project.

---

## 8. Non-negotiable correctness rules

1. **Never fabricate an emission factor, default value, coordinate, or benchmark.** If a
   value is unavailable, propagate `NA` and surface it in the UI with an explanation.
2. **Turkish cement/clinker default values are unstable.** The Commission withdrew the
   default value and benchmark in late 2025 pending reissue at amended levels, and as of
   early 2026 work with Turkish authorities to close data gaps was ongoing. Handle this
   explicitly with a flag — do **not** substitute a global average silently.
3. **Emissions are modelled estimates, not verified data.** Facility-level verified GHG
   reports exist in Türkiye but are not publicly released. Every emissions figure in the UI
   must be visibly marked as an estimate.
4. **Build an audit trail.** Every number displayed must be traceable to its inputs and
   formula through an in-app panel. Calculation functions already produce intermediate
   values — retain them rather than discarding them. This is a core differentiator against
   closed commercial tools.
5. **This is an accounting framework, not an equilibrium model.** No price elasticity, no
   substitution, no trade diversion. The claim is: "given this output and emission
   intensity, liability under scenario X is Y."
6. **Do not commit `data/raw/`.** Reproducibility comes from the fetch scripts, not from
   committed binaries. Respect upstream licences — Climate TRACE is CC BY 4.0 and attribution
   is a legal requirement, surfaced in a visible "Veri Kaynakları" tab.

---

## 9. Working method

- **One file at a time.** Do not generate the whole codebase in a single pass. If asked for
  `ui.R`, output only `ui.R`.
- **No destructive rewrites.** If a file exists, explain what is changing before replacing
  it. Prefer targeted edits and clear diffs.
- **Explain before fixing.** When given an R error, diagnose the root cause first, then
  provide the corrected code.
- **The author writes the analytical core.** The CBAM cost calculation, phase-in application
  and any offset logic should be authored or closely reviewed by the human, not generated
  wholesale. Offer review rather than replacement for these functions.
- **The author writes all prose in `METHODOLOGY.md`.** Structure and critique are welcome;
  the sentences must be theirs. The README discloses AI coding assistance while attributing
  methodological decisions and documentation text to the author — keep that statement true.

---

## 10. Licensing and release

- Code: **MIT**
- Documentation and derived data: **CC BY 4.0**
- Upstream data retains its original licence; maintain the attribution chain in
  `data/processed/SOURCES.md`.
- Release path: working v0.1 → git tag → Zenodo DOI → preprint → JOSS submission.
- JOSS will require: working installation instructions, tests, documentation, example data,
  and a contribution guide. Build toward these from the start rather than retrofitting.

**Author:** Selahattin İlhan · selahattinilkhan@gmail.com · ORCID: 0009-0007-4824-752X

---

## 11. Immediate next tasks

Completed:
- [x] `.gitignore` (R/renv defaults plus `data/raw/`)
- [x] `ROADMAP.md`
- [x] `LICENSE` (MIT)
- [x] Git repository initialised on branch `main`

Next, in order:
1. `scripts/00_coverage_audit.R` — produce a sector × year × variable data-availability
   matrix from Climate TRACE and report the empirical intersection that determines `t₀`.
   Commit the resulting matrix to `data/processed/` as evidence, not merely to the console.
2. `policies/*.json` skeletons
3. `scripts/01_fetch_climate_trace.R`
4. `README.md` and `CITATION.cff`
5. Only then: `app/global.R`, `app/ui.R`, `app/server.R`

### Climate TRACE API — verified endpoints

Reconnaissance performed 2026-08-19. Public, no authentication, no API key.

| Purpose | Endpoint |
|---|---|
| Subsector vocabulary | `GET /v6/definitions/subsectors` |
| Facility list (latest year only) | `GET /v6/assets?countries=TUR&subsectors=<s>&limit=500` |
| **Per-facility time series** | `GET /v6/assets/{id}` → `EmissionsDetails[]`, each with a `Year` |

Base URL `https://api.climatetrace.org`. Relevant subsectors: `iron-and-steel`, `cement`,
`aluminum` (US spelling). Turkish asset counts at time of audit: cement 58, iron-and-steel
27, aluminum 3 — 88 facilities, so per-facility calls are cheap.

Fields that map directly onto the data model: `Name`, `Id`, `NativeId`, `AssetType`
(→ `technology`), `Owners[].CompanyName` (→ `operator_name`), `Centroid.Geometry` with
`SRID 4326` (→ `lat`/`lon`, already in the target CRS), and per year `Activity`
(→ `production_activity`), `Capacity`, `CapacityFactor`, `EmissionsFactor`
(→ `emission_intensity`), `EmissionsQuantity` (→ `co2_direct_t`).

`Confidence` carries a per-year, per-variable rating (`high`/`medium`/`low`/`very low`).
**Retain it** — it feeds both the `value_type` assignment and the §8.4 audit trail, and
buying that information back later is impossible.

**Note on `app/ui.R`:** a file of that name exists in the repository but was written
against a superseded project brief (an energy-policy tracker with English labels). It does
not reflect current scope and must be rewritten, not extended, when step 5 is reached.
