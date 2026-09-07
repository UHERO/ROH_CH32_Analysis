# =========================================================
# Project: ROH CH32 Pipeline Analysis
# Author: Rafael Munoz, Graduate Assistant, UHERO
# Assistance: Google Gemini AI
# Description: Pipeline analysis comparing ROH Chapter 32 
# multifamily permits against the non-Chapter 32 baseline.
# =========================================================

# Load necessary libraries
library(tidyverse)
library(lubridate) # Required for advanced date math
library(showtext)

# =========================================================
# ASSET LOADING & STYLING SETUP
# =========================================================

# Load Custom Fonts from the /fonts subdirectory
font_add(family = "Trajan", 
         regular = "fonts/TrajanPro-Regular.otf", 
         bold = "fonts/TrajanPro-Bold.otf")

font_add(family = "Gotham", 
         regular = "fonts/Gotham-Regular.ttf", 
         bold = "fonts/Gotham-Bold.ttf")

# Activate showtext to render the fonts in plots
showtext_auto()

# Standardized Color Palette
uhero_dark_blue <- "#1D667F"
uhero_light_blue<- "#7EC4CA"
uhero_gray      <- "#505050"
uhero_gold      <- "#F6A01B"
uhero_green     <- "#9BBB59"
uhero_purple    <- "#8064A2"

# CUSTOM FUNCTION: Standardized Plot Theme
# This enforces consistent styling across all graphs without code repetition.
theme_uhero <- function(base_size = 14) {
  theme_minimal(base_size = base_size) +
    theme(
      legend.position = "bottom",
      # Titles, subtitles, and captions remain original size
      plot.title = element_text(family = "Gotham", face = "bold", size = 16, color = uhero_dark_blue),
      plot.subtitle = element_text(family = "Gotham", size = 12, color = uhero_gray),
      plot.caption = element_text(family = "Gotham", face = "italic", color = uhero_gray, hjust = 0),
      axis.title = element_text(family = "Gotham", face = "bold", color = uhero_gray),
      axis.text = element_text(family = "Gotham", color = uhero_gray),
      legend.title = element_text(family = "Gotham", face = "bold", color = uhero_gray),
      legend.text = element_text(family = "Gotham", color = uhero_gray),
      panel.grid.major.x = element_blank() # Removes vertical grid lines for a cleaner look
    )
}

# =========================================================
# DATA LOADING & INTEGRITY CLEANING
# =========================================================
# Note: Data is loaded from the local /data directory. 
# Do not push these files to version control.
permits_data <- read_csv("data/hnlpermits_with_status_0625.csv")
roh32_data <- read_csv("data/roh32_by_project_20260903.csv")

# Load newly scraped metrics
permit_metrics <- read_csv("data/MASTER_Metrics.csv")
plan_reviews <- read_csv("data/MASTER_Plan_Reviews.csv")

# Ensure Permit Numbers are characters for clean joining/filtering
permits_data <- permits_data %>% mutate(buildingpermitno = as.character(buildingpermitno))
roh32_data <- roh32_data %>% mutate(primary_permit = as.character(primary_permit))

# Isolate ROH Chapter 32 permit numbers to ensure the baseline is mutually exclusive
roh32_permit_numbers <- unique(na.omit(roh32_data$primary_permit))

# Define the exact date the Posse system stopped updating
posse_freeze_date <- as.Date("2025-07-28")

# =========================================================
# SCRAPED DATA MATH: DPP VS DEVELOPER TIME & ZOMBIES
# =========================================================

# 1. SANITIZE PLAN REVIEWS (Handling the City's missing date placeholders)
clean_plan_reviews <- plan_reviews %>%
  mutate(
    # Nullify placeholder text before date parsing to prevent R warnings
    Clean_Start = ifelse(`Date Plans Received` %in% c("mmm dd, yyyy", "There is no plan review information available for this permit."), NA, `Date Plans Received`),
    Clean_End = ifelse(`Date Completed` %in% c("mmm dd, yyyy"), NA, `Date Completed`),
    
    start = mdy(Clean_Start),
    end = mdy(Clean_End)
  ) %>%
  filter(!is.na(start))

