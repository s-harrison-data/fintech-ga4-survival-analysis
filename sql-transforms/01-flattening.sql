-- Build your flattened events table
CREATE OR REPLACE TABLE `your-gcp-project.your_fintech_dataset.flattened_events` AS
SELECT 
  event_date,
  PARSE_DATE('%Y%m%d', event_date) as event_date_parsed,
  event_timestamp,
  event_name,

-- 1. THE FINTECH ALIASING LAYER
  CASE 
    WHEN event_name = 'purchase' THEN 'deposit_money'
    WHEN event_name = 'begin_checkout' THEN 'start_kyc_verification'
    WHEN event_name = 'view_item' THEN 'view_yield_rates'
    WHEN event_name = 'add_to_cart' THEN 'initiate_crypto_buy'
    ELSE event_name
  END AS fintech_event_name,
  
  user_pseudo_id,
  user_id,
  
  -- Extract core event_params
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') as page_location,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') as ga_session_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') as engagement_time_msec,

-- 2. FINANCIAL ATTRIBUTE EXTRACTION
-- Maps the original e-commerce item value into a cash deposit metric
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'value') as deposit_amount_usd,
  
  -- Traffic source
  traffic_source.source as traffic_source,
  traffic_source.medium as traffic_medium,
  
  -- Geo
  geo.country as country

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20210101' AND '20210107';
