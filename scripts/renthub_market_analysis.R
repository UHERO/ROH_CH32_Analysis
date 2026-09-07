# ==============================================================================
# Project: Honolulu Bill 7 Market Feasibility & Spatial Analysis
# Author: Rafael Munoz, Graduate Assistant, UHERO
# 
# Purpose & Methodology: 
#   This script evaluates whether Honolulu's "Bill 7" affordable housing policy
#   results in a true financial penalty for developers. By analyzing 3 years of 
#   scraped rental listings, it compares the legal "Affordable" rent guidelines 
#   (100% Area Median Income) against the actual open-market rents in the 
#   specific urban neighborhoods where these projects are built.
#
# Key Steps:
#   1. Clean 3 years of stacked RentHub data (2023-2026).
#   2. Calculate Sub-Area market rents (Macro-level).
#   3. Perform a 0.5-mile spatial buffer around Bill 7 projects (Neighborhood-level).
#   4. Use City Building Permits to isolate New Construction (2015+) for fair comps.
#   5. Use exact regex address matching to extract verified, actual Bill 7 rent prices.
# ==============================================================================

library(tidyverse)
library(sf)
library(lubridate)

# Define Hawaii-specific projected coordinate system for accurate distance buffering (UTM Zone 4N)
# This ensures our 0.5-mile buffers are perfectly circular and measured in meters.
crs_hawaii_projected <- 32604 

# ==============================================================================
# 1. LOAD & DE-DUPLICATE DATA
# ==============================================================================
print("Loading data...")

# We load a stacked dataset covering 3 years (2023-2026) instead of just 1 month.
# WHY: Apartments are only listed when vacant. A 3-year net ensures we capture historical 
# listings for Bill 7 buildings that might currently be 100% occupied.
renthub_raw_stacked <- read_csv("data/renthub_combined_2024_2026.csv", show_col_types = FALSE)

# CRITICAL: Remove duplicates. An apartment might sit on Zillow for 3 months, 
# appearing in multiple scrapes. We sort by timestamp and keep only the newest listing price.
renthub_raw <- renthub_raw_stacked %>%
  arrange(desc(`scraped timestamp`)) %>%
  distinct(`property id`, `unit id`, .keep_all = TRUE)

# Load cleaned Bill 7 Application Dataset
b7_data <- read_csv("data/roh32_complete_cleaned (1).csv", show_col_types = FALSE) %>%
  filter(!is.na(`Building permit #`))

# Load Honolulu City Council Districts for macro-level comparisons
council_districts <- st_read("data/Honolulu_County_Council_Districts.geojson", quiet = TRUE) %>%
  st_transform(4326) %>%
  st_make_valid()

# --- INTEGRITY TEST 1 ---
stopifnot(
  "FAIL: RentHub data is empty" = nrow(renthub_raw) > 0,
  "FAIL: Bill 7 data missing coordinates" = "geometry" %in% names(b7_data)
)
print("PASS: Raw data loaded successfully.")

# ==============================================================================
# 2. CLEAN RENT HUB DATA
# ==============================================================================
renthub_clean <- renthub_raw %>%
  # Filter strictly to Oahu using a bounding box. 
  # WHY: RentHub covers the whole state. This isolates Honolulu County cleanly.
  filter(latitude > 21.2 & latitude < 21.8 & longitude > -158.3 & longitude < -157.6) %>%
  
  rename(
    rent_price = `rent price`,
    building_type = `building type`
  ) %>%
  
  # Data Cleaning & Outlier Removal
  # WHY: Scraped data often contains typos (e.g., $1 daily parking rates or $50,000 mansions).
  # We cap it to reasonable residential limits so our medians aren't skewed.
  filter(
    !is.na(latitude), !is.na(longitude),
    !is.na(rent_price),
    rent_price >= 500,  
    rent_price <= 10000 
  ) %>%
  
  # Normalize addresses to uppercase and remove extra spaces for easier matching later
  mutate(
    rent_per_bed = ifelse(beds > 0, rent_price / beds, rent_price),
    rent_per_sqft = ifelse(!is.na(sqft) & sqft > 100, rent_price / sqft, NA),
    clean_address = str_squish(str_to_upper(address))
  )

print(paste("PASS: RentHub data cleaned. Remaining Oahu listings:", nrow(renthub_clean)))

# Convert cleaned RentHub dataframe to a spatial 'sf' object mapping the GPS coordinates
renthub_sf <- st_as_sf(renthub_clean, coords = c("longitude", "latitude"), crs = 4326)

# ==============================================================================
# 3. TASK A: MACRO-LEVEL MARKET RENTS (BY COUNCIL DISTRICT)
# ==============================================================================
# Join each listing to its respective Council District via spatial intersection
renthub_districts <- st_join(renthub_sf, council_districts, join = st_intersects, left = FALSE)

