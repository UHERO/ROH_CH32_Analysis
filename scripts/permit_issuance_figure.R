# =========================================================
# Project: ROH CH32 Permit Issuance Figure (Bill 7 vs. Other Multifamily)
# Author: Trey Gordner, UHERO
# Assistance: Claude (Anthropic)
#
# PURPOSE:
#   Plots the cumulative share of permits issued by years since application,
#   for Bill 7 (ROH 32) and other new multifamily buildings of 10-100 units,
#   2019-2024 applications. Kaplan-Meier estimates treat permits still pending at
#   the snapshot date as censored, so slow, unfinished permits are not dropped
#   (unlike Graph 3's issued-only medians).
#
#   Same definitions as scripts/baseline_permit_times.py, which prints the numbers
#   quoted in the report (e.g., 25% vs. 78% issued within two years).
#
# DATA (data/, run from the repo root):
#   - honolulu_bp_newbuilding_2018_2025.csv (python scripts/baseline_permit_times.py --download)
#   - roh32_by_project_20260903.csv
#   - MASTER_Plan_Reviews.csv (optional: adds a "Bill 7, excluding dormant" line)
#
# OUTPUT: outputs/Plot_Permit_Issuance_Bill7_vs_Multifamily.png
# =========================================================

library(tidyverse)
library(lubridate)
library(survival)

# =========================================================
# ASSET LOADING & STYLING SETUP
# =========================================================

