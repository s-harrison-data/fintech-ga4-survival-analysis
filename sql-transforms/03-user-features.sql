-- User Features for Churn Prediction (Working Version)
CREATE OR REPLACE TABLE `your-gcp-project-id.analytics_mart.mart_fintech_survival_features` AS
WITH 
-- Step 1: Get country counts per user first
user_country_counts AS (
  SELECT 
    user_pseudo_id,
    country,
    COUNT(*) as country_count,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY COUNT(*) DESC) as country_rank
  FROM `g4-architect-sandbox.g4_demo.flattened_events`
  WHERE country IS NOT NULL
  GROUP BY user_pseudo_id, country
),

-- Step 2: Get only the top country per user
user_primary_country AS (
  SELECT 
    user_pseudo_id,
    country as primary_country
  FROM user_country_counts
  WHERE country_rank = 1
),

-- Step 3: Main user aggregates
user_aggregates AS (
  SELECT 
    f.user_pseudo_id,
    MIN(f.event_timestamp) as first_seen,
    MAX(f.event_timestamp) as last_seen,
    COUNT(DISTINCT f.ga_session_id) as total_sessions,
    COUNT(*) as total_events,
    SUM(f.engagement_time_msec) as total_engagement_ms,
    COUNT(DISTINCT CASE WHEN f.event_name = 'purchase' THEN f.ga_session_id END) as purchase_sessions,
    COUNT(DISTINCT CASE WHEN f.event_name = 'add_to_cart' THEN f.ga_session_id END) as cart_sessions,
    COUNT(DISTINCT f.page_location) as unique_pages_viewed
  FROM `your-gcp-project-id.analytics_mart.stg_ga4_user_sessions` f
  GROUP BY f.user_pseudo_id
)

-- Step 4: Join everything together
SELECT 
  a.user_pseudo_id,
  a.first_seen,
  a.last_seen,
  a.total_sessions,
  a.total_events,
  a.total_engagement_ms,
  a.purchase_sessions,
  a.cart_sessions,
  a.unique_pages_viewed,
  
  -- Primary country (joined)
  c.primary_country,
  
  -- Recency (days since last visit)
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MICROS(a.last_seen), DAY) as days_since_last_visit,
  
  -- Tenure (days since first visit)
  TIMESTAMP_DIFF(TIMESTAMP_MICROS(a.last_seen), TIMESTAMP_MICROS(a.first_seen), DAY) as days_since_first_visit,
  
  -- Average session duration (seconds)
  a.total_engagement_ms / NULLIF(a.total_sessions, 0) / 1000 as avg_session_duration_seconds,
  
  -- Purchase rate per session
  a.purchase_sessions / NULLIF(a.total_sessions, 0) as purchase_rate,
  
  -- Cart rate per session
  a.cart_sessions / NULLIF(a.total_sessions, 0) as cart_rate,
  
  -- CHURN LABEL: User is churned if inactive for 7+ days
  CASE 
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP_MICROS(a.last_seen), DAY) > 7 THEN 1 
    ELSE 0 
  END as churned,
  
  -- Session frequency (sessions per day of activity)
  a.total_sessions / NULLIF(TIMESTAMP_DIFF(TIMESTAMP_MICROS(a.last_seen), TIMESTAMP_MICROS(a.first_seen), DAY), 0) as sessions_per_day

FROM user_aggregates a
LEFT JOIN user_primary_country c
  ON a.user_pseudo_id = c.user_pseudo_id;
