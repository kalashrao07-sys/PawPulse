"""
PawPulse -- Activity Classification: Preprocessing
====================================================

DATASET -- where to get it
---------------------------
Vehkaoja et al., "Description of Movement Sensor Dataset for Dog Behavior
Classification", Data in Brief, 2021/2022. Real dog accelerometer + gyroscope
data (back and neck sensors, 100 Hz), 10.6M+ rows, labeled by behavior.

Option A -- Kaggle (needs a free Kaggle account):
    1. Go to: https://www.kaggle.com/datasets/benjamingray44/inertial-data-for-dog-behaviour-classification
    2. Click "Download" (or use the Kaggle API once you've placed your
       kaggle.json API token in ~/.kaggle/):
           pip install kaggle
           kaggle datasets download -d benjamingray44/inertial-data-for-dog-behaviour-classification
           unzip inertial-data-for-dog-behaviour-classification.zip

Option B -- Mendeley Data (open access, no account needed):
    https://data.mendeley.com/datasets/vxhx934tbn/1
    Click "Download All" to get DogMoveData.csv, DogInfo.csv, and
    Data_description.txt directly.

Either source gives you the same underlying files. Put DogMoveData.csv
somewhere local and point RAW_CSV_PATH below at it.

IMPORTANT: the exact column names below are taken from the dataset's public
documentation, not verified against a live copy of the file (this sandbox
can't reach kaggle.com or data.mendeley.com). Open Data_description.txt after
downloading and check COLUMN_MAP below against it before running this on the
real file -- if a name differs, fix it there and nothing else needs to change.

WHAT THIS SCRIPT DOES
----------------------
1. Loads the raw 100 Hz sensor stream.
2. Splits it into fixed-length windows, never crossing a DogID/TestNum
   boundary (crossing one would silently blend two unrelated recordings).
3. Computes summary features per window (mean, variance, RMS per axis, for
   both accelerometer and gyroscope, both sensor locations) -- the same
   windowed-feature approach the roadmap recommended over raw-sample input,
   since it's what feeds a Random Forest / Gradient Boosting model well.
4. Writes out one row per window: features + majority behavior label + the
   DogID it came from (kept through to preprocessing's output specifically so
   train.py can do a grouped, per-dog train/test split -- splitting by row
   instead would leak a dog's individual movement signature across the
   train/test boundary and inflate reported accuracy).
"""

import numpy as np
import pandas as pd

# ---- configuration ---------------------------------------------------------

RAW_CSV_PATH = "DogMoveData.csv"          # point this at your downloaded file
OUTPUT_FEATURES_PATH = "activity_features.csv"

SAMPLING_HZ = 100                          # documented sampling rate of the dataset
WINDOW_SECONDS = 2.0                       # 2s windows = 200 samples/window at 100Hz
WINDOW_SIZE = int(SAMPLING_HZ * WINDOW_SECONDS)
WINDOW_STEP = WINDOW_SIZE                  # non-overlapping; set smaller (e.g. WINDOW_SIZE//2)
                                            # for overlapping windows if you want more training rows

# Column names as documented; adjust to match Data_description.txt if they differ.
ID_COLS = ["DogID", "TestNum", "t_sec"]
ACCEL_COLS = ["ABack_x", "ABack_y", "ABack_z", "ANeck_x", "ANeck_y", "ANeck_z"]
GYRO_COLS = ["GBack_x", "GBack_y", "GBack_z", "GNeck_x", "GNeck_y", "GNeck_z"]
SENSOR_COLS = ACCEL_COLS + GYRO_COLS
LABEL_COL = "Behavior_1"                   # primary behavior label; the dataset allows up to
                                            # three simultaneous annotations -- using just the
                                            # primary one is the simple, defensible starting choice

# Behaviors kept for classification. Rows with anything else (or missing label)
# are dropped -- start narrow and add categories back in once the pipeline works.
KEEP_BEHAVIORS = ["Lying chest", "Sitting", "Standing", "Sniffing",
                   "Walking", "Trotting", "Galloping"]

