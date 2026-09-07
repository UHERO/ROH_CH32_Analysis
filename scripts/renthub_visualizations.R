# ==============================================================================
# Project: Honolulu Bill 7 Market Feasibility Visualizations
# Author: Rafael Munoz, Graduate Assistant, UHERO
# 
# Purpose: 
#   Translates the spatial analysis outputs from `renthub_market_analysis.R` 
#   into public-facing, UHERO-branded graphics. These charts visually communicate 
#   the "Feasibility Gap" / Developer Loophole by showing how the HHFDC 100% AMI 
#   county-wide guideline overshoots natural market rents in the urban core.
# ==============================================================================

library(tidyverse)
library(showtext)
library(scales)

# ==============================================================================
# 1. SETUP UHERO THEME & COLORS
# ==============================================================================
# Load UHERO's official Gotham brand fonts
font_add(family = "Gotham", regular = "fonts/Gotham-Regular.ttf", bold = "fonts/Gotham-Bold.ttf")
showtext_auto()

# UHERO Color Palette
uhero_dark_blue  <- "#1D667F"
uhero_light_blue <- "#7EC4CA"
uhero_gray       <- "#505050"
uhero_gold       <- "#F6A01B"
uhero_green      <- "#9BBB59"

# Custom theme optimized for presentation and readability
theme_uhero <- function(base_size = 16) {
  theme_minimal(base_size = base_size) +
    theme(
      text = element_text(family = "Gotham", color = uhero_gray),
      plot.title = element_text(face = "bold", size = 22, color = uhero_dark_blue, margin = margin(b = 8)),
      plot.subtitle = element_text(size = 16, color = uhero_gray, margin = margin(b = 18)),
      plot.caption = element_text(size = 12, color = uhero_gray, hjust = 0, margin = margin(t = 15), lineheight = 1.2),
      axis.title = element_text(face = "bold", size = 16),
      axis.text = element_text(face = "bold", size = 14),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank(),
      legend.position = "top",
      legend.title = element_blank(),
      legend.text = element_text(size = 16, face = "bold") 
    )
}

# 2026 HHFDC Guideline for a 1-Bedroom (100% Area Median Income)
# Bill 7 Restrictive Covenant limits 80% of units to 100% AMI or below.
ami_100_1bed_cap <- 2887

# Shared Caption Block for all charts incorporating HHFDC Notes
shared_caption <- "Source: RentHub (2023-2026), HNL Permits, HHFDC. Analyzed by UHERO.\nNote: Bill 7 requires 80% of units to be affordable at 100% AMI. *HHFDC acknowledges area market rents may be lower than guidelines.\n**Rent guidelines include utility allowances."

# ==============================================================================
# 2. LOAD ANALYTICS DATA
# ==============================================================================
districts <- read_csv("outputs/RentHub_Council_District_Market_Rents.csv", show_col_types = FALSE)
b7_gaps <- read_csv("outputs/Bill7_Feasibility_Gap_Half_Mile_Radius.csv", show_col_types = FALSE)

# ==============================================================================
# PLOT 1: THE COUNCIL DISTRICT LOOPHOLE (MACRO LEVEL)
# Demonstrates that Districts 5 & 6 (the urban core where Bill 7s are built) 
# actually have the lowest open-market rents on the island, falling well below 
# the "affordable" 100% AMI guideline.
# ==============================================================================
plot1_data <- districts %>%
  filter(!is.na(median_rent_1bed)) %>%
  mutate(
    is_urban_core = ifelse(distname %in% c("District V", "District VI"), "Urban Core (Most Bill 7s)", "Other Districts"),
    distname = reorder(distname, median_rent_1bed)
  )

plot_1 <- ggplot(plot1_data, aes(x = distname, y = median_rent_1bed, fill = is_urban_core)) +
  geom_col(width = 0.7) +
  coord_flip() +
  # Reference line for the 100% AMI Policy Guideline
  geom_hline(yintercept = ami_100_1bed_cap, linetype = "dashed", color = uhero_green, linewidth = 1.2) +
  annotate("text", x = 1.5, y = 1900, label = "HHFDC 100% AMI Guideline ($2,887)", 
           color = uhero_green, family = "Gotham", fontface = "bold", hjust = 0, size = 5.5) +
  scale_fill_manual(values = c("Urban Core (Most Bill 7s)" = uhero_gold, "Other Districts" = uhero_dark_blue)) +
  scale_y_continuous(labels = scales::dollar_format()) +
  labs(
    title = "1-BED MARKET RENTS BY DISTRICT",
    subtitle = "Urban Core open market rents are already cheaper than affordable guidelines.",
    x = "",
    y = "Median 1-Bedroom Market Rent",
    caption = shared_caption
  ) +
  theme_uhero() +
  theme(legend.position = "bottom")

