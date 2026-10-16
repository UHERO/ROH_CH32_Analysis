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

## Confidentiality

**The GitHub repo is public.** Never commit `data/` or `docs/`.
- `data/` is gitignored, along with all `*.csv`, `*.xlsx`, `*.png` and `*.jpg` files. The data is internal to UHERO and lives on the NAS.
- `docs/` is gitignored too. It holds internal drafts, and the preliminary brief is marked "not for public distribution". Never force-add it (`git add -f`). Check `git status` before any `git add`.
- Don't paste rows of the permits export into commits, issues or PRs.

## Data (`data/`, local only)

As of 2026-10-16, the local `data/` folder holds four files: the two described below, provided by the user, and the two `MASTER_*.csv` files re-scraped by Claude (see the next paragraph). Most of the other inputs the scripts expect are **not** present (see the pipeline table). Ask for missing files rather than inventing stand-ins.

**`MASTER_Plan_Reviews.csv` and `MASTER_Metrics.csv`** were re-scraped from the public Posse site on 2026-10-16 with Rafael's scraper and compiler, unmodified except for how the browser driver starts.
- They cover 61 of the scraper's 65 applications. The 4 `MA-` master applications fail: the job-search page's search box never appears.
- The site's review data stop at 2025-07-28.
- They reproduce the draft's Figure 4 exactly.
- `MASTER_Metrics.csv` has DPP's own milestones per application: application accepted, permit ready for pickup, issued, and "Days Waiting for Pickup".
- Rafael's own copies, if he sends them, should match. Compare before replacing.

Running the scraper on this machine:
- The `scraping` env has Selenium 4.25 but **not** `webdriver-manager`, and Chrome isn't installed system-wide. Selenium's cached Chrome for Testing and chromedriver are in `~/.cache/selenium/` (v142).
- So run the scraper through a wrapper that swaps the `ChromeDriverManager` lines for `Service(executable_path=...)` with `Options.binary_location`, running headless. Don't edit the committed script.
- The scraper writes to the current directory. Run it in a scratch folder.
- `dpp_csv_compiler.py` crashes on Windows when printing its ✅ emoji (cp1252 console). Run it with `PYTHONIOENCODING=utf-8`.
- Windows filename matching ignores case, so the compiler's `*_metrics.csv` / `*_plan_reviews.csv` searches also match its own `MASTER_*` outputs. **Run it once, in a folder without old MASTER files**, or the metrics rows get duplicated.

**`roh32_by_project_20260903.csv`**: DPP's list of ROH 32 projects. It has 85 rows, one per project, keyed by `primary_permit` and `tmk`, an 8-digit TMK.
- It's an updated version of the file the author used for the pipeline graphs. It was renamed on 2026-10-16 so that `roh_ch32_analysis.R` finds it. **The date in the name is the old snapshot's, not this file's.** This file runs to late September 2026.
- It has every column the script uses (`primary_permit`, `tmk`, `created_date`, `status`, `issued_date`, `units_added`) and only status values the script's `case_when` handles.
- The latest dates in it are issued 2026-09-22 and accepted 2026-09-24.
- It reproduces the draft final brief's figures: 85 projects, 7 completed projects with 224 units, and 475 units applied for in 2023. It shows 23 projects and 812 units permitted but not completed, against the brief's 22 and 776 "as of September 2026". The difference is probably one permit issued after the 2026-09-03 snapshot.
- Since July 2025, new permits are numbered `BP-YYYY-NNNNNN` (14 projects) rather than `AYYYY-MM-NNNN`. The scraper's `app_list` covers neither these nor the other 2025 additions. It also lists 6 IDs that aren't in this file, mostly `MA-` master applications.
- It does **not** have the columns that `baseline-comparison-export.R`, `council_district_analysis.R` and `renthub_market_analysis.R` read from `roh32_complete_cleaned (1).csv` (`Building permit #`, `TMK`, `Units`, `geometry`). Those scripts still need the old file.

