# =========================================================
# Project: ROH CH32 vs. Non-CH32 Apartment Permit Times (public data)
# Author: Trey Gordner, UHERO
# Assistance: Claude (Anthropic)
#
# PURPOSE:
#   Compares time from application to permit issuance for Bill 7 (ROH 32)
#   projects and other new apartment projects in Honolulu, using DPP's public
#   permit snapshot (Jan 2005 - Jun 30, 2025).
#
#   Graph 3 in roh_ch32_analysis.R compares medians among *issued* permits only,
#   which is biased toward fast permits in recent cohorts. This script reports
#   Kaplan-Meier estimates that count still-pending projects as censored at the
#   snapshot date, so slow, unfinished projects aren't dropped.
#
# DATA (data/, run from the repo root):
#   - honolulu_bp_newbuilding_2018_2025.csv: download with --download, from
#     https://data.honolulu.gov/resource/4vab-c87q (newbuilding = 'Y', created 2018+)
#   - roh32_by_project_20260903.csv: identifies Bill 7 permits by application number
#   - MASTER_Plan_Reviews.csv (optional): flags dormant Bill 7 applications
#
# OUTPUT: outputs/permit_issuance_projects.csv (one row per project; read by
#         permit_issuance_figure.R)
#
# USAGE:
#   python scripts/baseline_permit_times.py [--download] [--data-dir data]
#
# DEFINITIONS:
#   - Apartment projects: DPP structure code "53 - APARTMENT (3 OR MORE)", excluding
#     townhouse projects (proposed use mentions TOWNHOUSE), 4+ units per project.
#     Bill 7 projects are identified by application number and always included.
#     (Occupancy codes R-1/R-2 are building-code classes, not unit counts:
#     single-family and duplexes are R-3, and many Bill 7 permits are coded R-1.)
#   - Projects: large developments file one permit per building, often on the same
#     day. Non-Bill 7 permits are grouped into projects by parcel (first TMK) and
#     application date. A project is issued when all of its permits are issued.
#   - Duration: application -> issuance. "Job Cancelled" permits are excluded.
#     Projects not fully issued are censored at the snapshot date.
# =========================================================

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

SNAPSHOT_DATE = pd.Timestamp("2025-06-30")
POSSE_FREEZE_DATE = pd.Timestamp("2025-07-28")
PUBLIC_FILE = "honolulu_bp_newbuilding_2018_2025.csv"
ROH32_FILE = "roh32_by_project_20260903.csv"
OUTPUT_FILE = Path("outputs") / "permit_issuance_projects.csv"
SOCRATA_URL = "https://data.honolulu.gov/resource/4vab-c87q.csv"
SOCRATA_COLUMNS = ("buildingpermitno,externalfilenum,externalid,createddate,issuedate,completeddate,"
                   "datereviewscompleted,statusdescription,statusid,numunitsadd,occupancygroupcategory,"
                   "proposeduse,structurecode,buildingpermittype,commercialresidential,processreviewtype,"
                   "coissued,finalcoissued,tmk,totalfloorarea,finalstories,cityproject,stateproject")
APARTMENT_STRUCTURE = "53 - APARTMENT (3 OR MORE)"
MIN_PROJECT_UNITS = 4
BILL7_ERA = (2019, 2024)  # application years compared
DORMANT_DAYS = 120
# Graph 3's original text filter, kept only to reproduce its issued-only medians
GRAPH3_PATTERN = "R-1|R-2|R1|R2|APARTMENT|MULTI-FAMILY|MULTIFAMILY|APT|TOWNHOUSE"


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


def load_permits(data_dir):
    permits = pd.read_csv(Path(data_dir) / PUBLIC_FILE, dtype=str)
    roh32 = pd.read_csv(Path(data_dir) / ROH32_FILE, dtype=str)
    permits["units"] = pd.to_numeric(permits.numunitsadd, errors="coerce")
    permits["created"] = pd.to_datetime(permits.createddate).dt.normalize()
    permits["issued"] = pd.to_datetime(permits.issuedate).dt.normalize()
    permits["app_year"] = permits.created.dt.year
    permits["is_bill7"] = permits.externalfilenum.isin(roh32.primary_permit)
    permits["canceled"] = permits.statusdescription.eq("Job Cancelled")
    # first 8-digit TMK in the field (some list several, e.g. "*481551, 43008045")
    permits["parcel"] = permits.tmk.str.extract(r"(\d{8})")[0].fillna(permits.tmk)
    return permits


def dormant_bill7_ids(data_dir):
    """Bill 7 applications with no review action in the DORMANT_DAYS before the Posse freeze."""
    path = Path(data_dir) / "MASTER_Plan_Reviews.csv"
    if not path.exists():
        return None
    reviews = pd.read_csv(path, dtype=str)
    last_action = pd.to_datetime(reviews["Date Completed"], format="%b %d, %Y", errors="coerce") \
        .groupby(reviews.Application_Number).max()
    return set(last_action[last_action < POSSE_FREEZE_DATE - pd.Timedelta(days=DORMANT_DAYS)].index)


