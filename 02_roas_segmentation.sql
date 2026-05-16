-- =============================================================================
-- 02_roas_segmentation.sql
-- ROAS tier classification + investment productivity analysis
-- Mirrors Google AVA advertiser segmentation logic
-- =============================================================================

-- Step 1: Compute rolling 90-day ROAS per advertiser
CREATE OR REPLACE VIEW v_rolling_roas AS
SELECT
    advertiser_id,
    campaign_date,
    vertical,
    spend_gbp,
    revenue_gbp,
    roas,

    -- 90-day rolling ROAS (smoothed signal vs. noisy daily)
    ROUND(
        SUM(revenue_gbp) OVER (
            PARTITION BY advertiser_id
            ORDER BY campaign_date
            ROWS BETWEEN 89 PRECEDING AND CURRENT ROW
        ) /
        NULLIF(SUM(spend_gbp) OVER (
            PARTITION BY advertiser_id
            ORDER BY campaign_date
            ROWS BETWEEN 89 PRECEDING AND CURRENT ROW
        ), 0),
    2) AS rolling_90d_roas,

    -- Quarter-over-quarter ROAS delta
    roas - LAG(roas, 90) OVER (
        PARTITION BY advertiser_id ORDER BY campaign_date
    ) AS roas_qoq_delta

FROM v_enriched_advertising;


-- Step 2: Classify advertisers into AVA-style ROAS tiers
-- These tiers determine commercial intervention strategy
CREATE OR REPLACE VIEW v_roas_tiers AS
SELECT
    advertiser_id,
    vertical,
    ROUND(AVG(rolling_90d_roas), 2) AS avg_90d_roas,
    ROUND(SUM(spend_gbp), 2)        AS total_spend_gbp,
    ROUND(SUM(revenue_gbp), 2)      AS total_revenue_gbp,
    ROUND(AVG(roas_qoq_delta), 3)   AS avg_roas_momentum,

    -- Core ROAS tier classification
    CASE
        WHEN AVG(rolling_90d_roas) >= 6.0  THEN 'Tier 1: Star'
        WHEN AVG(rolling_90d_roas) >= 4.0  THEN 'Tier 2: Growth'
        WHEN AVG(rolling_90d_roas) >= 2.0  THEN 'Tier 3: Developing'
        WHEN AVG(rolling_90d_roas) >= 1.0  THEN 'Tier 4: Break-even'
        ELSE                                    'Tier 5: At-Risk'
    END AS roas_tier,

    -- Commercial priority flag (AVA intervention trigger)
    CASE
        WHEN AVG(rolling_90d_roas) < 2.0
         AND SUM(spend_gbp) > 10000          THEN 'HIGH — Immediate Review'
        WHEN AVG(rolling_90d_roas) BETWEEN 2.0 AND 4.0
         AND AVG(roas_qoq_delta) < -0.5      THEN 'MEDIUM — Declining Trajectory'
        WHEN AVG(rolling_90d_roas) >= 4.0
         AND SUM(spend_gbp) < 5000           THEN 'OPPORTUNITY — Scale Candidate'
        ELSE                                     'MONITOR — Stable'
    END AS commercial_priority

FROM v_rolling_roas
GROUP BY advertiser_id, vertical;


-- Step 3: Diminishing returns analysis
-- Identifies the optimal spend level per vertical before ROAS decay
CREATE OR REPLACE VIEW v_diminishing_returns AS
SELECT
    vertical,
    spend_band,
    COUNT(DISTINCT advertiser_id)       AS advertiser_count,
    ROUND(AVG(roas), 2)                 AS avg_roas,
    ROUND(MEDIAN(roas), 2)              AS median_roas,
    ROUND(STDDEV(roas), 2)              AS roas_stddev,
    ROUND(SUM(spend_gbp) / 1000, 0)    AS total_spend_k_gbp,
    ROUND(SUM(revenue_gbp) / 1000, 0)  AS total_revenue_k_gbp

FROM v_enriched_advertising
GROUP BY vertical, spend_band
ORDER BY vertical, AVG(spend_gbp);


-- Step 4: Pareto analysis — which advertisers drive incremental value?
CREATE OR REPLACE VIEW v_pareto_analysis AS
WITH ranked AS (
    SELECT
        advertiser_id,
        SUM(revenue_gbp)    AS total_revenue,
        SUM(conversions)    AS total_conversions,
        ROW_NUMBER() OVER (ORDER BY SUM(revenue_gbp) DESC) AS revenue_rank,
        COUNT(*) OVER ()    AS total_advertisers
    FROM v_enriched_advertising
    GROUP BY advertiser_id
),
cumulative AS (
    SELECT
        *,
        ROUND(revenue_rank::DECIMAL / total_advertisers * 100, 1) AS percentile,
        ROUND(
            SUM(total_revenue) OVER (ORDER BY revenue_rank) /
            SUM(total_revenue) OVER () * 100
        , 1) AS cumulative_revenue_pct
    FROM ranked
)
SELECT
    percentile,
    cumulative_revenue_pct,
    -- Flag the Pareto boundary (top 20% driving ~80% revenue)
    CASE WHEN percentile <= 20 THEN 'Core 20%' ELSE 'Long Tail 80%' END AS pareto_segment
FROM cumulative
ORDER BY percentile;
