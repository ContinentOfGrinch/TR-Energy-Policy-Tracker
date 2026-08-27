# Roadmap

Scope decisions, deferred features, and the release path for `karbon-atlasi-turkiye`.

This file is the authoritative record of what is **deliberately** out of scope. If a
feature is absent from v0.1, it should appear here with a reason — absence without a
recorded reason is a gap, not a decision.

---

## Status

**Current version:** pre-0.1

**Scope merged 2026-08-19.** The project now covers both industrial CBAM exposure and the
energy fleet that drives its indirect emissions. The industrial half is built and verified;
the energy half is decided but not yet built.

| Component | State |
|---|---|
| `scripts/_sources.R`, `00`, `01`, `01b`, `02` | done — industrial only |
| `facilities.rds` | 88 industrial facilities, verified |
| **Energy assets (210)** | **not started** — subsectors identified and counted, nothing fetched |
| **GEM commissioning years** | **not started** — required for the 2000–2026 fleet timeline |
| **Grid emission factor** | **not started** — no longer a placeholder |
| `policies/*.json` | 4 files done (CBAM phase-in, carbon prices, TR-ETS, CN codes) |
| `facility_panel.rds` | not started — blocked on the direct/indirect decomposition |
| CBAM liability calculation | not started — author's analytical core (§9) |
| App | industrial map, filters and sources tab working; no time slider, no cost layer, no energy layer |
| `README.md`, `CITATION.cff` | done |
| `METHODOLOGY.md` | not started — author's prose only |

`t₀ = 2021` for emissions; last complete year `2025`; 2026 partial at 5 months.

**Verification, 2026-08-19:** 34 checks passed, 0 failed, 3 flagged for human resolution
(open questions 3 and 4 below, plus two "Elmadağ Cement Plant" records in Ankara confirmed
as genuinely distinct sites 4.4 km apart under different operators). Sixteen facilities
were checked against publicly known locations and all sixteen were assigned correctly,
including the Karadeniz Ereğli / Marmara Ereğlisi pair that a name-based method would
confuse. **This verification covers the industrial half only.**

**Next milestone:** extend `00_coverage_audit.R` to the five energy subsectors, then fetch
and build the energy half of `facilities.rds`. The province and İBBS-2 assignment machinery
transfers unchanged.

---

## v0.1 — target scope

### In scope

| Dimension | Decision |
|---|---|
| Industrial sectors | Iron & steel, cement, aluminium — 88 facilities |
| Energy assets | Electricity generation 157, coal mining 38, oil & gas 15 — 210 facilities |
| Total | **298 facilities** |
| Geography | Türkiye |
| Unit of analysis | Individual facility |
| Emissions panel | `t₀` set empirically by the coverage audit — currently 2021 |
| Fleet timeline | Back to **2000** via GEM commissioning years; emissions stay 2021+ |
| Policy | EU CBAM liability under user-defined carbon price scenarios; energy policy timeline |
| Aggregation | Facility → province → İBBS-2 → national |
| Output | Shiny dashboard (Turkish UI) with a full audit trail per displayed figure |

### Scope decisions already taken

**1. Three of the six CBAM goods categories.**
CBAM covers cement, iron & steel, aluminium, fertilisers, electricity and hydrogen.
v0.1 covers cement, iron & steel and aluminium as **CBAM goods**. The three exclusions are
not equivalent and must not be presented as though they were:

- **Electricity — excluded as a CBAM good, by choice.** Türkiye's electricity *exports* to
  the EU are marginal, so electricity is not modelled as a traded CBAM good.
- **Hydrogen — excluded by choice.** Negligible export volume.
- **Fertilisers — excluded on evidence.** See the closed question below. This one is a
  finding, not a preference, and should be reported as such.

> **Do not confuse two different things called "electricity".** Electricity as an *imported
> CBAM good* — Türkiye selling power across the border — remains out of scope. Electricity
> *generation assets* are very much in scope since the 2026-08-19 merge, but in a different
> role: they are `indirect_driver`s that set the grid carbon intensity feeding the
> industrial installations' indirect emissions. A reviewer will ask about this; the README
> and METHODOLOGY must draw the line explicitly.

**This 3-of-6 restriction must be stated explicitly in the README and METHODOLOGY.**

**2. EU export share is modelled at sector level, not assumed to be 100%.**
CBAM liability arises only on goods actually exported to the EU. A facility selling
entirely into the domestic market has zero CBAM exposure. v0.1 therefore carries an
`eu_export_share` field derived from HS-code-level export statistics (TÜİK / TİM),
applied uniformly within a sector, and exposed as a user-adjustable control in the UI.