def build_projects(permits, dormant_ids):
    """One row per project: Bill 7 permits as-is; other apartment permits grouped by
    parcel and application date."""
    apartments = permits[~permits.canceled & (permits.units > 0) & (
        permits.is_bill7 | (permits.structurecode.eq(APARTMENT_STRUCTURE)
                            & ~permits.proposeduse.str.upper().str.contains("TOWNHOUSE", na=False)))].copy()
    apartments["project_id"] = np.where(
        apartments.is_bill7, apartments.externalfilenum,
        apartments.parcel + "_" + apartments.created.dt.strftime("%Y-%m-%d"))

    projects = apartments.groupby("project_id").agg(
        is_bill7=("is_bill7", "first"),
        created=("created", "min"),
        all_issued=("issued", lambda s: s.notna().all()),
        issued=("issued", "max"),
        units=("units", "sum"),
        permits=("externalfilenum", "size"),
        application_numbers=("externalfilenum", lambda s: ";".join(sorted(s.dropna()))),
    ).reset_index()
    projects["issued"] = projects.issued.where(projects.all_issued)
    projects["event"] = projects.all_issued
    projects["days"] = np.where(projects.event, (projects.issued - projects.created).dt.days,
                                (SNAPSHOT_DATE - projects.created).dt.days)
    projects["app_year"] = projects.created.dt.year
    projects["group"] = np.where(projects.is_bill7, "Bill 7", "Other apartment projects")
    projects["dormant"] = (projects.is_bill7 & ~projects.event
                           & projects.project_id.isin(dormant_ids or set()))
    projects = projects[(projects.units >= MIN_PROJECT_UNITS) & projects.app_year.between(*BILL7_ERA)]
    return projects.drop(columns="all_issued")


# =========================================================
# 2. KAPLAN-MEIER ESTIMATES
# =========================================================

def kaplan_meier(days, event):
    """Survival curve S(t) = share of projects not yet issued by day t."""
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
        "projects": len(df),
        "issued": int(df.event.sum()),
        "pending (censored)": int((~df.event).sum()),
        "at risk at 2 yrs": int((df.days >= 730).sum()),
        "KM median days": below_half.index[0] if len(below_half) else np.nan,
        "issued within 1 yr": share_issued_by(365),
        "issued within 2 yrs": share_issued_by(730),
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

    permits = load_permits(args.data_dir)
    dormant_ids = dormant_bill7_ids(args.data_dir)
    projects = build_projects(permits, dormant_ids)
    bill7 = projects[projects.is_bill7]
    other = projects[~projects.is_bill7]
    print(f"{BILL7_ERA[0]}-{BILL7_ERA[1]} applications, {MIN_PROJECT_UNITS}+ units: "
          f"{len(bill7)} Bill 7 projects; {len(other)} other apartment projects "
          f"from {other.permits.sum()} permits (largest: {other.permits.max()} permits)")
    print("Units per project (median):", projects.groupby("group").units.median().to_dict())

    samples = {
        "Bill 7": bill7,
        "Other apartment projects, 4+ units": other,
        "Other apartment projects, 10-100 units": other[other.units.between(10, 100)],
    }
    if dormant_ids is not None:
        samples["Bill 7, excluding dormant"] = bill7[~bill7.dormant]
        print(f"Dormant Bill 7 applications (no review action in {DORMANT_DAYS} days before the freeze): "
              f"{bill7.dormant.sum()} of {len(bill7)}")

    print("\n[1] Application -> issuance (Kaplan-Meier, projects)")
    table = pd.DataFrame({name: km_summary(df) for name, df in samples.items()}).T
    print(table.to_string(formatters={
        "issued within 1 yr": "{:.0%}".format, "issued within 2 yrs": "{:.0%}".format,
        "KM median days": "{:.0f}".format}))
    print("(KM medians are unstable when most projects are still pending; prefer the within-N-years shares.)")

    print("\n[2] By application period (share issued within 1 / 2 years)")
    rows = []
    for period, years in {"2019-2021": (2019, 2021), "2022-2024": (2022, 2024)}.items():
        for name, df in samples.items():
            s = km_summary(df[df.app_year.between(*years)])
            rows.append({"period": period, "sample": name, "projects": int(s.projects),
                         "within 1 yr": f"{s['issued within 1 yr']:.0%}",
                         "within 2 yrs": f"{s['issued within 2 yrs']:.0%}"})
    print(pd.DataFrame(rows).to_string(index=False))

    # Reproduce Graph 3's issued-only medians with its original permit-level filter
    text = (permits.occupancygroupcategory.fillna("") + " " + permits.proposeduse.fillna("")).str.upper()
    g3 = permits[text.str.contains(GRAPH3_PATTERN) & (permits.units > 0) & ~permits.canceled
                 & permits.issued.notna()]
    g3 = g3.assign(days=(g3.issued - g3.created).dt.days,
                   group=np.where(g3.is_bill7, "Bill 7", "Non-Bill 7 (Graph 3 filter)"))
    print("\n[3] Graph 3 reproduction: issued-only median days by application year (permit level)")
    print(g3.pivot_table(index="app_year", columns="group", values="days", aggfunc="median").round(0).to_string())

    OUTPUT_FILE.parent.mkdir(exist_ok=True)
    projects.sort_values(["group", "created"]).to_csv(OUTPUT_FILE, index=False)
    print(f"\nWrote {OUTPUT_FILE} ({len(projects)} projects)")


if __name__ == "__main__":
    main()
