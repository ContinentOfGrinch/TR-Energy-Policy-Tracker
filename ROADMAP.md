# Roadmap

Scope decisions, deferred features, and the release path for `skdm-turkiye`.

This file is the authoritative record of what is **deliberately** out of scope. If a
feature is absent from v0.1, it should appear here with a reason — absence without a
recorded reason is a gap, not a decision.

---

## Status

**Current version:** pre-0.1

**Data foundation complete** (2026-08-19). Acquisition, provenance, coverage audit and
the facility table are done and verified; the analytical layer has not been started.

| Component | State |
|---|---|
| `scripts/_sources.R`, `00`, `01`, `02` | done |
| `facilities.rds` | 88 facilities, verified |
| `facility_panel.rds` | **not started** — blocked on the direct/indirect decomposition |
| `policies/*.json` | not started |
| CBAM liability calculation | **not started** — author's analytical core (§9) |
| App | map, filters and sources tab working; no time slider, no liability figure |
| `README.md`, `CITATION.cff`, `METHODOLOGY.md` | not started |

`t₀ = 2021`; last complete year `2025`; 2026 partial at 5 months. 88 facilities: cement 58,
iron & steel 27, aluminium 3.

**Verification, 2026-08-19:** 34 checks passed, 0 failed, 3 flagged for human resolution
(open questions 3 and 4 below, plus two "Elmadağ Cement Plant" records in Ankara confirmed
as genuinely distinct sites 4.4 km apart under different operators). Sixteen facilities
were checked against publicly known locations and all sixteen were assigned correctly,
including the Karadeniz Ereğli / Marmara Ereğlisi pair that a name-based method would
confuse.

**Next milestone:** `policies/*.json` skeletons — the only remaining piece that needs no
analytical decision and can proceed in parallel with the author's work on the panel.

---

## v0.1 — target scope

### In scope

| Dimension | Decision |
|---|---|
| Sectors | Iron & steel, cement, aluminium |
| Geography | Türkiye |
| Unit of analysis | Individual facility |
| Time | Historical panel only; `t₀` set empirically by the coverage audit |
| Policy | EU CBAM liability under user-defined carbon price scenarios |
| Aggregation | Facility → province → national |
| Output | Shiny dashboard (Turkish UI) with a full audit trail per displayed figure |

### Scope decisions already taken

**1. Three of the six CBAM goods categories.**
CBAM covers cement, iron & steel, aluminium, fertilisers, electricity and hydrogen.
v0.1 covers cement, iron & steel and aluminium. The three exclusions are not equivalent
and must not be presented as though they were:

- **Electricity — excluded by choice.** Türkiye's electricity exports to the EU are
  marginal, and the channel requires the indirect-emissions treatment and a grid emission
  factor, both deferred below.
- **Hydrogen — excluded by choice.** Negligible export volume.
- **Fertilisers — excluded on evidence.** See the closed question below. This one is a
  finding, not a preference, and should be reported as such.

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

| Feature | Target | Reason for deferral |
|---|---|---|
| Electricity generation assets (thermal + renewable) | v0.2 | Requires the indirect-emissions channel and a grid emission factor. Expands the facility universe by an order of magnitude. The `liability_class` field already anticipates this. |
| Indirect emissions channel | v0.2 | Depends on an endogenous grid emission factor; `policies/grid_emission_factor.json` is reserved as a placeholder. |
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

5. **How far do GEM and Climate TRACE disagree?**
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
