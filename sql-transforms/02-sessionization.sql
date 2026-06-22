-- Sessionization table
CREATE OR REPLACE TABLE `your-gcp-project.your_fintech_dataset.stg_ga4_user_sessions` AS
WITH session_data AS (
  SELECT 
    user_pseudo_id,
    ga_session_id,
    -- Safely convert raw GA4 microseconds into standard timestamps during aggregation
    TIMESTAMP_MICROS(MIN(event_timestamp)) as session_start,
    TIMESTAMP_MICROS(MAX(event_timestamp)) as session_end,
    SUM(engagement_time_msec) as total_engagement_ms,
    COUNT(DISTINCT event_name) as unique_event_types,
    COUNT(*) as total_events,
    
    -- Landing page
    ARRAY_AGG(page_location ORDER BY event_timestamp ASC LIMIT 1)[OFFSET(0)] as landing_page,
    
    -- First touch attribution
    ARRAY_AGG(traffic_source ORDER BY event_timestamp ASC LIMIT 1)[OFFSET(0)] as first_touch_source,
    ARRAY_AGG(traffic_medium ORDER BY event_timestamp ASC LIMIT 1)[OFFSET(0)] as first_touch_medium,
    
    -- Did they fund their account? (Fintech translation of 'purchase')
    LOGICAL_OR(fintech_event_name = 'deposit_money') as had_deposit,
    
    -- Bounce (single pageview, no engagement)
    COUNT(DISTINCT page_location) = 1 AND SUM(engagement_time_msec) < 1000 as is_bounce

  FROM `your-gcp-project.your_fintech_dataset.flattened_events`
  GROUP BY user_pseudo_id, ga_session_id
)
SELECT 
  *,
  -- Clean calculation using standardized timestamps
  TIMESTAMP_DIFF(session_end, session_start, SECOND) as session_duration_seconds
FROM session_data;

