# =========================================================
# Project: ROH CH32 Plan Review Breakdown (Graph 5 / report Figure 5)
# Author: Trey Gordner, UHERO
# Assistance: Claude (Anthropic)
#
# PURPOSE:
#   1. Reproduces Graph 5 of roh_ch32_analysis.R (Figure 5 in the revised brief)
#      without the inputs Graph 5 doesn't use (hnlpermits_with_status_0625.csv,
#      roh32_complete_cleaned (1).csv). The data prep and plot code are copied
#      from roh_ch32_analysis.R. If Graph 5 changes there, update this script to match.
#   2. Adds a three-color version that splits agency time into DPP review and
#      review by other agencies routed through DPP's system (Fire, Board of Water
#      Supply, State DOH/DLNR/DOE, private third-party reviewers). A day counts as
#      DPP time if any DPP review is open, otherwise as other-agency time if any
#      other review is open. DPP + other agency = Graph 5's agency time.
#
# DATA (data/, run from the repo root):
#   - roh32_by_project_20260903.csv
#   - MASTER_Plan_Reviews.csv, MASTER_Metrics.csv (scraped from Posse)
#
# OUTPUT: outputs/Plot5_ROH32_Plan_Review_Breakdown.png (original)
#         outputs/Plot5b_ROH32_Plan_Review_DPP_vs_Other_Agency.png (three-way split)
# =========================================================

library(tidyverse)
library(lubridate)

# =========================================================
# ASSET LOADING & STYLING SETUP (as in roh_ch32_analysis.R)
# =========================================================

# Falls back to the default font if showtext isn't installed
if (requireNamespace("showtext", quietly = TRUE)) {
  library(showtext)
  font_add(family = "Trajan",
           regular = "fonts/TrajanPro-Regular.otf",
           bold = "fonts/TrajanPro-Bold.otf")
  font_add(family = "Gotham",
           regular = "fonts/Gotham-Regular.ttf",
           bold = "fonts/Gotham-Bold.ttf")
  showtext_auto()
  showtext_opts(dpi = 300)
  uhero_font <- "Gotham"
} else {
  message("showtext not installed: using the default font. Install it for the Gotham version.")
  uhero_font <- ""
}

uhero_dark_blue <- "#1D667F"
uhero_light_blue<- "#7EC4CA"
uhero_gray      <- "#505050"
uhero_gold      <- "#F6A01B"
uhero_green     <- "#9BBB59"

theme_uhero <- function(base_size = 14) {
  theme_minimal(base_size = base_size) +
    theme(
      legend.position = "bottom",
      plot.title = element_text(family = uhero_font, face = "bold", size = 16, color = uhero_dark_blue),
      plot.subtitle = element_text(family = uhero_font, size = 12, color = uhero_gray),
      plot.caption = element_text(family = uhero_font, face = "italic", color = uhero_gray, hjust = 0),
      axis.title = element_text(family = uhero_font, face = "bold", size = 22, color = uhero_gray),
      axis.text = element_text(family = uhero_font, size = 20, color = uhero_gray),
      legend.title = element_text(family = uhero_font, size = 22, face = "bold", color = uhero_gray),
      legend.text = element_text(family = uhero_font, size = 20, color = uhero_gray),
      panel.grid.major.x = element_blank() # Removes vertical grid lines for a cleaner look
    )
}

# =========================================================
# DATA LOADING (Graph 5 inputs only)
# =========================================================
roh32_data <- read_csv("data/roh32_by_project_20260903.csv", show_col_types = FALSE)
permit_metrics <- read_csv("data/MASTER_Metrics.csv", show_col_types = FALSE)
plan_reviews <- read_csv("data/MASTER_Plan_Reviews.csv", show_col_types = FALSE)

roh32_data <- roh32_data %>% mutate(primary_permit = as.character(primary_permit))

# Define the exact date the Posse system stopped updating
posse_freeze_date <- as.Date("2025-07-28")

# =========================================================
# SCRAPED DATA MATH: DPP VS DEVELOPER TIME & ZOMBIES (as in roh_ch32_analysis.R)
# =========================================================

# 1. SANITIZE PLAN REVIEWS (Handling the City's missing date placeholders)
clean_plan_reviews <- plan_reviews %>%
  mutate(
    Clean_Start = ifelse(`Date Plans Received` %in% c("mmm dd, yyyy", "There is no plan review information available for this permit."), NA, `Date Plans Received`),
    Clean_End = ifelse(`Date Completed` %in% c("mmm dd, yyyy"), NA, `Date Completed`),
    start = mdy(Clean_Start),
    end = mdy(Clean_End)
  ) %>%
  filter(!is.na(start))

# 2. CALCULATE DPP TIME
dpp_daily <- clean_plan_reviews %>%
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
    last_end = max(coalesce(end, posse_freeze_date), na.rm = TRUE),
    Total_Review_Days = as.numeric(last_end - first_start) + 1,
    Last_Action_Date = max(end, na.rm = TRUE),
    .groups = 'drop'
  )

