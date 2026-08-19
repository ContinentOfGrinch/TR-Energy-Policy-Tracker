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
| Sectors | Iron & steel, cement, aluminium, fertilisers |
| Geography | Türkiye |
| Unit of analysis | Individual facility |
| Time | Historical panel only; `t₀` set empirically by the coverage audit |
| Policy | EU CBAM liability under user-defined carbon price scenarios |
| Aggregation | Facility → province → national |
| Output | Shiny dashboard (Turkish UI) with a full audit trail per displayed figure |

### Scope decisions already taken

**1. Four of the six CBAM goods categories.**
CBAM covers cement, iron & steel, aluminium, fertilisers, electricity and hydrogen.
v0.1 covers the first four. Electricity is excluded because Türkiye's electricity
exports to the EU are marginal and because the indirect-emissions channel requires a
grid emission factor (deferred below). Hydrogen is excluded as negligible in volume.
**This 4-of-6 restriction must be stated explicitly in the README and METHODOLOGY** —
it is a scope choice, not an oversight.

**2. EU export share is modelled at sector level, not assumed to be 100%.**
CBAM liability arises only on goods actually exported to the EU. A facility selling
entirely into the domestic market has zero CBAM exposure. v0.1 therefore carries an
`eu_export_share` field derived from HS-code-level export statistics (TÜİK / TİM),
applied uniformly within a sector, and exposed as a user-adjustable control in the UI.

The field carries its own `value_type = assumption` and must be rendered as such.
Facility-level export shares are not publicly available in Türkiye and will not be
fabricated. The uniform-within-sector assumption is a known limitation, documented in
METHODOLOGY.

**3. Coverage audit evaluates two candidate sources, not one.**
Climate TRACE provides facility-level emission *estimates* with coordinates but has
patchier production and capacity coverage. The Global Energy Monitor sector trackers
provide capacity, technology and commissioning year but no emissions. The audit
scans both before the source strategy is fixed, so that `t₀` and the source decision
are empirical outcomes rather than prior assumptions.

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

## Open questions — to be resolved by evidence, not assumption

These are live risks. Each will be closed by a specific artefact, not by discussion.

1. **Does the fertiliser sector survive at facility level?**
   Steel and cement have strong open facility trackers; aluminium is moderate;
   fertilisers have no comparable open source. If the coverage audit shows fertiliser
   coverage is materially thinner, the options are (a) drop the sector from v0.1, or
   (b) retain it with an explicit low-confidence flag surfaced in the UI. Reducing
   scope to three sectors is an empirical finding to be reported, not a failure.
   *Closed by:* `scripts/00_coverage_audit.R`

2. **Where does `t₀` actually fall?**
   Determined by the intersection of source × year × variable availability across all
   retained sectors. The audit output is committed to `data/processed/` as evidence for
   the claim, not merely printed to the console.
   *Closed by:* `scripts/00_coverage_audit.R`

3. **Is `production_activity` or `co2_direct_t` the binding constraint?**
   CBAM liability needs tonnes of goods and embedded emissions per tonne. If production
   coverage is thinner than emissions coverage, the panel's effective time span is set
   by production, not emissions.
   *Closed by:* `scripts/00_coverage_audit.R`

4. **How are Climate TRACE and GEM facilities matched?**
   If both sources are retained, entity resolution (name similarity plus coordinate
   distance) becomes a distinct work item with its own error rate that must be reported.
   *Closed by:* a matching-diagnostics section in `scripts/02_build_facilities.R`

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
