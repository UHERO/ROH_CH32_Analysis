import pandas as pd
import glob
import os

print("Starting compilation...")

# ==========================================
# 1. COMPILE PLAN REVIEWS
# ==========================================
# Find all files in the folder that end with "_plan_reviews.csv"
plan_review_files = glob.glob("*_plan_reviews.csv")
plan_df_list = []

for file in plan_review_files:
    app_num = file.replace("_plan_reviews.csv", "") # Extract the application number from the filename
    try:
        df = pd.read_csv(file)
        # Add the application number as the first column so we can track it!
        df.insert(0, "Application_Number", app_num) 
        plan_df_list.append(df)
    except Exception as e:
        print(f"Skipping {file} (might be empty): {e}")

if plan_df_list:
    all_plans = pd.concat(plan_df_list, ignore_index=True)
    all_plans.to_csv("MASTER_Plan_Reviews.csv", index=False)
    print(f"✅ Compiled {len(plan_review_files)} Plan Review files into 'MASTER_Plan_Reviews.csv'")
else:
    print("No Plan Review files found to compile.")


# ==========================================
# 2. COMPILE METRICS
# ==========================================
# Find all files in the folder that end with "_metrics.csv"
metric_files = glob.glob("*_metrics.csv")
metric_df_list = []

for file in metric_files:
    try:
        df = pd.read_csv(file)
        metric_df_list.append(df)
    except Exception as e:
        print(f"Skipping {file} (might be empty): {e}")

if metric_df_list:
    # Glue them all together. (Since we formatted these as 1-row dataframes in the scraper, 
    # pd.concat will perfectly stack them on top of each other!)
    all_metrics = pd.concat(metric_df_list, ignore_index=True)
    all_metrics.to_csv("MASTER_Metrics.csv", index=False)
    print(f"✅ Compiled {len(metric_files)} Metrics files into 'MASTER_Metrics.csv'")
else:
    print("No Metrics files found to compile.")

print("\nDone! You can now load these MASTER files into R.")