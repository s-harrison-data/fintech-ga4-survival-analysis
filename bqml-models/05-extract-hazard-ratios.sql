-- ========================================================================================
-- Script ID: 05-extract-hazard-ratios.sql
-- Goal: Extract advanced model weights and translate raw log-odds into Risk Metrics (Odds Ratios).
-- Data Layer: Materializes an optimized View to serve as the direct data source for Looker Studio.
-- ========================================================================================

CREATE OR REPLACE VIEW `your-gcp-project.your_fintech_dataset.v_vc_retention_risk_factors` AS 

SELECT
  -- 1. FEATURE IDENTIFICATION
  processed_input AS feature_name,
  
  -- 2. CATEGORICAL HANDLING: Identifies numeric continuous fields vs distinct categorical groups
  COALESCE(category, 'Numeric') AS feature_category,
  
  -- 3. RAW MODEL OUTPUT
  weight AS raw_log_odds,
  
  -- 4. RISK VELOCITY METRIC: Translates raw log-odds into an actionable Odds Ratio via EXP()
  ROUND(EXP(weight), 4) AS odds_ratio,
  
  -- 5. BUSINESS IMPACT: Computes the net percentage change in churn risk per unit increase
  ROUND((EXP(weight) - 1) * 100, 2) AS percentage_impact_on_churn,
  
  -- 6. STATISTICAL SIGNIFICANCE: Extracts p-values to separate true signals from noise
  ROUND(p_value, 4) AS p_value,
  CASE 
    WHEN p_value IS NULL THEN 'Reference Category / Intercept Baseline 📌'
    WHEN p_value < 0.05 THEN 'Statistically Significant ✅'
    ELSE 'Not Significant ❌'
  END AS significance_status

FROM
  -- Calls ADVANCED_WEIGHTS to expose flat categories and p-values natively
  ML.ADVANCED_WEIGHTS(MODEL `your-gcp-project.your_fintech_dataset.retention_velocity_model`)

WHERE 
  -- Excludes the intercept baseline row to cleanly isolate behavioral covariates
  processed_input IS NOT NULL;