permit_times <- review_spans %>%
  left_join(dpp_daily, by = "Application_Number") %>%
  mutate(
    Developer_Days = Total_Review_Days - DPP_Days,
    Developer_Days = ifelse(Developer_Days < 0, 0, Developer_Days)
  )

# =========================================================
# PREP ROH Chapter 32 DATA (unit rescue omitted: Graph 5 doesn't use units)
# =========================================================
roh32_clean <- roh32_data %>%
  mutate(
    BP_App_Date = ymd(created_date),
    year_created = year(BP_App_Date),

    Project_Stage = case_when(
      status %in% c("Cancelled", "Revoked", "Canceled", "Withdrawn") ~ "Canceled/Withdrawn",
      status == "Completed" ~ "Constructed (CO Issued)",
      status %in% c("In Progress", "Revision", "SAI", "Pending") & !is.na(issued_date) ~ "Approved & Permitted",
      status %in% c("In Progress", "Revision", "SAI", "Pending") & is.na(issued_date) ~ "In Application Review",
      TRUE ~ "Unknown"
    ),
    Project_Stage = factor(Project_Stage, levels = c("Canceled/Withdrawn", "In Application Review", "Approved & Permitted", "Constructed (CO Issued)"))
  ) %>%
  filter(!is.na(year_created)) %>%
  left_join(permit_times, by = c("primary_permit" = "Application_Number")) %>%
  left_join(permit_metrics, by = c("primary_permit" = "Application_Number")) %>%
  mutate(
    Days_Since_Last_Action = as.numeric(posse_freeze_date - Last_Action_Date),
    Is_Zombie = ifelse(Project_Stage == "In Application Review" & Days_Since_Last_Action > 120, TRUE, FALSE)
  )

# =========================================================
# GRAPH 5: ISOLATING DPP VS. DEVELOPER TIME (ROH 32)
# =========================================================
active_clean_times <- roh32_clean %>%
  # Exclude zombies, canceled projects, AND partial/misleading 2025+ data
  filter(!is.na(DPP_Days), Is_Zombie == FALSE, Project_Stage != "Canceled/Withdrawn", year_created < 2025) %>%
  group_by(year_created) %>%
  summarize(
    `Agency Time (with DPP)` = mean(DPP_Days, na.rm = TRUE),
    `Developer Time (Revisions)` = mean(Developer_Days, na.rm = TRUE),
    .groups = 'drop'
  ) %>%
  pivot_longer(cols = c(`Agency Time (with DPP)`, `Developer Time (Revisions)`),
               names_to = "Time_Type", values_to = "Average_Days") %>%
  mutate(Time_Type = factor(Time_Type, levels = c("Developer Time (Revisions)", "Agency Time (with DPP)")))

# --- INTEGRITY TEST: matches the draft brief's Figure 4 (2026-10-16 re-scrape) ---
figure4_agency <- c(`2019` = 236, `2020` = 131, `2021` = 161, `2022` = 234, `2023` = 154, `2024` = 88)
agency_now <- active_clean_times %>% filter(Time_Type == "Agency Time (with DPP)") %>%
  { setNames(round(.$Average_Days), .$year_created) }
if (!identical(agency_now[names(figure4_agency)], figure4_agency)) {
  warning("Agency-time bars differ from the draft brief's Figure 4. Check the input files.")
}

dpp_isolation_plot <- ggplot(active_clean_times, aes(x = year_created, y = Average_Days, fill = Time_Type)) +
  geom_bar(stat = "identity", position = "stack", width = 0.65) +
  geom_text(aes(label = ifelse(Average_Days > 0, round(Average_Days), "")),
            position = position_stack(vjust = 0.5),
            color = "white", family = uhero_font, fontface = "bold", size = 6) +
  geom_hline(yintercept = 90, linetype = "dashed", color = uhero_dark_blue, linewidth = 0.8) +
  annotate("text", x = min(active_clean_times$year_created), y = 60,
           label = "90-day Shot Clock",
           color = uhero_dark_blue, family = uhero_font, fontface = "bold", hjust = 0, size = 5) +
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
  theme_uhero()

print(dpp_isolation_plot)

if (!dir.exists("outputs")) dir.create("outputs")
ggsave("outputs/Plot5_ROH32_Plan_Review_Breakdown.png", dpp_isolation_plot,
       width = 12, height = 8, dpi = 300, bg = "white")

# =========================================================
# GRAPH 5b: SPLITTING AGENCY TIME INTO DPP VS. OTHER AGENCIES
# =========================================================
# Review types as named in DPP's Posse "Plan Reviews" tab. The Civil Engineering,
# Traffic Review, and Wastewater branches are treated as DPP (site development).
dpp_reviews <- c("Building Code", "Electrical Code", "Mechanical Code", "Zoning Code (ZPRB)",
                 "Civil Engineering Branch (CEB)", "Traffic Review Branch (TRB)", "Wastewater Branch (WWB)")
other_reviews <- c("Fire Code (HFD)", "Board of Water Supply (BWS)", "State DOH (A/C Ventilation Branch)",
                   "State DOH (Wastewater Branch)", "State DLNR (Historical)", "State - DOE Impact Fee",
                   "Third Party Review (Building)", "Third Party Review (Electrical)",
                   "Third Party Review (Mechanical)", "Third Party Review (Structural)")

