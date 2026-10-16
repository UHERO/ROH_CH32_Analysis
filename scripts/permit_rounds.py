# =========================================================
# Project: ROH CH32 Plan Review Rounds Analysis
# Author: Trey Gordner, UHERO
# Assistance: Claude (Anthropic)
#
# PURPOSE:
#   Describes how Bill 7 plan reviews unfold, to support the report's
#   permitting section without over- or under-stating DPP's role:
#     1. Review rounds per discipline, and the last discipline to approve
#     2. Agency turnaround per review over time
#     3. Agency turnaround and applicant response time by round number
#     4. Comments returned after the same discipline had already approved
#     5. How concurrent first-round reviews are across disciplines
#     6. Gap between the final review and permit issuance (pickup delay)
#
# DATA (from data/, run from the repo root):
#   - roh32_by_project_20260903.csv (project list, issued dates)
#   - Plan reviews from ONE of:
#       MASTER_Plan_Reviews.csv  (scraped from Posse; see dpp_csv_compiler.py)
#       permits_and_activity_by_tmk_plus_parcel_redacted_no_high_risk_comments.csv
#         (April 2026 DPP export; covers ~50 of 85 projects)
#     --source auto (default) uses MASTER_Plan_Reviews.csv if it exists.
#
# USAGE:
#   python scripts/permit_rounds.py [--source auto|master|export] [--data-dir data]
#
# CAVEATS:
#   - "Received" is when a reviewer received the plans, not when the applicant
#     resubmitted, so routing/queue time shows up as applicant time.
#   - Review data stop at the Posse freeze (2025-07-28).
#   - Outcome-based results (approvals, reopened reviews) need an outcome column.
#     If the scraped file has none, those sections are skipped.
# =========================================================

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

POSSE_FREEZE_DATE = pd.Timestamp("2025-07-28")
ROH32_FILE = "roh32_by_project_20260903.csv"
MASTER_FILE = "MASTER_Plan_Reviews.csv"
EXPORT_FILE = "permits_and_activity_by_tmk_plus_parcel_redacted_no_high_risk_comments.csv"

# Posse placeholders that mean "no date"
DATE_PLACEHOLDERS = ["mmm dd, yyyy", "There is no plan review information available for this permit."]
# Possible names for the outcome column in the scraped Posse table
MASTER_OUTCOME_CANDIDATES = ["Outcome", "Review Outcome", "Result", "Status"]
# Core plan-conformance disciplines, under the export's names. Scraped Posse names
# (e.g., "Building Code", "Fire Code (HFD)") are mapped to these. Set to None to keep all.
CORE_DISCIPLINES = ["BLDG", "Electrical", "Fire", "Mechanical", "TRB", "WWB", "ZPRB"]
DISCIPLINE_ALIASES = {"Building Code": "BLDG", "Electrical Code": "Electrical",
                      "Mechanical Code": "Mechanical", "HFD": "Fire"}
# Review types that aren't part of the plan-conformance rounds
NON_CORE_PATTERN = "revised or shop|Flood|Over the Counter"


# =========================================================
# 1. LOAD DATA
# =========================================================

def load_projects(data_dir):
    projects = pd.read_csv(Path(data_dir) / ROH32_FILE, dtype=str)
    projects["created"] = pd.to_datetime(projects["created_date"])
    projects["issued"] = pd.to_datetime(projects["issued_date"])
    return projects


def load_reviews_from_master(path):
    """Scraped Posse 'Plan Reviews' tables, stacked by dpp_csv_compiler.py."""
    raw = pd.read_csv(path, dtype=str)
    outcome_col = next((c for c in MASTER_OUTCOME_CANDIDATES if c in raw.columns), None)
    print(f"Outcome column in {path.name}: {outcome_col or 'none found (outcome sections skipped)'}")

    def parse(col):
        return pd.to_datetime(raw[col].where(~raw[col].isin(DATE_PLACEHOLDERS)), format="%b %d, %Y", errors="coerce")

    return pd.DataFrame({
        "permit_number": raw["Application_Number"],
        "review_type": raw["Type of Review"],
        "rec": parse("Date Plans Received"),
        "done": parse("Date Completed"),
        "outcome": raw[outcome_col] if outcome_col else pd.NA,
    })