# Galloping is a genuinely rare behavior in this dataset -- a first real run
# produced only ~32 windows out of 21,692 (about 0.15%), with almost all
# reporting confusion falling against the adjacent Trotting class. A
# precision/recall number built on a handful of test examples isn't a result
# worth publishing on its own. Merging the two into one "fast gait" class is
# the honest fix, not further tuning -- the other five classes stay separate
# and unaffected. Set this to {} to keep all seven classes distinct instead.
LABEL_MERGE_MAP = {
    "Galloping": "Trotting/Galloping (fast gait)",
    "Trotting": "Trotting/Galloping (fast gait)",
}


def load_raw(path: str) -> pd.DataFrame:
    usecols = ID_COLS + SENSOR_COLS + [LABEL_COL]
    df = pd.read_csv(path, usecols=usecols)
    missing = [c for c in usecols if c not in df.columns]
    if missing:
        raise ValueError(
            f"Expected columns not found: {missing}. "
            "Check Data_description.txt from your download and update the "
            "column name constants at the top of this file."
        )
    return df


def make_windows(df: pd.DataFrame) -> pd.DataFrame:
    df = df[df[LABEL_COL].isin(KEEP_BEHAVIORS)].copy()
    if LABEL_MERGE_MAP:
        df[LABEL_COL] = df[LABEL_COL].replace(LABEL_MERGE_MAP)
    feature_rows = []

    # group by DogID + TestNum so a window never straddles two recordings
    for (dog_id, test_num), group in df.groupby(["DogID", "TestNum"], sort=False):
        group = group.sort_values("t_sec").reset_index(drop=True)
        n = len(group)
        for start in range(0, n - WINDOW_SIZE + 1, WINDOW_STEP):
            chunk = group.iloc[start:start + WINDOW_SIZE]

            # majority label in the window; skip ambiguous windows outright
            label_counts = chunk[LABEL_COL].value_counts()
            majority_label = label_counts.index[0]
            majority_frac = label_counts.iloc[0] / len(chunk)
            if majority_frac < 0.8:
                continue  # window spans a behavior transition -- too ambiguous to label cleanly

            feats = {"DogID": dog_id, "TestNum": test_num, "label": majority_label}
            for col in SENSOR_COLS:
                vals = chunk[col].to_numpy()
                feats[f"{col}_mean"] = vals.mean()
                feats[f"{col}_var"] = vals.var()
                feats[f"{col}_rms"] = np.sqrt(np.mean(vals ** 2))

            # Tilt/inclination angle per sensor, from the window's mean gravity-vector
            # direction. Added specifically to test the Standing/Lying/Sitting confusion
            # a first real run showed (215/553 Standing windows called "Lying chest").
            # Raw per-axis means already partially encode orientation, but this is a more
            # direct way to hand the model the one signal that should separate near-static
            # postures -- standard technique in accelerometer-based posture classification.
            # NOTE: sign conventions assume a typical axis mounting; if pitch/roll come out
            # inverted or degenerate for your sensor orientation, flip the relevant sign --
            # the technique doesn't depend on getting the convention exactly right.
            for loc in ("Back", "Neck"):
                ax = chunk[f"A{loc}_x"].mean()
                ay = chunk[f"A{loc}_y"].mean()
                az = chunk[f"A{loc}_z"].mean()
                feats[f"A{loc}_pitch"] = np.degrees(np.arctan2(-ax, np.sqrt(ay ** 2 + az ** 2)))
                feats[f"A{loc}_roll"] = np.degrees(np.arctan2(ay, az if az != 0 else 1e-6))

            feature_rows.append(feats)

    return pd.DataFrame(feature_rows)


def main():
    raw = load_raw(RAW_CSV_PATH)
    print(f"Loaded {len(raw):,} raw samples across {raw['DogID'].nunique()} dogs.")

    features = make_windows(raw)
    print(f"Built {len(features):,} windows ({WINDOW_SECONDS}s each) "
          f"across {features['DogID'].nunique()} dogs.")
    print(features["label"].value_counts())

    features.to_csv(OUTPUT_FEATURES_PATH, index=False)
    print(f"Saved features to {OUTPUT_FEATURES_PATH}")


if __name__ == "__main__":
    main()