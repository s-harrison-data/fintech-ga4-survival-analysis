-- FILE: bqml-models/04-train-retention-model.sql
-- DESCRIPTION: Trains a native BQML Logistic Regression model to calculate retention velocity.
-- SNAPSHOT WINDOW: Anchored to a 2-day relative inactivity window based on dataset ceiling boundaries.

CREATE OR REPLACE MODEL `your-gcp-project.g4_demo.retention_velocity_model`
OPTIONS(
  MODEL_TYPE = 'LOGISTIC_REG',
  INPUT_LABEL_COLS = ['is_churned']
) AS

WITH data_ceiling AS (
  SELECT MAX(last_seen) as max_last_seen_raw
  FROM `g4-architect-sandbox.g4_demo.user_features`
),

prepared_matrix AS (
  SELECT 
    f.user_pseudo_id,
    CASE 
      WHEN TIMESTAMP_DIFF(TIMESTAMP_MICROS(c.max_last_seen_raw), TIMESTAMP_MICROS(f.last_seen), DAY) >= 2 THEN 1 
      ELSE 0 
    END AS is_churned,
    CAST(f.days_since_first_visit AS FLOAT64) AS timeline_tenure_days,
    CAST(f.total_events AS FLOAT64) AS total_events,
    CAST(f.unique_pages_viewed AS FLOAT64) AS unique_pages_viewed,
    COALESCE(f.avg_session_duration_seconds, 0.0) AS avg_session_duration_seconds,
    COALESCE(f.purchase_rate, 0.0) AS purchase_rate,
    COALESCE(f.cart_rate, 0.0) AS cart_rate,
    COALESCE(f.sessions_per_day, f.total_sessions) AS sessions_per_day,
    COALESCE(f.primary_country, 'Unknown') AS primary_country
  FROM `your-gcp-project.g4_demo.user_features` f
  CROSS JOIN data_ceiling c
  WHERE f.total_sessions IS NOT NULL
)

SELECT 
  is_churned,
  timeline_tenure_days,
  total_events,
  unique_pages_viewed,
  avg_session_duration_seconds,
  purchase_rate,
  cart_rate,
  sessions_per_day,
  primary_country
FROM prepared_matrix
WHERE ABS(MOD(FARM_FINGERPRINT(user_pseudo_id), 10)) < 8;