The field carries its own `value_type = assumption` and must be rendered as such.
Facility-level export shares are not publicly available in Türkiye and will not be
fabricated. The uniform-within-sector assumption is a known limitation, documented in
METHODOLOGY.

**3. Climate TRACE is the primary source; GEM is cross-validation only.**
The original plan was to merge two sources because Climate TRACE was expected to have
thin production and capacity coverage. API reconnaissance (2026-08-19) disproved that
premise: Climate TRACE already carries `AssetType` (technology, e.g. BF/BOF), `Capacity`
and `Activity` (production in tonnes of product) per facility per year.

The merge is therefore dropped. Entity resolution between two facility registers would
have introduced a matching error rate into every downstream number in exchange for fields
that turned out to already be present — a bad trade.

GEM is retained in a narrower role: an **independent check** on capacity and commissioning
year for the facilities it also covers. The disagreement rate is reported in METHODOLOGY
as a data-quality statistic. GEM values do not enter `facility_panel.rds`, so the panel
keeps a single licence and a single attribution chain.

**4. Forward years are retained but never rendered as observations.**
Climate TRACE publishes estimates beyond the last observed year (currently 2025–2026).
These enter the panel with `value_type = projected` and must be drawn differently from
observed values — dashed, desaturated, badged. Displaying 2026 matters, because that is
when CBAM's definitive regime applies; presenting it as a realised figure would not.

**4. Estimated exposure is not a tax bill.**
CBAM certificates are surrendered by the EU importer, not by the Turkish producer. The
figure this tool produces is the cost pressure embedded in a facility's EU-bound output,
not an invoice that facility receives. How much of that cost is passed back to the
producer is a bargaining question and is outside an accounting framework. UI wording
must preserve this distinction — "maruziyet" and "maliyet baskısı", never "vergi" or
"ödeyeceği tutar".

---

## Deferred features

Each entry states *why* it is deferred, so the decision can be revisited on evidence
rather than re-argued from scratch.

**Three rows left this table on 2026-08-19** when the scopes were merged: electricity
generation assets, the indirect-emissions channel, and the endogenous grid emission factor
are all now in v0.1. They are listed under "In scope" above. The deferral reasoning that
used to sit here — "expands the facility universe by an order of magnitude" — turned out
to be right about the magnitude (88 → 298) and wrong about it being a reason to wait: the
`electricity_use` and `grid_emissions_intensity` fields already in the industrial panel
made the link cheap to compute once the fleet was mapped.

| Feature | Target | Reason for deferral |
|---|---|---|
| TR-ETS liability and domestic carbon price offset | v0.2 | CBAM permits deduction of carbon prices *effectively paid* in the country of origin. During the TR-ETS pilot (2026–2027) allocation is 100% free, so the deductible amount is approximately zero. Deferring the offset is therefore the **correct** treatment for the pilot period, not a simplification. It becomes material from the first compliance period (2028–2035). |
| Forward projection to 2035 | v0.2 | The `value_type = projected` encoding exists from day one so projections can be added without a schema change, but v0.1 makes no forward claims. |
| Monte Carlo / uncertainty quantification | v0.3 | Requires characterised input distributions. Premature while emission estimates are single-point modelled values with undocumented error bounds. |
| EPİAŞ Transparency Platform integration | v0.2+ | Requires authenticated (TGT/ticket) access, unsuitable for a public app without a scheduled server-side ETL. |
| Country-agnostic architecture | v0.3+ | `country_iso3` and `regime_id` are present from day one so this remains cheap, but no second country is targeted in v0.1. |
| Facility-level EU export shares | not planned | Firm-level export data is not public in Türkiye. Sector-level shares are the honest ceiling of what is knowable from open data. |

---

## Closed questions

**Does the fertiliser sector survive at facility level? — No.**
*Closed 2026-08-19 by Climate TRACE API reconnaissance.*

Climate TRACE publishes no fertiliser-**production** subsector. The similarly named
`synthetic-fertilizer-application` covers N₂O released when fertiliser is applied to
agricultural soils — a different emission source from a different part of the economy,
and not what CBAM regulates. Substituting it would be a category error, not an
approximation. GEM publishes no fertiliser tracker. The `chemicals` subsector returns
3 Turkish assets but spans petrochemicals and other chemicals, so it cannot stand in
for fertilisers without fabricating a sectoral boundary that the data does not support.

