-- =============================================================================
-- 01_data_ingestion.sql
-- Schema setup and raw data ingestion
-- Dataset: Kaggle Advertising Dataset (advertising.csv)
-- =============================================================================

-- Create the raw advertising table
-- Columns mirror the Kaggle dataset: TV, Radio, Newspaper spend + Sales
CREATE TABLE IF NOT EXISTS raw_advertising (
    advertiser_id     INTEGER,
    campaign_date     DATE,
    vertical          VARCHAR(50),
    channel           VARCHAR(20),   -- TV, Radio, Newspaper, Search, Display
    spend_gbp         DECIMAL(12, 2),
    impressions       INTEGER,
    clicks            INTEGER,
    conversions       INTEGER,
    revenue_gbp       DECIMAL(12, 2),
    is_holdout        BOOLEAN DEFAULT FALSE  -- For incrementality estimation
);

-- Synthetic enrichment view: derive campaign-level identifiers
-- In production this would join to CRM / Ads Manager tables
CREATE OR REPLACE VIEW v_enriched_advertising AS
SELECT
    advertiser_id,
    campaign_date,
    DATE_TRUNC('month', campaign_date)          AS campaign_month,
    vertical,
    channel,
    spend_gbp,
    impressions,
    clicks,
    conversions,
    revenue_gbp,
    is_holdout,

    -- Derived metrics
    CASE WHEN impressions > 0
        THEN ROUND(clicks::DECIMAL / impressions * 100, 2)
        ELSE 0
    END                                          AS ctr_pct,

    CASE WHEN clicks > 0
        THEN ROUND(conversions::DECIMAL / clicks * 100, 2)
        ELSE 0
    END                                          AS cvr_pct,

    CASE WHEN spend_gbp > 0
        THEN ROUND(revenue_gbp / spend_gbp, 2)
        ELSE 0
    END                                          AS roas,

    CASE WHEN conversions > 0
        THEN ROUND(spend_gbp / conversions, 2)
        ELSE NULL
    END                                          AS cost_per_conversion,

    -- Spend band for diminishing returns analysis
    CASE
        WHEN spend_gbp < 5000    THEN 'Micro (<£5K)'
        WHEN spend_gbp < 20000   THEN 'Small (£5K–£20K)'
        WHEN spend_gbp < 50000   THEN 'Mid (£20K–£50K)'
        WHEN spend_gbp < 100000  THEN 'Large (£50K–£100K)'
        ELSE                          'Enterprise (£100K+)'
    END                                          AS spend_band

FROM raw_advertising;


-- Validate ingestion quality
CREATE OR REPLACE VIEW v_data_quality_report AS
SELECT
    COUNT(*)                                             AS total_rows,
    COUNT(DISTINCT advertiser_id)                        AS unique_advertisers,
    COUNT(DISTINCT campaign_date)                        AS date_range_days,
    MIN(campaign_date)                                   AS earliest_date,
    MAX(campaign_date)                                   AS latest_date,
    SUM(CASE WHEN spend_gbp IS NULL THEN 1 ELSE 0 END)  AS null_spend_count,
    SUM(CASE WHEN revenue_gbp < 0   THEN 1 ELSE 0 END)  AS negative_revenue_count,
    ROUND(AVG(roas), 2)                                  AS avg_roas,
    ROUND(SUM(spend_gbp) / 1000000, 2)                  AS total_spend_millions_gbp
FROM v_enriched_advertising;