# 2. CALCULATE DPP TIME (Preventing overlapping double-counts from multiple agencies)
dpp_daily <- clean_plan_reviews %>%
  # If end date is missing, it was sitting on an agency desk AT THE TIME the database froze
  mutate(end = if_else(is.na(end), posse_freeze_date, end)) %>%
  rowwise() %>%
  mutate(date_seq = list(seq(start, end, by = "day"))) %>%
  unnest(date_seq) %>%
  distinct(Application_Number, date_seq) %>%
  group_by(Application_Number) %>%
  summarize(DPP_Days = n(), .groups = 'drop')

# 3. CALCULATE TOTAL TIMELINES
review_spans <- clean_plan_reviews %>%
  group_by(Application_Number) %>%
  summarize(
    first_start = min(start, na.rm = TRUE),
    # If a review is still open, the timeline stops at the database freeze date
    last_end = max(coalesce(end, posse_freeze_date), na.rm = TRUE),
    Total_Review_Days = as.numeric(last_end - first_start) + 1,
    Last_Action_Date = max(end, na.rm = TRUE), # Tracks the most recent touchpoint
    .groups = 'drop'
  )

permit_times <- review_spans %>%
  left_join(dpp_daily, by = "Application_Number") %>%
  mutate(
    Developer_Days = Total_Review_Days - DPP_Days,
    # Floor at 0 in case of minor data entry overlaps from the city
    Developer_Days = ifelse(Developer_Days < 0, 0, Developer_Days) 
  )

# =========================================================
# PREP NON-ROH Chapter 32 BASELINE DATA
# =========================================================
baseline_mf_data <- permits_data %>%
  # Exclude ROH Chapter 32 permits 
  filter(!buildingpermitno %in% roh32_permit_numbers) %>%
  filter(year_created >= 2018) %>%
  filter(!status_category %in% c("Rejected/Cancelled", "Approved Then Revoked")) %>%
  filter(newbuilding == "Y" | str_detect(replace_na(toupper(buildingpermittype), ""), "NEW")) %>%
  filter(
    str_detect(replace_na(toupper(occupancygroupcategory), ""), "R-1|R-2|R1|R2|APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT") | 
      str_detect(replace_na(toupper(proposeduse), ""), "APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT|TOWNHOUSE")
  ) %>%
  mutate(
    Project_Stage = case_when(
      coissued == "Y" ~ "Constructed (CO Issued)",
      status_category %in% c("Active/Approved", "Approved Pending Issue", "Completed Successfully") & coissued == "N" ~ "Approved & Permitted",
      status_category %in% c("Under Review", "Administrative", "Other") ~ "In Application Review",
      TRUE ~ "Unknown"
    ),
    Project_Stage = factor(Project_Stage, levels = c("In Application Review", "Approved & Permitted", "Constructed (CO Issued)")),
    Data_Status = ifelse(year_created >= 2023, "Incomplete/Censored", "Complete"),
    Group = "Non-ROH Chapter 32 Baseline"
  ) %>%
  filter(numunitsadd > 0, !is.na(numunitsadd))