Fertilisers are therefore dropped from v0.1 and the exclusion is reported as a result:
*at facility resolution, with open data, Turkish fertiliser production is not currently
addressable.* This is worth stating plainly in METHODOLOGY — it maps the edge of what
open data can support, which is useful to the next researcher.

**Where does `t₀` fall? — 2021.**
*Closed 2026-08-19 by `scripts/00_coverage_audit.R`.*

Under the pre-specified rule (≥90% of facilities in every sector carrying non-missing
`activity` **and** `emissions_quantity`, in a temporally complete year), every year from
2021 to 2025 passes at 100% coverage in all three sectors. 2026 fails only on
completeness: 5 of 12 months. The panel therefore spans **2021–2026**, with 2026 flagged
partial and never annualised by scaling — cement output is seasonal, so a 12/5 multiplier
would bias the figure systematically rather than randomly.

**Is production or emissions the binding constraint? — Neither.**
*Closed 2026-08-19 by `scripts/00_coverage_audit.R`.*

Both `activity` and `emissions_quantity` are present for 100% of facilities in every
sector-year. The concern that production coverage would truncate the panel did not
materialise. Note that `activity × emissions_factor == emissions_quantity` holds for 100%
of cement and aluminium rows and 93.8% of iron & steel rows — the residual is worth
inspecting before the panel is built, but it does not constrain `t₀`.

**Can the REST API supply the panel? — No.**
*Closed 2026-08-19 by `scripts/00_coverage_audit.R`.*

`GET /v6/assets/{id}` returns a single year (the latest) and silently ignores every year
parameter tried: `year`, `years`, `since`/`to`, `startDate`/`endDate`. An audit run
against it reports the endpoint's limit rather than the data's. The bulk country package
at `downloads.climatetrace.org/latest/country_packages/{gas}/{ISO3}.zip` carries monthly
facility-level records from 2021 onward **plus** the `other1..other10` fields the API
omits entirely, and is the only viable source. Note the release mismatch: the bulk
package is tagged `v5_9_0` while the API serves `v6`; cite the package version.

---

## Open questions — to be resolved by evidence, not assumption

These are live risks. Each will be closed by a specific artefact, not by discussion.

1. **Which years are observation and which are estimate?**
   The audit established that 2021–2025 are temporally complete and 2026 is partial
   (5 months). It did **not** establish whether 2025 is a realised observation or a
   Climate TRACE nowcast — completeness is not the same as being observed. This boundary
   determines which years may carry `value_type = observed`, so it must be settled from
   Climate TRACE's release documentation rather than inferred from the data.
   *Closed by:* `latest/about_the_data/about_the_data.pdf` in the country package,
   recorded in `data/processed/SOURCES.md`

2. **How is the indirect component separated from the direct one, per sector?**
   The audit found that `other1..other10` slot meanings are **sector-specific**. Iron &
   steel exposes `direct and indirect emissions` as a quantity; cement instead exposes a
   `Calcination emissions factor` and a separate `Fuel emissions factor`; aluminium
   exposes `total emissions`. There is therefore no single expression that recovers the
   indirect share across all three sectors, and any parser must key on the `_def` label
   rather than the slot number.

   CBAM regulates direct emissions for v0.1, so this decomposition determines what enters
   the calculation at all. It is analytical core work and belongs to the author (§9).
   *Closed by:* the author, in `scripts/03_build_panel.R`, reviewed against
   `data/processed/coverage_other_fields.csv`