# Load Custom Fonts from the /fonts subdirectory (falls back to the default font
# if showtext isn't installed, so the figure can still be checked)
if (requireNamespace("showtext", quietly = TRUE)) {
  library(showtext)
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

# Standardized Color Palette (Bill 7 = dark blue, baseline = gold, as in Graph 3)
uhero_dark_blue <- "#1D667F"
uhero_gray      <- "#505050"
uhero_gold      <- "#F6A01B"

theme_uhero <- function(base_size = 14) {
  theme_minimal(base_size = base_size) +
    theme(
      legend.position = "bottom",
      plot.title = element_text(family = uhero_font, face = "bold", size = 16, color = uhero_dark_blue),
      plot.subtitle = element_text(family = uhero_font, size = 12, color = uhero_gray),
      plot.caption = element_text(family = uhero_font, face = "italic", color = uhero_gray, hjust = 0),
      axis.title = element_text(family = uhero_font, face = "bold", size = 14, color = uhero_gray),
      axis.text = element_text(family = uhero_font, size = 13, color = uhero_gray),
      legend.text = element_text(family = uhero_font, size = 13, color = uhero_gray),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank()
    )
}

# =========================================================
# DATA LOADING (same definitions as baseline_permit_times.py)
# =========================================================
snapshot_date <- as.Date("2025-06-30")      # end of DPP's public permit snapshot
posse_freeze_date <- as.Date("2025-07-28")  # last date in the Posse plan-review records
mf_pattern <- "R-1|R-2|R1|R2|APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT|TOWNHOUSE"

permits <- read_csv("data/honolulu_bp_newbuilding_2018_2025.csv",
                    col_types = cols(.default = col_character()))
roh32_data <- read_csv("data/roh32_by_project_20260903.csv", show_col_types = FALSE)

multifamily <- permits %>%
  mutate(use_text = toupper(paste(replace_na(occupancygroupcategory, ""), replace_na(proposeduse, "")))) %>%
  filter(str_detect(use_text, mf_pattern)) %>%
  mutate(
    units = as.numeric(numunitsadd),
    created = as.Date(ymd_hms(createddate)),
    issued = as.Date(ymd_hms(issuedate)),
    app_year = year(created),
    is_bill7 = externalfilenum %in% roh32_data$primary_permit,
    event = !is.na(issued),
    days = as.numeric(if_else(event, issued - created, snapshot_date - created))
  ) %>%
  filter(units > 0, statusdescription != "Job Cancelled", between(app_year, 2019, 2024))

samples <- bind_rows(
  multifamily %>% filter(is_bill7) %>% mutate(Group = "Bill 7"),
  multifamily %>% filter(!is_bill7, between(units, 10, 100)) %>%
    mutate(Group = "Other multifamily (10-100 units)")
)

# Optional: Bill 7 without dormant applications (pending, no review action in the
# 120 days before the Posse freeze), as Graph 5 excludes them
if (file.exists("data/MASTER_Plan_Reviews.csv")) {
  last_action <- read_csv("data/MASTER_Plan_Reviews.csv", col_types = cols(.default = col_character())) %>%
    mutate(done = suppressWarnings(mdy(`Date Completed`))) %>%
    group_by(Application_Number) %>%
    summarize(last_action = suppressWarnings(max(done, na.rm = TRUE)), .groups = "drop")
  dormant_ids <- multifamily %>%
    filter(is_bill7, !event) %>%
    left_join(last_action, by = c("externalfilenum" = "Application_Number")) %>%
    filter(last_action < posse_freeze_date - 120) %>%
    pull(externalfilenum)
  samples <- bind_rows(
    samples,
    multifamily %>% filter(is_bill7, !externalfilenum %in% dormant_ids) %>%
      mutate(Group = "Bill 7, excluding dormant applications")
  )
}

group_levels <- c("Bill 7", "Bill 7, excluding dormant applications", "Other multifamily (10-100 units)")
samples <- samples %>% mutate(Group = factor(Group, levels = intersect(group_levels, unique(Group))))

# --- INTEGRITY TEST ---
stopifnot(
  "FAIL: no Bill 7 permits matched" = sum(samples$Group == "Bill 7") > 0,
  "FAIL: negative durations" = all(samples$days >= 0)
)

# =========================================================
# KAPLAN-MEIER: CUMULATIVE SHARE ISSUED
# =========================================================
km_fit <- survfit(Surv(days, event) ~ Group, data = samples)

# Stop each curve once fewer than this many permits remain at risk: past that point
# each step reflects one or two permits and the estimate is unreliable
min_at_risk <- 10

km_curves <- tibble(
  Group = factor(rep(sub("^Group=", "", names(km_fit$strata)), km_fit$strata), levels = levels(samples$Group)),
  Years = km_fit$time / 365.25,
  Share_Issued = 1 - km_fit$surv,
  At_Risk = km_fit$n.risk
) %>%
  filter(At_Risk >= min_at_risk) %>%
  # start every curve at zero
  bind_rows(tibble(Group = factor(levels(samples$Group), levels = levels(samples$Group)),
                   Years = 0, Share_Issued = 0, At_Risk = NA_real_)) %>%
  arrange(Group, Years)

km_marks <- summary(km_fit, times = c(365, 730), extend = TRUE)
km_labels <- tibble(
  Group = factor(sub("^Group=", "", as.character(km_marks$strata)), levels = levels(samples$Group)),
  Years = km_marks$time / 365.25,
  Share_Issued = 1 - km_marks$surv,
  At_Risk = km_marks$n.risk
)

group_counts <- samples %>% count(Group)
print(km_labels %>% left_join(group_counts, by = "Group") %>%
        mutate(Share_Issued = scales::percent(Share_Issued, accuracy = 1)))

# Label only the two-year mark on the chart (the one-year shares are close together)
km_labels_2yr <- km_labels %>% filter(round(Years) == 2)
stopifnot("FAIL: too few permits at risk at two years to label" = all(km_labels_2yr$At_Risk >= min_at_risk))

# =========================================================
# GRAPH: SHARE OF PERMITS ISSUED BY YEARS SINCE APPLICATION
# =========================================================
group_colors <- c("Bill 7" = uhero_dark_blue,
                  "Bill 7, excluding dormant applications" = uhero_dark_blue,
                  "Other multifamily (10-100 units)" = uhero_gold)
group_lines <- c("Bill 7" = "solid",
                 "Bill 7, excluding dormant applications" = "dashed",
                 "Other multifamily (10-100 units)" = "solid")
legend_labels <- group_counts %>%
  mutate(label = paste0(str_remove(Group, " \\(10-100 units\\)"),
                        if_else(str_detect(Group, "10-100"), ", 10-100 units", ""),
                        " (n = ", n, ")")) %>%
  { setNames(.$label, as.character(.$Group)) }

x_max <- ceiling(max(km_curves$Years))

issuance_plot <- ggplot(km_curves, aes(x = Years, y = Share_Issued, color = Group, linetype = Group)) +
  geom_vline(xintercept = 2, color = "#E0E0E0", linewidth = 0.5) +
  geom_step(linewidth = 1.1) +
  geom_point(data = km_labels_2yr, size = 3, show.legend = FALSE) +
  geom_text(data = km_labels_2yr, aes(label = scales::percent(Share_Issued, accuracy = 1)),
            hjust = -0.3, vjust = 1.3, family = uhero_font, fontface = "bold", size = 5,
            show.legend = FALSE) +
  scale_color_manual(values = group_colors, labels = legend_labels) +
  scale_linetype_manual(values = group_lines, labels = legend_labels) +
  scale_x_continuous(breaks = 0:x_max, limits = c(0, x_max), expand = expansion(mult = c(0, 0.02))) +
  scale_y_continuous(breaks = seq(0, 1, 0.25), limits = c(0, 1),
                     labels = c("0", "25", "50", "75", "100%")) +
  labs(
    title = "SHARE OF MULTIFAMILY PERMITS ISSUED, BY TIME SINCE APPLICATION",
    subtitle = "New multifamily building permits applied for 2019-2024, Bill 7 vs. other multifamily projects of 10-100 units",
    caption = paste0(
      "Note: Kaplan-Meier estimates; permits not yet issued by June 30, 2025 are treated as censored, and canceled permits are excluded.\n",
      "Dormant applications had no plan-review action in the 120 days before July 28, 2025. Lines end when fewer than ", min_at_risk, " permits remain pending.\n",
      "Source: City and County of Honolulu Department of Planning and Permitting (DPP), building permits through June 30, 2025; UHERO calculations"
    ),
    x = "Years Since Application",
    y = "Share of Permits Issued",
    color = NULL, linetype = NULL
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE)) +
  theme_uhero()

print(issuance_plot)

if (!dir.exists("outputs")) dir.create("outputs")
ggsave("outputs/Plot_Permit_Issuance_Bill7_vs_Multifamily.png", issuance_plot,
       width = 12, height = 7, dpi = 300, bg = "white")
