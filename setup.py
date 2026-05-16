"""
setup.py
Orchestrates the full APIS pipeline:
  1. Load Kaggle advertising data
  2. Enrich with synthetic fields (advertiser IDs, channels, verticals, holdout)
  3. Register all SQL views in DuckDB
  4. Export processed tables for the dashboard
"""

import duckdb
import pandas as pd
import numpy as np
import os
from pathlib import Path

RAW_PATH    = Path("data/raw/advertising.csv")
OUT_PATH    = Path("data/processed")
SQL_PATH    = Path("sql")
OUT_PATH.mkdir(parents=True, exist_ok=True)

VERTICALS = ["Retail", "Finance", "Travel", "Automotive", "Technology", "FMCG"]
CHANNELS  = ["Search", "Display", "Video", "Shopping", "App"]


def load_and_enrich(path: Path) -> pd.DataFrame:
    """
    Load the Kaggle dataset and synthesise the fields needed for
    the AVA-style analysis (IDs, verticals, holdout flag, etc.)
    """
    df = pd.read_csv(path)

    # The Kaggle dataset has columns: TV, Radio, Newspaper, Sales
    # We treat each row as one monthly campaign record
    n = len(df)
    rng = np.random.default_rng(42)

    df = df.rename(columns={
        "TV":        "tv_spend",
        "Radio":     "radio_spend",
        "Newspaper": "newspaper_spend",
        "Sales":     "sales_revenue"
    })

    # Build tidy, per-channel rows
    records = []
    for idx, row in df.iterrows():
        adv_id   = 1000 + (idx % 50)           # 50 synthetic advertisers
        vertical = VERTICALS[idx % len(VERTICALS)]
        date     = pd.Timestamp("2023-01-01") + pd.DateOffset(days=idx)

        channel_map = {
            "TV":        (row["tv_spend"],        row["sales_revenue"] * 0.40),
            "Radio":     (row["radio_spend"],      row["sales_revenue"] * 0.25),
            "Newspaper": (row["newspaper_spend"],  row["sales_revenue"] * 0.15),
            "Search":    (row["tv_spend"] * 0.3,   row["sales_revenue"] * 0.15),
            "Display":   (row["radio_spend"] * 0.2,row["sales_revenue"] * 0.05),
        }
        for channel, (spend, rev) in channel_map.items():
            if spend <= 0:
                continue
            impressions = int(spend * rng.uniform(80, 200))
            clicks      = int(impressions * rng.uniform(0.01, 0.05))
            conversions = int(clicks * rng.uniform(0.02, 0.15))
            records.append({
                "advertiser_id": adv_id,
                "campaign_date": date.date(),
                "vertical":      vertical,
                "channel":       channel,
                "spend_gbp":     round(spend, 2),
                "impressions":   impressions,
                "clicks":        clicks,
                "conversions":   conversions,
                "revenue_gbp":   round(rev, 2),
                "is_holdout":    bool(rng.random() < 0.15),  # 15% holdout
            })

    return pd.DataFrame(records)


def register_sql_views(con: duckdb.DuckDBPyConnection) -> None:
    """Execute all SQL files in order."""
    sql_files = sorted(SQL_PATH.glob("*.sql"))
    for f in sql_files:
        print(f"  → Executing {f.name}")
        con.execute(f.read_text())


def export_tables(con: duckdb.DuckDBPyConnection) -> None:
    """Export key views to CSV for the dashboard."""
    exports = {
        "kpi_summary":       "SELECT * FROM v_executive_kpi_summary",
        "roas_tiers":        "SELECT * FROM v_roas_tiers",
        "incrementality":    "SELECT * FROM v_incrementality_lift",
        "cohort_ltv":        "SELECT * FROM v_cohort_ltv_12m",
        "risk_register":     "SELECT * FROM v_risk_register LIMIT 200",
        "pareto":            "SELECT * FROM v_pareto_analysis",
        "vertical_perf":     "SELECT * FROM v_vertical_performance",
        "retention":         "SELECT * FROM v_retention_curve",
        "diminishing":       "SELECT * FROM v_diminishing_returns",
    }
    for name, query in exports.items():
        try:
            df = con.execute(query).df()
            out = OUT_PATH / f"{name}.csv"
            df.to_csv(out, index=False)
            print(f"  ✓ Exported {name}.csv ({len(df)} rows)")
        except Exception as e:
            print(f"  ✗ Skipped {name}: {e}")


def main():
    print("=" * 60)
    print("  Advertiser Profitability Intelligence System (APIS)")
    print("=" * 60)

    # 1. Load data
    if not RAW_PATH.exists():
        print(f"\n⚠️  Place advertising.csv into {RAW_PATH.parent}/")
        print("   Download from: https://www.kaggle.com/datasets/ashydv/advertising-dataset\n")
        print("   Running with synthetic demo data instead...\n")
        # Generate fully synthetic demo data
        rng = np.random.default_rng(42)
        n = 200
        demo = pd.DataFrame({
            "TV":        rng.uniform(10, 300, n),
            "Radio":     rng.uniform(5,  100, n),
            "Newspaper": rng.uniform(1,   50, n),
            "Sales":     rng.uniform(5,   30, n),
        })
        RAW_PATH.parent.mkdir(parents=True, exist_ok=True)
        demo.to_csv(RAW_PATH, index=False)

    print("\n[1/4] Loading and enriching data...")
    df = load_and_enrich(RAW_PATH)
    print(f"      {len(df):,} campaign records across {df['advertiser_id'].nunique()} advertisers")

    # 2. Init DuckDB and ingest
    print("\n[2/4] Ingesting into DuckDB...")
    con = duckdb.connect()
    con.execute("CREATE TABLE raw_advertising AS SELECT * FROM df")

    # 3. Register SQL views
    print("\n[3/4] Registering SQL views...")
    register_sql_views(con)

    # 4. Export
    print("\n[4/4] Exporting processed tables...")
    export_tables(con)

    print("\n✅ Pipeline complete. Run `cd dashboard && python app.py` to launch.")
    print("=" * 60)


if __name__ == "__main__":
    main()
