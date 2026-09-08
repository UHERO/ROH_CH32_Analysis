# Honolulu Affordable Housing Policy Evaluation (ROH Chapter 32)

**Author:** Rafael Munoz w/ Gemini AI Assitance
**Role:** Graduate Research Assistant, UHERO (University of Hawaii Economic Research Organization)  
**Date:** April 2026

## Executive Summary
This repository contains the end-to-end data engineering pipeline, geospatial analysis, and automated web scrapers used to evaluate the economic feasibility and bureaucratic processing efficiency of the City and County of Honolulu's ROH Chapter 32 (Bill 7) affordable housing program.

The pipeline proves whether the policy's statutory rent caps (100% AMI) impose a genuine financial penalty on developers or function as a density loophole by comparing statutory limits against localized open-market rents.

## Technical Architecture & Stack
This project operates across two languages to leverage their respective strengths:

* **Python (Data Ingestion & Automation):** Utilizes `Selenium` and `Pandas` to scrape undocumented government portals (DPP Posse). It extracts, flattens, and compiles asynchronous permitting milestones and plan review timelines into structural dataframes.
* **R (Geospatial & Econometric Analysis):** Utilizes `sf` and `tidyverse` to perform spatial joins (0.5-mile localized neighborhood buffers) and coordinate projections (UTM Zone 4N) to match active market listings against new construction permits. 

## Core Methodologies
1. **Automated Web Scraping:** Bypasses legacy government databases to extract real-time application processing metrics.
2. **Geospatial Neighborhood Buffering:** Matches new affordable housing coordinates to authentic neighborhood market rates within an 800-meter radius, eliminating island-wide statistical skew.
3. **Data-Driven Imputation:** Uses empirical medians (1,112 sqft/unit) to accurately estimate missing housing unit data across baseline multifamily permits.

## Data Access Note
*The raw datasets (e.g., `hnlpermits_with_status_0625.csv`, `renthub_combined_2024_2026.csv`) are proprietary/internal to UHERO and the City of Honolulu, and are therefore omitted from this repository via `.gitignore`. The code is provided to demonstrate the pipeline architecture and spatial analysis methodology.*