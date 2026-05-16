-- =============================================================================
-- 03_incrementality_model.sql
-- Holdout-based incrementality estimation
-- Estimates Google's true marginal contribution beyond baseline conversions
-- =============================================================================

-- Step 1: Separate holdout (control) vs. exposed (treatment) groups
-- In production: holdout_id comes from Google Ads Experiments API
CREATE OR REPLACE VIEW v_holdout_split AS
SELECT
    advertiser_id,
    campaign_date,
    campaign_month,
    channel,
    vertical,
    spend_gbp,
    conversions,
    revenue_gbp,
    is_holdout,
    CASE WHEN is_holdout THEN 'Control' ELSE 'Treatment' END AS group_label
FROM v_enriched_advertising;


-- Step 2: Compute observed conversion rates per group per month
CREATE OR REPLACE VIEW v_group_conversion_rates AS
SELECT
    campaign_month,
    vertical,
    group_label,
    COUNT(DISTINCT advertiser_id)                       AS advertiser_n,
    SUM(conversions)                                    AS total_conversions,
    SUM(spend_gbp)                                      AS total_spend,
    ROUND(AVG(cvr_pct), 3)                              AS avg_cvr_pct,
    ROUND(SUM(revenue_gbp), 2)                          AS total_revenue
FROM v_holdout_split h
JOIN v_enriched_advertising e USING (advertiser_id, campaign_date)
GROUP BY campaign_month, vertical, group_label;


-- Step 3: Incrementality lift calculation
-- Lift = (Treatment CVR - Control CVR) / Control CVR
CREATE OR REPLACE VIEW v_incrementality_lift AS
WITH pivoted AS (
    SELECT
        campaign_month,
        vertical,
        MAX(CASE WHEN group_label = 'Treatment' THEN avg_cvr_pct END) AS treatment_cvr,
        MAX(CASE WHEN group_label = 'Control'   THEN avg_cvr_pct END) AS control_cvr,
        MAX(CASE WHEN group_label = 'Treatment' THEN total_spend   END) AS treatment_spend,
        MAX(CASE WHEN group_label = 'Treatment' THEN total_conversions END) AS treatment_conversions,
        MAX(CASE WHEN group_label = 'Control'   THEN total_conversions END) AS control_conversions
    FROM v_group_conversion_rates
    GROUP BY campaign_month, vertical
)
SELECT
    campaign_month,
    vertical,
    ROUND(treatment_cvr, 3)                              AS treatment_cvr_pct,
    ROUND(control_cvr, 3)                                AS control_cvr_pct,
    treatment_spend,

    -- Absolute lift in CVR points
    ROUND(treatment_cvr - control_cvr, 3)               AS absolute_lift_pp,

    -- Relative lift (incrementality %)
    CASE WHEN control_cvr > 0
        THEN ROUND((treatment_cvr - control_cvr) / control_cvr * 100, 1)
        ELSE NULL
    END                                                  AS relative_lift_pct,

    -- Incremental conversions attributed to Google
    ROUND(
        (treatment_cvr - control_cvr) / 100.0 *
        (treatment_conversions + control_conversions)
    , 0)                                                 AS incremental_conversions,

    -- Cost per incremental conversion (key AVA metric)
    CASE
        WHEN (treatment_cvr - control_cvr) > 0
         AND treatment_spend > 0
        THEN ROUND(
            treatment_spend /
            NULLIF(
                (treatment_cvr - control_cvr) / 100.0 *
                (treatment_conversions + control_conversions)
            , 0)
        , 2)
        ELSE NULL
    END                                                  AS cost_per_incremental_conversion,

    -- Incrementality quality flag
    CASE
        WHEN (treatment_cvr - control_cvr) / NULLIF(control_cvr, 0) > 0.3
            THEN 'HIGH — Strong Google lift'
        WHEN (treatment_cvr - control_cvr) / NULLIF(control_cvr, 0) BETWEEN 0.1 AND 0.3
            THEN 'MEDIUM — Moderate lift'
        WHEN (treatment_cvr - control_cvr) / NULLIF(control_cvr, 0) BETWEEN 0 AND 0.1
            THEN 'LOW — Marginal lift'
        ELSE 'NEGATIVE — Review targeting'
    END                                                  AS incrementality_grade

FROM pivoted;


-- Step 4: Blended iROAS (incremental ROAS) — the metric Google GBO cares most about
-- iROAS = Incremental Revenue / Spend (vs. total revenue / spend for standard ROAS)
CREATE OR REPLACE VIEW v_iroas_summary AS
SELECT
    vertical,
    ROUND(AVG(relative_lift_pct), 1)                    AS avg_incrementality_pct,
    ROUND(SUM(incremental_conversions), 0)              AS total_incremental_conversions,
    ROUND(SUM(treatment_spend), 0)                      AS total_spend_gbp,
    ROUND(AVG(cost_per_incremental_conversion), 2)      AS avg_cpic_gbp,
    -- iROAS proxy: assume avg order value of £85 (configurable)
    ROUND(SUM(incremental_conversions) * 85.0 /
        NULLIF(SUM(treatment_spend), 0), 2)             AS iroas_proxy,
    COUNT(DISTINCT campaign_month)                      AS months_measured
FROM v_incrementality_lift
GROUP BY vertical
ORDER BY iroas_proxy DESC;
