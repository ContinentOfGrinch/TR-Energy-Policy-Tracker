# Roadmap

Scope decisions, deferred features, and the release path for `skdm-turkiye`.

This file is the authoritative record of what is **deliberately** out of scope. If a
feature is absent from v0.1, it should appear here with a reason — absence without a
recorded reason is a gap, not a decision.

---

## Status

**Current version:** pre-0.1 (repository scaffolding)

**Next milestone:** `scripts/00_coverage_audit.R` — the data-availability matrix that
determines the empirical start year `t₀` and confirms which sectors survive at
facility-level resolution.

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

---

## Open questions — to be resolved by evidence, not assumption

These are live risks. Each will be closed by a specific artefact, not by discussion.

1. **Where does `t₀` actually fall?**
   Determined by the intersection of source × year × variable availability across all
   retained sectors. The audit output is committed to `data/processed/` as evidence for
   the claim, not merely printed to the console.
   *Closed by:* `scripts/00_coverage_audit.R`

2. **Is `production_activity` or `co2_direct_t` the binding constraint?**
   CBAM liability needs tonnes of goods and embedded emissions per tonne. Both fields are
   present in the API, but presence is not coverage — the audit must measure the non-null
   share per sector per year. If production is thinner than emissions, production sets the
   panel's effective span.
   *Closed by:* `scripts/00_coverage_audit.R`

3. **Which years are observation and which are estimate?**
   Climate TRACE returns years beyond the last realised year. The `Confidence` block is
   the only in-band signal available for telling them apart, and it may not distinguish
   them cleanly. If it does not, the boundary must be sourced from Climate TRACE's own
   release documentation rather than inferred.
   *Closed by:* `scripts/00_coverage_audit.R`

4. **How far do GEM and Climate TRACE disagree?**
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
