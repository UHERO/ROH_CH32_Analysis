# =========================================================
# Project: Non-Chapter 32 Baseline Dataset Generation
# Author: Rafael Munoz, Graduate Assistant, UHERO
# Assistance: Gemini AI
#
# PURPOSE:
#   Generates a multifamily housing pipeline dataset (>= 2018)
#   that is mutually exclusive from Chapter 32 permits,
#   formatted to match the ROH32 data structure for comparison.
#
# METHODOLOGY NOTE:
#   Unit counts missing from the source (DPP permits database) are
#   estimated using the median gross sqft per unit derived from
#   permits with complete data (~1,112 sqft/unit). Estimated rows
#   are flagged in the "Units Estimated?" column. As of this run,
#   ~25.6% of total units are estimated, concentrated in the
#   "Approved & Permitted" status category, reflecting source data
#   limitations.
#
# OUTPUT: outputs/DHLM_Non_CH32_Baseline_Projects.csv
# =========================================================

library(tidyverse)
library(lubridate)

# 1. LOAD DATA
permits_data <- read_csv("data/hnlpermits_with_status_0625.csv", show_col_types = FALSE)
roh32_data <- read_csv("data/roh32_complete_cleaned (1).csv", show_col_types = FALSE)

# 2. EXTRACT ROH32 PERMITS
roh32_permit_numbers <- unique(as.character(na.omit(roh32_data$`Building permit #`)))

# =========================================================
# 3. STRICT COLUMN VALIDATION (Fails early if data changes)
# =========================================================
required_cols <- c("buildingpermitno", "year_created", "status_category", "newbuilding", 
                   "buildingpermittype", "occupancygroupcategory", "proposeduse", 
                   "numunitsadd", "totalfloorarea", "tmk", "address", "applicant", 
                   "contractor", "createddate", "coissued")

missing_cols <- setdiff(required_cols, colnames(permits_data))
if(length(missing_cols) > 0) {
  stop(paste("CRITICAL ERROR: Missing expected columns in baseline data:", paste(missing_cols, collapse = ", ")))
}

# =========================================================
# 4. FILTER NON-CH32 BASELINE MULTIFAMILY
# =========================================================
baseline_mf_filtered <- permits_data %>%
  mutate(buildingpermitno_chr = as.character(buildingpermitno)) %>%
  filter(!buildingpermitno_chr %in% roh32_permit_numbers) %>%
  filter(year_created >= 2018) %>%
  filter(!status_category %in% c("Rejected/Cancelled", "Approved Then Revoked")) %>%
  filter(
    newbuilding == "Y" | 
    str_detect(replace_na(toupper(buildingpermittype), ""), "NEW")
  ) %>%
  filter(
    str_detect(replace_na(toupper(occupancygroupcategory), ""), "R-1|R-2|R1|R2|APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT") | 
    str_detect(replace_na(toupper(proposeduse), ""), "APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT|TOWNHOUSE")
  )

# =========================================================
# 5. DATA-DRIVEN UNIT ESTIMATION (Rafael's Method)
# =========================================================
# First, find the real median sqft per unit from projects where we have complete data
valid_size_data <- baseline_mf_filtered %>%
  mutate(
    u = as.numeric(numunitsadd),
    a = as.numeric(totalfloorarea)
  ) %>%
  filter(!is.na(u), u > 0, !is.na(a), a > 0) %>%
  mutate(gross_sqft_per_unit = a / u)

empirical_sqft_per_unit <- median(valid_size_data$gross_sqft_per_unit, na.rm = TRUE)

print(paste("Data-Driven Median Gross SqFt per Unit:", round(empirical_sqft_per_unit, 1)))

# Now apply this empirical ratio to the missing units
baseline_mf_units <- baseline_mf_filtered %>%
  mutate(
    stated_units = as.numeric(numunitsadd),
    stated_units = ifelse(is.na(stated_units) | stated_units < 0, 0, stated_units),
    
    clean_floorarea = as.numeric(totalfloorarea),
    clean_floorarea = ifelse(is.na(clean_floorarea) | clean_floorarea < 0, 0, clean_floorarea),
    
    # Estimate using the dataset's actual median
    estimated_units = case_when(
      clean_floorarea > 0 ~ floor(clean_floorarea / empirical_sqft_per_unit),
      TRUE ~ 0
    ),
    
    Final_Units = ifelse(stated_units > 0, stated_units, estimated_units),
    Units_Imputed = ifelse(stated_units == 0 & estimated_units > 0, TRUE, FALSE)
  ) %>%
  filter(Final_Units > 0)

