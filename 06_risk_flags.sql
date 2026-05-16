-- =============================================================================
-- 06_risk_flags.sql
-- At-risk advertiser detection using statistical anomaly detection
-- Z-score method on spend/ROAS trajectory — production-ready signal
-- =============================================================================

-- Step 1: Compute advertiser-level spend and ROAS statistics
CREATE OR REPLACE VIEW v_advertiser_stats AS
SELECT
    advertiser_id,
    vertical,
    AVG(spend_gbp)      AS mean_spend,
    STDDEV(spend_gbp)   AS stddev_spend,
    AVG(roas)           AS mean_roas,
    STDDEV(roas)        AS stddev_roas,
    COUNT(*)            AS observation_count
FROM v_enriched_advertising
GROUP BY advertiser_id, vertical;


-- Step 2: Flag anomalies in the most recent 30 days
CREATE OR REPLACE VIEW v_recent_anomalies AS
SELECT
    e.advertiser_id,
    e.campaign_date,
    e.vertical,
    e.spend_gbp,
    e.roas,
    s.mean_spend,
    s.mean_roas,

    -- Z-score: how many standard deviations from the advertiser's own mean?
    ROUND((e.spend_gbp - s.mean_spend) / NULLIF(s.stddev_spend, 0), 2)
                            AS spend_z_score,
    ROUND((e.roas - s.mean_roas) / NULLIF(s.stddev_roas, 0), 2)
                            AS roas_z_score,

    -- Anomaly classification
    CASE
        WHEN ABS((e.spend_gbp - s.mean_spend) / NULLIF(s.stddev_spend, 0)) > 3
            THEN 'EXTREME SPEND ANOMALY'
        WHEN ABS((e.spend_gbp - s.mean_spend) / NULLIF(s.stddev_spend, 0)) > 2
            THEN 'SPEND ANOMALY'
        ELSE 'NORMAL'
    END                     AS spend_flag,

    CASE
        WHEN (e.roas - s.mean_roas) / NULLIF(s.stddev_roas, 0) < -2
            THEN 'ROAS DETERIORATION'
        WHEN (e.roas - s.mean_roas) / NULLIF(s.stddev_roas, 0) > 2
            THEN 'ROAS SPIKE — VALIDATE'
        ELSE 'NORMAL'
    END                     AS roas_flag

FROM v_enriched_advertising e
JOIN v_advertiser_stats s USING (advertiser_id)
WHERE e.campaign_date >= CURRENT_DATE - INTERVAL '30 days';


-- Step 3: Master risk register — actionable table for commercial teams
CREATE OR REPLACE VIEW v_risk_register AS
SELECT
    a.advertiser_id,
    a.vertical,
    t.roas_tier,
    t.commercial_priority,
    ch.churn_status,
    ch.days_since_last_activity,
    ch.historical_revenue_gbp,
    ch.historical_roas,

    -- Count recent anomaly days
    COUNT(CASE WHEN ra.spend_flag != 'NORMAL' THEN 1 END)   AS anomaly_days_30d,
    COUNT(CASE WHEN ra.roas_flag = 'ROAS DETERIORATION' THEN 1 END)
                                                            AS roas_deterioration_days,

    -- Composite risk score (0–100)
    LEAST(100, GREATEST(0,
        -- Low ROAS contributes up to 40 points
        CASE
            WHEN ch.historical_roas < 1.0 THEN 40
            WHEN ch.historical_roas < 2.0 THEN 25
            WHEN ch.historical_roas < 3.0 THEN 10
            ELSE 0
        END +
        -- Churn risk contributes up to 30 points
        CASE
            WHEN ch.churn_status = 'CHURNED'   THEN 30
            WHEN ch.churn_status = 'HIGH RISK' THEN 20
            WHEN ch.churn_status = 'WATCH LIST' THEN 10
            ELSE 0
        END +
        -- Anomaly frequency contributes up to 30 points
        LEAST(30, COUNT(CASE WHEN ra.spend_flag != 'NORMAL' THEN 1 END) * 3)
    ))                                                      AS risk_score_0_100,

    -- Recommended commercial action
    CASE
        WHEN ch.churn_status = 'CHURNED' AND ch.historical_revenue_gbp > 50000
            THEN 'WIN-BACK: High-value churned advertiser — escalate to AM'
        WHEN t.commercial_priority = 'HIGH — Immediate Review'
            THEN 'URGENT: Schedule AVA deep-dive within 2 weeks'
        WHEN t.commercial_priority = 'OPPORTUNITY — Scale Candidate'
            THEN 'GROWTH: Propose budget uplift and product expansion'
        WHEN t.commercial_priority = 'MEDIUM — Declining Trajectory'
            THEN 'RETAIN: Deploy optimization recommendations'
        ELSE 'MONITOR: Include in monthly review cycle'
    END                                                     AS recommended_action

FROM v_advertiser_stats a
JOIN v_roas_tiers t USING (advertiser_id)
JOIN v_churn_risk ch USING (advertiser_id)
LEFT JOIN v_recent_anomalies ra USING (advertiser_id)
GROUP BY
    a.advertiser_id, a.vertical, t.roas_tier, t.commercial_priority,
    ch.churn_status, ch.days_since_last_activity,
    ch.historical_revenue_gbp, ch.historical_roas
ORDER BY risk_score_0_100 DESC;
