# STATUS.md — where this project stands

**Read this first when resuming work.** `KARBON_ATLASI.md` says what the project *is*;
this file says where it *got to*, what runs, what is blocked, and which traps have already
been paid for.

Last updated: **2026-09-01** · 32 commits · **~58% complete** · 133 assertions passing

> The figure moved 53% → 35% → 58%. The drop was the scope merge on 2026-08-19 growing the
> denominator, not work being lost; the recovery is the energy half being built. Both
> populations are now on the map. What remains is disproportionately the analytical core,
> which §9 reserves for the author.

**Published:** <https://github.com/ContinentOfGrinch/TR-Energy-Policy-Tracker>
(rename to `karbon-atlasi-turkiye` still outstanding)

> Keep this file current. When a milestone lands or a decision changes, update the
> relevant section here in the same commit. A stale STATUS.md is worse than none, because
> it will be trusted.

---

## 1. What this is, in one paragraph

`karbon-atlasi-turkiye` — **Türkiye Karbon Atlası** — maps Türkiye's carbon-intensive
infrastructure at facility level and links two populations that are normally studied apart:

- **88 industrial installations** (iron & steel, cement, aluminium) and their EU CBAM /
  SKDM exposure under user-defined carbon price scenarios;
- **212 energy assets** (157 power stations, 38 coal mines, 17 oil & gas facilities) which
  carry their own emissions *and* set the grid carbon intensity that produces the
  industrial installations' indirect emissions. The 17 sit at 11 locations: each of the
  six fields is listed twice, under production and under transport.

R Shiny, `shinydashboard`, `leaflet`, `sf`. Author: Selahattin İlhan, ORCID
0009-0007-4824-752X. Destination: Zenodo DOI, then JOSS.

**The bridge is the contribution.** Climate TRACE already publishes `electricity_use` and
`grid_emissions_intensity` for every industrial facility; the energy layer explains where
that intensity comes from. Neither half alone is novel — CBAM exposure is studied
nationally, energy dashboards ignore trade exposure. The combination, at facility
resolution, with an audit trail, is what is unoccupied.

---

## 2. Current state

### What works end to end

- Acquisition, provenance and integrity checks for all raw sources — Climate TRACE (both
  gas packages), GEM, Ember, Natural Earth, Eurostat Comext
- Coverage audit that establishes `t₀` from evidence rather than assumption, for both
  populations
- `facilities.rds` — **300 records at 290 locations**, both populations, with province and
  İBBS-2 assignment verified against 18 known locations
- `fleet_renewables.rds` — 3,136 operating renewable plants, 58.8 GW, deliberately kept
  out of the emissions register and drawn as an optional context layer
- Commissioning years from GEM: **78.3% of the register**, earliest 1911
- Three independent grid carbon intensity estimates, assembled and reconciled
- Policy parameters as JSON — 5 files, all carrying `source_url` and a retrieval date, each
  validated against a schema in `policies/_schema/`
- Tiered pipeline gates (`_validate.R`) plus 133 testthat assertions
- Shiny app: both populations on one Türkiye-bounded map, sector/province/captive filters,
  grid-intensity tab, geocode-quality and commissioning panels, sources tab

**Both halves are now built.** What is missing is no longer a data layer; it is the panel
and the arithmetic on top of it.

### What does not exist yet

| Missing | Blocked on |
|---|---|
| `facility_panel.rds` | Author decisions **B1** (direct/indirect split) and **B2** (annual aggregation) |
| CBAM liability figure | Author decisions **B7** (`eu_export_share`) and **B9** (the calculation) |
| Grid factor **selection** | Author decision — three estimates exist, `selection.chosen` is deliberately `null` |
| Time slider, cost layer, audit-trail panel | the panel above |
| The 2000–2026 fleet timeline | the panel; commissioning years are ingested and joined |
| `METHODOLOGY.md` | author writes the prose (§9) |

### Progress by component

