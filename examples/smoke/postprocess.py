"""一般の Python で計算結果・追加パッケージ・日本語描画を検証する。"""
import json
import sys
import warnings
from pathlib import Path
import foamlib
import numpy as np
import scipy
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import japanize_matplotlib  # noqa: F401: 日本語フォントを設定する
import optuna
import pandas as pd
from scipy.linalg import norm

root = Path(sys.argv[1])
serial = foamlib.FoamCase(root / "serial")
parallel = foamlib.FoamCase(root / "parallel")
assert len(serial) > 1
assert np.isclose(serial[-1].time, 0.02)
assert np.isclose(parallel[-1].time, serial[-1].time)
errors = {}
for field in ("U", "p"):
    a = np.asarray(serial[-1][field].internal_field)
    b = np.asarray(parallel[-1][field].internal_field)
    assert np.isfinite(a).all() and np.isfinite(b).all()
    np.testing.assert_allclose(a, b, rtol=1e-4, atol=1e-6)
    errors[field] = float(norm(a-b))
speeds = np.linalg.norm(np.asarray(serial[-1]["U"].internal_field), axis=1)
assert speeds.max() > 0
pd.DataFrame({"cell": np.arange(len(speeds)), "speed": speeds}).to_csv(root / "velocity.csv", index=False)
# 最適化ライブラリについても import だけでなく小さな計算を確認する。
optuna.logging.set_verbosity(optuna.logging.WARNING)
study = optuna.create_study(sampler=optuna.samplers.RandomSampler(seed=0))
study.optimize(lambda trial: trial.suggest_float("x", -1, 1) ** 2, n_trials=2)
with warnings.catch_warnings():
    warnings.filterwarnings("error", message="Glyph.*missing.*")
    fig, ax = plt.subplots()
    ax.plot(speeds)
    ax.set(xlabel="セル番号", ylabel="速度", title="キャビティ流れの計算結果")
    fig.savefig(root / "velocity-ja.png")
    plt.close(fig)
(root / "logs/postprocess.json").write_text(json.dumps({
    "final_time": serial[-1].time, "cells": len(speeds), "mpi_errors": errors,
    "numpy": np.__version__, "scipy": scipy.__version__,
    "matplotlib": matplotlib.__version__, "pandas": pd.__version__,
    "optuna": optuna.__version__,
}, indent=2))
