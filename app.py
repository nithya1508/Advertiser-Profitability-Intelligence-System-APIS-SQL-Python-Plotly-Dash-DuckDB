"""
dashboard/app.py
Executive Dashboard — Advertiser Profitability Intelligence System
Mirrors the kind of reporting surface a Google GBO Finance analyst would own.
"""

import dash
from dash import dcc, html, dash_table, Input, Output
import plotly.graph_objects as go
import plotly.express as px
import pandas as pd
import numpy as np
from pathlib import Path

# ─── Load processed data ───────────────────────────────────────────────────────
DATA = Path("../data/processed")

def safe_load(name):
    p = DATA / f"{name}.csv"
    return pd.read_csv(p) if p.exists() else pd.DataFrame()

kpi_df      = safe_load("kpi_summary")
roas_df     = safe_load("roas_tiers")
incr_df     = safe_load("incrementality")
cohort_df   = safe_load("cohort_ltv")
risk_df     = safe_load("risk_register")
pareto_df   = safe_load("pareto")
vert_df     = safe_load("vertical_perf")
ret_df      = safe_load("retention")

# ─── Colour system ─────────────────────────────────────────────────────────────
GOOGLE_BLUE  = "#4285F4"
GOOGLE_RED   = "#EA4335"
GOOGLE_YELLOW= "#FBBC04"
GOOGLE_GREEN = "#34A853"
BG           = "#0F1117"
CARD_BG      = "#1A1D27"
TEXT         = "#E8EAED"
MUTED        = "#8A8D9F"
BORDER       = "#2D3142"

COLORS = [GOOGLE_BLUE, GOOGLE_GREEN, GOOGLE_YELLOW, GOOGLE_RED,
          "#A142F4", "#24C1E0", "#FF6D00", "#00BFA5"]

CARD_STYLE = {
    "background": CARD_BG, "border": f"1px solid {BORDER}",
    "borderRadius": "12px", "padding": "20px", "margin": "8px",
}

# ─── Helper: KPI card ──────────────────────────────────────────────────────────
def kpi_card(label, value, delta=None, color=GOOGLE_BLUE):
    delta_el = html.Div(delta, style={
        "fontSize": "12px", "color": GOOGLE_GREEN if (delta or "").startswith("+") else GOOGLE_RED,
        "marginTop": "4px"
    }) if delta else html.Div()
    return html.Div([
        html.Div(label, style={"fontSize": "11px", "color": MUTED, "letterSpacing": "1px",
                               "textTransform": "uppercase", "marginBottom": "8px"}),
        html.Div(value, style={"fontSize": "28px", "fontWeight": "700", "color": color}),
        delta_el
    ], style={**CARD_STYLE, "flex": "1", "minWidth": "160px"})


# ─── App ───────────────────────────────────────────────────────────────────────
app = dash.Dash(
    __name__,
    title="APIS — Advertiser Profitability Intelligence",
    meta_tags=[{"name": "viewport", "content": "width=device-width, initial-scale=1"}]
)

# Compute headline KPIs
if not kpi_df.empty:
    latest = kpi_df.iloc[-1]
    total_rev   = f"£{kpi_df['revenue_k_gbp'].sum():,.0f}K"
    avg_roas    = f"{kpi_df['blended_roas'].mean():.2f}x"
    rev_mom     = f"{latest.get('revenue_mom_pct', 0):+.1f}% MoM"
    total_adv   = f"{int(kpi_df['active_advertisers'].max())}"
else:
    total_rev, avg_roas, rev_mom, total_adv = "—", "—", "—", "—"

if not risk_df.empty:
    high_risk   = str(len(risk_df[risk_df.get("churn_status", pd.Series()) == "HIGH RISK"]))
else:
    high_risk   = "—"

