from io import StringIO
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager
import pandas as pd
import time

# 1. Your Master List of Applications
app_list = [
    "A2019-10-0829", "A2020-02-0439", "A2020-04-0226", "A2021-08-1299", "A2021-08-1465",
    "A2021-11-0190", "A2021-11-0957", "A2021-12-0604", "A2022-01-0039", "A2022-01-0064",
    "A2022-09-1596", "A2023-01-1230", "A2023-03-0727", "A2024-06-0020", "A2023-09-0783",
    "A2024-03-0331", "A2024-11-0943", "A2019-10-1481", "A2021-01-0938", "A2022-05-1606",
    "A2022-11-1082", "A2022-11-1572", "A2024-03-1106", "A2020-05-0631", "A2020-07-1587",
    "A2020-10-0283", "A2020-11-0902", "A2021-01-0067", "A2021-07-0613", "A2021-08-1085",
    "A2021-10-0454", "A2021-11-0369", "A2022-04-0729", "A2022-04-1454", "A2025-03-0016",
    "A2022-11-0830", "A2022-11-1722", "A2023-01-0097", "A2023-01-0880", "A2023-01-1333",
    "A2023-03-0470", "A2023-04-0024", "A2023-05-0995", "A2023-06-0706", "A2024-08-1190",
    "A2023-06-0917", "MA-2025-0171", "A2023-07-1121", "A2024-03-0996", "A2024-11-0711",
    "A2024-09-0744", "A2024-11-1198", "A2024-11-1249", "A2025-01-0945", "A2025-02-0389",
    "A2025-04-0176", "A2025-05-0918", "A2023-03-0130", "A2023-12-0586", "A2024-11-0901",
    "A2025-02-0848", "MA-2025-0153", "MA-2025-0244", "MA-2025-0318", "A2024-05-1343"
]

print(f"Starting the browser to scrape {len(app_list)} applications...")

service = Service(ChromeDriverManager().install())
driver = webdriver.Chrome(service=service)
wait = WebDriverWait(driver, 10) 

# Base URLs depending on permit type
building_url = "https://dppweb.honolulu.gov/DPPWeb/Default.aspx?PossePresentation=BuildingSignPermitSearch"
job_url = "https://dppweb.honolulu.gov/DPPWeb/Default.aspx?PossePresentation=JobSearch"

# 2. Loop through every application
for app_num in app_list:
    try:
        print(f"\n========================================")
        print(f"Processing: {app_num}")
        
        # Determine correct search URL (Master Apps use JobSearch)
        if app_num.startswith("MA-"):
            driver.get(job_url)
        else:
            driver.get(building_url)
            
        time.sleep(2) 

        # We use a broad CSS selector here to catch the search box regardless of what the page calls it
        search_selectors = "input[id^='ApplicationNumber_'], input[id^='JobNumber_'], input[id^='ReferenceNumber_'], input[id^='FileNumber_']"
        search_box = wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, search_selectors)))
        
        search_box.clear()
        search_box.send_keys(app_num)
        search_box.send_keys(Keys.RETURN)
        
        time.sleep(3)

        # ---------------------------------------------------------
        # SCRAPE 1: PLAN REVIEWS TAB
        # ---------------------------------------------------------
        try:
            plan_reviews_tab = wait.until(EC.presence_of_element_located((By.XPATH, "//*[contains(text(), 'Plan Reviews')]")))
            driver.execute_script("arguments[0].click();", plan_reviews_tab)
            time.sleep(2) 
            
            html = driver.page_source
            tables = pd.read_html(StringIO(html), match="Type of Review")
            plan_df = tables[-1] 
            plan_df = plan_df.dropna(axis=1, how='all').dropna(axis=0, how='all')
            if 'Unnamed' in str(plan_df.columns[0]):
                plan_df = plan_df.iloc[:, 1:]
                
            plan_df.to_csv(f"{app_num}_plan_reviews.csv", index=False)
            print(f"[*] Saved clean Plan Reviews.")
            
        except Exception as e:
            print(f"[!] Could not scrape Plan Reviews for {app_num}. (It might not have this tab yet)")

        # ---------------------------------------------------------
        # SCRAPE 2: METRICS TAB (WITH CLEANING!)
        # ---------------------------------------------------------
        try:
            metrics_tab = wait.until(EC.presence_of_element_located((By.XPATH, "//*[contains(text(), 'Metrics')]")))
            driver.execute_script("arguments[0].click();", metrics_tab)
            time.sleep(2)
            
            html = driver.page_source
            metric_tables = pd.read_html(StringIO(html))
            raw_metrics_df = max(metric_tables, key=len)
            
            # Create a dictionary to hold our clean, flat data
            clean_metrics = {"Application_Number": app_num}
            
            # Loop through the raw visual table and extract the actual data points
            for _, row in raw_metrics_df.iterrows():
                
                # Check for Milestones (Label in Col 1, Date in Col 3)
                if pd.notna(row.iloc[1]) and isinstance(row.iloc[1], str) and ":" in row.iloc[1]:
                    label = row.iloc[1].replace(":", "").strip()
                    clean_metrics[label] = row.iloc[3]
                    
                # Check for Timelines (Label in Col 0, Days in Col 1)
                if pd.notna(row.iloc[0]) and isinstance(row.iloc[0], str) and "Days" in row.iloc[0]:
                    label = row.iloc[0].strip()
                    clean_metrics[label] = row.iloc[1]

            # Convert dictionary into a flat 1-row DataFrame and save
            clean_metrics_df = pd.DataFrame([clean_metrics])
            clean_metrics_df.to_csv(f"{app_num}_metrics.csv", index=False)
            print(f"[*] Saved clean Metrics.")
            
        except Exception as e:
            print(f"[!] Could not scrape Metrics for {app_num}. (It might not have this tab yet)")

    except Exception as general_error:
        print(f"[!] Critical error processing {app_num}: {general_error}")
        continue 

print("\n========================================")
print("ALL SCRAPING COMPLETE!")
time.sleep(3)
driver.quit()