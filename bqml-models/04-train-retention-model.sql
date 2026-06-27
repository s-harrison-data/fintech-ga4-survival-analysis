-- Create or replace a Native BigQuery ML Logistic Regression Model
CREATE OR REPLACE MODEL `your-gcp-project.your_fintech_dataset.retention_velocity_model`
OPTIONS(
  MODEL_TYPE = 'LOGISTIC_REG',
  INPUT_LABEL_COLS = ['is_churned'],
  DATA_SPLIT_METHOD = 'NO_SPLIT' -- Forces BQML to respect our deterministic validation split
) AS

SELECT 
  -- 1. CLEAN TARGET: Pulls directly from the leak-free merge table field
  churned AS is_churned,
  
  -- 2. TIMELINE COVARIATE
  CAST(days_since_first_visit AS FLOAT64) AS timeline_tenure_days,
  
  -- 3. NUMERIC COVARIATES
  CAST(total_events AS FLOAT64) AS total_events,
  CAST(unique_pages_viewed AS FLOAT64) AS unique_pages_viewed,
  COALESCE(avg_session_duration_seconds, 0.0) AS avg_session_duration_seconds,
  COALESCE(purchase_rate, 0.0) AS purchase_rate,
  COALESCE(cart_rate, 0.0) AS cart_rate,
  
  -- 4. CLEAN NULL FREQUENCIES
  COALESCE(sessions_per_day, 0.0) AS sessions_per_day,
  
  -- 5. CATEGORICAL COVARIATES
  COALESCE(primary_country, 'Unknown') AS primary_country

FROM `your-gcp-project.your_fintech_dataset.mart_fintech_survival_features`
-- Train model on an 80% split using a deterministic hash for reproducibility
WHERE ABS(MOD(FARM_FINGERPRINT(user_pseudo_id), 10)) < 8;

