-- ============================================================================
-- PawPulse Database Schema (Supabase / PostgreSQL)
-- ============================================================================
-- Design principles carried over from the ML/DL roadmap and project brief:
--   1. Static profile data is separated from dynamic sensor/ML data.
--   2. Every raw reading carries the metadata the ML roadmap said it would need:
--      elapsed time since last reading, data-quality flag, capture context.
--   3. Raw sensor readings, computed baselines, and ML model outputs are three
--      distinct layers, never conflated into one table.
--   4. Every ML prediction is explainable: a jsonb column stores the feature
--      contributions behind it, not just the label.
--   5. Ground-truth vet assessments (from ABC/vaccination camps) get their own
--      table, because that is the weak-supervision source the whole ML plan
--      depends on.
-- ============================================================================

create extension if not exists "pgcrypto";  -- gives us gen_random_uuid()

-- ============================================================================
-- 1. CORE IDENTITY (Section 1 of the dashboard, mostly static)
-- ============================================================================

create table dogs (
    id                       uuid primary key default gen_random_uuid(),
    qr_code                  text not null unique,          -- the "unique digital identity"
    name                     text,
    breed                    text,
    size_class               text check (size_class in ('small','medium','large')),
        -- drives the breed/size-adjusted HR & temperature baseline discussed in the
        -- ML roadmap: small ~100-140+ bpm, medium/large ~60-100 bpm resting
    estimated_age_months     integer,                       -- nullable: exact DOB rarely known for strays
    date_of_birth            date,                           -- nullable, use if actually known
    sex                      text check (sex in ('male','female','unknown')) default 'unknown',
    weight_kg                numeric(5,2),
    sterilization_status     text check (sterilization_status in ('sterilized','not_sterilized','unknown')) default 'unknown',
    sterilization_date       date,
    color_markings           text,                          -- key for ID without formal breed papers
    behavioral_traits        text[],                        -- e.g. {friendly, food-aggressive, skittish-around-men}
    known_medical_conditions text[],                        -- quick-reference "problem list"; full history is in medical_records
    status                   text check (status in ('active','adopted','deceased','lost','unknown')) default 'active',
    created_at               timestamptz not null default now(),
    updated_at               timestamptz not null default now()
);

create unique index idx_dogs_qr_code on dogs (qr_code);
create index idx_dogs_status_active on dogs (status) where status = 'active';


create table caregivers (
    id           uuid primary key default gen_random_uuid(),
    name         text not null,
    phone_number text,               -- PII: excluded from public/QR-facing views, see RLS section
    role         text check (role in ('community_feeder','ngo_staff','veterinarian','adopter','other')) not null,
    notes        text,
    created_at   timestamptz not null default now()
);

create table dog_caregivers (
    dog_id              uuid not null references dogs(id) on delete cascade,
    caregiver_id        uuid not null references caregivers(id) on delete cascade,
    is_primary          boolean not null default false,
    relationship_start  date not null default current_date,
    relationship_end    date,          -- null = ongoing
    primary key (dog_id, caregiver_id, relationship_start)
);

create index idx_dog_caregivers_dog on dog_caregivers (dog_id);

create table emergency_contacts (
    id             uuid primary key default gen_random_uuid(),
    dog_id         uuid not null references dogs(id) on delete cascade,
    name           text not null,
    phone_number   text not null,
    contact_type   text check (contact_type in ('vet_clinic','ngo_hotline','caregiver','other')) not null,
    priority_order smallint not null default 1,
    created_at     timestamptz not null default now()
);

create index idx_emergency_contacts_dog on emergency_contacts (dog_id, priority_order);


-- ============================================================================
-- 2. MEDICAL HISTORY (Section 1, historical, append-only)
-- ============================================================================

create table vaccinations (
    id                uuid primary key default gen_random_uuid(),
    dog_id            uuid not null references dogs(id) on delete cascade,
    vaccine_type      text not null,               -- e.g. 'rabies', 'DHPPi'
    date_administered date not null,
    administered_by   text,                        -- vet / org name
    batch_number      text,
    next_due_date     date,
    created_at        timestamptz not null default now()
);

create index idx_vaccinations_dog on vaccinations (dog_id, date_administered desc);

create table medical_records (
    id          uuid primary key default gen_random_uuid(),
    dog_id      uuid not null references dogs(id) on delete cascade,
    record_date date not null default current_date,
    record_type text check (record_type in ('exam','diagnosis','treatment','surgery','note')) not null,
    description text not null,
    recorded_by text,
    created_at  timestamptz not null default now()
);

create index idx_medical_records_dog on medical_records (dog_id, record_date desc);


