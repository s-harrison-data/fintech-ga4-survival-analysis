-- User Features for Churn Prediction (Working Version)
CREATE OR REPLACE TABLE `your-gcp-project.your_fintech_dataset.mart_fintech_survival_features` AS
WITH 
-- Step 1: Get country counts per user first from the base flattened table
user_country_counts AS (
  SELECT 
    user_pseudo_id,
    country,
    COUNT(*) as country_count,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY COUNT(*) DESC) as country_rank
  FROM `your-gcp-project.your_fintech_dataset.flattened_events`
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

-- Step 3: Main user aggregates directly using the sessionized data layer
user_aggregates AS (
  SELECT 
    f.user_pseudo_id,
    MIN(f.session_start) as first_seen,
    MAX(f.session_end) as last_seen,
    COUNT(DISTINCT f.ga_session_id) as total_sessions,
    SUM(f.total_events) as total_events,
    SUM(f.total_engagement_ms) as total_engagement_ms,
    -- Count sessions where a fintech deposit transaction occurred
    COUNT(DISTINCT CASE WHEN f.had_deposit = TRUE THEN f.ga_session_id END) as deposit_sessions,
    COUNT(DISTINCT f.landing_page) as unique_pages_viewed
  FROM `your-gcp-project.your_fintech_dataset.stg_ga4_user_sessions` f
  GROUP BY f.user_pseudo_id
)

-- Step 4: Join everything together and calculate Survival Matrix Covariates
SELECT 
  a.user_pseudo_id,
  a.first_seen,
  a.last_seen,
  a.total_sessions,
  a.total_events,
  a.total_engagement_ms,
  a.deposit_sessions,
  a.unique_pages_viewed,
  
  -- Primary country (joined)
  c.primary_country,
  
  -- Recency (days since last session)
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), a.last_seen, DAY) as days_since_last_visit,
  
  -- Tenure / Time Parameter (T): Days since first session to last tracked session
  -- Safely handling zero-tenure actions by defaulting early drops to 1 day minimum
  IF(TIMESTAMP_DIFF(a.last_seen, a.first_seen, DAY) = 0, 1, TIMESTAMP_DIFF(a.last_seen, a.first_seen, DAY)) as tenure_days,
  
  -- Average session duration (seconds)
  a.total_engagement_ms / NULLIF(a.total_sessions, 0) / 1000 as avg_session_duration_seconds,
  
  -- Deposit rate per session (Fintech velocity index)
  a.deposit_sessions / NULLIF(a.total_sessions, 0) as deposit_rate,
  
  -- EVENT PARAMETER (E): User is dormant if inactive for 7+ days relative to maximum window cut-off
  CASE 
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), a.last_seen, DAY) > 7 THEN 1 
    ELSE 0 
  END as is_dormant,
  
  -- Session frequency (sessions per day of active tenure)
  a.total_sessions / NULLIF(TIMESTAMP_DIFF(a.last_seen, a.first_seen, DAY), 0) as sessions_per_day

FROM user_aggregates a
LEFT JOIN user_primary_country c
  ON a.user_pseudo_id = c.user_pseudo_id;

