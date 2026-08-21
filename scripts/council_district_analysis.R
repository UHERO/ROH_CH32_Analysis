# =========================================================
# Project: ROH CH32 Council District Spatial Analysis
# Author: Rafael Munoz, Graduate Assistant, UHERO
# Assistance: Gemini AI
# Purpose:
#   Spatially match ROH Chapter 32 / Bill 7 permits and
#   non-ROH multifamily baseline permits to Honolulu City
#   Council Districts.
#
# Key design choices:
#   1. ROH permits already have point geometry.
#   2. Baseline permits are matched to parcel geometries by TMK.
#   3. Some baseline permits contain multiple TMKs in one cell.
#      These are split, matched, then collapsed back to one permit row.
#   4. Some baseline TMKs do not exist in the parcel file.
#      Those are reported as unmatched data limitations.
# =========================================================

# =========================================================
# 1. LOAD LIBRARIES
# =========================================================

library(tidyverse)
library(sf)
library(showtext)
library(lubridate)

# =========================================================
# 2. UHERO STYLE SETUP
# =========================================================

font_add(
  family = "Trajan",
  regular = "fonts/TrajanPro-Regular.otf",
  bold = "fonts/TrajanPro-Bold.otf"
)

font_add(
  family = "Gotham",
  regular = "fonts/Gotham-Regular.ttf",
  bold = "fonts/Gotham-Bold.ttf"
)

showtext_auto()

uhero_dark_blue  <- "#1D667F"
uhero_light_blue <- "#7EC4CA"
uhero_gray       <- "#505050"
uhero_gold       <- "#F6A01B"
uhero_green      <- "#9BBB59"

theme_uhero <- function(base_size = 14) {
  theme_minimal(base_size = base_size) +
    theme(
      legend.position = "bottom",
      
      plot.title = element_text(
        family = "Gotham",
        face = "bold",
        size = 16,
        color = uhero_dark_blue
      ),
      
      plot.subtitle = element_text(
        family = "Gotham",
        size = 12,
        color = uhero_gray
      ),
      
      plot.caption = element_text(
        family = "Gotham",
        face = "italic",
        color = uhero_gray,
        hjust = 0
      ),
      
      axis.title = element_text(
        family = "Gotham",
        face = "bold",
        size = 20,
        color = uhero_gray
      ),
      
      axis.text = element_text(
        family = "Gotham",
        size = 16,
        color = uhero_gray
      ),
      
      legend.title = element_text(
        family = "Gotham",
        face = "bold",
        size = 20,
        color = uhero_gray
      ),
      
      legend.text = element_text(
        family = "Gotham",
        size = 18,
        color = uhero_gray
      ),
      
      panel.grid.major.x = element_blank()
    )
}

# =========================================================
# 3. LOAD DATA
# =========================================================

permits_raw <- read_csv(
  "data/hnlpermits_with_status_0625.csv",
  show_col_types = FALSE
)

roh32_data <- read_csv(
  "data/roh32_complete_cleaned (1).csv",
  show_col_types = FALSE
)

council_districts <- st_read(
  "data/Honolulu_County_Council_Districts.geojson",
  quiet = TRUE
) %>%
  st_transform(4326) %>%
  st_make_valid()

parcels <- st_read(
  "data/Parcels_-_Honolulu_County_(Island_of_Oahu).geojson",
  quiet = TRUE
) %>%
  st_transform(4326)

# =========================================================
# 4. STANDARDIZE PERMIT IDS AND TMKS
# =========================================================
# Important:
#   The baseline permit data sometimes stores multiple TMKs
#   in one cell, for example:
#
#     "23002110, 23002109"
#
#   The script extracts valid 8- or 9-digit TMKs only.
#   This avoids keeping junk values like "*133396".
#
#   We create original_permit_row_id BEFORE splitting TMKs.
#   This lets us collapse back to one row per original permit later.