**`permits_and_activity_by_tmk_plus_parcel_redacted_no_high_risk_comments.csv`**: a cleaned export of DPP building-permit records from April 2026 (latest `LastModifiedDate` is 2026-04-18).
- The records are from POSSE, DPP's old system, but the fields are named in the new Salesforce/Clariti style (`MUSW__*`, `clariti__*`, `*__c`). `Legacy_Permit_Name__c` holds the old POSSE number.
- There is **one row per permit × plan-review activity**: 1,723 rows covering 329 permits. Permit fields come first, then the review fields.
- The review fields include `Review_Type__c`, `Date_Plans_Received__c`, `Date_Completed__c` and `Status__c`. They run from 2018-10 to 2025-07-28, the date of `posse_freeze_date`. These are the same per-discipline review timelines the scraper pulled from the Posse "Plan Reviews" tab, but the file is **not a drop-in replacement** for `MASTER_Plan_Reviews.csv`:
  - Running Graph 5's math on it as-is gives agency times about 3× Figure 4's. Reviews with no `Date_Completed__c` (170 rows that are In Progress or Pending, many of them post-issuance shop drawings) get extended to the freeze date.
  - Keeping only completed reviews brings the yearly bars close to Figure 4 (2019: 222 vs 236; 2024: 74 vs 88), but they still don't match.
  - Only 50 of the 85 projects have review rows here.
  - The timestamps are migration artifacts. Use the stored calendar date (`substr(x, 1, 10)`), not an HST conversion, which puts some completions before receipt.
- Column names repeat between the two halves (`Id`, `Name`, `CreatedDate`, `input_tmk`, …). pandas renames the second copy to `Id.1`; readr renames copies to `Id...123`. Select columns by position or rename them right after reading.
- The file is **not countywide**. It covers permits on the parcels of ROH 32 projects only: `match_source` is `TMK_MATCH` or `PARCEL_EXPANSION`. It includes 57 of the 85 projects, plus demolition, fence, trenching and other permits on the same lots.
- So it can't replace `hnlpermits_with_status_0625.csv` for the non-CH32 baseline, which needs all multifamily permits on Oʻahu.
- Read it with `low_memory=False` / `guess_max`. It has 674 columns, most of them sparse.

## Running

- Run every script **from the repo root**. Paths like `data/...`, `outputs/...` and `fonts/...` are relative and there's no `setwd`/`here()`.
- Python is Miniconda at `C:\Users\curly\miniconda3`. The `scraping` env has selenium and pandas, the `geoanalysis` env has geopandas, and `base` has pandas. Call the interpreter by path, e.g. `C:\Users\curly\miniconda3\envs\scraping\python.exe`.
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
| `permit_rounds.py` (added 2026-10-16) | `data/roh32_by_project_20260903.csv`, plus `data/MASTER_Plan_Reviews.csv` if present, otherwise the April 2026 export (`--source auto\|master\|export`, `--data-dir`) | nothing. It prints review rounds, turnaround, applicant response, reopened reviews, first-round lag, and final-review-to-issuance gaps. |
| `permit_rounds_checks.py` | same as above; imports `permit_rounds.py` | nothing. It prints coverage, date-integrity, and core-vs-all-reviews sensitivity checks. |

`roh_ch32_analysis.R` is the script under active revision; recent commits change Graph 5 in response to report comments.

`permit_rounds.py` supports the rewrite of the permitting section; the plan and draft text are in `docs/permitting_section_plan.md`.
- Run it with the `base` or `scraping` env (it needs only pandas), from the repo root: `C:\Users\curly\miniconda3\python.exe scripts\permit_rounds.py`.
- On the scraped file, it looks for an outcome column named `Outcome`, `Review Outcome`, `Result` or `Status`. If it finds none, it skips the approval-based sections (first approvals, reopened reviews), so check the first lines of its output.
- With `data/MASTER_Plan_Reviews.csv` present it uses the scraped reviews (59 of 85 projects have reviews). `--source export` forces the April export (50 projects).
- Scraped discipline names ("Building Code", "Fire Code (HFD)") are mapped to the export's codes (`DISCIPLINE_ALIASES`), and only the seven core disciplines in `CORE_DISCIPLINES` are counted.

## Which report sections this repo feeds (`docs/`)

There are two briefs. "Assessing Honolulu's 'Bill 7' Infill/Workforce Housing Program" is by Trey Gordner, Edith Prager and Rafael Munoz.
- **`docs/ROH 32 Policy Brief - preliminary results.pdf`** (May 2026), marked not for public distribution.
- **`docs/ROH 32 Policy Brief - draft final.md`**, about to be shared. Its images are embedded as base64. Strip them before reading (they make up roughly 90% of the 384 KB), and don't read the raw file whole.

