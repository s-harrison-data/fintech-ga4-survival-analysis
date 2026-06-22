-- Sessionization table
CREATE OR REPLACE TABLE `your-gcp-project-id.analytics_mart.stg_ga4_user_sessions` AS
WITH session_data AS (
  SELECT 
    user_pseudo_id,
    ga_session_id,
    MIN(event_timestamp) as session_start,
    MAX(event_timestamp) as session_end,
    SUM(engagement_time_msec) as total_engagement_ms,
    COUNT(DISTINCT event_name) as unique_event_types,
    COUNT(*) as total_events,
    
    -- Landing page
    ARRAY_AGG(page_location ORDER BY event_timestamp ASC LIMIT 1)[OFFSET(0)] as landing_page,
    
    -- First touch attribution
    ARRAY_AGG(traffic_source ORDER BY event_timestamp ASC LIMIT 1)[OFFSET(0)] as first_touch_source,
    ARRAY_AGG(traffic_medium ORDER BY event_timestamp ASC LIMIT 1)[OFFSET(0)] as first_touch_medium,
    
    -- Did they purchase?
    LOGICAL_OR(event_name = 'purchase') as had_purchase,
    
    -- Bounce (single pageview, no engagement)
    COUNT(DISTINCT page_location) = 1 AND SUM(engagement_time_msec) < 1000 as is_bounce

  FROM `your-gcp-project-id.analytics_mart.stg_ga4_flattened_events`
  GROUP BY user_pseudo_id, ga_session_id
)
SELECT 
  *,
  TIMESTAMP_DIFF(TIMESTAMP_MICROS(session_end), TIMESTAMP_MICROS(session_start), SECOND) as session_duration_seconds
FROM session_data;