def load_reviews_from_export(path):
    """April 2026 export: one row per permit x review. Column names repeat
    between the permit and review halves, so take the review half by position."""
    raw = pd.read_csv(path, dtype=str, low_memory=False)

    def review_half(name):
        # pandas renames the second copy of a duplicated column to "<name>.1"
        return raw[f"{name}.1"] if f"{name}.1" in raw.columns else raw[name]

    def stored_date(col):
        # Use the stored calendar date; converting to HST puts some completions before receipt
        return pd.to_datetime(raw[col].str[:10], errors="coerce")

    return pd.DataFrame({
        "permit_number": raw["permit_number"],
        "review_type": review_half("MUSW__Type__c"),
        "rec": stored_date("Date_Plans_Received__c"),
        "done": stored_date("Date_Completed__c"),
        "outcome": review_half("Outcome__c"),
    })


def load_reviews(data_dir, source="auto"):
    data_dir = Path(data_dir)
    if source == "auto":
        source = "master" if (data_dir / MASTER_FILE).exists() else "export"
    print(f"Plan review source: {source}")
    if source == "master":
        return load_reviews_from_master(data_dir / MASTER_FILE)
    return load_reviews_from_export(data_dir / EXPORT_FILE)


# =========================================================
# 2. PREP CORE REVIEW ROUNDS
# =========================================================

def prep_core_reviews(reviews, projects):
    """Keep core plan-conformance reviews for Bill 7 permits and number the rounds
    within each permit x discipline."""
    c = reviews[reviews.permit_number.isin(projects.primary_permit) & reviews.rec.notna()].copy()
    disc = c.review_type.str.extract(r"\(([^)]+)\)")[0].fillna(c.review_type)
    c["disc"] = disc.replace(DISCIPLINE_ALIASES)
    c = c[~c.review_type.str.contains(NON_CORE_PATTERN, na=False)]
    if CORE_DISCIPLINES is not None:
        c = c[c.disc.isin(CORE_DISCIPLINES)]

    outcome = c.outcome.astype("string").fillna("")
    c["has_outcome"] = outcome.ne("").any()
    c["approved"] = (outcome.str.contains("Approved|No Review Required|N/A")
                     & ~outcome.str.contains("Rejected"))
    c["negative"] = outcome.isin(["Reviewed - Comments", "Plans Rejected"])

    c = c.drop_duplicates(["permit_number", "disc", "rec", "done", "outcome"])
    c = c.sort_values(["permit_number", "disc", "rec", "done"])
    c["round"] = c.groupby(["permit_number", "disc"]).cumcount() + 1
    c["round_cap"] = c["round"].clip(upper=6)
    c["turnaround"] = (c.done - c.rec).dt.days.clip(lower=0)
    c["review_year"] = c.rec.dt.year
    c["next_rec"] = c.groupby(["permit_number", "disc"]).rec.shift(-1)
    c["applicant_gap"] = (c.next_rec - c.done).dt.days

    c = c.merge(projects[["primary_permit", "created", "issued", "status"]],
                left_on="permit_number", right_on="primary_permit")
    c["app_year"] = c.created.dt.year
    return c


# =========================================================
# 3. ANALYSES
# =========================================================

def rounds_per_discipline(c):
    rounds = c.groupby(["permit_number", "disc"])["round"].max().rename("n_rounds").reset_index()
    by_disc = rounds.groupby("disc").n_rounds.describe()[["count", "mean", "50%", "max"]]
    per_project = rounds.groupby("permit_number").n_rounds.max()
    return by_disc, per_project


def first_approvals(c, projects):
    """Date and round of each discipline's first approval; last discipline to approve
    among issued projects."""
    ok = c[c.approved]
    first_ok = ok.groupby(["permit_number", "disc"]).agg(first_ok=("rec", "min"),
                                                         round_at_ok=("round", "min")).reset_index()
    issued = first_ok[first_ok.permit_number.isin(projects.loc[projects.issued.notna(), "primary_permit"])]
    last_disc = issued.loc[issued.groupby("permit_number").first_ok.idxmax(), "disc"].value_counts()
    round_at_ok = first_ok.groupby("disc").round_at_ok.describe()[["count", "mean", "50%", "max"]]
    return last_disc, round_at_ok


def turnaround_by_year(c):
    return c.groupby("review_year").turnaround.agg(
        n="size", mean="mean", median="median", p90=lambda s: s.quantile(0.9))


def turnaround_by_discipline_period(c):
    period = np.where(c.review_year < 2022, "pre-2022", "2022+")
    return c.assign(period=period).pivot_table(index="disc", columns="period", values="turnaround", aggfunc="mean")


def by_round(c):
    agency = c.groupby("round_cap").turnaround.agg(n="size", mean="mean", median="median")
    # Applicant response follows a review that asked for changes; without outcomes, use any review
    resp = c[c.negative & c.next_rec.notna()] if c.has_outcome.any() else c[c.next_rec.notna()]
    applicant = resp.groupby("round_cap").applicant_gap.agg(n="size", mean="mean", median="median")
    return agency, applicant, resp