permits_data <- permits_raw %>%
  mutate(
    original_permit_row_id = row_number(),
    buildingpermitno_chr = as.character(buildingpermitno),
    tmk_raw = as.character(tmk),
    
    # Extract all 8- or 9-digit strings from the TMK field.
    # This is safer than comma-splitting because some cells contain
    # symbols, asterisks, notes, or malformed fragments.
    tmk_list = str_extract_all(tmk_raw, "\\d{8,9}")
  ) %>%
  unnest_longer(
    tmk_list,
    values_to = "tmk_clean",
    keep_empty = TRUE
  ) %>%
  mutate(
    # Convert extracted TMKs to clean character strings.
    tmk_clean = as.character(tmk_clean),
    
    # Honolulu parcel file has both:
    #   tmk    = 8-digit TMK
    #   tmk9txt = 9-digit TMK with leading island code
    #
    # We keep both formats.
    tmk_8_digit = case_when(
      nchar(tmk_clean) == 8 ~ tmk_clean,
      nchar(tmk_clean) == 9 ~ str_sub(tmk_clean, 2, 9),
      TRUE ~ NA_character_
    ),
    
    tmk_9_digit = case_when(
      nchar(tmk_clean) == 8 ~ paste0("1", tmk_clean),
      nchar(tmk_clean) == 9 ~ tmk_clean,
      TRUE ~ NA_character_
    )
  )

roh32_data <- roh32_data %>%
  mutate(
    building_permit_chr = as.character(`Building permit #`)
  )

# =========================================================
# 5. PREP ROH CHAPTER 32 / BILL 7 SPATIAL DATA
# =========================================================
# ROH data already has WKT point geometry in the geometry column.
# We parse application dates to create year_created.

roh32_data <- roh32_data %>%
  mutate(
    BP_App_Date = parse_date_time(
      `BP Application Date`,
      orders = c("mdy", "dmy", "ymd")
    ),
    year_created = year(BP_App_Date)
  )

roh32_sf <- st_as_sf(
  roh32_data,
  wkt = "geometry",
  crs = 4326
)

# =========================================================
# 6. PREP NON-ROH MULTIFAMILY BASELINE DATA
# =========================================================
# Logic:
#   1. Exclude ROH Chapter 32 / Bill 7 permits.
#   2. Keep permits from 2018 onward.
#   3. Remove rejected, cancelled, or revoked permits.
#   4. Keep new buildings.
#   5. Keep multifamily-like residential uses.
#   6. Keep positive unit additions.
#
# Note:
#   Because we split multiple TMKs above, one original permit row
#   may now appear multiple times. That is okay for matching.
#   We collapse back to one original permit later.

baseline_mf_data <- permits_data %>%
  filter(!buildingpermitno_chr %in% roh32_data$building_permit_chr) %>%
  filter(year_created >= 2018) %>%
  filter(!status_category %in% c("Rejected/Cancelled", "Approved Then Revoked")) %>%
  filter(
    newbuilding == "Y" |
      str_detect(replace_na(toupper(buildingpermittype), ""), "NEW")
  ) %>%
  filter(
    str_detect(
      replace_na(toupper(occupancygroupcategory), ""),
      "R-1|R-2|R1|R2|APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT"
    ) |
      str_detect(
        replace_na(toupper(proposeduse), ""),
        "APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT|TOWNHOUSE"
      )
  ) %>%
  filter(numunitsadd > 0, !is.na(numunitsadd))

# =========================================================
# 7. BASELINE FILTER DIAGNOSTICS
# =========================================================
# These counts show how the baseline sample is reduced step by step.

baseline_filter_diagnostics <- tibble(
  step = c(
    "Original permits",
    "Exclude ROH32",
    "Year >= 2018",
    "Remove rejected/cancelled/revoked",
    "New buildings only",
    "Multifamily-like use",
    "Positive units"
  ),
  rows = c(
    nrow(permits_data),
    
    permits_data %>%
      filter(!buildingpermitno_chr %in% roh32_data$building_permit_chr) %>%
      nrow(),
    
    permits_data %>%
      filter(!buildingpermitno_chr %in% roh32_data$building_permit_chr) %>%
      filter(year_created >= 2018) %>%
      nrow(),
    
    permits_data %>%
      filter(!buildingpermitno_chr %in% roh32_data$building_permit_chr) %>%
      filter(year_created >= 2018) %>%
      filter(!status_category %in% c("Rejected/Cancelled", "Approved Then Revoked")) %>%
      nrow(),
    
    permits_data %>%
      filter(!buildingpermitno_chr %in% roh32_data$building_permit_chr) %>%
      filter(year_created >= 2018) %>%
      filter(!status_category %in% c("Rejected/Cancelled", "Approved Then Revoked")) %>%
      filter(
        newbuilding == "Y" |
          str_detect(replace_na(toupper(buildingpermittype), ""), "NEW")
      ) %>%
      nrow(),
    
    permits_data %>%
      filter(!buildingpermitno_chr %in% roh32_data$building_permit_chr) %>%
      filter(year_created >= 2018) %>%
      filter(!status_category %in% c("Rejected/Cancelled", "Approved Then Revoked")) %>%
      filter(
        newbuilding == "Y" |
          str_detect(replace_na(toupper(buildingpermittype), ""), "NEW")
      ) %>%
      filter(
        str_detect(
          replace_na(toupper(occupancygroupcategory), ""),
          "R-1|R-2|R1|R2|APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT"
        ) |
          str_detect(
            replace_na(toupper(proposeduse), ""),
            "APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT|TOWNHOUSE"
          )
      ) %>%
      nrow(),
    
    nrow(baseline_mf_data)
  )
)