app.layout = html.Div(style={"background": BG, "minHeight": "100vh",
                              "fontFamily": "'Google Sans', 'Segoe UI', sans-serif",
                              "color": TEXT, "padding": "0"}, children=[

    # ── Header ──────────────────────────────────────────────────────────────────
    html.Div([
        html.Div([
            html.Span("G", style={"color": GOOGLE_BLUE}),
            html.Span("o", style={"color": GOOGLE_RED}),
            html.Span("o", style={"color": GOOGLE_YELLOW}),
            html.Span("g", style={"color": GOOGLE_BLUE}),
            html.Span("l", style={"color": GOOGLE_GREEN}),
            html.Span("e", style={"color": GOOGLE_RED}),
        ], style={"fontSize": "22px", "fontWeight": "700", "letterSpacing": "-0.5px"}),
        html.Div([
            html.Span("APIS", style={"fontWeight": "700", "fontSize": "16px"}),
            html.Span(" · Advertiser Profitability Intelligence System",
                      style={"color": MUTED, "fontSize": "13px"}),
        ]),
        html.Div("EMEA GBO Product Finance", style={"color": MUTED, "fontSize": "11px"}),
    ], style={
        "background": CARD_BG, "borderBottom": f"1px solid {BORDER}",
        "padding": "16px 32px", "display": "flex", "alignItems": "center", "gap": "24px"
    }),

    html.Div(style={"padding": "24px 32px"}, children=[

        # ── KPI Row ─────────────────────────────────────────────────────────────
        html.Div([
            kpi_card("Total Revenue",     total_rev,  rev_mom,       GOOGLE_BLUE),
            kpi_card("Blended ROAS",      avg_roas,   None,          GOOGLE_GREEN),
            kpi_card("Active Advertisers",total_adv,  None,          GOOGLE_YELLOW),
            kpi_card("High-Risk Accounts",high_risk,  None,          GOOGLE_RED),
        ], style={"display": "flex", "flexWrap": "wrap", "margin": "0 -8px 16px"}),

        # ── Tab Navigation ───────────────────────────────────────────────────────
        dcc.Tabs(id="tabs", value="overview", style={"borderBottom": f"1px solid {BORDER}"},
                 colors={"border": BORDER, "primary": GOOGLE_BLUE, "background": BG},
                 children=[
            dcc.Tab(label="📊 Overview",          value="overview"),
            dcc.Tab(label="📈 ROAS Segmentation", value="roas"),
            dcc.Tab(label="🎯 Incrementality",    value="incrementality"),
            dcc.Tab(label="📅 Cohort LTV",        value="cohort"),
            dcc.Tab(label="⚠️ Risk Register",    value="risk"),
        ]),

        html.Div(id="tab-content", style={"marginTop": "24px"}),
    ])
])