# =========================================================
# PREP ROH Chapter 32 DATA (UPDATED FOR 2026-09-03)
# =========================================================
roh32_clean <- roh32_data %>%
  # Filter out dead projects to match the baseline methodology
  filter(!status %in% c("Cancelled", "Revoked", "Canceled", "Withdrawn")) %>%
  mutate(
    # Parse the new date format (yyyy-mm-dd)
    BP_App_Date = ymd(created_date),
    year_created = year(BP_App_Date),
    
    # Translate the new `status` column into the old Project_Stage logic
    Project_Stage = case_when(
      status == "Completed" ~ "Constructed (CO Issued)",
      status %in% c("In Progress", "Revision", "SAI", "Pending") & !is.na(issued_date) ~ "Approved & Permitted",
      status %in% c("In Progress", "Revision", "SAI", "Pending") & is.na(issued_date) ~ "In Application Review",
      TRUE ~ "Unknown"
    ),
    Project_Stage = factor(Project_Stage, levels = c("In Application Review", "Approved & Permitted", "Constructed (CO Issued)")),
    
    Data_Status = ifelse(year_created >= 2023, "Incomplete/Censored", "Complete"),
    Group = "ROH Chapter 32",
    
    # Standardize the new units column back to the old name so the graphs don't break
    Units = as.numeric(units_added)
  ) %>%
  filter(!is.na(year_created)) %>%
  # Join our calculated time splits & metrics using the new ID column
  left_join(permit_times, by = c("primary_permit" = "Application_Number")) %>%
  left_join(permit_metrics, by = c("primary_permit" = "Application_Number")) %>%
  mutate(
    Days_Since_Last_Action = as.numeric(posse_freeze_date - Last_Action_Date),
    Is_Zombie = ifelse(Project_Stage == "In Application Review" & Days_Since_Last_Action > 120, TRUE, FALSE)
  )

# Join with permit data to get processing times for graph 3
roh32_with_time <- roh32_clean %>%
  left_join(
    permits_data %>% select(buildingpermitno, processing_days, was_approved), 
    by = c("primary_permit" = "buildingpermitno")
  )

# =========================================================
# GRAPH 1: BASELINE MULTIFAMILY PIPELINE
# =========================================================
baseline_volume_summary <- baseline_mf_data %>%
  group_by(year_created, Project_Stage) %>%
  summarize(Total_Units = sum(numunitsadd, na.rm = TRUE), .groups = "drop") 

baseline_plot <- ggplot(baseline_volume_summary, aes(x = year_created, y = Total_Units, fill = Project_Stage)) +
  geom_bar(stat = "identity", position = "stack", width = 0.65) +
  scale_fill_manual(values = c("Constructed (CO Issued)" = uhero_green,  
                               "Approved & Permitted" = uhero_dark_blue,     
                               "In Application Review" = uhero_gold)) + 
  labs(
    title = "NON-ROH CHAPTER 32 MULTIFAMILY HOUSING PIPELINE",
    subtitle = "Total baseline units moving through DPP, categorized by current stage",
    caption = "Source: City and County of Honolulu Department of Planning and Permitting (DPP)",
    x = "Application Year",
    y = "Total Units Added",
    fill = "" 
  ) +
  scale_x_continuous(breaks = seq(2018, 2025, by = 1)) +
  theme_uhero() # Applies custom formatting

print(baseline_plot)

# =========================================================
# GRAPH 2: ROH Chapter 32 PIPELINE WITH 500-UNIT TARGET LINE
# =========================================================
roh32_volume_summary <- roh32_clean %>%
  group_by(year_created, Project_Stage) %>%
  summarize(Total_Units = sum(Units, na.rm = TRUE), .groups = "drop") 

roh32_plot <- ggplot(roh32_volume_summary, aes(x = year_created, y = Total_Units, fill = Project_Stage)) +
  geom_bar(stat = "identity", position = "stack", width = 0.65) +
  geom_hline(yintercept = 500, linetype = "dashed", color = uhero_green, linewidth = 1.2) +
  # Annotation size converted for ggplot (~size 6.5 represents ~18-20pt font)
  annotate("text", x = 2019, y = 520, label = "Policy Goal (500 units constructed/year)", 
           color = uhero_green, family = "Gotham", fontface = "bold", hjust = 0, size = 6.5) +
  coord_cartesian(ylim = c(0, max(550, max(roh32_volume_summary$Total_Units)))) +
  scale_fill_manual(values = c("Constructed (CO Issued)" = uhero_green,  
                               "Approved & Permitted" = uhero_dark_blue,     
                               "In Application Review" = uhero_gold)) + 
  labs(
    title = "ROH CHAPTER 32 MULTIFAMILY HOUSING PIPELINE",
    subtitle = "Total ROH Chapter 32 units moving through DPP, categorized by current stage",
    caption = "Source: City and County of Honolulu Department of Planning and Permitting (DPP)",
    x = "Application Year",
    y = "Total Units Added",
    fill = "" 
  ) +
  scale_x_continuous(breaks = seq(min(roh32_volume_summary$year_created), 
                                  max(roh32_volume_summary$year_created), by = 1)) +
  theme_uhero() # Applies custom formatting

