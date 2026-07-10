-- PawPulse -- migration: flexible feature storage for activity_windows
-- ============================================================================
-- The original activity_windows schema stored a fixed set of typed columns
-- (accel_mean_x/y/z, accel_var_x/y/z, accel_rms). The deployed Random Forest
-- needs all 40 features from preprocess.py -- mean/var/rms for accelerometer
-- AND gyroscope, back AND neck sensors, plus pitch/roll -- and that set has
-- already changed once during model development (36 -> 40 when tilt features
-- were added). Typed columns would need a schema migration on every retrain;
-- a jsonb column matching the model's feature_columns list doesn't.
--
-- The original typed columns are kept (still useful for quick dashboard
-- queries like "average activity today" without unpacking JSON) but stop
-- being the source of truth for model inference -- `features` is.

alter table activity_windows
    add column features jsonb;

comment on column activity_windows.features is
    'Full feature vector matching the deployed model''s feature_columns list '
    '(see activity_model.json), e.g. {"ABack_x_mean": 0.12, "GNeck_z_var": 0.03, ...}. '
    'Source of truth for inference; accel_mean_x/y/z etc. are kept for cheap '
    'dashboard queries but are not read by the cascade function.';

create index idx_activity_windows_features on activity_windows using gin (features);
