from __future__ import annotations

import numpy as np
import pandas as pd


FEATURE_COLS = [
    "cbg_clean",
    "RoC_1",
    "RoC_2",
    "IOB_analogue",
    "IOB_regular",
    "IOB_NPH",
    "COB_mixed",
    "HR_smooth",
    "GSR_smooth",
    "t_sin",
    "t_cos",
    "missing_flag",
]


def compute_iob_rapid(
    bolus_series,
    time_step_min=5,
    tau_end=240,
    tau_peak=75,
):
    iob = np.zeros(len(bolus_series))
    bolus_vals = bolus_series.fillna(0).values

    for t in range(len(bolus_vals)):
        if bolus_vals[t] > 0:
            for tau_idx in range(int(tau_end / time_step_min)):
                if t + tau_idx < len(bolus_vals):
                    tau = tau_idx * time_step_min

                    s_rapid = 1 - (
                        tau / tau_end
                    ) * (
                        1
                        + (tau_end - tau)
                        / (tau_end - tau_peak)
                    )

                    s_rapid = max(0.0, s_rapid)
                    iob[t + tau_idx] += (
                        bolus_vals[t] * s_rapid
                    )

    return iob


def compute_iob_regular(
    bolus_series,
    time_step_min=5,
    tau_onset=30,
    tau_end=480,
):
    iob = np.zeros(len(bolus_series))
    bolus_vals = bolus_series.fillna(0).values

    for t in range(len(bolus_vals)):
        if bolus_vals[t] > 0:
            for tau_idx in range(int(tau_end / time_step_min)):
                if t + tau_idx < len(bolus_vals):
                    tau = tau_idx * time_step_min

                    if tau < tau_onset:
                        s_reg = 1.0
                    else:
                        s_reg = 1.0 - (
                            (tau - tau_onset)
                            / (tau_end - tau_onset)
                        ) ** 2

                    s_reg = max(0.0, s_reg)
                    iob[t + tau_idx] += (
                        bolus_vals[t] * s_reg
                    )

    return iob


def compute_iob_nph(
    basal_series,
    time_step_min=5,
    tau_peak=480,
    tau_end=960,
    sigma=180,
):
    iob = np.zeros(len(basal_series))
    basal_vals = basal_series.fillna(0).values

    for t in range(len(basal_vals)):
        if basal_vals[t] > 0:
            for tau_idx in range(int(tau_end / time_step_min)):
                if t + tau_idx < len(basal_vals):
                    tau = tau_idx * time_step_min

                    s_nph = np.exp(
                        -((tau - tau_peak) ** 2)
                        / (2 * (sigma ** 2))
                    )

                    iob[t + tau_idx] += (
                        basal_vals[t] * s_nph
                    )

    return iob


def compute_cob(
    carb_series,
    time_step_min=5,
    tau_carb=45,
    duration_min=300,
):
    cob = np.zeros(len(carb_series))
    carb_vals = carb_series.fillna(0).values

    for t in range(len(carb_vals)):
        if carb_vals[t] > 0:
            for tau_idx in range(
                int(duration_min / time_step_min)
            ):
                if t + tau_idx < len(carb_vals):
                    tau = tau_idx * time_step_min

                    s_carb = (
                        1
                        - (tau / tau_carb)
                        * np.exp(
                            1 - (tau / tau_carb)
                        )
                    )

                    s_carb = max(0.0, s_carb)
                    cob[t + tau_idx] += (
                        carb_vals[t] * s_carb
                    )

    return cob


def build_features(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()

    required = [
        "cbg",
        "basal",
        "hr",
        "gsr",
        "carbInput",
        "bolus",
    ]

    for column in required:
        if column not in df.columns:
            df[column] = 0.0

    df["missing_flag"] = (
        df["cbg"].isna().astype(float)
    )

    df["cbg_clean"] = (
        df["cbg"]
        .interpolate(
            method="spline",
            order=2,
            limit=3,
        )
        .bfill()
        .ffill()
    )

    df["IOB_analogue"] = compute_iob_rapid(
        df["bolus"]
    )

    df["IOB_regular"] = compute_iob_regular(
        df["bolus"]
    )

    df["IOB_NPH"] = compute_iob_nph(
        df["basal"]
    )

    df["COB_mixed"] = compute_cob(
        df["carbInput"]
    )

    df["RoC_1"] = (
        df["cbg_clean"]
        - df["cbg_clean"].shift(3)
    ) / 15.0

    df["RoC_2"] = (
        df["RoC_1"]
        - df["RoC_1"].shift(3)
    ) / 15.0

    df["RoC_1"] = df["RoC_1"].fillna(0.0)
    df["RoC_2"] = df["RoC_2"].fillna(0.0)

    df["HR_smooth"] = (
        df["hr"]
        .rolling(
            window=3,
            min_periods=1,
        )
        .mean()
        .fillna(0.0)
    )

    df["GSR_smooth"] = (
        df["gsr"]
        .rolling(
            window=3,
            min_periods=1,
        )
        .mean()
        .fillna(0.0)
    )

    if "timestamp" in df.columns:
        timestamps = pd.to_datetime(
            df["timestamp"]
        )
        minutes = (
            timestamps.dt.hour * 60
            + timestamps.dt.minute
        )
    else:
        minutes = (
            df.index * 5
        ) % 1440

    df["t_sin"] = np.sin(
        2 * np.pi * minutes / 1440.0
    )

    df["t_cos"] = np.cos(
        2 * np.pi * minutes / 1440.0
    )

    return df


def preprocess_history(
    df: pd.DataFrame,
    feature_mean,
    feature_scale,
) -> np.ndarray:
    """
    Convert raw glucose history into the exact
    scaled 24 x 12 tensor expected by the ONNX model.

    The final 24 rows become the model context window.
    """

    if len(df) < 24:
        raise ValueError(
            "At least 24 glucose readings are required."
        )

    features = build_features(df)

    raw_features = features[
        FEATURE_COLS
    ].tail(24).to_numpy(
        dtype=np.float32
    )

    feature_mean = np.asarray(
        feature_mean,
        dtype=np.float32,
    )

    feature_scale = np.asarray(
        feature_scale,
        dtype=np.float32,
    )

    if len(feature_mean) != 12:
        raise ValueError(
            "feature_mean must contain 12 values."
        )

    if len(feature_scale) != 12:
        raise ValueError(
            "feature_scale must contain 12 values."
        )

    scaled_features = (
        raw_features - feature_mean
    ) / feature_scale

    return scaled_features.astype(
        np.float32
    )
