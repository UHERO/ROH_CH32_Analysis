# =========================================================
# Project: ROH CH32 Permit Issuance Figure (Bill 7 vs. Other Multifamily)
# Author: Trey Gordner, UHERO
# Assistance: Claude (Anthropic)
#
# PURPOSE:
#   Plots the cumulative share of projects with permits issued, by years since
#   application, for Bill 7 (ROH 32) projects and other new apartment projects
#   (4+ units), 2019-2024 applications. Kaplan-Meier estimates treat projects still
#   pending at the snapshot date as censored, so slow, unfinished projects are not
#   dropped (unlike Graph 3's issued-only medians).
#
#   Reads the project table written by scripts/baseline_permit_times.py, which
#   holds the definitions (apartment structure code, no townhouses, permits
#   grouped into projects) and prints the numbers quoted in the report.
#
# DATA (run from the repo root):
#   - outputs/permit_issuance_projects.csv (python scripts/baseline_permit_times.py)
#
# OUTPUT: outputs/Plot_Permit_Issuance_Bill7_vs_Apartments.png
# =========================================================

library(tidyverse)
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
# DATA LOADING (definitions live in baseline_permit_times.py)
# =========================================================
projects <- read_csv("outputs/permit_issuance_projects.csv", show_col_types = FALSE)

samples <- bind_rows(
  projects %>% filter(is_bill7) %>% mutate(Group = "Bill 7"),
  projects %>% filter(is_bill7, !dormant) %>% mutate(Group = "Bill 7, excluding dormant applications"),
  projects %>% filter(!is_bill7) %>% mutate(Group = "Other apartment projects")
)

group_levels <- c("Bill 7", "Bill 7, excluding dormant applications", "Other apartment projects")
samples <- samples %>% mutate(Group = factor(Group, levels = group_levels))

# --- INTEGRITY TEST ---
stopifnot(
  "FAIL: no Bill 7 projects" = sum(samples$Group == "Bill 7") > 0,
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
stopifnot("FAIL: too few projects at risk at two years to label" = all(km_labels_2yr$At_Risk >= min_at_risk))

# =========================================================
# GRAPH: SHARE OF PROJECTS ISSUED BY YEARS SINCE APPLICATION
# =========================================================
group_colors <- c("Bill 7" = uhero_dark_blue,
                  "Bill 7, excluding dormant applications" = uhero_dark_blue,
                  "Other apartment projects" = uhero_gold)
group_lines <- c("Bill 7" = "solid",
                 "Bill 7, excluding dormant applications" = "dashed",
                 "Other apartment projects" = "solid")
legend_labels <- group_counts %>%
  mutate(label = paste0(Group, " (n = ", n, ")")) %>%
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
    title = "SHARE OF APARTMENT PROJECTS PERMITTED, BY TIME SINCE APPLICATION",
    subtitle = "New apartment projects (4+ units) applied for 2019-2024: Bill 7 vs. other apartment projects",
    caption = paste0(
      "Note: Kaplan-Meier estimates. Projects not fully permitted by June 30, 2025 are treated as censored; canceled permits are excluded. ",
      "Other apartment projects
are DPP structure code 53 (apartment, 3+ units) excluding townhouses, with building permits grouped by parcel and application date. ",
      "Dormant applications had
no plan-review action in the 120 days before July 28, 2025. Lines end when fewer than ", min_at_risk, " projects remain pending.
",
      "Source: City and County of Honolulu Department of Planning and Permitting (DPP), building permits through June 30, 2025; UHERO calculations"
    ),
    x = "Years Since Application",
    y = "Share of Projects Permitted",
    color = NULL, linetype = NULL
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE)) +
  theme_uhero()

print(issuance_plot)

if (!dir.exists("outputs")) dir.create("outputs")
ggsave("outputs/Plot_Permit_Issuance_Bill7_vs_Apartments.png", issuance_plot,
       width = 12, height = 7, dpi = 300, bg = "white")
