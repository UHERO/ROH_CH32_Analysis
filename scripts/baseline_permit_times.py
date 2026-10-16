# =========================================================
# Project: ROH CH32 vs. Non-CH32 Multifamily Permit Times (public data)
# Author: Trey Gordner, UHERO
# Assistance: Claude (Anthropic)
#
# PURPOSE:
#   Compares time from application to permit issuance for Bill 7 (ROH 32)
#   and other new multifamily building permits in Honolulu, using DPP's
#   public permit snapshot (Jan 2005 - Jun 30, 2025).
#
#   Graph 3 in roh_ch32_analysis.R compares medians among *issued* permits only,
#   which is biased toward fast permits in recent cohorts. This script also reports
#   Kaplan-Meier estimates that count still-pending permits as censored at the
#   snapshot date, so slow, unfinished permits aren't dropped.
#
# DATA (data/, run from the repo root):
#   - honolulu_bp_newbuilding_2018_2025.csv: download with --download, from
#     https://data.honolulu.gov/resource/4vab-c87q (newbuilding = 'Y', created 2018+)
#   - roh32_by_project_20260903.csv: identifies Bill 7 permits by application number
#
# USAGE:
#   python scripts/baseline_permit_times.py [--download] [--data-dir data]
#
# DEFINITIONS:
#   - Multifamily: same text filter as roh_ch32_analysis.R (R-1/R-2/apartment/
#     multi-family/townhouse in occupancy group or proposed use), units added > 0
#   - Duration: createddate -> issuedate. "Job Cancelled" permits are excluded.
#   - Permits without an issue date are censored at the snapshot date.
#   - Each permit counts once; some baseline projects file one permit per building.
# =========================================================

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

SNAPSHOT_DATE = pd.Timestamp("2025-06-30")
POSSE_FREEZE_DATE = pd.Timestamp("2025-07-28")
PUBLIC_FILE = "honolulu_bp_newbuilding_2018_2025.csv"
ROH32_FILE = "roh32_by_project_20260903.csv"
SOCRATA_URL = "https://data.honolulu.gov/resource/4vab-c87q.csv"
SOCRATA_COLUMNS = ("buildingpermitno,externalfilenum,externalid,createddate,issuedate,completeddate,"
                   "datereviewscompleted,statusdescription,statusid,numunitsadd,occupancygroupcategory,"
                   "proposeduse,structurecode,buildingpermittype,commercialresidential,processreviewtype,"
                   "coissued,finalcoissued,tmk,totalfloorarea,finalstories,cityproject,stateproject")
MF_PATTERN = "R-1|R-2|R1|R2|APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT|TOWNHOUSE"
BILL7_ERA = (2019, 2024)  # application years compared


# =========================================================
# 1. LOAD DATA
# =========================================================

def download(data_dir):
    import urllib.parse
    import urllib.request
    query = urllib.parse.urlencode({
        "$where": "newbuilding='Y' AND createddate>='2018-01-01'",
        "$select": SOCRATA_COLUMNS,
        "$limit": 50000,
    })
    path = Path(data_dir) / PUBLIC_FILE
    urllib.request.urlretrieve(f"{SOCRATA_URL}?{query}", path)
    print(f"Downloaded {path}")


def load_multifamily(data_dir):
    permits = pd.read_csv(Path(data_dir) / PUBLIC_FILE, dtype=str)
    roh32 = pd.read_csv(Path(data_dir) / ROH32_FILE, dtype=str)

    text = (permits.occupancygroupcategory.fillna("") + " " + permits.proposeduse.fillna("")).str.upper()
    mf = permits[text.str.contains(MF_PATTERN)].copy()
    mf["units"] = pd.to_numeric(mf.numunitsadd, errors="coerce")
    mf = mf[mf.units > 0]

    mf["created"] = pd.to_datetime(mf.createddate).dt.normalize()
    mf["issued"] = pd.to_datetime(mf.issuedate).dt.normalize()
    mf["app_year"] = mf.created.dt.year
    mf["group"] = np.where(mf.externalfilenum.isin(roh32.primary_permit), "Bill 7", "Non-Bill 7 multifamily")
    mf["canceled"] = mf.statusdescription.eq("Job Cancelled")
    mf["event"] = mf.issued.notna()
    mf["days"] = np.where(mf.event, (mf.issued - mf.created).dt.days, (SNAPSHOT_DATE - mf.created).dt.days)
    return mf


# =========================================================
# 2. KAPLAN-MEIER ESTIMATES
# =========================================================