# =========================================================
# 6. MAP TO ROH CH32 STRUCTURE & DEDUPLICATE
# =========================================================
baseline_export <- baseline_mf_units %>%
  transmute(
    `Building permit #` = buildingpermitno_chr,
    `BP Application Date` = as.character(createddate), 
    `Year` = year_created,
    
    # Standardize statuses exactly as UHERO did in the Bill 7 analysis
    `Project Status` = case_when(
      coissued == "Y" ~ "Constructed (CO Issued)",
      status_category %in% c("Active/Approved", "Approved Pending Issue", "Completed Successfully") & coissued == "N" ~ "Approved & Permitted",
      status_category %in% c("Under Review", "Administrative", "Other") ~ "In Application Review",
      TRUE ~ "Unknown"
    ),
    
    `Units` = Final_Units,
    `Units Estimated?` = ifelse(Units_Imputed, "Yes", "No"),
    `TMK` = tmk,
    `Address` = address,
    `Floor Area (sqft)` = clean_floorarea,
    `Project Type/Use` = proposeduse,
    
    # Developer Capacity Tracking Variables
    Applicant = applicant,
    Contractor = contractor
  ) %>%
  # DEDUPLICATION FIX: Give NA permit numbers a unique temporary ID 
  # so they don't collapse into each other!
  mutate(dedup_id = ifelse(is.na(`Building permit #`), paste0("PENDING_", row_number()), `Building permit #`)) %>%
  group_by(dedup_id) %>%
  slice(1) %>%
  ungroup() %>%
  select(-dedup_id) # Remove the temporary ID column

# =========================================================
# 7. AUTOMATED DATA INTEGRITY TESTS
# =========================================================
print("=== Running Strict Data Integrity Tests ===")

# Test 1: Leakage check
leaked_permits <- intersect(baseline_export$`Building permit #`, roh32_permit_numbers)
stopifnot("FAIL: Bill 7 permits leaked into baseline!" = length(leaked_permits) == 0)
print("PASS: Baseline is mutually exclusive from Chapter 32.")

# Test 2: Unit Logic check
stopifnot("FAIL: Zero or negative units found!" = all(baseline_export$Units > 0))
print("PASS: All exported permits have > 0 units.")

# Test 3: Math check for Empirical logic
imputed_rows <- baseline_export %>% filter(`Units Estimated?` == "Yes")
if(nrow(imputed_rows) > 0) {
  math_check <- all(imputed_rows$Units == floor(imputed_rows$`Floor Area (sqft)` / empirical_sqft_per_unit))
  stopifnot("FAIL: Empirical formula applied incorrectly!" = math_check)
}
print("PASS: Imputed units strictly match the data-driven median.")

# Test 4: Year bounds
stopifnot("FAIL: Found permits older than 2018!" = all(baseline_export$Year >= 2018))
print("PASS: All permits strictly >= 2018.")

# Test 5: Missing uniqueness (Ignoring NAs for pending projects)
duplicate_bids <- baseline_export %>% 
  filter(!is.na(`Building permit #`)) %>%  # Ignore pending projects with no ID yet
  count(`Building permit #`) %>% 
  filter(n > 1)

stopifnot("FAIL: Duplicate actual building permits found!" = nrow(duplicate_bids) == 0)
print("PASS: All issued building permits are unique.")

# =========================================================
# 8. EXPORT
# =========================================================
if(!dir.exists("outputs")) dir.create("outputs")
write_csv(baseline_export, "outputs/DHLM_Non_CH32_Baseline_Projects.csv")

print("=== EXPORT SUCCESSFUL ===")
print(paste("Total Baseline Projects Exported:", nrow(baseline_export)))
print(paste("Total Baseline Units Exported:", sum(baseline_export$Units, na.rm = TRUE)))
print(paste("Total Units estimated using the median formula:", nrow(imputed_rows)))