ggsave("outputs/Plot1_District_Loophole.png", plot_1, width = 12, height = 7, dpi = 300)

# ==============================================================================
# PLOT 2: LOCALIZED PROJECT FEASIBILITY GAPS (MESO LEVEL)
# Calculates the exact percentage and dollar amount "buffer" a developer gets 
# between their neighborhood's open market rent and the 100% HHFDC guideline.
# ==============================================================================
plot2_data <- b7_gaps %>%
  filter(comp_listings_within_half_mile > 20) %>% # Filter out low-sample areas for accuracy
  head(15) %>%
  mutate(
    short_address = str_extract(`Property Address`, "^[^,]+"),
    short_address = reorder(short_address, feasibility_gap_1bed),
    gap_status = ifelse(feasibility_gap_1bed > 0, "Market is Higher (Penalty)", "Guideline is Higher (Loophole)"),
    # Calculate percentage deviation from the 100% Guideline baseline
    pct_gap = feasibility_gap_1bed / ami_100_1bed_cap,
    label_text = paste0(ifelse(pct_gap > 0, "+", ""), scales::percent(pct_gap, accuracy = 1))
  )

plot_2 <- ggplot(plot2_data, aes(y = short_address, color = gap_status)) +
  # Diverging Arrows stemming from the zero-line
  geom_segment(aes(x = 0, xend = feasibility_gap_1bed, y = short_address, yend = short_address), 
               arrow = arrow(length = unit(0.25, "cm"), type = "closed"), 
               linewidth = 1.5) +
  # Percentage Text Labels applied to the end of the arrows
  geom_text(aes(x = feasibility_gap_1bed, label = label_text, 
                hjust = ifelse(feasibility_gap_1bed > 0, -0.3, 1.3)),
            family = "Gotham", fontface = "bold", size = 4.5, show.legend = FALSE) +
  geom_vline(xintercept = 0, color = uhero_gray, linewidth = 1) +
  scale_color_manual(values = c("Guideline is Higher (Loophole)" = uhero_green, 
                               "Market is Higher (Penalty)" = uhero_gold)) +
  scale_x_continuous(labels = scales::dollar_format(), expand = expansion(mult = c(0.15, 0.15))) +
  labs(
    title = "100% AMI GUIDELINE TO BILL 7 NEIGHBORHOOD 1-BED RENT GAP",
    subtitle = "% and dollar difference between market rent in neighborhoods with Bill 7 Projects (0.5mi buffer) and 100% AMI Guideline.",
    x = "Rent Gap (Market minus Guideline)",
    y = "",
    caption = shared_caption
  ) +
  theme_uhero() +
  theme(legend.position = "bottom")

ggsave("outputs/Plot2_Project_Feasibility.png", plot_2, width = 12, height = 7, dpi = 300)

# ==============================================================================
# PLOT 3: THE PEW-STYLE DUMBBELL PLOT (MICRO LEVEL / ACTUALS)
# Uses exact address matching and permit age-controls to compare ACTUAL 
# Bill 7 asking rents against newly built apartments (2015+) on the same block.
# ==============================================================================
print("Building the Exact Match Dumbbell Plot...")

dumbbell_data <- read_csv("outputs/Bill7_Dumbbell_Plot_Data_ExactMatch.csv", show_col_types = FALSE) %>%
  mutate(
    short_address = str_extract(`Property Address`, "^[^,]+"),
    rent_gap = local_market_new_1bed_rent - actual_b7_1bed_rent,
    short_address = fct_reorder(short_address, rent_gap) 
  )

