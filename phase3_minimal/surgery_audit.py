"""Phase 3 C: registry surgery-code feasibility and descriptive AJ estimates.

Date: 2026-10-27. Random seed is an explicit argument to run_surgery.
Dependencies: Python 3.13, numpy, pandas; no external writes or model fitting.
The caller writes returned aggregate records to the authorized workbook.
"""
from __future__ import annotations

import ast
import os
from pathlib import Path

import numpy as np
import pandas as pd


SURGERY_URL = "https://seer.cancer.gov/seerstat/variables/seer/surgery/"
OLD_URL = "https://seer.cancer.gov/archive/manuals/2022/AppendixC/Surgery_Codes_Other_Sites_2022.pdf"
NEW_URL = "https://seer.cancer.gov/manuals/2023/AppendixC/Surgery_Codes_Other_Sites_2023.pdf"
OLD_FIELD = "RX Summ--Surg Prim Site (1998-2022)"
NEW_FIELD = "RX Summ--Surg Prim Site 2023 (2023+)"
CODE_DEFINITIONS = {
    "30": "Simple/partial surgical removal of primary site",
    "40": "Total surgical removal of primary site",
    "60": "Radical surgery: primary-site removal with contiguous other-organ resection",
    "A300": "Simple/partial surgical removal of primary site",
    "A400": "Total surgical removal of primary site",
    "A600": "Radical surgery: primary-site removal with contiguous other-organ resection",
}


def _load_original_aj(project: Path):
    """Execute only the frozen constants and AJSpec class, not its analysis."""
    source = project / "python" / "scripts" / "stage1_burden.py"
    tree = ast.parse(source.read_text(encoding="utf-8-sig"), filename=str(source))
    chosen = []
    for node in tree.body:
        if isinstance(node, ast.Assign):
            names = {n.id for target in node.targets for n in ast.walk(target) if isinstance(n, ast.Name)}
            if names == {"YEAR", "MONTH", "HORIZON"}:
                chosen.append(node)
        elif isinstance(node, ast.ClassDef) and node.name == "AJSpec":
            chosen.append(node)
    if len(chosen) != 2:
        raise RuntimeError("Frozen AJ source no longer has the expected isolated constants/class")
    namespace = {"np": np}
    exec(compile(ast.Module(body=chosen, type_ignores=[]), str(source), "exec"), namespace)
    return namespace["AJSpec"], namespace["YEAR"], namespace["MONTH"], namespace["HORIZON"]


