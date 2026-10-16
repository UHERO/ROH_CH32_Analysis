# CLAUDE.md

UHERO evaluation of Honolulu's ROH Chapter 32 (Bill 7) affordable-housing program: permit pipeline and processing times compared with a non-CH32 multifamily baseline, plus a RentHub market-rent "feasibility gap" analysis. Author: Rafael Munoz (graduate RA). See [README.md](README.md) for the project summary.

## Working with the author

- The author is new to Git. Explain Git steps in plain language, and never force-push, rewrite history, delete branches or merge into `main` without asking.
- The scripts were written with Gemini assistance and are run interactively in RStudio. Keep edits in the same style: tidyverse pipes, `# ====` section banners, comments that say why.
- Ask before committing. Commits go straight to `main` (no PR workflow).

## Branches

The author made one branch per analysis, but **every branch has already been merged into `main`**. As of 2026-10-16 none of them has commits that aren't on `main`. They're 21–23 commits behind and are missing scripts added later.

| Branch | Analysis | Script it added |
|---|---|---|
| `council-district-analysis` | Matching permits to council districts | `scripts/council_district_analysis.R` |
| `baseline-comparison-export` | Non-CH32 control-group export | `scripts/baseline-comparison-export.R` |
| `renthub-spatial-analysis` | Probably intended for RentHub work, but holds only README edits | none (the RentHub scripts went straight to `main` in `ccaca0c`) |

- Treat `main` as the source of truth. Don't base new work on an old branch: its copy of `roh_ch32_analysis.R` is out of date.
- Before working on a branch, re-check with `git fetch` and `git log main..origin/<branch>`. The author may have pushed new work to one since.
- For a new analysis, start a fresh branch from the current `main`.
- The repo was moved from `rafaelcbmunoz-sudo/ROH_CH32_Analysis` to `UHERO/ROH_CH32_Analysis`. Old merge messages still name the old URL.

## Running

- Run every script **from the repo root**. Paths like `data/...`, `outputs/...` and `fonts/...` are relative and there's no `setwd`/`here()`.
- `data/` and `outputs/` are gitignored and not in the repo. So are all `*.csv`, `*.xlsx`, `*.png` and `*.jpg` files. The raw data is internal to UHERO and lives on the NAS. If `data/` is missing, scripts fail on the first `read_csv`. Ask the user for the data rather than inventing stand-ins.
- R packages: `tidyverse`, `lubridate`, `scales`, `sf`, `showtext`. Python packages: `selenium`, `webdriver-manager`, `pandas`.
- There are no tests. Scripts check their inputs with `stopifnot()` blocks labelled "INTEGRITY TEST" / "Test N". Keep them, and add similar checks when you change joins or filters.

## Pipeline and data flow

| Script | Reads | Writes |
|---|---|---|
| `dpp_metrics_plan_reviews_scraper.py` | DPP Posse website. The application list is hardcoded in `app_list`. | `<app>_plan_reviews.csv`, `<app>_metrics.csv` in the **current directory** |
| `dpp_csv_compiler.py` | `*_plan_reviews.csv`, `*_metrics.csv` in the current directory | `MASTER_Plan_Reviews.csv`, `MASTER_Metrics.csv` in the current directory. **Move these to `data/` by hand.** |
| `baseline-comparison-export.R` | `data/hnlpermits_with_status_0625.csv`, `data/roh32_complete_cleaned (1).csv` | `outputs/DHLM_Non_CH32_Baseline_Projects.csv` |
| `council_district_analysis.R` | the above, plus `data/Honolulu_County_Council_Districts.geojson` and `data/Parcels_-_Honolulu_County_(Island_of_Oahu).geojson` | CSVs to **`data/`** (not `outputs/`), and `outputs/Council_District_Bill7_Plot.png` |
| `renthub_market_analysis.R` | `data/renthub_combined_2024_2026.csv`, the CH32 CSV, the districts geojson, the permits CSV | `outputs/RentHub_*.csv`, `outputs/Bill7_*.csv` |
| `renthub_visualizations.R` | `outputs/` CSVs from `renthub_market_analysis.R` | `outputs/Plot1`–`Plot4` PNGs |
| `roh_ch32_analysis.R` (main report graphs 1–5) | the permits CSV, `data/roh32_by_project_20260903.csv`, the old CH32 CSV (to recover unit counts), `data/MASTER_*.csv` | nothing. Plots go to the viewer with `print()`, not `ggsave`. |

`roh_ch32_analysis.R` is the script under active revision; recent commits change Graph 5 in response to report comments.

## Domain conventions

- Use "ROH Chapter 32", "CH32" and "Bill 7" for the same program, consistently with the surrounding code. The comparison group is "Non-ROH Chapter 32 Baseline".
- The baseline must not overlap CH32: CH32 permit numbers are always filtered out of it.
- `posse_freeze_date = 2025-07-28` is when DPP's Posse system stopped updating. Open reviews are cut off at that date.
- Application years 2023 and later are flagged "Incomplete/Censored", because recent cohorts only show their fastest permits. Graph 5 drops years 2025 and later. "Zombie" projects (in review with more than 120 days since the last action) are excluded from the timing figures.
- TMKs are cleaned with `-`/`:` removed and zero-padded to 8 digits. Baseline permits may hold several TMKs in one cell. `council_district_analysis.R` splits, matches and re-collapses them.
- Spatial work uses EPSG:4326 for joins and EPSG:32604 (UTM 4N) for the 0.5-mile buffers.

## Styling

UHERO branding: Gotham and Trajan fonts loaded from `fonts/` with `showtext`, and colors dark blue `#1D667F`, light blue `#7EC4CA`, gray `#505050`, gold `#F6A01B`, green `#9BBB59` and purple `#8064A2` (canceled/withdrawn). Every R script defines its own copy of `theme_uhero()`, and the copies' font sizes differ slightly. If you change one, ask whether the others should match.
