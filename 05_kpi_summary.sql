-- =============================================================================
-- 05_kpi_summary.sql
-- Executive KPI rollup — the "one-pager" finance leaders see in QBRs
-- =============================================================================

CREATE OR REPLACE VIEW v_executive_kpi_summary AS
WITH monthly AS (
    SELECT
        campaign_month,
        SUM(spend_gbp)                                  AS total_spend,
        SUM(revenue_gbp)                                AS total_revenue,
        SUM(conversions)                                AS total_conversions,
        COUNT(DISTINCT advertiser_id)                   AS active_advertisers,
        ROUND(SUM(revenue_gbp) / NULLIF(SUM(spend_gbp), 0), 2)   AS blended_roas,
        ROUND(SUM(spend_gbp) / NULLIF(SUM(conversions), 0), 2)   AS avg_cpa
    FROM v_enriched_advertising
    GROUP BY campaign_month
),
with_mom AS (
    SELECT
        *,
        LAG(total_spend, 1)     OVER (ORDER BY campaign_month) AS prev_spend,
        LAG(total_revenue, 1)   OVER (ORDER BY campaign_month) AS prev_revenue,
        LAG(blended_roas, 1)    OVER (ORDER BY campaign_month) AS prev_roas,
        LAG(active_advertisers, 1) OVER (ORDER BY campaign_month) AS prev_advertisers
    FROM monthly
)
SELECT
    campaign_month,
    ROUND(total_spend / 1000, 1)            AS spend_k_gbp,
    ROUND(total_revenue / 1000, 1)          AS revenue_k_gbp,
    total_conversions,
    active_advertisers,
    blended_roas,
    avg_cpa,

    -- MoM growth rates
    ROUND((total_spend - prev_spend) / NULLIF(prev_spend, 0) * 100, 1)
                                            AS spend_mom_pct,
    ROUND((total_revenue - prev_revenue) / NULLIF(prev_revenue, 0) * 100, 1)
                                            AS revenue_mom_pct,
    ROUND(blended_roas - prev_roas, 2)      AS roas_mom_delta,
    ROUND((active_advertisers - prev_advertisers)::DECIMAL /
        NULLIF(prev_advertisers, 0) * 100, 1)
                                            AS advertiser_growth_mom_pct,

    -- Traffic light status for exec dashboards
    CASE
        WHEN blended_roas >= 4.0 AND (total_revenue - prev_revenue) / NULLIF(prev_revenue, 0) > 0.05
            THEN '🟢 On Track'
        WHEN blended_roas >= 2.5 OR (total_revenue - prev_revenue) / NULLIF(prev_revenue, 0) > 0
            THEN '🟡 Monitor'
        ELSE '🔴 Action Required'
    END                                     AS health_status

FROM with_mom
ORDER BY campaign_month;


-- Vertical performance decomposition
CREATE OR REPLACE VIEW v_vertical_performance AS
SELECT
    vertical,
    COUNT(DISTINCT advertiser_id)               AS advertisers,
    ROUND(SUM(spend_gbp) / 1000, 1)             AS spend_k_gbp,
    ROUND(SUM(revenue_gbp) / 1000, 1)           AS revenue_k_gbp,
    ROUND(AVG(roas), 2)                         AS avg_roas,
    ROUND(MEDIAN(roas), 2)                      AS median_roas,
    SUM(conversions)                            AS total_conversions,
    ROUND(SUM(spend_gbp) / NULLIF(SUM(conversions), 0), 2)  AS blended_cpa,

    -- Vertical contribution to total revenue
    ROUND(SUM(revenue_gbp) / SUM(SUM(revenue_gbp)) OVER () * 100, 1)
                                                AS revenue_share_pct

FROM v_enriched_advertising
GROUP BY vertical
ORDER BY SUM(revenue_gbp) DESC;
