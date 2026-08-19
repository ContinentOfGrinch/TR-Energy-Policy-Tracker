# skdm-turkiye

**Facility-level EU CBAM exposure for Türkiye.**

An open-source R Shiny dashboard that maps individual carbon-intensive industrial
installations in Türkiye and estimates their exposure to the EU Carbon Border Adjustment
Mechanism (CBAM) under user-defined carbon price scenarios.

> **Status: v0.1 in development.** The data pipeline and facility map work. The emissions
> panel, the CBAM liability calculation and the time slider are not built yet. See
> [ROADMAP.md](ROADMAP.md) for what is deliberately out of scope and what is simply not
> done.

---

## Türkçe özet

Bu proje, Türkiye'deki karbon yoğun sanayi tesislerini **tesis düzeyinde** haritalayan ve
bunların **Sınırda Karbon Düzenleme Mekanizması (SKDM)** karşısındaki maruziyetini
kullanıcı tanımlı karbon fiyatı senaryolarına göre tahmin eden açık kaynaklı bir R Shiny
panosudur.

Kapsam: demir-çelik, çimento ve alüminyum — 88 tesis, 2021–2026.

**Önemli:** Bu araç bir **vergi hesaplayıcısı değildir.** SKDM sertifikalarını AB'deki
ithalatçı satın alır, Türk üretici değil. Üretilen rakam, tesisin AB'ye giden üretimine
gömülü emisyonun yarattığı **maliyet baskısıdır** — tesise kesilecek bir fatura değil.
Bu maliyetin ne kadarının üreticiye yansıyacağı bir pazarlık gücü sorusudur ve bu modelin
dışındadır.

Tüm emisyon rakamları **modellenmiş tahmindir.** Türkiye'de tesis düzeyinde doğrulanmış
sera gazı raporları kamuya açık değildir.

---

## Why this exists

Existing analyses of Turkish CBAM exposure work at national or sectoral resolution. That
is enough to say "Turkish steel is exposed"; it is not enough to say *which plants, in
which provinces, by how much*. Regional development agencies, journalists and policymakers
need the second answer and cannot get it from an aggregate.

The contribution is the combination — facility-level, spatially explicit, open source,
with an audit trail from every displayed figure back to its inputs. The arithmetic itself
is commodity.

---

## Scope

### What is covered

| Dimension | v0.1 |
|---|---|
| Sectors | Iron & steel, cement, aluminium |
| Facilities | 88 (cement 58, iron & steel 27, aluminium 3) |
| Geography | Türkiye, facility → province → İBBS-2 region → national |
| Years | 2021–2026 (`t₀ = 2021`, established empirically; 2026 partial at 5 months) |
| Regime | EU CBAM |

### What is not covered, and why

These are decisions with reasons, not gaps left by accident. Each is argued in
[ROADMAP.md](ROADMAP.md).

- **Three of the six CBAM goods categories.** CBAM also covers fertilisers, electricity
  and hydrogen. Electricity and hydrogen are excluded by choice — Turkish electricity
  exports to the EU are marginal and hydrogen volumes negligible. **Fertilisers are
  excluded on evidence:** no open source publishes Turkish fertiliser-*production*
  facilities. Climate TRACE's similarly named `synthetic-fertilizer-application` covers
  N₂O from fertiliser applied to soils — a different emission source, and not what CBAM
  regulates.
- **Aluminium PFCs.** CBAM covers CO₂ *and* perfluorocarbons for aluminium. No PFC country
  package is published, so aluminium exposure computed here is an underestimate. The gap
  is flagged in the interface rather than filled.
- **No equilibrium modelling.** This is an accounting framework. No price elasticity, no
  substitution, no trade diversion. The claim is narrow and deliberate: *given this output
  and this emission intensity, liability under scenario X is Y.*

---

## Installation

Requires **R 4.5.1 or later**. Development and testing were done on Windows 11.

```r
# 1. Clone, then from the project root:
install.packages("renv")
renv::restore()      # installs the exact package versions in renv.lock
```

`sf` needs GDAL, GEOS and PROJ. On Windows these ship with the CRAN binary. On Linux
install `libgdal-dev libgeos-dev libproj-dev` first.

### Build the data

`data/raw/` is not committed — reproducibility comes from the fetch scripts, not from a
45 MB blob in git history. Run the pipeline in order:

```bash
Rscript scripts/00_coverage_audit.R      # optional: regenerates the availability evidence
Rscript scripts/01_fetch_climate_trace.R # downloads sources, writes SOURCES.md
Rscript scripts/02_build_facilities.R    # builds facilities.rds
```

On Windows use `Rscript`, not `R` — in PowerShell `R` collides with the `Invoke-History`
alias.

### Run the app

```r
shiny::runApp("app")
```

---

## Repository layout

```
app/          global.R, ui.R, server.R — the dashboard
data/raw/     downloaded sources (not tracked)
data/processed/  facilities.rds, coverage matrices, SOURCES.md
policies/     regulatory parameters as JSON, read at runtime
scripts/      numbered ETL pipeline plus _sources.R helpers
```

Regulatory parameters live in `policies/*.json` and are **never hardcoded in R**. This is
not a style preference: TR-ETS secondary legislation was still being finalised through
mid-2026 and CBAM certificate prices update quarterly. If maintenance required editing R
source, this project would be dead within two years.

---

## Data sources

| Source | Use | Licence |
|---|---|---|
| [Climate TRACE](https://climatetrace.org) | Facility emissions, production, capacity, technology | CC BY 4.0 |
| [Natural Earth](https://www.naturalearthdata.com) | Province and İBBS-2 assignment | Public domain |
| European Commission | CBAM phase-in factors, certificate prices | — |

Full provenance — release tags, SHA-256 digests, retrieval dates and the complete
attribution chain — is in [data/processed/SOURCES.md](data/processed/SOURCES.md),
regenerated by the fetch script.

Climate TRACE is CC BY 4.0. **Attribution is a licence condition.** If you redistribute
data derived from this project, carry the chain forward.

---

## Known data-quality issues

Published rather than hidden, because a tool that shows 88 confident dots while knowing
some of them are uncertain is overstating what it knows.

- **22 of 88 facilities** sit within 2 km of a province boundary or were snapped from
  offshore port locations. Every facility carries a `geocode_quality` flag, and per-facility
  distances are in `data/processed/facilities_geocode_report.csv`.
- **Possible double count in Kars.** Two cement records sit 71 m apart with independent
  full time series under operators consistent with one plant recorded twice across an
  ownership change. Unresolved; neither record has been dropped on suspicion.
- **One probable province misassignment.** Koç Metalurji Toprakkale was assigned to Hatay
  while two neighbouring plants 600 m away went to Osmaniye. Both provinces are İBBS-2
  TR63, so regional figures are unaffected.
- **The İBBS-2 mapping is transcribed, not fetched** from an authoritative file, and
  carries a verification marker pending a citation to the official TÜİK classification.

---

## Licence

- Code: [MIT](LICENSE)
- Documentation and derived data: CC BY 4.0
- Upstream data retains its original licence

## Citation

See [CITATION.cff](CITATION.cff).

## Author

**Selahattin İlhan** · [ORCID 0009-0007-4824-752X](https://orcid.org/0009-0007-4824-752X)

### Disclosure

Code in this repository was written with AI coding assistance (Claude). All scope
decisions, source selections and methodological choices were made by the author, and the
analytical core — the CBAM liability calculation and emissions decomposition — is authored
by the author. `METHODOLOGY.md` is written by the author.