print(roh32_plot)

# =========================================================
# GRAPH 3: PROCESSING TIME COMPARISON
# =========================================================
baseline_time_summary <- baseline_mf_data %>%
  filter(!is.na(processing_days), was_approved == TRUE) %>%
  group_by(year_created, Group, Data_Status) %>%
  summarize(Median_Days = median(processing_days, na.rm = TRUE), .groups = "drop")

roh32_time_summary <- roh32_with_time %>%
  filter(!is.na(processing_days)) %>%
  group_by(year_created, Group, Data_Status) %>%
  summarize(Median_Days = median(processing_days, na.rm = TRUE), .groups = "drop")

combined_time_summary <- bind_rows(baseline_time_summary, roh32_time_summary)

time_plot <- ggplot(combined_time_summary, aes(x = year_created, y = Median_Days, color = Group, group = Group)) +
  geom_line(linewidth = 1.2) +
  geom_point(aes(shape = Data_Status), size = 3.5, fill = "white", stroke = 1.5) +
  scale_color_manual(values = c("Non-ROH Chapter 32 Baseline" = uhero_gold, "ROH Chapter 32" = uhero_dark_blue)) +
  scale_shape_manual(values = c("Complete" = 19, "Incomplete/Censored" = 21)) +
  geom_hline(yintercept = 554, linetype = "dashed", color = uhero_green, linewidth = 1) + 
  annotate("text", x = 2018, y = 580, label = "2024 Median Benchmark (554 days)", 
           color = uhero_green, family = "Gotham", fontface = "bold", hjust = 0, size = 6.5) +
  geom_hline(yintercept = 90, linetype = "dashed", color = uhero_dark_blue, linewidth = 1) + 
  annotate("text", x = 2018, y = 125, label = "ROH Chapter 32's 90-day Shot Clock", 
           color = uhero_dark_blue, family = "Gotham", fontface = "bold", hjust = 0, size = 6.5) +
  labs(
    title = "MULTIFAMILY PERMIT PROCESSING TIME COMPARISON",
    subtitle = "Honolulu County median days from application to issuance (ROH Chapter 32 vs. Non-ROH Chapter 32)",
    caption = "*Note: Drop in recent years is due to censoring (only fastest permits issued so far).\nSource: City and County of Honolulu Department of Planning and Permitting (DPP)",
    x = "Application Year",
    y = "Median Processing Time (Days)",
    color = "Dataset",
    shape = "Data Maturity"
  ) +
  scale_x_continuous(breaks = seq(2018, 2026, by = 1)) +
  theme_uhero() # Applies custom formatting

print(time_plot)

# =========================================================
# GRAPH 4: COMPLETED MULTIFAMILY UNITS (MARKET SHARE)
# =========================================================
baseline_completed <- baseline_mf_data %>%
  filter(Project_Stage == "Constructed (CO Issued)") %>%
  group_by(year_created, Group) %>%
  summarize(Total_Units = sum(numunitsadd, na.rm = TRUE), .groups = "drop")

roh32_completed <- roh32_clean %>%
  filter(Project_Stage == "Constructed (CO Issued)") %>%
  group_by(year_created, Group) %>%
  summarize(Total_Units = sum(Units, na.rm = TRUE), .groups = "drop")

