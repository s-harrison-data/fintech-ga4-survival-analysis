-- Build your flattened events table
CREATE OR REPLACE TABLE `your-gcp-project.your_fintech_dataset.flattened_events` AS
SELECT 
  event_date,
  PARSE_DATE('%Y%m%d', event_date) as event_date_parsed,
  event_timestamp,
  event_name,
  user_pseudo_id,
  user_id,
  
  -- Extract core event_params
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') as page_location,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') as ga_session_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') as engagement_time_msec,
  
  -- Traffic source
  traffic_source.source as traffic_source,
  traffic_source.medium as traffic_medium,
  
  -- Geo
  geo.country as country

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20210101' AND '20210107';