| Component | Weight | Done |
|---|---|---|
| Scaffolding, licence, instructions, roadmap | 4 | ✅ |
| renv / reproducible environment | 3 | ✅ |
| Coverage audit + t₀ (industrial) | 5 | ✅ |
| Fetch + provenance chain (industrial) | 5 | ✅ |
| `facilities.rds` (industrial, 88) | 5 | ✅ |
| `policies/*.json` + JSON schemas | 4 | ✅ |
| README + CITATION.cff | 2 | ✅ |
| App shell + map | 5 | ✅ |
| `tests/` + pipeline validation gates | 3 | ✅ |
| Energy coverage audit + fetch (5 subsectors) | 6 | ✅ |
| Energy facilities (212, merged to 300) | 6 | ✅ |
| GEM commissioning years → 2000 timeline | 5 | ◐ 50% — ingested and joined at 78%, but the timeline is not drawn |
| Grid emission factor | 6 | ◐ 60% — three estimates assembled, selection pending |
| `eu_export_share` | 4 | ◐ 50% — fetch works, definition pending |
| App phase 2 (slider, cost, energy layer, audit trail) | 8 | ◐ 30% — energy layer and grid tab done; no slider, cost or audit trail |
| Energy emissions panel | 6 | ❌ |
| `facility_panel.rds` (industrial) | 8 | ❌ |
| CBAM calculation core | 8 | ❌ |
| `METHODOLOGY.md` | 5 | ❌ |
| Zenodo / JOSS packaging | 2 | ❌ |

**Of the remaining ~42 points, about 25 are the author's own work** under §9 — the
direct/indirect decomposition, the annual aggregation rule, the `eu_export_share`
definition, the grid-factor selection, the CBAM calculation, and METHODOLOGY.

The other ~17 are buildable without waiting: the energy emissions panel, the rest of the
app once the panel exists, the fleet timeline, and release packaging.

**The remaining work is now more author-blocked than builder-blocked, which was not true a
week ago.** Every source is fetched, every register is built, every gate is in place. What
is missing is mostly decisions about what the numbers mean.

---

## 3. How to run everything

Requires R 4.5.1. On Windows use `Rscript`, never `R` — see the traps section.

```bash
# environment
Rscript -e "renv::restore()"

# pipeline, in order
Rscript scripts/00_coverage_audit.R       # optional; regenerates the t0 evidence
Rscript scripts/01_fetch_climate_trace.R  # all raw acquisition + SOURCES.md
Rscript scripts/01b_fetch_eu_trade.R      # Eurostat Comext trade quantities
Rscript scripts/01c_ingest_gem.R          # commissioning years + captive flags
Rscript scripts/01d_fetch_ember.R         # national generation -> grid intensity
Rscript scripts/02_build_facilities.R     # -> facilities.rds + fleet_renewables.rds
# scripts/03_build_panel.R                # DOES NOT EXIST YET (blocked on B1/B2)

# tests — run these SEPARATELY from any commit
Rscript tests/testthat.R

# app
Rscript -e "shiny::runApp('app', port=3838, launch.browser=TRUE)"
```

**`01c` needs a manual download.** GEM distributes its trackers behind a form, not a URL.
Put the Global Integrated Power Tracker workbook (and optionally the Global Coal Mine
Tracker) unrenamed into `data/raw/gem/`. The script stops with instructions if the file is
absent and never proceeds with an empty table. Use `--profile-only` to inspect a workbook's
sheets and columns before trusting a parser against it.

`data/raw/` is gitignored. Reproducibility comes from re-running `01`, not from committed
binaries. First run downloads ~60 MB and takes a few minutes; afterwards everything is
cached and re-runs take seconds.

---

## 4. Established facts — do not re-derive these

