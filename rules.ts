// PawPulse -- Level 0 rule engine (hydration risk + overall health status)
//
// Translated directly from rules_design_test.py, which was validated against
// nine scenarios (healthy baseline, mild/strong dehydration signal, isolated
// fever, two emergency overrides, a threshold-boundary case, and two cold-
// start/low-variance edge cases) before being ported here. The weights and
// thresholds below are a literature-grounded starting point, not a claimed-
// final clinical formula -- they're meant to be recalibrated against real
// vet_assessments once enough ground truth accumulates from ABC/vaccination
// camp visits (see the vet_assessments table in the schema).

export interface Baseline {
  hr_mean: number;
  hr_stddev: number;
  temp_mean: number;
  temp_stddev: number;
  activity_mean: number;
  activity_stddev: number;
  sample_count: number;
}

export type SizeClass = "small" | "medium" | "large";

export const POPULATION_BASELINES: Record<SizeClass, Omit<Baseline, "sample_count">> = {
  small:  { hr_mean: 120, hr_stddev: 15, temp_mean: 38.6, temp_stddev: 0.3, activity_mean: 0.35, activity_stddev: 0.15 },
  medium: { hr_mean: 80,  hr_stddev: 12, temp_mean: 38.6, temp_stddev: 0.3, activity_mean: 0.35, activity_stddev: 0.15 },
  large:  { hr_mean: 75,  hr_stddev: 12, temp_mean: 38.6, temp_stddev: 0.3, activity_mean: 0.35, activity_stddev: 0.15 },
};

const MIN_SAMPLE_COUNT = 10; // below this, don't trust the personal baseline yet
const STDDEV_FLOOR = { hr: 5.0, temp: 0.15, activity: 0.05 }; // real physiological variance doesn't go to zero

function resolveBaseline(
  personalBaseline: Baseline | null,
  sizeClass: SizeClass
): { baseline: Omit<Baseline, "sample_count">; source: "personal_baseline" | "population_fallback" } {
  if (!personalBaseline || personalBaseline.sample_count < MIN_SAMPLE_COUNT) {
    return { baseline: POPULATION_BASELINES[sizeClass], source: "population_fallback" };
  }
  return {
    baseline: {
      hr_mean: personalBaseline.hr_mean,
      hr_stddev: Math.max(personalBaseline.hr_stddev, STDDEV_FLOOR.hr),
      temp_mean: personalBaseline.temp_mean,
      temp_stddev: Math.max(personalBaseline.temp_stddev, STDDEV_FLOOR.temp),
      activity_mean: personalBaseline.activity_mean,
      activity_stddev: Math.max(personalBaseline.activity_stddev, STDDEV_FLOOR.activity),
    },
    source: "personal_baseline",
  };
}

export interface HydrationResult {
  category: "Hydrated" | "Needs Water" | "Dehydration Risk";
  risk_score: number;
  margin: number;
  confident: boolean; // false => cascade should escalate to Level 1 if/when it exists for this module
  baseline_source: "personal_baseline" | "population_fallback";
  components: { hr_z: number; temp_z: number; activity_z: number };
}

export function hydrationRisk(
  hr: number,
  temp: number,
  activity: number,
  personalBaseline: Baseline | null,
  sizeClass: SizeClass,
  weights: [number, number, number] = [0.5, 0.3, 0.2]
): HydrationResult {
  const { baseline, source } = resolveBaseline(personalBaseline, sizeClass);
  const [wHr, wTemp, wAct] = weights;
  const eps = 1e-6;

  const hrZ = (hr - baseline.hr_mean) / Math.max(baseline.hr_stddev, eps);
  const tempZ = (temp - baseline.temp_mean) / Math.max(baseline.temp_stddev, eps);
  // reduced activity vs baseline is the risk signal, so the sign is flipped
  const actZ = (baseline.activity_mean - activity) / Math.max(baseline.activity_stddev, eps);

  const risk = wHr * Math.max(0, hrZ) + wTemp * Math.max(0, tempZ) + wAct * Math.max(0, actZ);

  let category: HydrationResult["category"];
  if (risk < 1.0) category = "Hydrated";
  else if (risk < 2.0) category = "Needs Water";
  else category = "Dehydration Risk";

  const margin = Math.min(Math.abs(risk - 1.0), Math.abs(risk - 2.0));

  return {
    category,
    risk_score: Math.round(risk * 100) / 100,
    margin: Math.round(margin * 100) / 100,
    confident: margin >= 0.3,
    baseline_source: source,
    components: {
      hr_z: Math.round(hrZ * 100) / 100,
      temp_z: Math.round(tempZ * 100) / 100,
      activity_z: Math.round(actZ * 100) / 100,
    },
  };
}

export interface OverallHealthResult {
  category: "Healthy" | "Monitor" | "Warning" | "Critical";
  risk_score: number;
  margin: number;
  confident: boolean;
  emergency_override: boolean;
}

export function overallHealth(
  hr: number,
  temp: number,
  hydrationResult: HydrationResult,
  pulseAnomalyScore = 0.0
): OverallHealthResult {
  // Absolute emergency override, deliberately independent of the weighted score
  // below -- a single dangerous absolute reading shouldn't get diluted by
  // otherwise-normal hydration/activity numbers.
  const emergency = temp >= 40.0 || temp <= 36.0 || hr >= 220;
  if (emergency) {
    return { category: "Critical", risk_score: 99, margin: 0, confident: true, emergency_override: true };
  }

  // Reuses hydration's already-fused signal rather than re-deriving from raw
  // HR/temp/activity a second time -- avoids double-counting the same three
  // raw signals under two different guises, per the fusion design in the roadmap.
  const risk = hydrationResult.risk_score + pulseAnomalyScore;

  let category: OverallHealthResult["category"];
  if (risk >= 2.5) category = "Warning";
  else if (risk >= 1.0) category = "Monitor";
  else category = "Healthy";

  const margin = Math.min(Math.abs(risk - 1.0), Math.abs(risk - 2.5));

  return {
    category,
    risk_score: Math.round(risk * 100) / 100,
    margin: Math.round(margin * 100) / 100,
    confident: margin >= 0.3,
    emergency_override: false,
  };
}
