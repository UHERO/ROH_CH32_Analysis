# ROH Chapter 32 (Bill 7) Pipeline Analysis

**Author:** Rafael Munoz (UHERO Graduate Assistant) w/ Gemini AI Assistance
**Date:** April 2026  


## Overview
This repository contains the analysis pipeline, web scrapers, and data compilation scripts used to evaluate the City and County of Honolulu's ROH Chapter 32 (Bill 7) affordable housing program. 

The pipeline compares Chapter 32 multifamily permit processing times and construction volumes against a non-Chapter 32 baseline, isolating developer revision time from agency processing time to track progress against the statutory 90-day shot clock.

---

### Data Location
To run these scripts, ensure you have access to the UHERO NAS and download/reference the data from the following directory:
`UHEROroot\work\research\housing\factbook\ROH Chapter 32 Analysis`

**Required Datasets:**
1. `hnlpermits_with_status_0625.csv`: Baseline DPP permit database.
2. `roh32_complete_cleaned (1).csv`: Cleaned dataset of Chapter 32 specific permits.
3. `MASTER_Metrics.csv`: Compiled scraper output of milestone dates.
4. `MASTER_Plan_Reviews.csv`: Compiled scraper output of agency review timelines.

---

## Repository Structure

```text
├── .gitignore              # Prevents data and figures from uploading
├── README.md               # Project documentation
├── scripts/                
│   ├── dpp_metrics_plan_reviews_scraper.py      # Selenium web scraper for DPP Posse site
│   ├── dpp_csv_compiler.py         # Merges individual scraper outputs into MASTER files
│   └── roh_ch32_analysis.R # Main R script generating formatted GGPlot visualizations
└── fonts/                  # Custom UHERO branding fonts
    ├── Gotham-Bold.ttf
    ├── Gotham-Regular.ttf
    ├── TrajanPro-Bold.otf
    └── TrajanPro-Regular.otf