| Fact | Value | Evidence |
|---|---|---|
| Energy assets built | electricity-generation **157**, coal-mining **38**, oil-and-gas production **6** / refining **5** / transport **6** = **212** | `facilities.rds` |
| Total population | **300** records at **290** locations = 88 industrial + 212 energy | same |
| `t₀` | **2021** | `data/processed/coverage_audit_summary.md` |
| Last complete year | 2025 | same |
| 2026 | partial, **5 of 12 months** | same |
| Industrial facilities | **88** — cement 58, iron & steel 27, aluminium 3 | `facilities.rds` |
| Gas basis | industrial **CO₂** (88), energy **CO₂e(100yr)** (212) — **never summed** | same |
| Commissioning years | **78.3%** overall; industrial 87.5%, energy 74.5%; oil & gas **0%**; earliest **1911** | measured 2026-09-01 |
| Captive plants | **27** flagged in the register; GEM declares 34 operating units / 4.46 GW fleet-wide | `is_captive` |
| Renewable fleet (context only) | **3,136** operating plants, **58.8 GW** | `fleet_renewables.rds` |
| Grid intensity 2024 | naive fleet **748**, Ember **471**, Climate TRACE reported **477** gCO₂/kWh | `grid_intensity.csv` |
| Source release | Climate TRACE **v5_9_0** | `SOURCES.md` |
| CBAM phase-in | 2026 **2.5%** → 2034 **100%** | `policies/cbam_phase_in.json` |
| CBAM certificate price | Q1 2026 **€75.36**, Q2 2026 **€75.28** | verified against the Commission price page |
| CBAM de minimis | 50 t per importer per year | recorded, deliberately **not applied** |
| TR-ETS | Law 7552, pilot 2026–27, 50,000 tCO₂e threshold, 100% free allocation | `policies/tr_ets.json` |
| Geocode quality | **220** within province, **64** boundary-proximate, **12** snapped to nearest, **4** offshore | `facilities_geocode_report.csv` |
| Verification | **133 assertions**, 0 failures | `Rscript tests/testthat.R` |

---

## 5. Decisions already taken

Full reasoning in `ROADMAP.md`. Compressed here so a resuming session does not reopen them.

1. **Three of six CBAM goods categories.** Electricity and hydrogen excluded *by choice*
   (marginal Turkish volumes). **Fertilisers excluded on evidence** — Climate TRACE has no
   fertiliser-*production* subsector; `synthetic-fertilizer-application` is agricultural
   N₂O and is a different emission source entirely. Never substitute it.
2. **Climate TRACE is the sole panel source.** GEM was demoted to cross-validation once
   reconnaissance showed Climate TRACE already carries `AssetType`, `Capacity` and
   `Activity`. The merge would have bought entity-resolution error for fields already
   present.
3. **The REST API cannot build a panel.** `/v6/assets/{id}` returns one year and ignores
   every year parameter. The bulk country package is the only viable source.
4. **Natural Earth, not geoBoundaries, for boundaries.** geoBoundaries' Turkey ADM1 layer
   is CC BY-SA 2.0; ShareAlike would propagate to this project's CC BY 4.0 derived data
   once polygons were redistributed for the province choropleths the scope requires.
5. **EU export share is modelled at sector level**, user-adjustable, `value_type =
   assumption`. Never assumed to be 100%.
6. **Forward years kept but never rendered as observations** — `value_type = projected`,
   dashed and badged.
7. **2026 enters partial, never annualised by scaling.** Cement output is seasonal, so a
   12/5 multiplier biases systematically rather than randomly.
8. **Exposure is not a tax bill.** The importer surrenders certificates. UI wording:
   *maruziyet*, *maliyet baskısı* — never *vergi* or *ödeyeceği tutar*.
9. **The energy and CBAM scopes were merged (2026-08-19).** Energy assets are not a second
   project sharing a map; they are `indirect_driver`s whose fleet composition sets the grid
   intensity that produces industrial indirect emissions. An app that draws both without
   computing that link has done half the job.
10. **Electricity means two different things — keep them apart.** Electricity as an
    *imported CBAM good* (Türkiye selling power to the EU) stays out of scope; volumes are
    marginal. Electricity *generation assets* are in scope, as indirect drivers. A reviewer
    will ask; README and METHODOLOGY must draw the line explicitly.
11. **Commissioning years come from GEM, not Climate TRACE**, which starts at 2021. This is
    what makes the 2000–2026 fleet timeline possible. `commissioning_source` records the
    provenance so a GEM year is never mistaken for an observation, and facilities without
    one carry `NA` and are visibly excluded from the pre-2021 animation.

---

## 6. Open — and who owns it

Numbered as in `ROADMAP.md`. The author-facing task list is published at
<https://claude.ai/code/artifact/3934ba71-177d-484b-800e-01f4ee3786aa> (B1–B10).

**Blocking the pipeline** — nothing downstream can be built until these land:

- **B1** Direct/indirect decomposition, *per sector*. The `other1`–`other10` slots carry
  different meanings in each sector: iron & steel `other2` is a direct-plus-indirect
  *quantity*, cement `other2` is a calcination *factor*, aluminium `other2` is a total
  *quantity*. Any parser must key on the `_def` label, never the slot number.
