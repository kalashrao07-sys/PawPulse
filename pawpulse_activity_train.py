"""
PawPulse -- Activity Classification: Training
===============================================

Takes the windowed features produced by preprocess.py and trains a Random
Forest classifier -- the simple, explainable model the roadmap recommended
over deep learning for this data regime (tabular features, moderate sample
count; see the tree-based-vs-deep-learning discussion in the ML roadmap).

Split strategy: grouped by DogID, not by row. If windows from the same dog
land in both train and test, the model can partly learn "this is Dog 7's
gait" rather than "this is what trotting looks like" -- and report inflated
accuracy that won't hold up on a genuinely new dog. GroupShuffleSplit fixes
this by keeping each dog entirely on one side of the split.

Output: a trained model (joblib), a held-out classification report, a
confusion matrix, and feature importances -- the explainability layer the
roadmap asked every module to have. This is meant to run server-side
(Supabase Edge Function or a small backend service), never on the ESP32,
per the integration plan in the roadmap.
"""

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import GroupShuffleSplit

FEATURES_PATH = "activity_features.csv"
MODEL_OUTPUT_PATH = "activity_rf_model.joblib"
RANDOM_STATE = 42


def load_features(path: str):
    df = pd.read_csv(path)
    feature_cols = [c for c in df.columns if c not in ("DogID", "TestNum", "label")]
    X = df[feature_cols].to_numpy()
    y = df["label"].to_numpy()
    groups = df["DogID"].to_numpy()
    return X, y, groups, feature_cols


def grouped_split(X, y, groups, test_size=0.25):
    splitter = GroupShuffleSplit(n_splits=1, test_size=test_size, random_state=RANDOM_STATE)
    train_idx, test_idx = next(splitter.split(X, y, groups))
    return (X[train_idx], X[test_idx], y[train_idx], y[test_idx],
            groups[train_idx], groups[test_idx])


def main():
    X, y, groups, feature_cols = load_features(FEATURES_PATH)
    n_dogs = len(set(groups))
    print(f"Loaded {len(X):,} windows from {n_dogs} dogs, {len(feature_cols)} features.")

    if n_dogs < 4:
        print(f"WARNING: only {n_dogs} dogs in this dataset -- a grouped split with "
              "this few dogs is a weak evaluation regardless of window count. "
              "The real Vehkaoja dataset has far more dogs than this; on synthetic "
              "test data this warning is expected.")

    X_train, X_test, y_train, y_test, g_train, g_test = grouped_split(X, y, groups)
    print(f"Train: {len(X_train)} windows / {len(set(g_train))} dogs | "
          f"Test: {len(X_test)} windows / {len(set(g_test))} dogs "
          f"(no dog appears in both)")

    clf = RandomForestClassifier(
        n_estimators=300,
        max_depth=None,
        min_samples_leaf=2,
        class_weight="balanced",   # guards against the label imbalance any real
                                    # deployment will have -- most windows will be
                                    # "resting" behaviors, not galloping
        random_state=RANDOM_STATE,
        n_jobs=-1,
    )
    clf.fit(X_train, y_train)

    y_pred = clf.predict(X_test)
    print("\n--- Held-out classification report (grouped by dog) ---")
    print(classification_report(y_test, y_pred, zero_division=0))

    labels = sorted(set(y))
    cm = confusion_matrix(y_test, y_pred, labels=labels)
    print("--- Confusion matrix ---")
    print("Rows = true label, columns = predicted label")
    print(pd.DataFrame(cm, index=labels, columns=labels))

    # explainability: feature importances, the cheapest real explanation a
    # tree ensemble gives you -- swap in SHAP later if you want per-prediction
    # explanations rather than global ones
    importances = pd.Series(clf.feature_importances_, index=feature_cols).sort_values(ascending=False)
    print("\n--- Top 10 feature importances ---")
    print(importances.head(10))

    joblib.dump({"model": clf, "feature_columns": feature_cols, "labels": labels}, MODEL_OUTPUT_PATH)
    print(f"\nSaved trained model to {MODEL_OUTPUT_PATH}")


if __name__ == "__main__":
    main()