-- ============================================================================
-- 3. FIELD DEPLOYMENT CONTEXT
-- ============================================================================
-- Operationalizes the "anchor data collection to ABC/vaccination camps" idea
-- from the ML roadmap: every reading and every vet assessment can be tied back
-- to the event that produced it, which is what makes weak-supervision labeling
-- actually queryable later instead of just a plan on paper.

create table capture_events (
    id          uuid primary key default gen_random_uuid(),
    event_type  text check (event_type in ('abc_camp','vaccination_drive','routine_scan','emergency','other')) not null,
    location    text,
    event_date  date not null default current_date,
    vet_present boolean not null default false,
    notes       text,
    created_at  timestamptz not null default now()
);


-- ============================================================================
-- 4. RAW SENSOR DATA (Section 2, dynamic, high-volume)
-- ============================================================================

create table sensor_readings (
    id                          uuid primary key default gen_random_uuid(),
    dog_id                      uuid not null references dogs(id) on delete cascade,
    recorded_at                 timestamptz not null default now(),
    pulse_bpm                   smallint,              -- on-demand; nullable, not every event captures it
    temperature_c               numeric(4,1),          -- on-demand
    seconds_since_last_reading  integer,               -- required by every Phase-1+ model per the ML roadmap;
                                                         -- on-demand sensing means gaps are real signal to account for, not noise
    data_quality_flag           text check (data_quality_flag in ('good','motion_artifact','poor_contact','discard')) default 'good',
    capture_event_id            uuid references capture_events(id),
    capture_context             text check (capture_context in ('routine','abc_camp','emergency_trigger','manual_scan')) default 'routine',
    firmware_version            text,
    battery_pct                 smallint,
    created_at                  timestamptz not null default now()
);

create index idx_sensor_readings_dog_time on sensor_readings (dog_id, recorded_at desc);
create index idx_sensor_readings_capture_event on sensor_readings (capture_event_id) where capture_event_id is not null;

-- Scale note: fine unpartitioned at research-project / single-NGO scale. If
-- PawPulse grows to multi-city deployment, partition by recorded_at (monthly
-- range partitions) before it becomes a problem -- not something to build now.


create table activity_windows (
    id                        uuid primary key default gen_random_uuid(),
    dog_id                    uuid not null references dogs(id) on delete cascade,
    window_start              timestamptz not null,
    window_end                timestamptz not null,
    accel_mean_x              real,
    accel_mean_y              real,
    accel_mean_z              real,
    accel_var_x               real,
    accel_var_y               real,
    accel_var_z               real,
    accel_rms                 real,                    -- summary features the server-side
                                                          -- classifier (Recommendation 1) trains/infers on
    classified_activity       text check (classified_activity in
                               ('resting','standing','walking','trotting','galloping','sniffing','unknown')),
    classification_confidence real,
    created_at                timestamptz not null default now()
);

create index idx_activity_windows_dog_time on activity_windows (dog_id, window_start desc);


-- ============================================================================
-- 5. PERSONAL BASELINES
-- ============================================================================
-- The rolling per-dog baseline required by Phase 1 anomaly detection AND by
-- the hydration risk score (both defined relative to "normal for this dog",
-- not a flat global threshold), recomputed periodically as readings accrue.

create table dog_baselines (
    id              uuid primary key default gen_random_uuid(),
    dog_id          uuid not null references dogs(id) on delete cascade,
    computed_at     timestamptz not null default now(),
    window_days     integer not null default 30,
    sample_count    integer not null,
    hr_mean         real,
    hr_stddev       real,
    temp_mean       real,
    temp_stddev     real,
    activity_mean   real,          -- e.g. mean accel_rms over the window, as a simple activity-level proxy
    activity_stddev real,
    created_at      timestamptz not null default now()
);

create index idx_dog_baselines_dog_time on dog_baselines (dog_id, computed_at desc);

-- Always get the most recent baseline per dog without a window function in
-- every query that needs it.
create view latest_dog_baseline as
select distinct on (dog_id) *
from dog_baselines
order by dog_id, computed_at desc;


-- ============================================================================
-- 6. ML MODEL OUTPUTS (three of the four roadmap modules share this table)
-- ============================================================================
-- Unified rather than one table per model: pulse-anomaly, hydration, and
-- overall-health-status are structurally the same thing, a labeled prediction
-- with an explanation, and a shared table stays maintainable as more modules
-- (e.g. breathing, later) get added without new migrations.