combined_completed <- bind_rows(baseline_completed, roh32_completed) %>%
  mutate(year_created = as.numeric(year_created))

completed_with_totals <- combined_completed %>%
  group_by(year_created) %>%
  mutate(
    Yearly_Total = sum(Total_Units),
    Percentage = ifelse(Yearly_Total > 0, (Total_Units / Yearly_Total) * 100, 0),
    Label_Text = ifelse(Group == "ROH Chapter 32", paste0(round(Percentage, 1), "%"), "")
  ) %>%
  ungroup()

market_share_plot <- ggplot(completed_with_totals, aes(x = year_created, y = Total_Units, fill = Group)) +
  geom_bar(stat = "identity", position = "stack", width = 0.65) +
  geom_text(aes(label = Label_Text), position = position_stack(vjust = 0.5), 
            family = "Gotham", fontface = "bold", color = "white", size = 6.5) +
  scale_fill_manual(values = c("Non-ROH Chapter 32 Baseline" = uhero_dark_blue, 
                               "ROH Chapter 32" = uhero_gold)) +
  labs(
    title = "SHARE OF COMPLETED MULTIFAMILY UNITS",
    subtitle = "Total constructed units (CO Issued) by year, Non-ROH Chapter 32 & ROH Chapter 32",
    caption = "Source: City and County of Honolulu Department of Planning and Permitting (DPP)",
    x = "Year Constructed (CO Issued)",
    y = "Total Units Completed",
    fill = "Project Type"
  ) +
  scale_x_continuous(breaks = seq(min(completed_with_totals$year_created, na.rm = TRUE), 
                                  max(completed_with_totals$year_created, na.rm = TRUE), by = 1)) +
  theme_uhero() # Applies custom formatting

print(market_share_plot)

# =========================================================
# GRAPH 5: ISOLATING DPP VS. DEVELOPER TIME (ROH 32)
# =========================================================
active_clean_times <- roh32_clean %>%
  filter(!is.na(DPP_Days), Is_Zombie == FALSE) %>%
  group_by(year_created) %>%
  summarize(
    `Agency Time (with DPP)` = mean(DPP_Days, na.rm = TRUE),
    `Developer Time (Revisions)` = mean(Developer_Days, na.rm = TRUE),
    .groups = 'drop'
  ) %>%
  pivot_longer(cols = c(`Agency Time (with DPP)`, `Developer Time (Revisions)`), 
               names_to = "Time_Type", values_to = "Average_Days") %>%
  mutate(Time_Type = factor(Time_Type, levels = c("Developer Time (Revisions)", "Agency Time (with DPP)")))

dpp_isolation_plot <- ggplot(active_clean_times, aes(x = year_created, y = Average_Days, fill = Time_Type)) +
  geom_bar(stat = "identity", position = "stack", width = 0.65) +
  geom_hline(yintercept = 90, linetype = "dashed", color = uhero_dark_blue, linewidth = 1.2) +
  annotate("text", x = min(active_clean_times$year_created), y = 130, 
           label = "ROH Chapter 32's 90-day Shot Clock (DPP Time)", 
           color = uhero_dark_blue, family = "Gotham", fontface = "bold", hjust = 0, size = 6.5) +
  scale_fill_manual(values = c("Agency Time (with DPP)" = uhero_gold, 
                               "Developer Time (Revisions)" = uhero_green)) +
  labs(
    title = "ROH CH32 PLAN REVIEW BREAKDOWN",
    subtitle = "Average days spent on agency desks vs. developer revisions (Active & Issued Projects)",
    caption = "Source: City and County of Honolulu Department of Planning and Permitting (DPP)",
    x = "Application Year",
    y = "Average Processing Days",
    fill = ""
  ) +
  scale_x_continuous(breaks = seq(min(active_clean_times$year_created), max(active_clean_times$year_created), by = 1)) +
  theme_uhero() # Applies custom formatting

print(dpp_isolation_plot)