print("--- Baseline filter diagnostics ---")
print(baseline_filter_diagnostics)

# =========================================================
# 8. PREP PARCELS FOR MATCHING
# =========================================================
# Important:
#   Do NOT use st_union() here.
#   It caused geometry errors because some parcel polygons are invalid
#   or self-crossing.
#
# Instead:
#   - Keep one parcel geometry per 8-digit TMK.
#   - Use slice(1) to avoid duplicate parcel geometries.
#   - Use parcel representative points later for district assignment.

parcels_one_per_tmk <- parcels %>%
  filter(!is.na(tmk)) %>%
  group_by(tmk) %>%
  slice(1) %>%
  ungroup() %>%
  select(tmk, tmk9txt, taxpin, geometry)

# =========================================================
# 9. CHECK BASELINE TMK-TO-PARCEL MATCHES
# =========================================================
# This diagnostic tells us how many baseline rows and units can be
# spatially matched through the parcel layer.

parcel_keys <- parcels_one_per_tmk %>%
  st_drop_geometry() %>%
  transmute(parcel_match_key = tmk)

baseline_join_check <- baseline_mf_data %>%
  mutate(
    parcel_matched = !is.na(tmk_8_digit) &
      tmk_8_digit %in% parcel_keys$parcel_match_key
  )

print("--- Baseline parcel match check ---")
print(
  baseline_join_check %>%
    summarize(
      baseline_rows = n(),
      matched_rows = sum(parcel_matched),
      unmatched_rows = sum(!parcel_matched),
      baseline_units = sum(numunitsadd, na.rm = TRUE),
      matched_units = sum(numunitsadd[parcel_matched], na.rm = TRUE),
      unmatched_units = sum(numunitsadd[!parcel_matched], na.rm = TRUE)
    )
)

print("--- Largest unmatched baseline permits ---")
print(
  baseline_join_check %>%
    filter(!parcel_matched) %>%
    arrange(desc(numunitsadd)) %>%
    select(
      buildingpermitno,
      tmk,
      tmk_clean,
      tmk_8_digit,
      tmk_9_digit,
      numunitsadd,
      year_created,
      proposeduse,
      occupancygroupcategory
    ) %>%
    head(50)
)

# =========================================================
# 10. CONFIRM UNMATCHED TMKS REALLY ARE ABSENT
# =========================================================
# This confirms whether unmatched baseline TMKs exist in any common
# parcel identifier column.

unmatched_check <- baseline_join_check %>%
  filter(!parcel_matched) %>%
  mutate(
    tmk8_exists = tmk_8_digit %in% parcels$tmk,
    tmk9_exists = tmk_9_digit %in% parcels$tmk9txt,
    taxpin_exists = suppressWarnings(as.integer(tmk_8_digit)) %in% parcels$taxpin
  ) %>%
  select(
    buildingpermitno,
    tmk,
    tmk_clean,
    tmk_8_digit,
    tmk_9_digit,
    numunitsadd,
    year_created,
    tmk8_exists,
    tmk9_exists,
    taxpin_exists
  )

print("--- Unmatched baseline TMK existence check ---")
print(
  unmatched_check %>%
    summarize(
      rows = n(),
      units = sum(numunitsadd, na.rm = TRUE),
      tmk8_matches = sum(tmk8_exists),
      tmk9_matches = sum(tmk9_exists),
      taxpin_matches = sum(taxpin_exists)
    )
)

# =========================================================
# 11. JOIN BASELINE PERMITS TO PARCEL GEOMETRY
# =========================================================
# We use an inner join here because only matched parcel records can be
# spatially assigned through parcel geometry.