3. **Is the Kars cement plant double-counted?**
   `Bozkale Cement Plant` (source_id 1897859) and `Kars Cement Plant`
   (source_id 42547309) sit **71 metres apart** in Kars, both typed
   `integrated dry`, both carrying full independent 2021–2026 series with
   similar capacities (49,167 vs 50,000 t/month). Their recorded operators are
   *Kars Çimento Sanayi ve Ticaret AŞ* and *Çimentaş İzmir Çimento Fabrikası
   Türk AŞ* — consistent with one physical plant appearing twice, once under a
   historical owner and once under the acquirer.

   If they are one plant, Kars province is double-counted and national cement
   CO₂ is overstated by roughly 236,000 t in 2024 (0.49% of the sector). At
   province level the error is 100%. Neither record may be dropped on suspicion;
   resolve against an authoritative plant register (TÜRKÇİMENTO membership or
   the facility's own disclosures) and record the decision.
   *Closed by:* manual verification, documented in METHODOLOGY

4. **Is the Koç Metalurji Toprakkale plant in Hatay or Osmaniye?**
   Three steel plants sit within 600 m of one another at Toprakkale. Two —
   Tosçelik and Tosyalı — were assigned to Osmaniye at 533 m and 572 m from the
   provincial boundary. The third, Koç Metalurji, was assigned to **Hatay** at
   129 m. Toprakkale is a district of Osmaniye, so the odd one out is probably a
   misassignment produced by Natural Earth's 10m geometry rather than a real
   difference.

   Both provinces fall in NUTS-2 **TR63**, so regional aggregation is unaffected
   either way; only the province figure is at risk. This is precisely the case
   the `boundary_proximate` flag exists to surface, and it should not be
   corrected by hand without a better boundary source.
   *Closed by:* a higher-resolution boundary check or the operator's own address

5. **Aluminium breaks the export-share ratio. What replaces it?**
   *Surfaced 2026-08-19 by `scripts/01b_fetch_eu_trade.R`.*

   The diagnostic ratio of EU imports to Turkish production comes out plausible
   for two sectors and impossible for the third:

   | sector | EU imports ÷ production, 2021–2025 |
   |---|---|
   | iron & steel | 0.14 – 0.20 |
   | cement | 0.05 – 0.10 |
   | **aluminium** | **2.79 – 3.34** |

   A share above 1 cannot be an export share. The cause is structural, not a
   coding error: Türkiye has essentially one primary aluminium producer
   (Seydişehir) but a large extrusion and rolling industry running on imported
   ingot. Chapter 76 exports therefore exceed domestic primary output several
   times over, and Climate TRACE's facility register — which covers primary
   production — cannot see the downstream processors that generate most of the
   trade.

   This is a real limitation of facility-level CBAM modelling for aluminium and
   belongs in METHODOLOGY regardless of how it is handled. The options are to
   restrict aluminium to primary-metal customs codes only, to report aluminium
   exposure without an export share and label it a ceiling, or to drop the
   sector. All three are defensible; none may be chosen silently.
   *Closed by:* the author, alongside the `eu_export_share` definition

6. **What is `eu_export_share` actually a ratio of?**
   The numerator from Comext counts finished goods in tonnes of product; the
   denominator from Climate TRACE counts crude steel, cement and primary
   aluminium. These are different physical quantities — there is yield loss
   between crude and finished steel, and Annex I does not cover every steel
   product. `01b_fetch_eu_trade.R` therefore emits the two series side by side
   and a ratio explicitly labelled `diagnostic_not_for_use`; it does not decide
   the conversion.
   *Closed by:* the author, in METHODOLOGY and `03_build_panel.R`

7. **Customs codes are provisional aggregates, not Annex I.**
   `policies/cbam_goods_cn_codes.json` currently holds HS2/HS4 aggregates
   because Annex I of Regulation (EU) 2023/956 could not be retrieved in
   machine-readable form. Chapter 72 contains steel products Annex I does not
   list, and chapter 76 likewise, so every share derived from them is an upper
   bound. The file carries `scope_status: PROVISIONAL_AGGREGATE` and the fetch
   script raises a warning until it is set to `annex_i_verified`.
   *Closed by:* transcribing the CN8 list from the Official Journal

8. **How far do GEM and Climate TRACE disagree?**
   GEM is a cross-check, not an input, so a disagreement does not have to be reconciled —
   but it does have to be measured and published. A large divergence in capacity or
   commissioning year is a finding about source reliability that readers need.
   *Closed by:* a validation section in `scripts/02_build_facilities.R`, reported in
   METHODOLOGY

5. **Turkish cement and clinker default values are unstable.**
   The Commission withdrew the default value and benchmark pending reissue at amended
   levels. These must be handled with an explicit flag and never silently replaced with
   a global average.
   *Closed by:* a versioned entry in `policies/` plus a visible UI warning.

---

## Open questions raised by the merge

These did not exist before 2026-08-19. None is blocked on the author; they are
build-and-measure questions.

**E1. Does Climate TRACE's `electricity-generation` include zero-emission plants? — NO.**
*Closed 2026-08-19 by inspecting the country package.*

Türkiye's `electricity-generation` register contains **158 combustion plants only**:

| Fuel | Plants | 2024 generation | 2024 CO₂ |
|---|---|---|---|
| coal | 30 | 102.5 TWh | 103.5 Mt |
| gas / gas+other fossil | 64 | 60.9 TWh | 23.6 Mt |
| biomass | 55 | 8.2 TWh | 0 (biogenic convention) |
| oil / mixed | 9 | 5.6 TWh | 5.4 Mt |

**There is no hydro, wind, solar, geothermal or nuclear.** Climate TRACE's
`grid_marginal_operating_emissions_intensity` field (`other7`) is empty for every record,
so it offers no fallback.

**The consequence was quantified and it is large.** A grid factor computed naively as
total emissions ÷ total generation over this fleet gives **0.748 tCO₂/MWh**. Climate
TRACE's own `grid_emissions_intensity`, carried in the *industrial* data, has a 2024 median
of **0.477 tCO₂/MWh**. The ratio, 0.637, is consistent with roughly 36% of Turkish
generation being renewable and therefore absent from the register. Computing the factor
from the mapped fleet alone would have **overstated industrial indirect emissions by about
57%** — and it would have done so silently, because the arithmetic is correct and only the
denominator is incomplete.

**Decision (2026-08-19): complete the denominator from TEİAŞ.** Numerator stays Climate
TRACE (fossil fleet emissions); denominator becomes TEİAŞ's official annual generation by
source, which includes hydro, wind and solar. This keeps the claim that the energy layer
explains the grid factor, rather than borrowing a number. TEİAŞ enters `SOURCES.md` as a
third upstream source with its own licence and retrieval date.

**Decision (2026-08-19): renewables are added to the map from GEM.** Hydro, wind, solar and
geothermal plants come from the GEM Global Integrated Power Tracker with coordinates and
commissioning years — the same fetch that E2 already requires. Their emissions stay zero or
`NA`. Without them the 2000–2026 fleet animation would omit the single largest change in
Türkiye's power sector, which is the point of having a timeline at all.

**E2. How many of the 210 energy assets have a GEM commissioning year?**
The 2000–2026 fleet timeline depends on it. Facilities without one carry `NA` and must be
visibly excluded from the pre-2021 animation rather than silently assumed to have always
existed. If coverage is thin, the timeline claim has to be scaled back.
*Closed by:* a coverage audit pass over GEM

**E3. Reported versus computed grid intensity — how far apart?**
Climate TRACE publishes `grid_emissions_intensity` per industrial facility (0.52 tCO₂/MWh
in the steel sample). The project will also compute its own from the mapped fleet. The gap
between them is a result, not an error to be tuned away, and belongs in METHODOLOGY.
*Closed by:* the grid factor script, reported in `grid_emission_factor.json`

**E4. Do coal mines and oil & gas assets belong in the same panel?**
They are `neutral` — outside both the CBAM calculation and the grid factor. Their emissions
are largely fugitive methane, a different gas with a different accounting basis from the
CO₂ the rest of the project handles. Including them in a CO₂-denominated total would be
wrong. Decide whether they are a separate map layer with their own units or are dropped.
*Closed by:* the author, when the energy panel is designed

---

## Repository visibility

**Private for now** (decided 2026-08-19). The work is honest about its gaps but several
are still open — two price scenarios without a citation, provisional customs codes, the
Kars duplicate and the Toprakkale assignment — and there is no reason to publish before
they are addressed.

**This must flip to public before the release path can proceed, and it is easy to forget.**
Zenodo's GitHub integration archives a release only from a public repository, and JOSS
requires the source to be openly readable throughout review. Making the repository public
at the moment of tagging also means the first thing a reviewer sees is a version whose
`README.md` already lists its own limitations, which is the intended impression.

Repository name: `karbon-atlasi-turkiye`, matching `CITATION.cff`.

---

## Release path

1. Working v0.1 on `main`, reproducible from a clean clone via `renv::restore()`
2. `tests/` — required by JOSS; add before tagging rather than retrofitting
3. `METHODOLOGY.md` complete, including every limitation recorded above
4. `data/processed/SOURCES.md` with the full upstream attribution chain
5. Git tag `v0.1.0`
6. Zenodo archive → DOI → update `CITATION.cff`
7. Preprint
8. JOSS submission

**JOSS readiness checklist:** installation instructions, automated tests, API/function
documentation, example data, contribution guide, statement of need, and a clear
comparison against existing tools.

---

## Licensing

- Code: MIT
- Documentation and derived data: CC BY 4.0
- Upstream data retains its original licence. Climate TRACE is CC BY 4.0 and
  attribution is a legal requirement, surfaced in a visible "Veri Kaynakları" tab.

---

## Version history

| Version | Date | Summary |
|---|---|---|
| pre-0.1 | — | Repository scaffolding; scope fixed; coverage audit pending |