- **B2** Monthly → annual aggregation rule. Flows sum; `capacity` is a stock and summing
  it gives a figure twelve times too large; ratios need a weighting decision.

**Blocking the cost figure:**

- **B6** Narrow `policies/cbam_goods_cn_codes.json` from HS2/HS4 aggregates to the Annex I
  CN8 list. Currently `scope_status: PROVISIONAL_AGGREGATE`; the fetch script warns until
  fixed. Every share derived from aggregates is an upper bound.
- **B7** Define `eu_export_share`. Numerator counts finished goods, denominator counts
  crude production — different physical quantities. **Aluminium breaks the ratio
  entirely** (see §7 below).
- **B9** Write the liability calculation, retaining every intermediate for the audit trail.

**Raised by the merge — E1, E2, E4, E5 and E6 are now CLOSED with evidence.** Do not reopen
them; the answers are in `ROADMAP.md` and, with their measurements, in `FINDINGS.md` if it
is on disk.

- ~~**E1**~~ **Answered: no.** `electricity-generation` is combustion-only — 158 plants,
  zero hydro/wind/solar/geothermal/nuclear. It covers 52% of 2024 national generation and
  the missing half is almost exactly the renewable half, so a fleet-derived factor gives
  748 against 471–477 gCO₂/kWh. Ember carries the denominator instead; the wrong figure is
  kept as `diagnostic_not_for_use`.
- ~~**E2**~~ **Answered:** 78.3% overall (see §4). WRI's GPPD was measured as the open
  alternative and rejected at 15% coverage frozen at 2017.
- **E3** How far apart are Climate TRACE's reported `grid_emissions_intensity` and the
  project's own computed figure? **Partly answered** — Ember and Climate TRACE agree within
  3.2% across five years, which isolates the naive fleet estimate as the outlier. What
  remains is the author's choice of which to use: `grid_emission_factor.json` carries
  `selection.chosen: null` deliberately.
- ~~**E4**~~ **Answered: no, not on one basis.** Coal mining is 18% CO₂ and 82% fugitive
  methane; a CO₂ basis understates it 5.6×. Energy runs on CO₂e(100yr), industrial on CO₂,
  and the two are never summed — the interface says so before the idea forms.
- ~~**E5**~~ **Answered:** GEM declares captive status directly (`Captive Industry Type`),
  34 operating units / 4.46 GW. The 1.5 km spatial heuristic was demoted to a cross-check.
- ~~**E6**~~ **Answered:** the `co2` and `co2e_100yr` packages carry different registers and
  neither is a subset of the other. `co2e_100yr` is authoritative for energy; the eight
  omissions are listed rather than silently reconciled.
- **E7** Twelve same-subsector near-duplicates remain unresolved — four coal-mine pairs at
  0 m and seven power-station pairs within 450 m, plus Kars. Nothing dropped on suspicion.

**Blocking publication only** — short tasks, but v0.1 cannot be tagged with any outstanding:

- **B3** Resolve the Kars possible-duplicate and the Toprakkale province assignment.
- **B4** Verify the İBBS-2 mapping against TÜİK's official classification. The table in
  `02_build_facilities.R` carries a `>>> VERIFY BEFORE PUBLICATION <<<` marker.
- **B5** Determine which years are observed versus nowcast. Answer is in
  `data/raw/climate_trace/about_the_data.pdf`, already downloaded, not yet read.
- **B8** Find the citation for the €75 / €150 scenarios. They currently sit in
  `carbon_price_scenarios.json` with `citation_required: true` and `source_url: null` —
  §7 forbids using a regulatory number without a citation, so the project currently
  violates its own rule.

---

## 7. Known data-quality issues

Published rather than hidden. A tool showing 300 confident dots while knowing some are
uncertain overstates what it knows. The fuller record, with the measurement behind each,
is in `FINDINGS.md` — local only, absent from a fresh clone.

- **80 of 300 facilities** are not cleanly inside a province polygon: 64 boundary-proximate,
  12 snapped to nearest, 4 offshore. Every record carries `geocode_quality`.
- **300 records are 290 places.** Each of the six oil and gas fields is listed twice, under
  production and under transport, at identical coordinates. Correct accounting, misleading
  cartography — report both counts.