baseline_sf_raw <- parcels_one_per_tmk %>%
  inner_join(
    baseline_mf_data,
    by = c("tmk" = "tmk_8_digit")
  )

# =========================================================
# 12. ASSIGN BASELINE PERMITS TO COUNCIL DISTRICTS
# =========================================================
# We assign council districts using a point on the parcel surface.
#
# Why point_on_surface?
#   - Parcel polygons can be large or complex.
#   - Using a representative point avoids double-counting where a
#     parcel polygon touches multiple districts.

baseline_points <- baseline_sf_raw %>%
  st_point_on_surface()

baseline_with_districts <- st_join(
  baseline_points,
  council_districts,
  join = st_intersects,
  left = TRUE
) %>%
  mutate(Group = "Non-ROH Chapter 32 Baseline") %>%
  rename(
    Units = numunitsadd,
    District = distname
  )

# Collapse back to one row per original permit record.
# This prevents duplicated unit counts from multi-TMK permit rows.
baseline_with_districts <- baseline_with_districts %>%
  group_by(original_permit_row_id) %>%
  slice(1) %>%
  ungroup()

# =========================================================
# 13. ASSIGN ROH CHAPTER 32 PERMITS TO COUNCIL DISTRICTS
# =========================================================
# ROH records already have point geometry, so we spatially join them
# directly to council districts.

roh32_with_districts <- st_join(
  roh32_sf,
  council_districts,
  join = st_intersects,
  left = TRUE
) %>%
  mutate(
    Group = "ROH Chapter 32",
    District = distname
  )

# =========================================================
# 14. POST-JOIN DIAGNOSTICS
# =========================================================

print("--- Baseline district assignment check ---")
print(
  baseline_with_districts %>%
    st_drop_geometry() %>%
    summarize(
      rows = n(),
      missing_district = sum(is.na(District)),
      units = sum(Units, na.rm = TRUE),
      missing_district_units = sum(Units[is.na(District)], na.rm = TRUE),
      unique_districts = n_distinct(District, na.rm = TRUE)
    )
)

print("--- ROH Chapter 32 district assignment check ---")
print(
  roh32_with_districts %>%
    st_drop_geometry() %>%
    summarize(
      rows = n(),
      missing_district = sum(is.na(District)),
      units = sum(Units, na.rm = TRUE),
      missing_district_units = sum(Units[is.na(District)], na.rm = TRUE),
      unique_districts = n_distinct(District, na.rm = TRUE)
    )
)

print("--- Unit comparison before and after spatial assignment ---")

raw_baseline_units <- sum(baseline_mf_data$numunitsadd, na.rm = TRUE)
joined_baseline_units <- sum(baseline_with_districts$Units, na.rm = TRUE)
unmatched_baseline_units <- raw_baseline_units - joined_baseline_units

raw_roh_units <- sum(roh32_data$Units, na.rm = TRUE)
joined_roh_units <- sum(roh32_with_districts$Units, na.rm = TRUE)

unit_comparison <- tibble(
  group = c("Baseline", "ROH Chapter 32"),
  raw_units = c(raw_baseline_units, raw_roh_units),
  joined_units = c(joined_baseline_units, joined_roh_units),
  difference = joined_units - raw_units
)

print(unit_comparison)

print("--- Duplicate baseline original row check ---")
print(
  baseline_with_districts %>%
    st_drop_geometry() %>%
    count(original_permit_row_id, sort = TRUE) %>%
    filter(n > 1)
)

print("--- ROH missing date check ---")
print(
  roh32_data %>%
    filter(is.na(year_created) | is.na(BP_App_Date)) %>%
    select(`Building permit #`, `BP Application Date`, Units)
)

# =========================================================
# 15. COMPILE FINAL SPATIAL DATA
# =========================================================

combined_spatial <- bind_rows(
  baseline_with_districts %>%
    select(year_created, Units, Group, District),
  
  roh32_with_districts %>%
    select(year_created, Units, Group, District)
) %>%
  st_drop_geometry() %>%
  filter(!is.na(District), !is.na(year_created)) %>%
  mutate(
    Group = factor(
      Group,
      levels = c("ROH Chapter 32", "Non-ROH Chapter 32 Baseline")
    )
  )

print("--- Final row counts by Group ---")
print(table(combined_spatial$Group))