# --- INTEGRITY TEST: every review type is classified ---
unclassified <- setdiff(unique(clean_plan_reviews$`Type of Review`), c(dpp_reviews, other_reviews))
stopifnot("FAIL: unclassified review types (add them to dpp_reviews or other_reviews)" = length(unclassified) == 0)

# Each open review-day gets one owner: DPP if any DPP review is open that day
reviewer_days <- clean_plan_reviews %>%
  mutate(
    end = if_else(is.na(end), posse_freeze_date, end),
    Reviewer = if_else(`Type of Review` %in% dpp_reviews, "DPP", "Other")
  ) %>%
  rowwise() %>%
  mutate(date_seq = list(seq(start, end, by = "day"))) %>%
  unnest(date_seq) %>%
  group_by(Application_Number, date_seq) %>%
  summarize(Owner = if_else(any(Reviewer == "DPP"), "DPP_Days_Only", "Other_Agency_Days"), .groups = "drop") %>%
  count(Application_Number, Owner) %>%
  pivot_wider(names_from = Owner, values_from = n, values_fill = 0)

split_times <- roh32_clean %>%
  # Same sample as Graph 5
  filter(!is.na(DPP_Days), Is_Zombie == FALSE, Project_Stage != "Canceled/Withdrawn", year_created < 2025) %>%
  left_join(reviewer_days, by = c("primary_permit" = "Application_Number")) %>%
  mutate(across(c(DPP_Days_Only, Other_Agency_Days), ~ replace_na(.x, 0)))

# --- INTEGRITY TEST: DPP + other agency days = Graph 5 agency days, for every project ---
stopifnot("FAIL: DPP + other agency days don't add up to Graph 5 agency days" =
            all(split_times$DPP_Days_Only + split_times$Other_Agency_Days == split_times$DPP_Days))

split_summary <- split_times %>%
  group_by(year_created) %>%
  summarize(
    `DPP Review` = mean(DPP_Days_Only),
    `Other Agency Review` = mean(Other_Agency_Days),
    `Developer Time` = mean(Developer_Days),
    .groups = "drop"
  )

cat("\nGraph 5b: mean days by application year\n")
print(split_summary %>% mutate(across(-year_created, round)))
cat("Cohort-year average:\n")
print(split_summary %>% summarize(across(-year_created, ~ round(mean(.x)))))
cat("Project-level average (n = ", nrow(split_times), "):\n", sep = "")
print(split_times %>% summarize(`DPP Review` = round(mean(DPP_Days_Only)),
                                `Other Agency Review` = round(mean(Other_Agency_Days)),
                                `Developer Time` = round(mean(Developer_Days))))

split_long <- split_summary %>%
  pivot_longer(-year_created, names_to = "Time_Type", values_to = "Average_Days") %>%
  mutate(
    Time_Type = factor(Time_Type, levels = c("Developer Time", "Other Agency Review", "DPP Review")),
    # Label segments big enough to hold a number; dark text on the light segment
    Label = ifelse(Average_Days >= 25, round(Average_Days), ""),
    Label_Color = ifelse(Time_Type == "Other Agency Review", uhero_dark_blue, "white")
  )

split_plot <- ggplot(split_long, aes(x = year_created, y = Average_Days, fill = Time_Type)) +
  geom_bar(stat = "identity", position = "stack", width = 0.65) +
  geom_text(aes(label = Label, color = Label_Color, group = Time_Type),
            position = position_stack(vjust = 0.5),
            family = uhero_font, fontface = "bold", size = 6, show.legend = FALSE) +
  scale_color_identity() +
  geom_hline(yintercept = 90, linetype = "dashed", color = uhero_dark_blue, linewidth = 0.8) +
  annotate("text", x = max(split_long$year_created) + 0.4, y = 90,
           label = "90-day\nShot Clock", vjust = 0.5,
           color = uhero_dark_blue, family = uhero_font, fontface = "bold", hjust = 0, size = 4.5) +
  scale_fill_manual(values = c("DPP Review" = uhero_gold,
                               "Other Agency Review" = uhero_light_blue,
                               "Developer Time" = uhero_green),
                    breaks = c("DPP Review", "Other Agency Review", "Developer Time")) +
  labs(
    title = "BILL 7 PERMIT TIME BY RESPONSIBLE PARTY",
    subtitle = "Average days with a DPP review open, only another agency's review open, or no review open (Active & Issued Projects)",
    # Definitions (other agencies, overlapping days) are in the report's footnote
    caption = "Source: City and County of Honolulu Department of Planning and Permitting (DPP); UHERO calculations",
    x = "Application Year",
    y = "Average Processing Days",
    fill = ""
  ) +
  scale_x_continuous(breaks = seq(min(split_long$year_created), max(split_long$year_created), by = 1),
                     expand = expansion(add = c(0.5, 1.1))) +
  theme_uhero()

print(split_plot)

ggsave("outputs/Plot5b_ROH32_Plan_Review_DPP_vs_Other_Agency.png", split_plot,
       width = 12, height = 8, dpi = 300, bg = "white")
