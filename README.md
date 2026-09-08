# Honolulu Affordable Housing Policy Evaluation (ROH Chapter 32)

**Author:** Rafael Munoz with Gemini AI Assistance
**Role:** Graduate Research Assistant, UHERO (University of Hawai'i Economic Research Organization)  
**Date:** April 2026

## Executive Summary
This repository contains the end-to-end data work, geospatial analysis, and automated web scrapers used to evaluate the economic feasibility and bureaucratic processing efficiency of the City and County of Honolulu's ROH Chapter 32 (Bill 7) affordable housing program.

The pipeline proves whether the policy's statutory rent caps (100% Area Median Income) impose a genuine financial penalty on developers or function as a density loophole by comparing statutory limits against localized open-market rents.

## Repository Structure
```text
├── data/                                 # Raw data (Ignored via .gitignore)
├── fonts/                                # UHERO brand typography
├── outputs/                              # Generated CSVs and PNGs (Ignored)
├── scripts/                
│   ├── dpp_metrics_plan_reviews_scraper.py   # Selenium web scraper for DPP Posse site
│   ├── dpp_csv_compiler.py                   # Merges individual scraper outputs
│   ├── baseline-comparison-export.R          # Generates non-ROH32 control group
│   ├── council_district_analysis.R           # Geospatial assignment of permits
│   ├── renthub_market_analysis.R             # 0.5-mile spatial buffering for rent comps
│   ├── renthub_visualizations.R              # Renders comparative charts
│   └── roh_ch32_analysis.R                   # Main R script generating GGPlot visualizations
├── .gitignore
└── README.md
```

## Setup & Prerequisites
To replicate this pipeline, ensure the following environments and dependencies are installed.

**Python 3.10+ (Scraping & Aggregation)**
* `selenium`, `webdriver-manager` (Chrome WebDriver is automatically handled)
* `pandas`

**R 4.2+ (Spatial & Econometric Analysis)**
* `tidyverse`, `lubridate`, `scales` (Data wrangling and visualization)
* `sf` (Geospatial buffer operations and projections)
* `showtext` (Custom typography rendering)

## Execution Pipeline

The scripts must be executed in the following sequential order to ensure data integrity:

1. **Data Ingestion:** Run `dpp_metrics_plan_reviews_scraper.py` to extract raw application data, followed by `dpp_csv_compiler.py` to flatten the output into master CSVs.
2. **Baseline Generation:** Run `baseline-comparison-export.R` to establish the control group dataset.
3. **Geospatial Processing:** Run `council_district_analysis.R` and `renthub_market_analysis.R` to execute the spatial joins and calculate the 100% AMI feasibility gaps.
4. **Visualization:** Run `renthub_visualizations.R` and `roh_ch32_analysis.R` to render the final UHERO-branded graphics.

## Outputs
Execution of the pipeline generates institutional-grade deliverables into the `/outputs/` directory.

## Data Access Limitations
The raw datasets (e.g., `hnlpermits_with_status_0625.csv`, `renthub_combined_2024_2026.csv`) are proprietary/internal to UHERO, and are therefore omitted from this repository.
