"""Phase 3 read-only intake and surgery module for the R one-click runner.

Date: 2026-10-27. Bootstrap seed: 20261030 (surgery), explicitly fixed.
Python 3.13; numpy/pandas/pyarrow/openpyxl from the existing installation.
Only an internal JSON IPC payload is written to stdout; diagnostics use stderr.
No patient table, cache, log, hash, or derived result is written to disk.
"""
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import json
import math
import os
from pathlib import Path
import sys

import numpy as np
import pandas as pd

sys.dont_write_bytecode = True


def load_local(path: Path, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load existing local helper: " + str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def clean_json(value):
    """Convert unavailable numerical values to JSON null, never fake zero."""
    if value is pd.NA or value is None:
        return None
    if isinstance(value, dict):
        return {str(key): clean_json(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [clean_json(item) for item in value]
    if isinstance(value, np.generic):
        return clean_json(value.item())
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, Path):
        return str(value)
    return value


def patient_records(frame: pd.DataFrame):
    columns = [
        "patient_id", "record_id", "year_dx", "age_dx", "age_90plus_flag", "sex",
        "T_model", "N_model", "grade_model", "survival_days_analysis",
        "event_competing", "event_os",
    ]
    missing = set(columns).difference(frame.columns)
    if missing:
        raise RuntimeError("Missing core Phase 3 input fields: " + ", ".join(sorted(missing)))
    ordered = frame.sort_values("patient_id", kind="stable").loc[:, columns].copy()
    ordered["patient_id"] = ordered.patient_id.astype("string")
    ordered["record_id"] = ordered.record_id.astype("string")
    return ordered.to_dict(orient="records")


def canonical_cr(frozen):
    out = []
    names = {"GBC_CIF": "gbc_cif", "Other_CIF": "other_cif",
             "GBC_RMTL": "gbc_rmtl_months", "Other_RMTL": "other_rmtl_months"}
    for landmark in range(6):
        row = dict(landmark=landmark, n=frozen[(landmark, "GBC_CIF")]["n"])
        for original, canonical in names.items():
            item = frozen[(landmark, original)]
            scale = .01 if original.endswith("CIF") else 1.
            row[canonical] = item["estimate"] * scale
            row[canonical + "_lower95"] = item["lo"] * scale
            row[canonical + "_upper95"] = item["hi"] * scale
            row[canonical + "_bootstrap_valid"] = item["valid"]
        row["other_minus_gbc_cif_pp"] = frozen[(landmark, "Delta_CIF")]["estimate"]
        out.append(row)
    return out


def crude_pathology(phase2, root: Path):
    rows = []
    contrasts = {"T": ("T3/4", "T1"), "N": ("N+", "N0"), "Grade": ("G3/4", "G1")}
    for target, (high, low) in contrasts.items():
        records = phase2.sheet_records(root / "outputs" / "STAGE1_RESULTS_v2.xlsx",
                                       target + "_attenuation", "row_type")
        for landmark in range(6):
            rd = [r for r in records if r["row_type"] == "RISK_DIFFERENCE"
                  and int(r["landmark_year"]) == landmark]
            if len(rd) != 1:
                raise RuntimeError("Incomplete/ambiguous frozen crude pathology contrast")
            item = rd[0]
            row = dict(target=target, landmark=landmark, contrast=item["contrast"],
                       high=high, low=low, crude_rd_pp=100 * item["estimate"],
                       crude_lower95_pp=100 * item["ci_lower"],
                       crude_upper95_pp=100 * item["ci_upper"],
                       crude_bootstrap_valid=item["bootstrap_valid"],
                       crude_bootstrap_attempts=1000)
            for arm, label in (("high", high), ("low", low)):
                group = [r for r in records if r["row_type"] == "GROUP_CANCER_CIF"
                         and int(r["landmark_year"]) == landmark and r["group"] == label]
                if len(group) != 1:
                    raise RuntimeError("Incomplete frozen crude pathology arm")
                group = group[0]
                for source, suffix in (("n_at_risk", "n"), ("cancer_events_3y", "gbc_events_36m"),
                                       ("other_events_3y", "other_events_36m"),
                                       ("n_at_3y_horizon", "at_36m"), ("estimate", "cif")):
                    row["crude_" + arm + "_" + suffix] = group[source]
            rows.append(row)
    return rows


def previous_standardization(phase2, root: Path):
    path = root / "outputs" / "STANDARDIZATION_RESULTS.xlsx"
    if not path.exists():
        return [], [], dict(available=False, path=str(path))
    rows = phase2.sheet_records(path, "standardized_contrasts", "target")
    keep = [r for r in rows if r.get("cause") == "GBC" and r.get("horizon_years") == 3]
    support = phase2.sheet_records(path, "support", "target")
    for row in keep:
        for source, destination in (("delta_CIF", "previous_rd_pp"),
                                    ("delta_CIF_lower95", "previous_lower95_pp"),
                                    ("delta_CIF_upper95", "previous_upper95_pp")):
            row[destination] = None if row.get(source) is None else row[source] * 100
    metadata = dict(
        available=True, path=str(path), contrast_rows=len(keep),
        note="Prior higher-dimensional adjustment/support target differs from Phase3 age/sex-only estimand",
        sheets=["support", "model_fit", "standardized_contrasts", "sensitivity_2y", "trajectory_summary", "plot_ready"],
    )
    return keep, support, metadata


def build_payload(root: Path, B: int, mode: str):
    root = root.resolve()
    code_root = Path(__file__).resolve().parents[1]
    phase2 = load_local(code_root / 'gbc_transfer_gate' / 'phase2' / 'phase2.py', 'phase2_readonly_intake')
    with contextlib.redirect_stdout(sys.stderr):
        patient, dynamic, life, _, _, _ = phase2.preflight(root)
        frozen = phase2.frozen_cr(root)
        phase2.cr_sensitivity(root, dynamic, dynamic, frozen, check_only=True)
    frozen_life = [r for r in phase2.sheet_records(root / "outputs" / "LIFETABLE_RESULTS.xlsx",
                                                "rmst_gap", "landmark")
                   if r.get("analysis_type") == "PRIMARY"]
    if len(frozen_life) != 6 or [int(r["n"]) for r in frozen_life] != [3796, 2469, 1775, 1420, 1191, 1048]:
        raise RuntimeError("Frozen life-table workbook count mismatch")
    crude = crude_pathology(phase2, root)
    surgery = load_local(code_root / "phase3_minimal" / "surgery_audit.py", "phase3_surgery_intake")
    surgery_rows, surgery_metadata = surgery.run_surgery(patient, B, 20261030)
    oldstd, oldsupport, oldmetadata = previous_standardization(phase2, root)
    upstream = Path(os.environ['GBC_PREPARATION_ROOT']).resolve()
    files = [
        upstream / "data_raw" / "gallbladder_SEER_2004_2023_raw.csv",
        upstream / "data_raw" / "gallbladder_SEER_2004_2023_raw.dic",
        upstream / "data_clean" / "01_gallbladder_harmonized_all_2004_2023.parquet",
        root / "data" / "analysis_patient_level_v2.parquet",
        root / "data" / "analysis_landmark_long_v2.parquet",
        code_root / "python/scripts/stage1_burden.py",
        root / "scripts" / "04_standardization.R",
        root / "scripts" / "05_lifetable_rmst_gap.R",
        root / "gbc_transfer_gate" / "SCIENTIFIC_AUDIT.md",
        root / "gbc_transfer_gate" / "phase2" / "PHASE2_DECISION.md",
        code_root / "gbc_transfer_gate" / "phase2" / "phase2.py",
        code_root / "scripts/current_kernels/lifetable_core.R",
        root / "data_external" / "US_Annual_ExpectedSurvival_1970_2023.txt",
        root / "outputs" / "STAGE1_RESULTS_v2.xlsx",
        root / "outputs" / "LIFETABLE_RESULTS.xlsx",
        root / "outputs" / "STANDARDIZATION_RESULTS.xlsx",
    ]
    requested_names = ("GBC_Polished_Manuscript.docx", "GBC_Supplementary_Information_Polished.pdf")
    current_documents = {name: [str(path) for path in root.rglob(name)] for name in requested_names}
    inventory = dict(
        root=str(root), mode=mode, B=B,
        files=[dict(path=str(path), exists=path.is_file()) for path in files],
        polished_documents=current_documents,
        polished_document_note="Exact named current documents not found within project" if not any(current_documents.values())
            else "Named files located; separate document review required for manuscript wording",
        source_n=len(patient), dynamic_n=len(dynamic), life_n=len(life),
        dynamic_landmark_n=[int(dynamic.survival_days_analysis.gt(s * phase2.YEAR).sum()) for s in range(6)],
        life_landmark_n=[int(life.survival_days_analysis.gt(s * phase2.YEAR).sum()) for s in range(6)],
        dynamic_age90plus_n=int(dynamic.age_90plus_flag.sum()),
        dynamic_age_missing_n=int(dynamic.age_dx.isna().sum()),
        dynamic_sex_counts={str(k): int(v) for k, v in dynamic.sex.value_counts(dropna=False).items()},
        old_standardization=oldmetadata,
        cohort_gate="PASS", frozen_cr_point_reconciliation="PASS: all 30 metrics within 1e-8",
    )
    return clean_json(dict(
        cr_patients=patient_records(dynamic), life_patients=patient_records(life),
        frozen_cr=canonical_cr(frozen), frozen_life=frozen_life,
        crude=crude, surgery_rows=surgery_rows, surgery_metadata=surgery_metadata,
        inventory=inventory, old_standardization=oldstd, old_support=oldsupport,
    ))


def main():
    parser = argparse.ArgumentParser(description="Read-only Phase 3 intake; internal JSON IPC on stdout")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--B", type=int, required=True)
    parser.add_argument("--mode", choices=("smoke", "formal"), required=True)
    args = parser.parse_args()
    if args.B < 1 or (args.mode == "formal" and args.B != 1000):
        parser.error("Positive B required; formal requires exactly 1000 attempts")
    payload = build_payload(args.root, args.B, args.mode)
    json.dump(payload, sys.stdout, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
