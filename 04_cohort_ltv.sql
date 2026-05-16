-- =============================================================================
-- 04_cohort_ltv.sql
-- Advertiser cohort LTV analysis
-- Answers: do advertiser relationships compound or decay over time?
-- =============================================================================

-- Step 1: Assign advertisers to acquisition cohorts (first month of activity)
CREATE OR REPLACE VIEW v_cohort_assignment AS
SELECT
    advertiser_id,
    MIN(campaign_month)     AS cohort_month,
    MIN(campaign_date)      AS first_seen_date,
    MAX(campaign_date)      AS last_seen_date,
    COUNT(DISTINCT campaign_month) AS active_months
FROM v_enriched_advertising
GROUP BY advertiser_id;


-- Step 2: Build cohort revenue matrix
-- Rows = cohort (when advertiser joined), Columns = months since join
CREATE OR REPLACE VIEW v_cohort_revenue_matrix AS
SELECT
    c.cohort_month,
    DATE_DIFF('month', c.cohort_month, e.campaign_month)  AS months_since_join,
    COUNT(DISTINCT e.advertiser_id)                        AS active_advertisers,
    ROUND(SUM(e.revenue_gbp), 2)                           AS cohort_revenue_gbp,
    ROUND(SUM(e.spend_gbp), 2)                             AS cohort_spend_gbp,
    ROUND(AVG(e.roas), 2)                                  AS cohort_avg_roas,

    -- Revenue per advertiser in cohort
    ROUND(SUM(e.revenue_gbp) / NULLIF(COUNT(DISTINCT e.advertiser_id), 0), 2)
                                                           AS revenue_per_advertiser

FROM v_enriched_advertising e
JOIN v_cohort_assignment c USING (advertiser_id)
WHERE e.campaign_month >= c.cohort_month
GROUP BY c.cohort_month, DATE_DIFF('month', c.cohort_month, e.campaign_month);


-- Step 3: Retention curve — what % of advertisers survive each month?
CREATE OR REPLACE VIEW v_retention_curve AS
WITH cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT advertiser_id) AS cohort_size
    FROM v_cohort_assignment
    GROUP BY cohort_month
),
monthly_active AS (
    SELECT
        c.cohort_month,
        DATE_DIFF('month', c.cohort_month, e.campaign_month) AS months_since_join,
        COUNT(DISTINCT e.advertiser_id) AS active_count
    FROM v_enriched_advertising e
    JOIN v_cohort_assignment c USING (advertiser_id)
    GROUP BY c.cohort_month, DATE_DIFF('month', c.cohort_month, e.campaign_month)
)
SELECT
    m.cohort_month,
    m.months_since_join,
    m.active_count,
    cs.cohort_size,
    ROUND(m.active_count::DECIMAL / cs.cohort_size * 100, 1) AS retention_rate_pct
FROM monthly_active m
JOIN cohort_sizes cs USING (cohort_month)
ORDER BY m.cohort_month, m.months_since_join;


-- Step 4: 12-month LTV by acquisition cohort
CREATE OR REPLACE VIEW v_cohort_ltv_12m AS
SELECT
    cohort_month,
    SUM(CASE WHEN months_since_join <= 11 THEN cohort_revenue_gbp ELSE 0 END)
                                                        AS ltv_12m_gbp,
    SUM(CASE WHEN months_since_join <= 5  THEN cohort_revenue_gbp ELSE 0 END)
                                                        AS ltv_6m_gbp,
    SUM(CASE WHEN months_since_join <= 2  THEN cohort_revenue_gbp ELSE 0 END)
                                                        AS ltv_3m_gbp,

    -- LTV acceleration ratio: does the cohort grow faster in later months?
    ROUND(
        SUM(CASE WHEN months_since_join BETWEEN 6 AND 11 THEN cohort_revenue_gbp ELSE 0 END) /
        NULLIF(SUM(CASE WHEN months_since_join BETWEEN 0 AND 5 THEN cohort_revenue_gbp ELSE 0 END), 0)
    , 2)                                                AS h2_vs_h1_revenue_ratio,

    -- Flag high-value cohorts
    CASE
        WHEN SUM(CASE WHEN months_since_join <= 11 THEN cohort_revenue_gbp ELSE 0 END) >
             PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY
                SUM(CASE WHEN months_since_join <= 11 THEN cohort_revenue_gbp ELSE 0 END)
             ) OVER ()
        THEN 'High-Value Cohort'
        ELSE 'Standard Cohort'
    END                                                 AS cohort_quality_flag

FROM v_cohort_revenue_matrix
GROUP BY cohort_month
ORDER BY cohort_month;


-- Step 5: Churn prediction signal
-- Advertisers who were active but haven't spent in 60+ days
CREATE OR REPLACE VIEW v_churn_risk AS
SELECT
    e.advertiser_id,
    e.vertical,
    MAX(e.campaign_date)                                AS last_active_date,
    DATEDIFF('day', MAX(e.campaign_date), CURRENT_DATE) AS days_since_last_activity,
    ROUND(SUM(e.revenue_gbp), 2)                        AS historical_revenue_gbp,
    ROUND(AVG(e.roas), 2)                               AS historical_roas,

    CASE
        WHEN DATEDIFF('day', MAX(e.campaign_date), CURRENT_DATE) > 90
            THEN 'CHURNED'
        WHEN DATEDIFF('day', MAX(e.campaign_date), CURRENT_DATE) > 60
            THEN 'HIGH RISK'
        WHEN DATEDIFF('day', MAX(e.campaign_date), CURRENT_DATE) > 30
            THEN 'WATCH LIST'
        ELSE 'ACTIVE'
    END                                                 AS churn_status

FROM v_enriched_advertising e
GROUP BY e.advertiser_id, e.vertical
ORDER BY days_since_last_activity DESC;