print("--- Final unit totals by Group ---")
print(
  combined_spatial %>%
    group_by(Group) %>%
    summarize(
      rows = n(),
      units = sum(Units, na.rm = TRUE),
      .groups = "drop"
    )
)

# =========================================================
# 16. CREATE DISTRICT-YEAR SUMMARY TABLE
# =========================================================

district_summary_table <- combined_spatial %>%
  group_by(year_created, District, Group) %>%
  summarize(
    Total_Units = sum(Units, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  complete(
    year_created,
    District,
    Group,
    fill = list(Total_Units = 0)
  ) %>%
  pivot_wider(
    names_from = Group,
    values_from = Total_Units
  ) %>%
  mutate(
    Total_Units_All = `ROH Chapter 32` + `Non-ROH Chapter 32 Baseline`,
    
    Bill_7_Percent = ifelse(
      Total_Units_All > 0,
      (`ROH Chapter 32` / Total_Units_All) * 100,
      0
    ),
    
    Bill_7_Percent = round(Bill_7_Percent, 1)
  ) %>%
  rename(
    `Application Year` = year_created,
    `Council District` = District,
    `Bill 7 Units` = `ROH Chapter 32`,
    `Baseline Units` = `Non-ROH Chapter 32 Baseline`,
    `Total Units` = Total_Units_All,
    `% Bill 7` = Bill_7_Percent
  ) %>%
  arrange(`Council District`, `Application Year`)

print("--- District summary table preview ---")
print(district_summary_table, n = 30)

# =========================================================
# 17. VALIDATE SUMMARY TABLE MATH
# =========================================================

math_check <- district_summary_table %>%
  mutate(
    recomputed_total = `Bill 7 Units` + `Baseline Units`,
    
    recomputed_percent = ifelse(
      recomputed_total > 0,
      round((`Bill 7 Units` / recomputed_total) * 100, 1),
      0
    ),
    
    total_matches = recomputed_total == `Total Units`,
    percent_matches = recomputed_percent == `% Bill 7`
  )

print("--- Summary math check failures ---")
print(math_check %>% filter(!total_matches | !percent_matches))

stopifnot(all(math_check$total_matches))
stopifnot(all(math_check$percent_matches))

# =========================================================
# 18. CREATE BAR CHART
# =========================================================

plot_caption <- paste0(
  "Source: City and County of Honolulu DPP & Hawaii Geoportal. ",
  "Note: Baseline excludes ",
  format(unmatched_baseline_units, big.mark = ","),
  " units whose TMKs could not be matched to the parcel layer."
)

district_plot <- ggplot(
  combined_spatial,
  aes(x = year_created, y = Units, fill = Group)
) +
  geom_bar(stat = "identity", position = "stack") +
  facet_wrap(~ District, ncol = 3) +
  scale_fill_manual(
    values = c(
      "Non-ROH Chapter 32 Baseline" = uhero_dark_blue,
      "ROH Chapter 32" = uhero_gold
    )
  ) +
  labs(
    title = "HOUSING PERMITS BY COUNCIL DISTRICT",
    subtitle = "New multifamily units proposed and built, ROH Chapter 32 vs Baseline",
    caption = plot_caption,
    x = "Application Year",
    y = "Total Units",
    fill = "Program"
  ) +
  scale_x_continuous(
    breaks = seq(2018, 2026, by = 1)
  ) +
  theme_uhero() +
  theme(
    strip.text = element_text(
      family = "Gotham",
      face = "bold",
      size = 18,
      color = uhero_dark_blue
    )
  )

print(district_plot)

# =========================================================
# 19. EXPORT OUTPUTS
# =========================================================

# Ensure your 'outputs/' folder exists before exporting
if(!dir.exists("outputs")) dir.create("outputs")

write_csv(
  district_summary_table,
  "data/Council_District_Bill7_Summary.csv"
)

write_csv(
  unmatched_check,
  "data/Unmatched_Baseline_TMKS.csv"
)

write_csv(
  unit_comparison,
  "data/Council_District_Unit_Comparison.csv"
)

ggsave(
  filename = "outputs/Council_District_Bill7_Plot.png",
  plot = district_plot,
  width = 14,
  height = 10,
  dpi = 300
)

print("DONE: Council district analysis completed.")
print(
  paste0(
    "NOTE: ",
    format(unmatched_baseline_units, big.mark = ","),
    " baseline units could not be matched to the parcel layer."
  )
)