def reopened_reviews(c):
    """Comments or rejection from a discipline that had already approved in an earlier round."""
    prior_ok = c.groupby(["permit_number", "disc"]).approved.transform(
        lambda s: s.shift(1, fill_value=False).cummax())
    prev_outcome = c.groupby(["permit_number", "disc"]).outcome.shift(1)
    reopened = c[prior_ok & c.negative].assign(prev_outcome=prev_outcome)
    return reopened, int(prior_ok.sum())


def first_round_spread(c):
    """How long after the first discipline each discipline received plans in round 1."""
    r1 = c[c["round"] == 1].copy()
    r1["lag"] = (r1.rec - r1.groupby("permit_number").rec.transform("min")).dt.days
    return r1


def project_cycles(reviews, projects, issued_ids, tolerances=(0, 7, 14)):
    """Project-level review cycles, all disciplines: merge review windows that start within
    `tol` days of the previous window's end. Merged spans = agency time; gaps = applicant time.
    With tol = 14 this approximates DPP's column (7+ cycles, ~36 agency days per cycle)."""
    r = reviews[reviews.permit_number.isin(issued_ids) & reviews.rec.notna()].copy()
    r["done"] = r.done.fillna(POSSE_FREEZE_DATE).clip(lower=r.rec)
    rows = []
    for tol in tolerances:
        for permit, g in r.sort_values("rec").groupby("permit_number"):
            spans = []
            for rec, done in zip(g.rec, g.done):
                if spans and rec <= spans[-1][1] + pd.Timedelta(days=tol):
                    spans[-1][1] = max(spans[-1][1], done)
                else:
                    spans.append([rec, done])
            agency = sum((e - b).days + 1 for b, e in spans)
            gaps = [(spans[i + 1][0] - spans[i][1]).days - 1 for i in range(len(spans) - 1)]
            rows.append({"merge_within_days": tol, "permit": permit, "cycles": len(spans),
                         "agency_days": agency, "applicant_days": sum(gaps),
                         "agency_per_cycle": agency / len(spans),
                         "applicant_per_gap": sum(gaps) / len(gaps) if gaps else np.nan})
    return pd.DataFrame(rows).groupby("merge_within_days").agg(
        permits=("permit", "nunique"), cycles_mean=("cycles", "mean"), cycles_median=("cycles", "median"),
        agency_days=("agency_days", "mean"), agency_per_cycle=("agency_per_cycle", "mean"),
        applicant_days=("applicant_days", "mean"), applicant_per_gap=("applicant_per_gap", "mean"))


def posse_milestones(data_dir, projects):
    """Posse 'Metrics' tab milestones per application (MASTER_Metrics.csv), if present."""
    path = Path(data_dir) / "MASTER_Metrics.csv"
    if not path.exists():
        return None
    m = pd.read_csv(path, dtype=str)
    m = m[m.Application_Number.isin(projects.primary_permit)].copy()
    day_cols = [c for c in m.columns if c.startswith("Days ") or c == "Total Days to Issue"]
    for col in day_cols:
        m[col] = pd.to_numeric(m[col], errors="coerce")
    for col in ["Application Submitted, Unchecked", "Application Accepted by DPP",
                "Permit Ready for Pickup", "Permit Issued"]:
        m[col] = pd.to_datetime(m[col], format="%b %d, %Y", errors="coerce")
    m["app_year"] = m["Application Submitted, Unchecked"].dt.year
    m["accepted_to_ready"] = (m["Permit Ready for Pickup"] - m["Application Accepted by DPP"]).dt.days
    return m, day_cols


def review_to_issuance(c, projects):
    """Final review completion to permit issuance. Only meaningful for permits issued
    before the Posse freeze; later reviews aren't in the data."""
    last_done = c.groupby("permit_number").done.max().rename("last_review_done")
    g = projects.set_index("primary_permit")[["created", "issued", "status"]].join(last_done, how="inner")
    g = g[g.issued.notna()].copy()
    g["review_to_issue"] = (g.issued - g.last_review_done).dt.days
    g["app_to_issue"] = (g.issued - g.created).dt.days
    g["issued_before_freeze"] = g.issued <= POSSE_FREEZE_DATE
    return g