@app.callback(Output("tab-content", "children"), Input("tabs", "value"))
def render_tab(tab):

    # ── OVERVIEW ────────────────────────────────────────────────────────────────
    if tab == "overview":
        figs = []

        # Revenue trend
        if not kpi_df.empty:
            fig = go.Figure()
            fig.add_trace(go.Bar(
                x=kpi_df["campaign_month"], y=kpi_df["revenue_k_gbp"],
                name="Revenue (£K)", marker_color=GOOGLE_BLUE, opacity=0.85
            ))
            fig.add_trace(go.Scatter(
                x=kpi_df["campaign_month"], y=kpi_df["blended_roas"],
                name="Blended ROAS", yaxis="y2", line=dict(color=GOOGLE_YELLOW, width=2.5)
            ))
            fig.update_layout(
                title="Monthly Revenue & Blended ROAS", paper_bgcolor=CARD_BG,
                plot_bgcolor=CARD_BG, font_color=TEXT,
                yaxis=dict(title="Revenue (£K)", gridcolor=BORDER),
                yaxis2=dict(title="ROAS", overlaying="y", side="right", gridcolor=BORDER),
                legend=dict(bgcolor=CARD_BG),
                height=320, margin=dict(t=40, b=20)
            )
            figs.append(dcc.Graph(figure=fig, style={"flex": "2"}))

        # Pareto
        if not pareto_df.empty:
            p = pareto_df.drop_duplicates("percentile").sort_values("percentile")
            fig2 = go.Figure(go.Scatter(
                x=p["percentile"], y=p["cumulative_revenue_pct"],
                fill="tozeroy", line=dict(color=GOOGLE_GREEN, width=2),
                fillcolor=f"rgba(52,168,83,0.15)"
            ))
            fig2.add_hline(y=80, line_dash="dash", line_color=GOOGLE_RED,
                           annotation_text="80% revenue", annotation_position="bottom right")
            fig2.add_vline(x=20, line_dash="dash", line_color=GOOGLE_RED)
            fig2.update_layout(
                title="Pareto: Advertiser Revenue Concentration",
                xaxis_title="Advertiser Percentile (%)",
                yaxis_title="Cumulative Revenue (%)",
                paper_bgcolor=CARD_BG, plot_bgcolor=CARD_BG, font_color=TEXT,
                height=320, margin=dict(t=40, b=20)
            )
            figs.append(dcc.Graph(figure=fig2, style={"flex": "1"}))

        return html.Div(figs, style={"display": "flex", "gap": "16px", "flexWrap": "wrap"})

    # ── ROAS SEGMENTATION ────────────────────────────────────────────────────────
    elif tab == "roas":
        if roas_df.empty:
            return html.Div("No ROAS data.", style={"color": MUTED})

        tier_counts = roas_df["roas_tier"].value_counts().reset_index()
        tier_counts.columns = ["tier", "count"]

        fig1 = px.pie(tier_counts, values="count", names="tier",
                      color_discrete_sequence=COLORS, hole=0.45,
                      title="Advertiser ROAS Tier Distribution")
        fig1.update_layout(paper_bgcolor=CARD_BG, font_color=TEXT, height=340)

        fig2 = px.scatter(roas_df, x="total_spend_gbp", y="avg_90d_roas",
                          color="roas_tier", hover_data=["advertiser_id", "vertical"],
                          color_discrete_sequence=COLORS,
                          title="Spend vs. 90-Day Rolling ROAS by Advertiser",
                          labels={"total_spend_gbp": "Total Spend (£)", "avg_90d_roas": "90d ROAS"})
        fig2.add_hline(y=2, line_dash="dash", line_color=GOOGLE_RED,
                       annotation_text="Break-even (2x)")
        fig2.add_hline(y=4, line_dash="dot", line_color=GOOGLE_GREEN,
                       annotation_text="Target ROAS (4x)")
        fig2.update_layout(paper_bgcolor=CARD_BG, plot_bgcolor=CARD_BG,
                           font_color=TEXT, height=360)

        return html.Div([
            html.Div([dcc.Graph(figure=fig1)], style={**CARD_STYLE, "flex": "1"}),
            html.Div([dcc.Graph(figure=fig2)], style={**CARD_STYLE, "flex": "2"}),
        ], style={"display": "flex", "gap": "16px"})

    # ── INCREMENTALITY ───────────────────────────────────────────────────────────
    elif tab == "incrementality":
        if incr_df.empty:
            return html.Div("No incrementality data.", style={"color": MUTED})

        fig = px.bar(incr_df, x="vertical", y="relative_lift_pct",
                     color="incrementality_grade",
                     color_discrete_sequence=COLORS,
                     title="Incrementality Lift % by Vertical",
                     labels={"relative_lift_pct": "Relative Lift (%)", "vertical": "Vertical"})
        fig.update_layout(paper_bgcolor=CARD_BG, plot_bgcolor=CARD_BG,
                          font_color=TEXT, height=380)

        fig2 = px.line(incr_df.sort_values("campaign_month"), x="campaign_month",
                       y="cost_per_incremental_conversion", color="vertical",
                       color_discrete_sequence=COLORS,
                       title="Cost per Incremental Conversion Over Time",
                       labels={"cost_per_incremental_conversion": "CpIC (£)"})
        fig2.update_layout(paper_bgcolor=CARD_BG, plot_bgcolor=CARD_BG,
                           font_color=TEXT, height=320)

        return html.Div([
            html.Div([dcc.Graph(figure=fig)], style={**CARD_STYLE}),
            html.Div([dcc.Graph(figure=fig2)], style={**CARD_STYLE}),
        ])

    # ── COHORT LTV ───────────────────────────────────────────────────────────────
    elif tab == "cohort":
        if cohort_df.empty:
            return html.Div("No cohort data.", style={"color": MUTED})

        fig = px.bar(cohort_df.sort_values("cohort_month"), x="cohort_month",
                     y=["ltv_3m_gbp", "ltv_6m_gbp", "ltv_12m_gbp"],
                     barmode="overlay", color_discrete_sequence=[GOOGLE_YELLOW, GOOGLE_GREEN, GOOGLE_BLUE],
                     title="Cohort LTV: 3M / 6M / 12M Revenue by Acquisition Month",
                     labels={"value": "Revenue (£)", "cohort_month": "Cohort Month"})
        fig.update_layout(paper_bgcolor=CARD_BG, plot_bgcolor=CARD_BG,
                          font_color=TEXT, height=380)

        fig2 = px.bar(cohort_df, x="cohort_month", y="h2_vs_h1_revenue_ratio",
                      color="cohort_quality_flag", color_discrete_sequence=[GOOGLE_GREEN, GOOGLE_BLUE],
                      title="H2/H1 Revenue Ratio (>1 = Cohort Accelerating)",
                      labels={"h2_vs_h1_revenue_ratio": "H2:H1 Revenue Ratio"})
        fig2.add_hline(y=1, line_dash="dash", line_color=GOOGLE_RED,
                       annotation_text="Breakeven")
        fig2.update_layout(paper_bgcolor=CARD_BG, plot_bgcolor=CARD_BG,
                           font_color=TEXT, height=300)

        return html.Div([
            html.Div([dcc.Graph(figure=fig)], style={**CARD_STYLE}),
            html.Div([dcc.Graph(figure=fig2)], style={**CARD_STYLE}),
        ])

    # ── RISK REGISTER ────────────────────────────────────────────────────────────
    elif tab == "risk":
        if risk_df.empty:
            return html.Div("No risk data.", style={"color": MUTED})

        display_cols = ["advertiser_id", "vertical", "roas_tier", "churn_status",
                        "historical_revenue_gbp", "historical_roas", "risk_score_0_100",
                        "recommended_action"]
        show_df = risk_df[[c for c in display_cols if c in risk_df.columns]].head(50)

        table = dash_table.DataTable(
            data=show_df.to_dict("records"),
            columns=[{"name": c.replace("_", " ").title(), "id": c} for c in show_df.columns],
            style_table={"overflowX": "auto"},
            style_header={"backgroundColor": BORDER, "color": TEXT, "fontWeight": "600"},
            style_cell={"backgroundColor": CARD_BG, "color": TEXT,
                        "border": f"1px solid {BORDER}", "fontSize": "12px", "padding": "8px"},
            style_data_conditional=[
                {"if": {"filter_query": "{risk_score_0_100} > 60"},
                 "backgroundColor": "rgba(234,67,53,0.15)", "color": GOOGLE_RED},
                {"if": {"filter_query": "{risk_score_0_100} > 30 && {risk_score_0_100} <= 60"},
                 "backgroundColor": "rgba(251,188,4,0.10)", "color": GOOGLE_YELLOW},
            ],
            sort_action="native", filter_action="native", page_size=20,
        )

        return html.Div([
            html.H3("At-Risk Advertiser Register", style={"color": TEXT, "marginBottom": "12px"}),
            html.P("Composite risk score 0–100. Red = >60 (immediate action). Yellow = 30–60 (monitor).",
                   style={"color": MUTED, "fontSize": "13px", "marginBottom": "16px"}),
            table
        ], style={**CARD_STYLE})

    return html.Div("Select a tab.")


if __name__ == "__main__":
    app.run(debug=True, port=8050)