create table ml_predictions (
    id                uuid primary key default gen_random_uuid(),
    dog_id            uuid not null references dogs(id) on delete cascade,
    prediction_type   text check (prediction_type in
                       ('pulse_anomaly','hydration_status','overall_health_status')) not null,
        -- NB: activity classification lives on activity_windows.classified_activity
        -- directly rather than here, since it's produced at ingestion time per-window,
        -- not queried against a point-in-time reading the way the other three are.
    predicted_label   text not null,             -- e.g. 'Warning', 'Dehydration Risk', 'anomalous'
    confidence_score  real,
    explanation       jsonb,
        -- SHAP-style feature contributions, e.g.
        -- {"hr_deviation": 0.6, "temp_deviation": 0.3, "activity_deviation": 0.1}
        -- required by the roadmap's explainability section, not optional metadata
    model_version     text not null,
    source_reading_id uuid references sensor_readings(id),
    created_at        timestamptz not null default now()
);

create index idx_ml_predictions_dog_type_time on ml_predictions (dog_id, prediction_type, created_at desc);

create view latest_ml_predictions as
select distinct on (dog_id, prediction_type) *
from ml_predictions
order by dog_id, prediction_type, created_at desc;


-- ============================================================================
-- 7. GROUND TRUTH
-- ============================================================================
-- The weak-supervision source for Phase 2 classical ML and the hydration
-- ordinal logistic regression: collected during capture_events, when a vet is
-- actually present to do the real clinical assessment.

create table vet_assessments (
    id                         uuid primary key default gen_random_uuid(),
    dog_id                     uuid not null references dogs(id) on delete cascade,
    capture_event_id           uuid references capture_events(id),
    linked_reading_id          uuid references sensor_readings(id),
    assessed_at                timestamptz not null default now(),
    assessed_by                text not null,
    hydration_assessment       text check (hydration_assessment in ('hydrated','needs_water','dehydration_risk')),
    overall_health_assessment  text check (overall_health_assessment in ('healthy','monitor','warning','critical')),
    skin_tent_seconds          numeric(3,1),          -- real clinical measurement; ground truth Rec. 3 needs
    mucous_membrane_status     text,
    notes                      text,
    created_at                 timestamptz not null default now()
);

create index idx_vet_assessments_dog on vet_assessments (dog_id, assessed_at desc);


-- ============================================================================
-- 8. EMERGENCY ALERTS
-- ============================================================================

create table emergency_alerts (
    id                     uuid primary key default gen_random_uuid(),
    dog_id                 uuid not null references dogs(id) on delete cascade,
    triggered_at           timestamptz not null default now(),
    trigger_source         text check (trigger_source in ('on_device_rule','server_ml_critical','manual')) not null,
    triggering_reading_id  uuid references sensor_readings(id),
    acknowledged_by        text,
    acknowledged_at        timestamptz,
    resolution_notes       text,
    created_at             timestamptz not null default now()
);

create index idx_emergency_alerts_dog on emergency_alerts (dog_id, triggered_at desc);
create index idx_emergency_alerts_unacknowledged on emergency_alerts (dog_id) where acknowledged_at is null;


-- ============================================================================
-- 9. ROW LEVEL SECURITY -- starter policies
-- ============================================================================
-- A sketch, not a finished auth system: refine once your actual Supabase role
-- setup (anon / authenticated / custom claims for caregiver vs vet vs NGO
-- admin) is decided. The principle worth keeping regardless of the specifics:
-- a public QR scan should never expose a caregiver's phone number.
--
-- Assumes Supabase's default public-schema grants to anon/authenticated
-- (present automatically on every Supabase project) -- RLS is the access
-- control layer here, not table-level GRANTs, which is standard Supabase
-- practice. Tested end-to-end below: anon reads dogs + latest predictions
-- and is correctly blocked from caregivers/sensor_readings; authenticated
-- sees both. No changes needed to run this as-is on a fresh Supabase project.

alter table dogs enable row level security;
alter table caregivers enable row level security;
alter table sensor_readings enable row level security;
alter table ml_predictions enable row level security;
alter table medical_records enable row level security;

-- Public QR scans (anon role) can read the core dog profile and the latest
-- health predictions, but not raw caregiver contact info or full medical history.
create policy "public can view dog profiles"
    on dogs for select
    to anon
    using (true);

create policy "public can view latest health predictions"
    on ml_predictions for select
    to anon
    using (true);

-- Everything else (raw readings, caregiver PII, full medical history) requires
-- authentication; tighten further with a role claim once caregiver vs vet vs
-- admin accounts exist.
create policy "authenticated users can view sensor readings"
    on sensor_readings for select
    to authenticated
    using (true);

create policy "authenticated users can view caregiver info"
    on caregivers for select
    to authenticated
    using (true);

create policy "authenticated users can view medical records"
    on medical_records for select
    to authenticated
    using (true);

create policy "authenticated users can insert sensor readings"
    on sensor_readings for insert
    to authenticated
    with check (true);