# =========================================================
# 4. REPORT
# =========================================================

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", choices=["auto", "master", "export"], default="auto")
    parser.add_argument("--data-dir", default="data")
    args = parser.parse_args()
    pd.set_option("display.width", 200)

    projects = load_projects(args.data_dir)
    reviews = load_reviews(args.data_dir, args.source)
    c = prep_core_reviews(reviews, projects)
    has_outcome = bool(c.has_outcome.any())
    print(f"Projects with reviews: {c.permit_number.nunique()} of {len(projects)}; core reviews: {len(c)}")

    by_disc, per_project = rounds_per_discipline(c)
    print("\n[1] Rounds per discipline:\n", by_disc.round(1).to_string())
    print(f"Slowest discipline's rounds per project: mean {per_project.mean():.1f}, "
          f"median {per_project.median():.0f}, range {per_project.min()}-{per_project.max()}")
    if has_outcome:
        last_disc, round_at_ok = first_approvals(c, projects)
        print("\nLast discipline to approve (issued projects):\n", last_disc.to_string())
        print("\nRound at first approval:\n", round_at_ok.round(1).to_string())

    print("\n[2] Agency turnaround per review (days), by year received:\n",
          turnaround_by_year(c).round(1).to_string())
    print(f"Closed same day: {(c.turnaround == 0).mean():.0%}; within 7 days: {(c.turnaround <= 7).mean():.0%}")
    print("\nMean turnaround by discipline, pre-2022 vs 2022+:\n",
          turnaround_by_discipline_period(c).round(1).to_string())

    agency, applicant, resp = by_round(c)
    print("\n[3] Agency turnaround by round (6 = 6+):\n", agency.round(1).to_string())
    print("\nApplicant response (days to resubmit, same discipline) by round:\n", applicant.round(1).to_string())
    print("\nApplicant response by application year (median days):\n",
          resp.groupby("app_year").applicant_gap.agg(n="size", median="median").to_string())

    if has_outcome:
        reopened, n_post_ok = reopened_reviews(c)
        print(f"\n[4] Comments/rejection after the same discipline had approved: "
              f"{len(reopened)} of {n_post_ok} post-approval reviews, "
              f"in {reopened.permit_number.nunique()} of {c.permit_number.nunique()} projects")
        print("Preceding outcome:\n", reopened.prev_outcome.value_counts().to_string())
        late = c[c["round"] >= 4]
        print(f"Round 4+ reviews: {len(late)}; share with comments/rejection: {late.negative.mean():.0%}")

    r1 = first_round_spread(c)
    print(f"\n[5] Round-1 lag behind the first discipline: median {r1.lag.median():.0f} days; "
          f"share > 30 days: {(r1.lag > 30).mean():.0%}")
    print(r1.groupby("disc").lag.median().to_string())

    g = review_to_issuance(c, projects)
    pre = g[g.issued_before_freeze]
    print(f"\n[6] Final review -> issuance, permits issued before {POSSE_FREEZE_DATE.date()} (n={len(pre)}): "
          f"median {pre.review_to_issue.median():.0f}, mean {pre.review_to_issue.mean():.0f}, "
          f"max {pre.review_to_issue.max():.0f} days; "
          f"{pre.review_to_issue.sum() / pre.app_to_issue.sum():.0%} of application -> issuance time")
    print(f"Application -> issuance for these: median {pre.app_to_issue.median():.0f}, "
          f"mean {pre.app_to_issue.mean():.0f} days")
    print(f"({(~g.issued_before_freeze).sum()} permits issued after the freeze are excluded: "
          f"their final reviews aren't in the data.)")

    issued_ids = set(pre.index)
    print(f"\n[7] Project-level review cycles (all disciplines), permits issued before the freeze:")
    print(project_cycles(reviews, projects, issued_ids).round(1).to_string())
    print("DPP column for comparison: 7+ cycles, 36 agency days/cycle, 46 applicant days/response.")

    milestones = posse_milestones(args.data_dir, projects)
    if milestones is not None:
        m, day_cols = milestones
        issued_m = m[m["Permit Issued"].notna()]
        print(f"\n[8] Posse milestone metrics (MASTER_Metrics.csv), issued permits (n={len(issued_m)}):")
        print(issued_m[day_cols].agg(["mean", "median"]).round(0).to_string())
        print(f"Acceptance -> ready for pickup: median {issued_m.accepted_to_ready.median():.0f} days; "
              f"within 90 days: {(issued_m.accepted_to_ready <= 90).sum()} of {len(issued_m)}")
        print("\nDays in Pre-Submission Queue by application year (all applications):")
        print(m.groupby("app_year")["Days in Pre-Submission Queue"].agg(["count", "median", "mean"]).round(0).to_string())


if __name__ == "__main__":
    main()
