MERGE `g4-architect-sandbox.g4_demo.user_features` T
USING (
  WITH data_bounds AS (
    -- 1. Identify the current absolute timestamp ceiling of your raw data
    SELECT MAX(event_timestamp) as max_raw_timestamp
    FROM `g4-architect-sandbox.g4_demo.flattened_events`
  ),

  time_windows AS (
    -- 2. Establish time boundaries as raw INT64 microseconds to match event_timestamp
    SELECT 
      max_raw_timestamp as dataset_end_micros,
      
      -- 48 hours in microseconds: 2 days * 24 hours * 60 mins * 60 secs * 1,000,000 micros
      max_raw_timestamp - (2 * 24 * 60 * 60 * 1000000) as feature_cutoff_micros,
      
      -- 24 hours in microseconds lookback for incremental delta processing
      max_raw_timestamp - (1 * 24 * 60 * 60 * 1000000) as incremental_lookback_micros
    FROM data_bounds
  ),

  -- 3. DELTA IDENTIFICATION: Find ONLY users active since the last run (Strict INT64 Comparison)
  affected_users AS (
    SELECT DISTINCT f.user_pseudo_id
    FROM `g4-architect-sandbox.g4_demo.flattened_events` f
    CROSS JOIN time_windows tw
    WHERE f.event_timestamp > tw.incremental_lookback_micros
  ),

  -- 4. RECALCULATE GEOGRAPHY: Only for the changed users, up to the cutoff line
  user_country_counts AS (
    SELECT 
      f.user_pseudo_id,
      f.country,
      COUNT(*) as country_count,
      ROW_NUMBER() OVER (PARTITION BY f.user_pseudo_id ORDER BY COUNT(*) DESC, f.country ASC) as country_rank
    FROM `g4-architect-sandbox.g4_demo.flattened_events` f
    INNER JOIN affected_users au ON f.user_pseudo_id = au.user_pseudo_id
    CROSS JOIN time_windows tw
    WHERE f.country IS NOT NULL
      AND f.event_timestamp <= tw.feature_cutoff_micros
    GROUP BY f.user_pseudo_id, f.country
  ),

  user_primary_country AS (
    SELECT user_pseudo_id, country as primary_country FROM user_country_counts WHERE country_rank = 1
  ),

  -- 5. RECALCULATE HISTORICAL AGGREGATES: Complete history for affected users only
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
    FROM `g4-architect-sandbox.g4_demo.flattened_events` f
    INNER JOIN affected_users au ON f.user_pseudo_id = au.user_pseudo_id
    CROSS JOIN time_windows tw
    WHERE f.event_timestamp <= tw.feature_cutoff_micros
    GROUP BY f.user_pseudo_id
  ),

  -- 6. RECALCULATE LABELS: Check the updated 2-day target window
  user_label_window AS (
    SELECT DISTINCT f.user_pseudo_id
    FROM `g4-architect-sandbox.g4_demo.flattened_events` f
    INNER JOIN affected_users au ON f.user_pseudo_id = au.user_pseudo_id
    CROSS JOIN time_windows tw
    WHERE f.event_timestamp > tw.feature_cutoff_micros
      AND f.event_timestamp <= tw.dataset_end_micros
  ),

  -- 7. GENERATE THE TARGET MATRIX DELTA
  delta_matrix AS (
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
      geo.primary_country,
      
      -- Recency and tenure ratios calculated uniformly using standard microsecond transformations
      TIMESTAMP_DIFF(TIMESTAMP_MICROS(tw.feature_cutoff_micros), TIMESTAMP_MICROS(a.last_seen), DAY) as days_since_last_visit,
      TIMESTAMP_DIFF(TIMESTAMP_MICROS(tw.feature_cutoff_micros), TIMESTAMP_MICROS(a.first_seen), DAY) + 1 as days_since_first_visit,
      
      a.total_engagement_ms / NULLIF(a.total_sessions, 0) / 1000 as avg_session_duration_seconds,
      a.purchase_sessions / NULLIF(a.total_sessions, 0) as purchase_rate,
      a.cart_sessions / NULLIF(a.total_sessions, 0) as cart_rate,
      a.total_sessions / (TIMESTAMP_DIFF(TIMESTAMP_MICROS(a.last_seen), TIMESTAMP_MICROS(a.first_seen), DAY) + 1) as sessions_per_day,
      CASE WHEN lbl.user_pseudo_id IS NULL THEN 1 ELSE 0 END as churned
    FROM user_aggregates a
    CROSS JOIN time_windows tw
    LEFT JOIN user_primary_country geo ON a.user_pseudo_id = geo.user_pseudo_id
    LEFT JOIN user_label_window lbl ON a.user_pseudo_id = lbl.user_pseudo_id
  )

  SELECT * FROM delta_matrix
) S
ON T.user_pseudo_id = S.user_pseudo_id

-- If the user already exists in the feature store, update their evolving metrics
WHEN MATCHED THEN
  UPDATE SET
    T.first_seen = S.first_seen,
    T.last_seen = S.last_seen,
    T.total_sessions = S.total_sessions,
    T.total_events = S.total_events,
    T.total_engagement_ms = S.total_engagement_ms,
    T.purchase_sessions = S.purchase_sessions,
    T.cart_sessions = S.cart_sessions,
    T.unique_pages_viewed = S.unique_pages_viewed,
    T.primary_country = S.primary_country,
    T.days_since_last_visit = S.days_since_last_visit,
    T.days_since_first_visit = S.days_since_first_visit,
    T.avg_session_duration_seconds = S.avg_session_duration_seconds,
    T.purchase_rate = S.purchase_rate,
    T.cart_rate = S.cart_rate,
    T.sessions_per_day = S.sessions_per_day,
    T.churned = S.churned

-- If it's a completely new user profile, insert the whole row seamlessly
WHEN NOT MATCHED THEN
   INSERT (
    user_pseudo_id, first_seen, last_seen, total_sessions, total_events, 
    total_engagement_ms, purchase_sessions, cart_sessions, unique_pages_viewed, 
    primary_country, days_since_last_visit, days_since_first_visit, 
    avg_session_duration_seconds, purchase_rate, cart_rate, sessions_per_day, churned
  )
  VALUES (
    S.user_pseudo_id, S.first_seen, S.last_seen, S.total_sessions, S.total_events, 
    S.total_engagement_ms, S.purchase_sessions, S.cart_sessions, S.unique_pages_viewed, 
    S.primary_country, S.days_since_last_visit, S.days_since_first_visit, 
    S.avg_session_duration_seconds, S.purchase_rate, S.cart_rate, S.sessions_per_day, S.churned
  );

