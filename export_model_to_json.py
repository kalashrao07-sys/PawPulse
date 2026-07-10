"""
PawPulse -- Export a trained Random Forest to portable JSON
==============================================================

Supabase Edge Functions run on Deno/TypeScript, not Python, so
activity_rf_model.joblib can't be loaded there directly. This script walks
every tree in the trained forest and serializes it to plain JSON (feature
index, split threshold, left/right children, or a leaf's class distribution)
-- no ONNX runtime, no Python runtime in the deployment, just a JSON file a
small TypeScript interpreter can walk directly.

Run this locally, next to your trained model:
    python export_model_to_json.py

Output: activity_model.json -- copy this into the Edge Function's folder.
"""

import json

import joblib
import numpy as np

MODEL_PATH = "activity_rf_model.joblib"
OUTPUT_PATH = "activity_model.json"


def export_tree(tree, class_names):
    """Walk one sklearn DecisionTreeClassifier.tree_ into a nested dict."""
    def node_to_dict(node_id):
        left = tree.children_left[node_id]
        right = tree.children_right[node_id]
        if left == -1 and right == -1:  # leaf
            counts = tree.value[node_id][0]
            probs = (counts / counts.sum()).tolist()
            return {"leaf": True, "class_probs": dict(zip(class_names, probs))}
        return {
            "leaf": False,
            "feature": int(tree.feature[node_id]),
            "threshold": float(tree.threshold[node_id]),
            "left": node_to_dict(left),
            "right": node_to_dict(right),
        }
    return node_to_dict(0)


def main():
    bundle = joblib.load(MODEL_PATH)
    clf = bundle["model"]
    feature_columns = bundle["feature_columns"]
    class_names = bundle["labels"]

    trees = [export_tree(est.tree_, class_names) for est in clf.estimators_]

    export = {
        "feature_columns": feature_columns,   # order matters: input vector must match this order
        "class_names": class_names,
        "n_trees": len(trees),
        "trees": trees,
    }

    with open(OUTPUT_PATH, "w") as f:
        json.dump(export, f)

    import os
    size_kb = os.path.getsize(OUTPUT_PATH) / 1024
    print(f"Exported {len(trees)} trees, {len(feature_columns)} features, "
          f"{len(class_names)} classes -> {OUTPUT_PATH} ({size_kb:.0f} KB)")
    if size_kb > 2000:
        print("NOTE: this is a fairly large bundle for an Edge Function. If cold-start "
              "load time becomes a problem, retrain with fewer estimators "
              "(n_estimators=100 instead of 300 loses little accuracy on this kind "
              "of tabular data and roughly cuts this file size proportionally) "
              "-- see the train.py comments on RandomForestClassifier's n_estimators.")


if __name__ == "__main__":
    main()