def kaplan_meier(days, event):
    """Survival curve S(t) = share of permits not yet issued by day t."""
    d = pd.DataFrame({"days": days, "event": event.astype(int)}).sort_values("days")
    at_risk = len(d)
    times, surv, s = [0], [1.0], 1.0
    for t, grp in d.groupby("days"):
        issued = grp.event.sum()
        if issued:
            s *= 1 - issued / at_risk
            times.append(t)
            surv.append(s)
        at_risk -= len(grp)
    return pd.Series(surv, index=times)


def km_summary(df):
    curve = kaplan_meier(df.days, df.event)
    below_half = curve[curve <= 0.5]
    def share_issued_by(t):
        return 1 - curve[curve.index <= t].iloc[-1]
    return pd.Series({
        "permits": len(df),
        "issued": int(df.event.sum()),
        "pending (censored)": int((~df.event).sum()),
        "KM median days": below_half.index[0] if len(below_half) else np.nan,
        "issued within 1 yr": share_issued_by(365),
        "issued within 2 yrs": share_issued_by(730),
        "issued-only median days": df.loc[df.event, "days"].median(),
    })


# =========================================================
# 3. REPORT
# =========================================================

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--download", action="store_true", help="re-download the public permit snapshot")
    parser.add_argument("--data-dir", default="data")
    args = parser.parse_args()
    pd.set_option("display.width", 200)
    if args.download:
        download(args.data_dir)

    mf = load_multifamily(args.data_dir)
    active = mf[~mf.canceled]
    era = active[active.app_year.between(*BILL7_ERA)]
    print(f"Multifamily new-building permits since 2018: {len(mf)} "
          f"({(mf.group == 'Bill 7').sum()} Bill 7); excluding {mf.canceled.sum()} canceled")
    print("Units per permit (median):", mf.groupby("group").units.median().to_dict())

    print(f"\n[1] Application -> issuance, {BILL7_ERA[0]}-{BILL7_ERA[1]} applications")
    samples = {
        "Bill 7": era[era.group == "Bill 7"],
        "Non-Bill 7, all sizes": era[era.group != "Bill 7"],
        "Non-Bill 7, 10-100 units": era[(era.group != "Bill 7") & era.units.between(10, 100)],
    }
    table = pd.DataFrame({name: km_summary(df) for name, df in samples.items()}).T
    print(table.to_string(formatters={
        "issued within 1 yr": "{:.0%}".format, "issued within 2 yrs": "{:.0%}".format,
        "KM median days": "{:.0f}".format, "issued-only median days": "{:.0f}".format}))

    print("\n[2] By application period")
    rows = []
    for (period, years) in {"2019-2021": (2019, 2021), "2022-2024": (2022, 2024)}.items():
        for name, df in samples.items():
            s = km_summary(df[df.app_year.between(*years)])
            rows.append({"period": period, "sample": name, "permits": int(s.permits),
                         "KM median days": s["KM median days"], "within 1 yr": f"{s['issued within 1 yr']:.0%}",
                         "within 2 yrs": f"{s['issued within 2 yrs']:.0%}"})
    print(pd.DataFrame(rows).to_string(index=False))
    print("(KM medians are unstable when most permits are still pending; prefer the within-N-years shares.)")

    # Sensitivity: drop Bill 7 applications that look abandoned (no review action in the
    # 120 days before the Posse freeze), as Graph 5 does. Baseline can't be screened this way.
    reviews_path = Path(args.data_dir) / "MASTER_Plan_Reviews.csv"
    if reviews_path.exists():
        reviews = pd.read_csv(reviews_path, dtype=str)
        last_action = pd.to_datetime(reviews["Date Completed"], format="%b %d, %Y", errors="coerce") \
            .groupby(reviews.Application_Number).max()
        bill7 = samples["Bill 7"]
        stale = bill7.externalfilenum.map(last_action) < POSSE_FREEZE_DATE - pd.Timedelta(days=120)
        dormant = ~bill7.event & stale.fillna(False)
        s = km_summary(bill7[~dormant])
        print(f"\n[2b] Bill 7 excluding {dormant.sum()} dormant applications (no review action in 120 days): "
              f"{int(s.permits)} permits; issued within 1 yr {s['issued within 1 yr']:.0%}, "
              f"within 2 yrs {s['issued within 2 yrs']:.0%}")

    print("\n[3] Issued-only medians by application year (as in Graph 3; biased low for recent years)")
    print(active[active.event].pivot_table(index="app_year", columns="group", values="days",
                                           aggfunc="median").round(0).to_string())


if __name__ == "__main__":
    main()