- **Twelve same-subsector near-duplicates** (E7), including four coal-mine pairs at 0 m.

- **Possible double count in Kars.** `Bozkale Cement Plant` (source_id 1897859) and
  `Kars Cement Plant` (42547309) sit **71 m apart**, both `integrated dry`, both with full
  independent 2021–2026 series, capacities 49,167 vs 50,000 t/month, operators *Kars
  Çimento AŞ* and *Çimentaş İzmir AŞ* — consistent with one plant recorded twice across an
  ownership change. If so, national cement CO₂ is overstated by ~236 kt in 2024 (0.49%)
  and Kars province by 100%. **Neither record has been dropped on suspicion.**
- **One probable province misassignment.** Koç Metalurji Toprakkale → Hatay while Tosçelik
  and Tosyalı Toprakkale, within 600 m, → Osmaniye. Toprakkale is an Osmaniye district.
  Both provinces are İBBS-2 TR63, so regional aggregation is unaffected.
- **Aluminium export ratio is impossible.** EU imports ÷ Turkish production runs 0.14–0.20
  for steel and 0.05–0.10 for cement, but **2.79–3.34 for aluminium**. Structural, not a
  bug: Türkiye has essentially one primary smelter (Seydişehir) but a large extrusion
  industry on imported ingot, and Climate TRACE's register cannot see the processors
  generating the trade. A real limitation of facility-level CBAM modelling for aluminium.
- **6.2% of iron-and-steel rows** fail `activity × emissions_factor = emissions_quantity`
  (~109 of 1,755). Cement and aluminium are at 100%. Cause not investigated.
- **Aluminium PFCs unavailable.** CBAM covers CO₂ *and* PFCs for aluminium; no `pfc`
  country package is published. Exposure is an underestimate, flagged not filled.
- **Two `Elmadağ Cement Plant` records in Ankara are NOT a duplicate** — checked; 4.4 km
  apart, different operators (Baştaş Başkent, Votorantim).

---

## 8. Traps already paid for

Every one of these cost real time. Do not rediscover them.

### Windows and PowerShell

- **`R` is not `R`.** PowerShell aliases `r` to `Invoke-History`. Always `Rscript`.
- **`Out-File -Encoding utf8` and `Set-Content -Encoding utf8` write a BOM** in Windows
  PowerShell 5.1, and R fails to parse a BOM'd script with `unexpected input`. Write files
  with the editor tooling, or `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`.
- **`Get-Content` displays valid UTF-8 as mojibake** (`Â§` for `§`) because it defaults to
  the ANSI codepage. The *file* is fine. Verify with
  `[System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)` before "fixing"
  anything.
- **`Rscript … | Select-Object -First N` closes the pipe early**, and the native command
  reports **exit 255** even though R succeeded. Capture to a variable, then filter.

### R

- **Column shadowing in `mutate()`.** The Climate TRACE CSVs have their own `sector`
  column valued `"manufacturing"`; the useful split is in `subsector`. Inside
  `imap(function(path, sector) …)`, `mutate(sector = sector)` resolves to the *column*,
  silently collapsing all three sectors into one and inflating a denominator threefold.
  Use a distinct argument name and `.env$`.
- **`renv` drops packages when the last script referencing them stops.** Refactoring
  `httr2` out of `00_coverage_audit.R` removed it from the lockfile and broke
  `01b_fetch_eu_trade.R`. Re-snapshot after refactors and check the pipeline still runs.
- **`runApp()` changes the working directory to the app folder**, so root-relative data
  paths resolve to `app/data/…`. `global.R` locates the project root by marker file.
- **`pivot_longer(names_to = c("slot", ".value"))` cannot produce an empty column name.**
  For `other1` / `other1_def` pairs, rename the unsuffixed half first.

### External services

- **Climate TRACE `/v6/assets/{id}` returns one year only** and silently ignores `year`,
  `years`, `since`/`to`, `startDate`/`endDate`. Use the bulk country package.
- **Natural Earth's Turkish province `name` field is corrupted at source** — "Kinkkale",
  "Zinguldak", "K. Maras", plus double-encoded characters no `ENCODING=` repairs. Key on
  `iso_3166_2`, which is clean and equals the vehicle plate codes (verified at 11 points).
