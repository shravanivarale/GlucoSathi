from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import onnxruntime as ort


BASE_DIR = Path(__file__).resolve().parents[2]
MODEL_DIR = BASE_DIR / "models"

MODEL_PATH = MODEL_DIR / "glucose_model.onnx"
SCALER_PATH = MODEL_DIR / "scalers.json"


class GlucosePredictor:
    def __init__(self):
        self.session = ort.InferenceSession(
            str(MODEL_PATH),
            providers=["CPUExecutionProvider"],
        )

        with open(SCALER_PATH, "r") as f:
            self.scalers = json.load(f)

        self.input_name = self.session.get_inputs()[0].name

        self.feature_mean = np.array(
            self.scalers["feature_mean"],
            dtype=np.float32,
        )

        self.feature_scale = np.array(
            self.scalers["feature_scale"],
            dtype=np.float32,
        )

        self.target_mean = float(
            self.scalers["target_mean"]
        )

        self.target_scale = float(
            self.scalers["target_scale"]
        )

    def predict_scaled(
        self,
        scaled_features: np.ndarray,
    ) -> dict:
        x = np.asarray(
            scaled_features,
            dtype=np.float32,
        )

        if x.shape != (24, 12):
            raise ValueError(
                f"Expected scaled input shape (24, 12), got {x.shape}"
            )

        x = np.expand_dims(x, axis=0)

        outputs = self.session.run(
            None,
            {self.input_name: x},
        )

        pred_30_scaled = float(outputs[0][0])
        pred_60_scaled = float(outputs[1][0])

        pred_30 = (
            pred_30_scaled * self.target_scale
            + self.target_mean
        )

        pred_60 = (
            pred_60_scaled * self.target_scale
            + self.target_mean
        )

        return {
            "prediction_30_min": round(pred_30, 2),
            "prediction_60_min": round(pred_60, 2),
        }

    def predict(
        self,
        features: list[list[float]],
    ) -> dict:
        x = np.asarray(
            features,
            dtype=np.float32,
        )

        if x.shape != (24, 12):
            raise ValueError(
                f"Expected input shape (24, 12), got {x.shape}"
            )

        x_scaled = (
            (x - self.feature_mean)
            / self.feature_scale
        ).astype(np.float32)

        return self.predict_scaled(x_scaled)


_predictor = None


def get_glucose_predictor() -> GlucosePredictor:
    global _predictor

    if _predictor is None:
        _predictor = GlucosePredictor()

    return _predictor