district_market_baseline <- renthub_districts %>%
  st_drop_geometry() %>%
  group_by(distname) %>%
  summarize(
    total_active_listings = n(),
    median_rent_all = median(rent_price, na.rm = TRUE),
    median_rent_1bed = median(rent_price[beds == 1], na.rm = TRUE),
    median_rent_2bed = median(rent_price[beds == 2], na.rm = TRUE),
    median_rent_per_sqft = median(rent_per_sqft, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(median_rent_all))

# ==============================================================================
# 4. TASK B: REASSEMBLE MULTI-UNIT BUILDINGS BY ADDRESS
# ==============================================================================
# Aggregate individual apartment listings back into whole buildings based on address
reassembled_buildings <- renthub_clean %>%
  group_by(clean_address, zip) %>%
  summarize(
    listings_in_building = n(),
    building_median_rent = median(rent_price, na.rm = TRUE),
    min_rent = min(rent_price, na.rm = TRUE),
    max_rent = max(rent_price, na.rm = TRUE),
    avg_beds = mean(beds, na.rm = TRUE),
    lat = first(latitude),
    lon = first(longitude),
    .groups = "drop"
  ) %>%
  filter(listings_in_building >= 3) %>% # A "building" must have multiple listings
  arrange(desc(listings_in_building))

# ==============================================================================
# 5. TASK C: THE BILL 7 FEASIBILITY GAP (0.5 MILE BUFFER)
# ==============================================================================
# Isolate Bill 7 coordinates and project to meters (UTM 4N)
b7_sf <- st_as_sf(b7_data, wkt = "geometry", crs = 4326) %>%
  select(`Building permit #`, `Property Address`, `Project Status`, `Units`)

b7_sf_proj <- st_transform(b7_sf, crs_hawaii_projected)
renthub_sf_proj <- st_transform(renthub_sf, crs_hawaii_projected)

# Draw an 800-meter (~0.5 mile) buffer around every single Bill 7 project.
# WHY: 0.5 miles represents roughly a 10-minute walk. This gives us the true, localized 
# neighborhood market rate, rather than an island-wide average.
b7_buffers <- st_buffer(b7_sf_proj, dist = 800)
b7_market_context <- st_join(b7_buffers, renthub_sf_proj, join = st_intersects, left = TRUE)

# Official 2026 HHFDC Affordable Rent Guidelines for Honolulu (100% AMI)
# Note: Bill 7 requires at least 80% of units to be restricted to 100% AMI.
ami_100_studio_cap <- 2695
ami_100_1bed_cap <- 2887

bill7_feasibility_gap <- b7_market_context %>%
  st_drop_geometry() %>%
  group_by(`Building permit #`, `Property Address`, `Units`) %>%
  summarize(
    comp_listings_within_half_mile = sum(!is.na(rent_price)),
    surrounding_market_median_rent = median(rent_price, na.rm = TRUE),
    surrounding_market_1bed_rent = median(rent_price[beds == 1], na.rm = TRUE),
    surrounding_market_studio_rent = median(rent_price[beds == 0], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    surrounding_market_1bed_rent = ifelse(is.na(surrounding_market_1bed_rent), 0, surrounding_market_1bed_rent),
    surrounding_market_studio_rent = ifelse(is.na(surrounding_market_studio_rent), 0, surrounding_market_studio_rent),
    
    # CALCULATING THE FEASIBILITY GAP
    # If the local market rent is ALREADY lower than the 100% HHFDC guideline, 
    # the developer is gaining density bonuses without taking a financial penalty.
    feasibility_gap_1bed = surrounding_market_1bed_rent - ami_100_1bed_cap,
    feasibility_gap_studio = surrounding_market_studio_rent - ami_100_studio_cap,
    
    market_dynamic_1bed = case_when(
      comp_listings_within_half_mile == 0 ~ "No Comps Available",
      feasibility_gap_1bed > 0 ~ "Guideline is Below Market (Developer Penalty)",
      feasibility_gap_1bed <= 0 ~ "Guideline is Above/Equal to Market (No Penalty)"
    )
  ) %>%
  arrange(desc(feasibility_gap_1bed))

# ==============================================================================
# 6. EXPORT STANDARD ANALYSES
# ==============================================================================
if(!dir.exists("outputs")) dir.create("outputs")
write_csv(district_market_baseline, "outputs/RentHub_Council_District_Market_Rents.csv")
write_csv(reassembled_buildings, "outputs/RentHub_Reassembled_Buildings.csv")
write_csv(bill7_feasibility_gap, "outputs/Bill7_Feasibility_Gap_Half_Mile_Radius.csv")

# ==============================================================================
# 7. AGE CONTROL VIA PERMIT DATA (FAIR COMPARISONS)
# ==============================================================================
print("Loading Permit Data for Age Control...")

# WHY: Comparing brand-new Bill 7 buildings against 50-year-old walk-ups is a flawed comparison.
# Because scraped RentHub listings rarely include a "Year Built" column, we use City Building 
# Permits to identify which RentHub addresses correspond to authentic New Construction.
hnl_permits <- read_csv("data/hnlpermits_with_status_0625.csv", show_col_types = FALSE)

new_build_permits <- hnl_permits %>%
  filter(year_created >= 2015) %>%
  filter(newbuilding == "Y" | numunitsadd > 0) %>%
  mutate(
    base_address = str_to_upper(address),
    base_address = str_remove(base_address, "\\s+(HONOLULU|WAHIAWA|EWA|WAIPAHU|KAILUA|MILILANI|KAPOLEI|PEARL|AIEA|KANEOHE).*"),
    base_address = str_squish(base_address)
  ) %>%
  distinct(base_address, .keep_all = TRUE) 

renthub_sf_tagged <- renthub_sf %>%
  mutate(
    # Strip unit/apt numbers so the base street address matches the permit record
    base_rent_address = str_remove(clean_address, "\\s+(APT|UNIT|STE|#|PH).*"),
    base_rent_address = str_squish(base_rent_address)
  ) %>%
  left_join(new_build_permits %>% select(base_address, permit_year = year_created), 
            by = c("base_rent_address" = "base_address")) %>%
  mutate(is_new_construction = !is.na(permit_year)) # Flag as TRUE if it linked to a 2015+ permit

# Recalculate the 0.5-mile market context STRICTLY against newly built apartments
renthub_new_sf_proj <- renthub_sf_tagged %>%
  filter(is_new_construction == TRUE) %>%
  st_transform(crs_hawaii_projected)

b7_market_new_comps <- st_join(b7_buffers, renthub_new_sf_proj, join = st_intersects, left = TRUE)

b7_new_market_summary <- b7_market_new_comps %>%
  st_drop_geometry() %>%
  group_by(`Building permit #`, `Property Address`) %>%
  summarize(
    new_comps_within_half_mile = sum(!is.na(rent_price)),
    local_market_new_1bed_rent = median(rent_price[beds == 1], na.rm = TRUE),
    .groups = "drop"
  )

# ==============================================================================
# 8. EXTRACT ACTUAL BILL 7 RENTS (EXACT ADDRESS MATCHING)
# ==============================================================================
print("Extracting Actual Bill 7 Rents via Address Matching...")

# WHY: We need to know what Bill 7 developers are ACTUALLY charging.
# We use regex to standardize address suffixes (STREET -> ST) and strip hyphens 
# so the Bill 7 Database links perfectly to the RentHub scraping output.

# 8a. Standardize Bill 7 Addresses
b7_addresses <- b7_data %>%
  select(`Building permit #`, `Property Address`) %>%
  mutate(
    street_address = str_extract(`Property Address`, "^[^,]+"),
    street_address = str_to_upper(street_address),
    
    # Strip trailing periods (e.g., "AVE." -> "AVE")
    street_address = str_remove(street_address, "\\.$"),
    # Strip hyphenated unit letters off house numbers (e.g., "1809-A DOLE ST" -> "1809 DOLE ST")
    street_address = str_replace(street_address, "^(\\d+)-[A-Z]\\b", "\\1"),
    
    # Standardize road type nomenclature
    match_address = str_replace_all(street_address, "\\bSTREET\\b", "ST"),
    match_address = str_replace_all(match_address, "\\bAVENUE\\b", "AVE"),
    match_address = str_replace_all(match_address, "\\bROAD\\b", "RD"),
    match_address = str_replace_all(match_address, "\\bPLACE\\b", "PL"),
    match_address = str_replace_all(match_address, "\\bBOULEVARD\\b", "BLVD"),
    match_address = str_replace_all(match_address, "\\bDRIVE\\b", "DR"),
    match_address = str_squish(match_address)
  )

# 8b. Standardize RentHub Addresses to match
renthub_match <- renthub_clean %>%
  mutate(
    match_address = str_remove(clean_address, "\\s+(APT|UNIT|STE|#|PH).*"),
    match_address = str_remove(match_address, "\\.$"),
    match_address = str_replace(match_address, "^(\\d+)-[A-Z]\\b", "\\1"),
    match_address = str_squish(match_address)
  )

# 8c. Join based on the exact matching string
b7_actual_summary <- b7_addresses %>%
  inner_join(renthub_match, by = "match_address") %>%
  group_by(`Building permit #`, `Property Address`) %>%
  summarize(
    actual_b7_listings_found = sum(!is.na(rent_price)),
    actual_b7_1bed_rent = median(rent_price[beds == 1], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(actual_b7_listings_found > 0)

# Merge with the localized 0.5mi new construction comps from Step 7
final_dumbbell_data <- b7_new_market_summary %>%
  inner_join(b7_actual_summary, by = c("Building permit #", "Property Address")) %>%
  # Exclude unbuilt projects to prevent false positives from neighboring buildings
  filter(`Building permit #` != "Not Issued") %>%
  filter(!is.na(actual_b7_1bed_rent) & !is.na(local_market_new_1bed_rent))

write_csv(final_dumbbell_data, "outputs/Bill7_Dumbbell_Plot_Data_ExactMatch.csv")
print("SUCCESS: Exact address matching completed. Pipeline finished.")