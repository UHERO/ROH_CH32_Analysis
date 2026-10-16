# =========================================================
# Project: ROH CH32 Plan Review Rounds - Data & Sensitivity Checks
# Author: Trey Gordner, UHERO
# Assistance: Claude (Anthropic)
#
# PURPOSE:
#   Checks behind permit_rounds.py, to run before quoting its numbers:
#     1. Coverage: which Bill 7 projects have review records
#     2. Date integrity: missing, reversed, or post-freeze dates
#     3. Sensitivity: do the headline numbers move if non-core reviews
#        (shop drawings, DOH, BWS, CEB, DOE impact fee) are kept?
#
# USAGE (from the repo root; same options as permit_rounds.py):
#   python scripts/permit_rounds_checks.py [--source auto|master|export] [--data-dir data]
# =========================================================

import argparse
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import permit_rounds as pr  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", choices=["auto", "master", "export"], default="auto")
    parser.add_argument("--data-dir", default="data")
    args = parser.parse_args()
    pd.set_option("display.width", 200)

    projects = pr.load_projects(args.data_dir)
    reviews = pr.load_reviews(args.data_dir, args.source)
    b7 = reviews[reviews.permit_number.isin(projects.primary_permit)]

    # ---- 1. Coverage
    covered = set(b7.loc[b7.rec.notna(), "permit_number"])
    missing = projects[~projects.primary_permit.isin(covered)]
    print(f"[1] Projects with review records: {len(covered)} of {len(projects)}")
    print("Missing, by status:\n", missing.status.value_counts().to_string())
    print("Missing, by application year:\n", missing.created.dt.year.value_counts().sort_index().to_string())

    # ---- 2. Date integrity
    has_rec = b7.rec.notna()
    print(f"\n[2] Review rows for Bill 7 permits: {len(b7)}; with a received date: {has_rec.sum()}")
    print(f"No completion date (counted as open to the freeze in Graph 5): {(has_rec & b7.done.isna()).sum()}")
    print(f"Completed before received: {(b7.done < b7.rec).sum()}")
    print(f"Received after the Posse freeze ({pr.POSSE_FREEZE_DATE.date()}): {(b7.rec > pr.POSSE_FREEZE_DATE).sum()}")
    print(f"Exact duplicate review rows: {b7.duplicated().sum()}")
    if b7.outcome.notna().any():
        print("Outcomes:\n", b7.outcome.value_counts(dropna=False).to_string())
    else:
        print("No outcome column: approval-based results in permit_rounds.py are skipped.")

    # ---- 3. Sensitivity to the core-review filter
    core = pr.prep_core_reviews(reviews, projects)
    original_pattern, original_discs = pr.NON_CORE_PATTERN, pr.CORE_DISCIPLINES
    pr.NON_CORE_PATTERN, pr.CORE_DISCIPLINES = "^$", None
    try:
        all_reviews = pr.prep_core_reviews(reviews, projects)
    finally:
        pr.NON_CORE_PATTERN, pr.CORE_DISCIPLINES = original_pattern, original_discs

    def headline(c):
        _, per_project = pr.rounds_per_discipline(c)
        g = pr.review_to_issuance(c, projects)
        pre = g[g.issued_before_freeze]
        return pd.Series({
            "reviews": len(c),
            "median rounds (slowest discipline)": per_project.median(),
            "mean turnaround (days)": c.turnaround.mean(),
            "share closed same day": (c.turnaround == 0).mean(),
            "median review->issue (pre-freeze)": pre.review_to_issue.median(),
        })

    print("\n[3] Headline numbers, core reviews vs all reviews:")
    print(pd.DataFrame({"core": headline(core), "all": headline(all_reviews)}).round(2).to_string())


if __name__ == "__main__":
    main()