def run_surgery(patient_dataframe: pd.DataFrame, B: int, seed: int):
    """Return (aggregate_records, metadata), never patient identifiers or files.

    Patient draws are global over the original 3,918-patient dynamic cohort;
    the same multiplicities are used at every landmark and in both groups.
    Screening thresholds (n >= 50, GBC events >= 10, at least one patient
    observed to 36 months) are descriptive feasibility guards, not power or
    precision guarantees. No group test, adjustment, or causal effect is fit.
    """
    if B < 1:
        raise ValueError("B must be positive")
    project = Path(__file__).resolve().parents[1]
    AJSpec, YEAR, MONTH, HORIZON = _load_original_aj(project)
    required = {
        "year_dx", "surgery_code", "surgery_old_raw", "surgery_new_raw",
        "surgery_source", "T_model", "N_model", "survival_days_analysis",
        "event_competing", "descriptive_source_flag",
    }
    absent = required.difference(patient_dataframe.columns)
    if absent:
        raise ValueError("Missing surgery audit fields: " + ", ".join(sorted(absent)))
    patient = patient_dataframe.copy()
    dynamic = patient.loc[patient.descriptive_source_flag.eq(True)].reset_index(drop=True)
    if len(patient) != 7007 or len(dynamic) != 3918:
        raise RuntimeError("Frozen source/dynamic cohort mismatch; surgery analysis stopped")
    code = patient.surgery_code.astype("string")
    if code.isna().any() or not code.isin(CODE_DEFINITIONS).all():
        raise RuntimeError("Unknown/missing surgery code in frozen resection source cohort")
    recent = patient.year_dx.ge(2023)
    selected_raw = patient.surgery_old_raw.where(~recent, patient.surgery_new_raw).astype("string")
    if not code.eq(selected_raw).all():
        raise RuntimeError("Harmonized surgery code does not reproduce the diagnosis-era raw field")
    if not patient.surgery_source.eq(np.where(recent, NEW_FIELD, OLD_FIELD)).all():
        raise RuntimeError("Surgery source field does not match diagnosis era")
    if not code.loc[recent].str.startswith("A").all() or code.loc[~recent].str.startswith("A").any():
        raise RuntimeError("Numeric/alphanumeric surgery-code era incompatibility")
    if not dynamic.event_competing.isin([0, 1, 2]).all():
        raise RuntimeError("Dynamic events are not exclusively 0/1/2")

    rows = []
    for cohort, frame in (("Source", patient), ("Dynamic", dynamic)):
        for surgery_code, group in frame.groupby("surgery_code", observed=True, dropna=False):
            q25, median, q75 = np.quantile(group.survival_days_analysis.to_numpy(float) / MONTH, [.25, .5, .75])
            rows.append(dict(
                row_type="CODE_INVENTORY", cohort=cohort, surgery_code=str(surgery_code),
                code_definition=CODE_DEFINITIONS[str(surgery_code)], n=len(group),
                percentage=100 * len(group) / len(frame),
                observed_time_q25_months=float(q25), observed_time_median_months=float(median),
                observed_time_q75_months=float(q75),
                note="Observed diagnosis-to-death/censor duration; not postoperative follow-up",
                dictionary_source=NEW_URL if str(surgery_code).startswith("A") else OLD_URL,
            ))
            for variable in ("T_model", "N_model"):
                for level, count in group[variable].value_counts(dropna=False).items():
                    rows.append(dict(
                        row_type="PATHOLOGY_DISTRIBUTION", cohort=cohort, surgery_code=str(surgery_code),
                        variable=variable, level=str(level), n=int(count),
                        denominator=len(group), percentage=100 * int(count) / len(group),
                    ))
        for (year, surgery_code), count in frame.groupby(["year_dx", "surgery_code"], observed=True).size().items():
            rows.append(dict(row_type="YEAR_CODE_COUNTS", cohort=cohort,
                             diagnosis_year=int(year), surgery_code=str(surgery_code), n=int(count)))

    # Check the export dictionary and raw code distribution without rebuilding cohorts.
    raw_dir = Path(os.environ['GBC_PREPARATION_ROOT']).resolve() / 'data_raw'
    dic = raw_dir / "gallbladder_SEER_2004_2023_raw.dic"
    raw_csv = raw_dir / "gallbladder_SEER_2004_2023_raw.csv"
    dictionary = dic.read_text(encoding="utf-8-sig")
    if OLD_FIELD not in dictionary or NEW_FIELD not in dictionary:
        raise RuntimeError("Original SEER export dictionary does not document both surgery fields")
    raw = pd.read_csv(raw_csv, usecols=["Year of diagnosis", OLD_FIELD, NEW_FIELD],
                      dtype="string", keep_default_na=False)
    raw_year = pd.to_numeric(raw["Year of diagnosis"], errors="coerce")
    raw_selected = raw[OLD_FIELD].where(raw_year.lt(2023), raw[NEW_FIELD])
    for raw_code, count in raw_selected.value_counts(dropna=False).items():
        rows.append(dict(row_type="RAW_EXPORT_CODE_COUNTS", cohort="Raw export, before cohort eligibility",
                         surgery_code=str(raw_code), n=int(count),
                         note="Includes noneligible histologies/stages; not the 7007-person source cohort"))
    raw_missing = int(raw_selected.isna().sum() + raw_selected.fillna("").isin(["", "Blank(s)", "NA"]).sum())
    raw_unknown = int(raw_selected.isin(["99", "A990"]).sum())
    off_era_old_present = int((~raw[OLD_FIELD].isin(["", "Blank(s)", "NA"]) & raw_year.ge(2023)).sum())
    off_era_new_present = int((~raw[NEW_FIELD].isin(["", "Blank(s)", "NA"]) & raw_year.lt(2023)).sum())
    checks = {
        "selected_source_missing_surgery_codes": int(code.isna().sum()),
        "raw_export_missing_selected_surgery_field": raw_missing,
        "raw_export_unknown_surgery_99_A990": raw_unknown,
        "raw_export_old_field_populated_in_2023": off_era_old_present,
        "raw_export_new_field_populated_before_2023": off_era_new_present,
    }
    for name, count in checks.items():
        rows.append(dict(row_type="CODING_CHECK", cohort="Raw/source as named", variable=name, n=count,
                         status="PASS" if count == 0 or name == "raw_export_unknown_surgery_99_A990" else "WARN"))

    dynamic_group = dynamic.surgery_code.map({"30": "30/40", "40": "30/40", "60": "60"})
    if dynamic_group.isna().any():
        raise RuntimeError("Unexpected surgery code in 2004-2015 dynamic cohort")
    totals = dynamic.survival_days_analysis.to_numpy(float)
    events = dynamic.event_competing.to_numpy(int)
    specs, spec_rows = [], []
    risk_counts = []
    for landmark in range(6):
        eligible = totals > landmark * YEAR
        risk_counts.append(int(eligible.sum()))
        for label in ("30/40", "60"):
            indices = np.flatnonzero(eligible & dynamic_group.eq(label).to_numpy())
            time = totals[indices] - landmark * YEAR
            event = events[indices]
            cancer_events = int(((event == 1) & (time <= HORIZON)).sum())
            other_events = int(((event == 2) & (time <= HORIZON)).sum())
            horizon_n = int((time >= HORIZON).sum())
            feasible = len(indices) >= 50 and cancer_events >= 10 and horizon_n > 0
            # Descriptive estimates remain clearly flagged when late event information is thin.
            status = "DESCRIPTIVE_ONLY_SPARSE_CAUTION" if cancer_events < 20 or other_events < 20 else "DESCRIPTIVE_ONLY"
            if not feasible:
                status = "FEASIBILITY_ONLY"
            row = dict(row_type="LANDMARK_ESTIMATE", cohort="Dynamic", surgery_group=label,
                       landmark=landmark, n=len(indices), gbc_events_36m=cancer_events,
                       other_events_36m=other_events, at_36m=horizon_n,
                       early_censored_36m=int(((event == 0) & (time < HORIZON)).sum()),
                       status=status, bootstrap_attempts=B, seed=int(seed),
                       feasibility_rule="n>=50; GBC events>=10; at36m>0",
                       note="Unadjusted registry-code-stratified description; not surgery effectiveness or R0 status")
            rows.append(row)
            if feasible:
                specs.append(AJSpec(indices, time, event))
                spec_rows.append(row)
    if risk_counts != [3918, 2496, 1786, 1423, 1192, 1047]:
        raise RuntimeError("Surgery landmark construction differs from frozen risk-set counts")

    if specs:
        point = np.stack([s.evaluate(np.ones(len(dynamic))) for s in specs])
        bootstrap = np.full((B, len(specs), 4), np.nan)
        rng = np.random.default_rng(seed)
        for replicate in range(B):
            multiplicity = np.bincount(rng.integers(0, len(dynamic), len(dynamic)), minlength=len(dynamic))
            for j, spec in enumerate(specs):
                bootstrap[replicate, j] = spec.evaluate(multiplicity)[[4, 5, 6, 7]]
        metrics = (("gbc_cif_36m", 4, 1.), ("other_cif_36m", 5, 1.),
                   ("gbc_rmtl_months", 6, 1. / MONTH), ("other_rmtl_months", 7, 1. / MONTH))
        for j, row in enumerate(spec_rows):
            assert np.all((point[j, 4:6] >= 0) & (point[j, 4:6] <= 1))
            assert point[j, 4:6].sum() <= 1 + 1e-10
            assert point[j, 6:8].sum() <= HORIZON + 1e-8
            for metric_index, (metric, point_index, scale) in enumerate(metrics):
                draw = bootstrap[:, j, metric_index] * scale
                valid = np.isfinite(draw)
                row[metric] = float(point[j, point_index] * scale)
                row[metric + "_bootstrap_valid"] = int(valid.sum())
                row[metric + "_bootstrap_valid_fraction"] = float(valid.mean())
                # Original Stage 1 policy: any failed replicate withholds the CI.
                if valid.all() and np.isfinite(row[metric]):
                    lower, upper = np.quantile(draw, [.025, .975], method="linear")
                    row[metric + "_lower95"] = float(lower)
                    row[metric + "_upper95"] = float(upper)
                else:
                    row[metric + "_lower95"] = np.nan
                    row[metric + "_upper95"] = np.nan
                    row["status"] += ";CI_UNRESOLVED"

    metadata = dict(
        module="C", source_n=len(patient), dynamic_n=len(dynamic), raw_export_n=len(raw),
        source_code_counts={str(k): int(v) for k, v in code.value_counts().items()},
        dynamic_code_counts={str(k): int(v) for k, v in dynamic.surgery_code.value_counts().items()},
        coding_checks=checks, landmark_counts=risk_counts,
        minimum_descriptive_n=50, minimum_gbc_events=10,
        bootstrap_attempts=B, seed=int(seed), bootstrap_unit="original dynamic patient",
        bootstrap_ci_policy="percentile; original Stage1 policy requires all attempts finite",
        code_source_urls=[SURGERY_URL, OLD_URL, NEW_URL],
        source_code_mapping="old 30/40/60 -> new A300/A400/A600 for 2023; no clinical R0 inference",
        dictionary_path=str(dic), frozen_harmonization="scripts/pipeline.py:372-382 in upstream project",
        recommendation="Supplement only, descriptive; no between-group test or treatment-effect interpretation",
    )
    return rows, metadata
