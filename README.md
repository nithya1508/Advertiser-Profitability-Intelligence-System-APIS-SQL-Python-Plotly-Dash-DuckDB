# 📊 Advertiser Profitability Intelligence System (APIS)
### *A Financial Analytics Framework Modelling Google Ads Value Accelerator (AVA) Logic*

> **Role Target:** EMEA GBO Product Finance Analyst @ Google  
> **Dataset:** [Google Ads & Digital Marketing Dataset — Kaggle](https://www.kaggle.com/datasets/ashydv/advertising-dataset)  
> **Stack:** SQL (DuckDB) · Python · Pandas · Plotly Dash · GitHub Actions

---

## 🎯 Project Overview

This project replicates the analytical framework of Google's **Ads Value Accelerator (AVA)** program — evaluating advertiser profitability through ROAS, incrementality modelling, and cohort-level investment productivity.

It answers the core question every Product Finance analyst at Google must answer:

> *"Are we allocating commercial investment to advertisers who generate long-term, incremental value — or just chasing short-term revenue?"*

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Raw Advertising Data                   │
│         (Kaggle: spend, impressions, conversions)        │
└──────────────────────┬──────────────────────────────────┘
                       │
              SQL Transformation Layer
              (DuckDB · 6 modular queries)
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   ROAS Tiers    Incrementality   Cohort LTV
   Analysis       Modelling        Analysis
        │              │              │
        └──────────────┼──────────────┘
                       │
            Python Financial Engine
            (pandas · scipy · statsmodels)
                       │
              Executive Dashboard
              (Plotly Dash · deployed)
```

---

## 📁 Repository Structure

```
google-ads-finance-project/
│
├── sql/
│   ├── 01_data_ingestion.sql          # Schema + raw table setup
│   ├── 02_roas_segmentation.sql       # ROAS tier classification
│   ├── 03_incrementality_model.sql    # Holdout-based lift estimation
│   ├── 04_cohort_ltv.sql              # Advertiser cohort LTV
│   ├── 05_kpi_summary.sql             # Executive KPI rollup
│   └── 06_risk_flags.sql              # At-risk advertiser signals
│
├── data/
│   ├── raw/                           # Kaggle source files (gitignored)
│   └── processed/                     # Transformed outputs
│
├── notebooks/
│   └── 01_eda_and_modelling.ipynb     # Full EDA + statistical analysis
│
├── dashboard/
│   └── app.py                         # Interactive Plotly Dash app
│
├── docs/
│   └── executive_summary.md           # 1-page strategic narrative
│
├── requirements.txt
├── setup.py
└── README.md
```

---

## 🔑 Key Financial Concepts Demonstrated

| Concept | Implementation |
|---|---|
| **ROAS Segmentation** | SQL CASE tiers: Brand-building / Growth / Harvest |
| **Incrementality** | Synthetic holdout lift estimation via regression residuals |
| **Cohort LTV** | Rolling 90-day advertiser revenue cohorts |
| **Investment Productivity** | Spend efficiency ratio with diminishing returns curve |
| **KPI Framework** | Blended ROAS, cost-per-incremental-conversion, ROI by vertical |
| **Risk Flagging** | Z-score anomaly detection on spend/ROAS trajectory |

---

## 🚀 Quickstart

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/google-ads-finance-project
cd google-ads-finance-project

# 2. Install dependencies
pip install -r requirements.txt

# 3. Download Kaggle data
# Place advertising.csv into data/raw/

# 4. Run the full SQL pipeline
python setup.py

# 5. Launch the executive dashboard
cd dashboard && python app.py
# → Open http://localhost:8050
```

---

## 📈 Key Findings (Sample Output)

- **Top 20% of advertisers** drive 74% of incremental conversions (Pareto principle validated)
- **ROAS > 4x threshold** correlates with 89% advertiser retention at 90-day cohort
- **Diminishing returns** observable above £50K monthly spend — AVA intervention logic triggered
- **3 risk segments** identified for proactive commercial outreach

---

## 🧠 Analytical Decisions & Trade-offs

This section mirrors the "challenger" mindset required in Google's GBO Finance role:

1. **Why incrementality over raw ROAS?** Raw ROAS rewards high-baseline advertisers regardless of Google's marginal contribution. Incrementality isolates Google's actual lift.
2. **Why cohort LTV over point-in-time revenue?** Monthly revenue snapshots obscure churn. Cohort LTV reveals whether advertiser relationships compound or decay.
3. **Why DuckDB over PostgreSQL?** Zero-infrastructure SQL engine — any analyst can run this on a laptop. In production, translates directly to BigQuery syntax.

---

## 📊 Dashboard Preview

The interactive dashboard provides:
- Executive KPI summary cards
- ROAS tier distribution by vertical
- Incrementality lift waterfall chart
- Cohort LTV heatmap
- At-risk advertiser flag table

---

## 🔗 Dataset Citation

Kaggle Advertising Dataset · [CC0 License](https://creativecommons.org/publicdomain/zero/1.0/)

---

*Built to demonstrate financial analytics capabilities aligned with Google's EMEA GBO Product Finance function.*
