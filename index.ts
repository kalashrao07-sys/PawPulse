// PawPulse -- Edge Function: cascade orchestrator
//
// Two entry points, matching the two things that trigger inference:
//   { "reading_id": "<uuid>" }  -- a new pulse/temperature reading came in.
//                                   Runs Level 0 (hydration risk, overall health).
//   { "window_id": "<uuid>" }   -- a new activity_windows row was computed.
//                                   Runs Level 1 (Random Forest activity classifier).
//
// Deploy: supabase functions deploy pawpulse-cascade
// Call from a Postgres trigger (recommended -- see the SQL comment at the
// bottom) or directly via HTTP POST from the ESP32 / a backend job.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hydrationRisk, overallHealth, type Baseline, type SizeClass } from "./rules.ts";
import { forestPredict, type ForestModel } from "./activity_forest.ts";

// Bundled at deploy time -- see export_model_to_json.py for how this file is produced.
import activityModel from "./activity_model.json" with { type: "json" };

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const MODEL_VERSION = "activity_rf_v1"; // bump this whenever activity_model.json is retrained/re-exported

Deno.serve(async (req: Request) => {
  try {
    const body = await req.json();

    if (body.reading_id) {
      return await handleReading(body.reading_id);
    }
    if (body.window_id) {
      return await handleActivityWindow(body.window_id);
    }
    return jsonResponse({ error: "Provide either reading_id or window_id" }, 400);
  } catch (err) {
    console.error(err);
    return jsonResponse({ error: String(err) }, 500);
  }
});

async function handleReading(readingId: string): Promise<Response> {
  const { data: reading, error: readingErr } = await supabase
    .from("sensor_readings")
    .select("id, dog_id, pulse_bpm, temperature_c")
    .eq("id", readingId)
    .single();
  if (readingErr || !reading) return jsonResponse({ error: "reading not found" }, 404);
  if (reading.pulse_bpm == null || reading.temperature_c == null) {
    return jsonResponse({ error: "reading is missing pulse_bpm or temperature_c; Level 0 needs both" }, 400);
  }

  const { data: dog, error: dogErr } = await supabase
    .from("dogs")
    .select("id, size_class")
    .eq("id", reading.dog_id)
    .single();
  if (dogErr || !dog) return jsonResponse({ error: "dog not found" }, 404);
  const sizeClass = (dog.size_class ?? "medium") as SizeClass;

  const { data: baselineRow } = await supabase
    .from("latest_dog_baseline")
    .select("*")
    .eq("dog_id", reading.dog_id)
    .maybeSingle();
  const personalBaseline: Baseline | null = baselineRow
    ? {
        hr_mean: baselineRow.hr_mean, hr_stddev: baselineRow.hr_stddev,
        temp_mean: baselineRow.temp_mean, temp_stddev: baselineRow.temp_stddev,
        activity_mean: baselineRow.activity_mean, activity_stddev: baselineRow.activity_stddev,
        sample_count: baselineRow.sample_count,
      }
    : null;

  // most recent activity level as a stand-in for "current activity" in the
  // hydration formula -- falls back to the baseline's own mean (i.e. "assume
  // typical" ) if no recent activity window exists yet for this dog
  const { data: recentWindow } = await supabase
    .from("activity_windows")
    .select("accel_rms")
    .eq("dog_id", reading.dog_id)
    .order("window_start", { ascending: false })
    .limit(1)
    .maybeSingle();
  const currentActivity = recentWindow?.accel_rms ?? personalBaseline?.activity_mean ?? 0.35;

  const hydration = hydrationRisk(reading.pulse_bpm, reading.temperature_c, currentActivity, personalBaseline, sizeClass);
  const health = overallHealth(reading.pulse_bpm, reading.temperature_c, hydration);

  // Cascade signal: neither result is "confident" here means Level 0 is
  // uncertain. There's no Level 1 classifier for hydration/overall-health yet
  // (per the roadmap, that needs vet_assessments ground truth first) -- for
  // now this just gets logged in the explanation so low-confidence cases are
  // queryable later, and the escalation path can be wired in once that model exists.
  const rows = [
    {
      dog_id: reading.dog_id,
      prediction_type: "hydration_status",
      predicted_label: hydration.category,
      confidence_score: hydration.confident ? 0.8 : 0.4, // placeholder scale until Level 1 exists for this module
      explanation: { ...hydration.components, risk_score: hydration.risk_score,
                      baseline_source: hydration.baseline_source, cascade_confident: hydration.confident },
      model_version: "rule_v1",
      source_reading_id: readingId,
    },
    {
      dog_id: reading.dog_id,
      prediction_type: "overall_health_status",
      predicted_label: health.category,
      confidence_score: health.confident ? 0.8 : 0.4,
      explanation: { risk_score: health.risk_score, emergency_override: health.emergency_override,
                      cascade_confident: health.confident, hydration_contribution: hydration.risk_score },
      model_version: "rule_v1",
      source_reading_id: readingId,
    },
  ];

  const { error: insertErr } = await supabase.from("ml_predictions").insert(rows);
  if (insertErr) return jsonResponse({ error: insertErr.message }, 500);

  if (health.category === "Critical") {
    await supabase.from("emergency_alerts").insert({
      dog_id: reading.dog_id,
      trigger_source: "server_ml_critical",
      triggering_reading_id: readingId,
    });
  }

  return jsonResponse({ hydration, health });
}

async function handleActivityWindow(windowId: string): Promise<Response> {
  const { data: win, error: winErr } = await supabase
    .from("activity_windows")
    .select("id, dog_id, features")
    .eq("id", windowId)
    .single();
  if (winErr || !win) return jsonResponse({ error: "activity window not found" }, 404);
  if (!win.features) {
    return jsonResponse({ error: "window has no features -- populate the features jsonb column at ingestion time (see preprocess.py's per-window feature computation)" }, 400);
  }

  const model = activityModel as ForestModel;
  const missing = model.feature_columns.filter((c) => !(c in win.features));
  if (missing.length) {
    return jsonResponse({ error: `window.features is missing required columns: ${missing.join(", ")}` }, 400);
  }

  const prediction = forestPredict(model, win.features as Record<string, number>);

  const { error: updateErr } = await supabase
    .from("activity_windows")
    .update({
      classified_activity: prediction.predicted_label,
      classification_confidence: prediction.confidence,
    })
    .eq("id", windowId);
  if (updateErr) return jsonResponse({ error: updateErr.message }, 500);

  return jsonResponse({ prediction, model_version: MODEL_VERSION });
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/* Recommended trigger, run once in the Supabase SQL editor, so inference runs
   automatically instead of needing a manual HTTP call after every insert:

   create or replace function trigger_pawpulse_cascade()
   returns trigger as $$
   begin
     perform net.http_post(
       url := '<your-project-ref>.functions.supabase.co/pawpulse-cascade',
       body := jsonb_build_object('reading_id', new.id)
     );
     return new;
   end;
   $$ language plpgsql;

   create trigger on_sensor_reading_insert
     after insert on sensor_readings
     for each row execute function trigger_pawpulse_cascade();

   (mirror this with a window_id version on activity_windows insert/update)
   -- requires the pg_net extension, enabled by default on Supabase projects. */