Most of the final brief comes from UHERO's Housing Policy Simulator, which is **not** in this repo. That covers the Methodology section, Tables 1–5, the sensitivity analysis, the comparisons with Ord. 26-7, and fee waivers. The transit and ACS analysis ("Bill 7 contributes to other policy goals") isn't here either. This repo feeds the following sections:

| Brief section | Content | Source here |
|---|---|---|
| Final: Executive Summary, Background, **Figure 1** "Bill 7 Pipeline, 2019 to 2026" | 85 projects / 2,280 units; 7 completed / 224 units; 22 permitted / 776 units; 2023 peak of 475 units, over ¼ of proposed multifamily units citywide; 274 withdrawn units | Graph 2 (pipeline) and Graphs 1 and 4 (CH32 share of all multifamily) in `roh_ch32_analysis.R`, built on `roh32_by_project` |
| Final: Discussion, "Permit delays…", **Figure 4** "Time with Agency vs. Developer" | Figure 4 bars, agency / developer days: 2019 236/370, 2020 131/1059, 2021 161/290, 2022 234/391, 2023 154/519, 2024 88/184. "167 days" is the unweighted mean of the six agency bars. The text's "140 agency / 350 developer" is the **project-level average from before** the 2026-09-20 commit that added `year_created < 2025` (re-scrape: 141 / 349). For the current figure it's 157 / 406 project-level, or 167 / 469 cohort-year. That was confirmed with `graph5_summary` on the re-scraped data. 120-day abandonment rule; data through July 2025 | Graph 5 in `roh_ch32_analysis.R`, built on the scraped plan reviews |
| Final: same section | "Bill 7 projects have taken roughly as long to get their permits as other multifamily projects" | Graph 3 (processing time compared with the baseline) |
| Final: Findings, "How program parameters affect feasibility" | Advertised rents 14–34% below the 100% AMI limit, from 100+ listings across 5 projects | `renthub_market_analysis.R` / `renthub_visualizations.R`, confirmed by the user (likely the exact-match comparison behind the dumbbell plot) |
| Preliminary: "Production volume and pipeline" | Pipeline chart; 189 units built; share of multifamily | Graph 2 (older data) |
| Preliminary: "Permitting times" | Processing-time chart; medians of 518–1,000 days for mature cohorts; 19 of 59 pending projects permitted, averaging 661 days (median 548) | Graph 3 |

Nothing in either brief visibly uses `council_district_analysis.R` or the plots from `renthub_visualizations.R` other than the rent-gap figure. When updating a number in a brief, re-derive it from the script and the current data, and say which data snapshot it comes from. The final brief's Figure 1 note says "data through early September".

## Domain conventions

- Use "ROH Chapter 32", "CH32" and "Bill 7" for the same program, consistently with the surrounding code. The comparison group is "Non-ROH Chapter 32 Baseline".
- The baseline must not overlap CH32: CH32 permit numbers are always filtered out of it.
- `posse_freeze_date = 2025-07-28` is when DPP's Posse system stopped updating. Open reviews are cut off at that date.
- Application years 2023 and later are flagged "Incomplete/Censored", because recent cohorts only show their fastest permits. Graph 5 drops years 2025 and later. "Zombie" projects (in review with more than 120 days since the last action) are excluded from the timing figures.
- TMKs are cleaned with `-`/`:` removed and zero-padded to 8 digits. Baseline permits may hold several TMKs in one cell. `council_district_analysis.R` splits, matches and re-collapses them.
- Spatial work uses EPSG:4326 for joins and EPSG:32604 (UTM 4N) for the 0.5-mile buffers.

## Styling

UHERO branding: Gotham and Trajan fonts loaded from `fonts/` with `showtext`, and colors dark blue `#1D667F`, light blue `#7EC4CA`, gray `#505050`, gold `#F6A01B`, green `#9BBB59` and purple `#8064A2` (canceled/withdrawn). Every R script defines its own copy of `theme_uhero()`, and the copies' font sizes differ slightly. If you change one, ask whether the others should match.