plot_dumbbell <- ggplot(dumbbell_data) +
  # Connecting line to show the spread between the two rent points
  geom_segment(aes(x = local_market_new_1bed_rent, xend = actual_b7_1bed_rent, 
                   y = short_address, yend = short_address), 
               color = uhero_gray, linewidth = 1) +
  # Dot 1: New Construction Market Rent (Age Controlled)
  geom_point(aes(x = local_market_new_1bed_rent, y = short_address, color = "Local Market Rent (2015+)"), 
             size = 4) +
  # Dot 2: Actual Bill 7 Rent
  geom_point(aes(x = actual_b7_1bed_rent, y = short_address, color = "Actual Bill 7 Rent"), 
             size = 4) +
  
  # The updated 100% AMI Line
  geom_vline(xintercept = ami_100_1bed_cap, linetype = "dashed", color = uhero_green, linewidth = 1.2) +
  annotate("text", x = ami_100_1bed_cap - 670, y = 1.5, 
           label = "HHFDC 100% AMI Guideline ($2,887)", 
           color = uhero_green, family = "Gotham", fontface = "bold", hjust = 0, size = 5.5) +
  
  scale_x_continuous(labels = scales::dollar_format(), breaks = seq(1000, 4500, by = 500)) +
  scale_color_manual(
    name = NULL, 
    values = c("Local Market Rent (2015+)" = uhero_dark_blue, 
               "Actual Bill 7 Rent" = uhero_gold)
  ) +
  labs(
    title = "BILL 7 VS NEW CONSTRUCTION 1-BED RENTS",
    subtitle = "Actual Bill 7 Rents (Exact Match) vs. Local New Construction (0.5mi radius).",
    x = "Monthly Rent (1-Bedroom)",
    y = "",
    caption = shared_caption
  ) +
  theme_uhero() +
  theme(
    panel.grid.major.y = element_line(color = "#E0E0E0", linetype = "dotted"),
    axis.text.y = element_text(face = "bold"),
    legend.position = "bottom",
    legend.justification = "center"
  )

ggsave("outputs/Plot3_Bill7_Dumbbell_Actuals_Exact.png", plot_dumbbell, width = 12, height = 8, dpi = 300)

# ==============================================================================
# PLOT 4: ACTUAL RENT GAPS (ARROWS + PCT)
# Extrapolates the data from Plot 3 into a clear diverging gap chart.
# Answers: "Are tenants getting a discount compared to the new building next door?"
# ==============================================================================
print("Building the Actual Rent Gaps Plot...")

plot4_data <- dumbbell_data %>%
  mutate(
    actual_rent_gap = local_market_new_1bed_rent - actual_b7_1bed_rent,
    short_address = fct_reorder(short_address, actual_rent_gap),
    gap_status = ifelse(actual_rent_gap > 0, "Market is Higher (Tenant Savings)", "Actual is Higher (Premium)"),
    pct_gap = actual_rent_gap / actual_b7_1bed_rent,
    label_text = paste0(ifelse(pct_gap > 0, "+", ""), scales::percent(pct_gap, accuracy = 1))
  )

plot_4 <- ggplot(plot4_data, aes(y = short_address, color = gap_status)) +
  geom_segment(aes(x = 0, xend = actual_rent_gap, y = short_address, yend = short_address), 
               arrow = arrow(length = unit(0.25, "cm"), type = "closed"), 
               linewidth = 1.5) +
  geom_text(aes(x = actual_rent_gap, label = label_text, 
                hjust = ifelse(actual_rent_gap > 0, -0.3, 1.3)),
            family = "Gotham", fontface = "bold", size = 4.5, show.legend = FALSE) +
  geom_vline(xintercept = 0, color = uhero_gray, linewidth = 1) +
  scale_color_manual(values = c("Market is Higher (Tenant Savings)" = uhero_green, 
                               "Actual is Higher (Premium)" = uhero_gold)) +
  scale_x_continuous(labels = scales::dollar_format(), expand = expansion(mult = c(0.15, 0.15))) +
  labs(
    title = "BILL 7 VS. NEW CONSTRUCTION 1-BED RENT GAP",
    subtitle = "Difference Between Actual Bill 7 Rents (Exact Match) vs. Local New Construction (0.5mi radius).",
    x = "Rent Gap (Market minus Actual Rent)",
    y = "",
    caption = shared_caption
  ) +
  theme_uhero() +
  theme(legend.position = "bottom")

ggsave("outputs/Plot4_Actual_Rent_Gaps.png", plot_4, width = 12, height = 7, dpi = 300)

print("SUCCESS: Visualizations exported to outputs/ folder!")

plot_1
plot_2
plot_dumbbell
plot_4