- **Eurostat Comext returns HTTP 413** on unfiltered queries. Filter to one product code
  and one year per request. Indicator codes are `VALUE_IN_EUROS`, `QUANTITY_IN_100KG`
  (hundreds of kg — divide by 10 for tonnes), `SUPPLEMENTARY_QUANTITY`.
- **EUR-Lex HTML fetches return empty content.** Annex I could not be retrieved
  machine-readably; hence the provisional CN codes.
- **Chapter and heading customs codes overlap.** `"72"` already contains every `72xx`
  heading; summing both double counts. `01b_fetch_eu_trade.R` has a guard.

---

## 9. Where things live

```
CLAUDE.md              one-line pointer -> KARBON_ATLASI.md. DO NOT DELETE:
                       without it the instructions are not auto-loaded.
KARBON_ATLASI.md        project instructions — scope, data model, rules, API endpoints
STATUS.md              this file
MEMORY.md              LOCAL ONLY, gitignored, absent from a fresh clone.
                       Chronological working journal: what was built in what
                       order, approaches tried and abandoned, mistakes made.
                       Read it after this file if it exists on disk.
ROADMAP.md             decisions with reasoning, open questions 1-8 and E1-E7
FINDINGS.md            LOCAL ONLY, gitignored, absent from a fresh clone.
                       What the data turned out to be: source defects, structural
                       traps and dead ends, each with its measurement. ROADMAP
                       records decisions; this records observations. Untracked
                       2026-09-01 — the generalisable findings are the author's
                       to write up first, and reach the public through
                       METHODOLOGY. Add new anomalies here, not to a commit
                       message where they will be lost.
README.md              public-facing; Turkish summary block
METHODOLOGY.md         NOT YET WRITTEN — author's prose only (§9)
CITATION.cff           ORCID recorded

app/global.R           data loading, Turkish label vocabulary, sector colours
app/ui.R               dashboard layout. Rewritten 2026-08-19; the pre-pivot
                       energy-tracker version is in commit f6b4038
app/server.R           selected_facilities() is the single filter reactive —
                       the time slider plugs in there and nothing else changes

scripts/_sources.R     shared acquisition, SHA-256, archive inspection.
                       Approved exception to the numbering convention (§3)
scripts/_validate.R    tiered pipeline gates — STOP on structural impossibility,
                       WARN on data quality. Approved exception (§3)
scripts/00_…           coverage audit -> t0
scripts/01_…           all raw acquisition -> SOURCES.md
scripts/01b_…          Eurostat Comext trade
scripts/01c_…          GEM ingest -> commissioning years, SOURCES_GEM.md.
                       NEEDS A MANUAL DOWNLOAD; stops rather than proceeding empty
scripts/01d_…          Ember -> grid_intensity.csv, SOURCES_EMBER.md
scripts/02_…           facilities.rds + fleet_renewables.rds
scripts/03_…           DOES NOT EXIST — the panel, blocked on B1/B2

tests/                 testthat; data-property assertions, not unit tests.
                       Skip rather than fail when an artefact is unbuilt
policies/*.json        5 files, all with source_url + retrieval date,
                       each validated against a schema in policies/_schema/
data/processed/        facilities.rds, fleet_renewables.rds, coverage matrices,
                       grid_intensity.csv, SOURCES*.md, geocode report
data/raw/              gitignored
```

---

## 10. Resuming

1. `KARBON_ATLASI.md` loads automatically via the `CLAUDE.md` pointer.
2. Read this file, then `ROADMAP.md` open questions, then — **if they exist on disk** —
   `MEMORY.md` and `FINDINGS.md`. Both are gitignored, so a fresh clone has neither.
   `FINDINGS.md` is what stops a resuming session from rediscovering a source defect that
   was already measured and paid for; if it is absent, assume that knowledge is gone and
   ask the author before re-deriving anything.
3. `git log --oneline` — commit messages carry the reasoning for each decision.
4. Ask the author what changed on the B track; work done in his head is not on disk.

That scratch verification suite is now superseded: `tests/` was approved and built, and
the checks live there permanently as 133 assertions. Run them **as their own command**,
never chained onto a commit — PowerShell has no `&&`, so `Rscript tests/testthat.R; git
commit` means "commit regardless", and that is how a failing test once reached a commit.
