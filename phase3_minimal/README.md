# Phase 3 and Phase 3B: public calculation entry points

This directory contains the final 2026-10-27 statistical strengthening code for
the BMC Gastroenterology submission. These are **not** legacy Model A/B/C
prediction-development workflows. No analysis starts when an entry point is
sourced; running it without an explicit mode only prints usage.

## Runtime and path configuration

The original calculations require **R 4.4.3 and survival 3.8.3**; the existing
version gates are retained. R also needs `jsonlite` and `processx`. The recorded
Python environment is Python 3.13, NumPy 2.4.2, pandas 2.3.3, pyarrow 23.0.1 and
openpyxl 3.1.5. Python performs authorized input reading and descriptive surgery
calculations; R performs pathology standardization, unified-cohort matching/RMST
and the L0 non-PH checks. No Node, proprietary artifact library, Codex runtime or
private skill is required by these public calculation entry points.

Set these environment variables before starting R, including before a parallel
worker is created:

| Variable | Meaning |
|---|---|
| `GBC_CODE_ROOT` | This public repository checkout |
| `GBC_FINAL_RUN_ROOT` | Private final-run input tree described below |
| `GBC_PREPARATION_ROOT` | Private upstream preparation/raw-export tree |
| `GBC_OUTPUT_ROOT` | An existing private output directory **outside this repository**; create it before running |
| `GBC_PYTHON` | Python executable; if unset, R uses `Sys.which("python")` |

Code-root discovery also supports execution from the checkout or a direct
script path. Explicit `GBC_CODE_ROOT` is recommended for worker reproducibility.
No SEER data or official life-table distribution is bundled or licensed by the
repository's code license.

## Required authorized inputs

`GBC_FINAL_RUN_ROOT` must contain:

```text
data/analysis_patient_level_v2.parquet
data/analysis_landmark_long_v2.parquet
outputs/STAGE1_RESULTS_v2.xlsx
outputs/LIFETABLE_RESULTS.xlsx
data_external/US_Annual_ExpectedSurvival_1970_2023.txt
data_external/US_Annual_ExpectedSurvival_1970_2023.dic
```

`GBC_PREPARATION_ROOT` must contain:

```text
data_clean/01_gallbladder_harmonized_all_2004_2023.parquet
data_raw/gallbladder_SEER_2004_2023_raw.csv
data_raw/gallbladder_SEER_2004_2023_raw.dic
```

These are study-specific authorized inputs, not general-purpose SEER filenames.
Preparation of correctly specified SEER fields, derived fields and matching
life-table exports is required. Missing files, schema differences or cohort
gate failures stop execution rather than trigger silent recoding or replacement.
The optional `outputs/STANDARDIZATION_RESULTS.xlsx` is read only as a historical
comparison; it is not used to fit the new age/sex-only models.

The L0-only entry additionally requires the original frozen workbook:

```text
GBC_FINAL_RUN_ROOT/phase3_minimal/phase3_results.xlsx
```

Its `Adjusted_Pathology` sheet has headers at row 5 and contains the original L0
and L5 reference, arm/event counts and PH estimates/intervals. It is a reconciliation
input, not a hardcoded substitute for model fitting. The public Phase 3 entry
exports aggregate CSV/JSON/RDS rather than reproducing that original workbook's
layout. Researchers without this frozen reconciliation input must prepare an
equivalent aggregate workbook from legally available calculations and document
that preparation; this repository does not claim an unrestricted end-to-end run
from raw SEER data with no further inputs.

## Explicit execution

From a configured checkout:

```text
Rscript --vanilla phase3_minimal/run_phase3.R --smoke
Rscript --vanilla phase3_minimal/run_phase3.R --formal
Rscript --vanilla phase3_l0_ph_check/run_L0_PH_check.R --point
Rscript --vanilla phase3_l0_ph_check/run_L0_PH_check.R --smoke
Rscript --vanilla phase3_l0_ph_check/run_L0_PH_check.R --formal
```

Phase 3 smoke uses 10 draws and suppresses formal intervals. Formal Phase 3
runs the original surgery module C at 1,000 draws, the 10-draw A technical test,
then 1,000-draw A and B. The Python `phase3_data.py` bridge is **not** a harmless
syntax or read-only check: it also runs surgery bootstrap. Do not invoke it just
to inspect dependencies. L0 smoke runs 50 draws; L0 formal runs those 50 technical
draws before 1,000 formal source-patient draws. No bootstrap was rerun merely to
perform this public-code migration.

The existing private output root must be outside the checkout **and both frozen input roots**.
Formal runs reject an existing destination before calculation; choose a fresh output root.
Formal output is written only under `GBC_OUTPUT_ROOT/phase3_minimal` or
`GBC_OUTPUT_ROOT/phase3_l0_ph_check`. Each module exports aggregate JSON and RDS;
Phase 3 exports `Adjusted_Pathology.csv`, `Unified_Cohort.csv`,
`Surgery_Code_Audit.csv`. L0 exports diagnostic, model-comparison, numerical/QC,
period-event and apparent-calibration CSVs. These outputs are for analysis review,
not automatic replacement of submission manuscripts or graphics.

Original workstation-only publication formatting, private spreadsheet/PDF QA
and proprietary Node exporters are intentionally not part of the public default
workflow. No third-party private skills were copied. Numeric calculation and
formal artifact typography are explicitly separated; public aggregate export is
not a claim of pixel-identical reproduction of the original XLSX/PDF files.

## Included custom dependency closure

```text
phase3_minimal/run_phase3.R
  phase3_data.py
    gbc_transfer_gate/phase2/phase2.py       read-only cohort gates/AJ checks
    surgery_audit.py
      python/scripts/stage1_burden.py       AST-only AJSpec/constants
  unified_cohort.R
    scripts/current_kernels/lifetable_core.R
  scripts/current_kernels/cause_specific.R
  scripts/current_kernels/public_config.R

phase3_l0_ph_check/run_L0_PH_check.R
  phase3_l0_ph_check/L0_model_core.R
  phase3_minimal/run_phase3.R               definitions only, no main
  scripts/current_kernels/cause_specific.R
  scripts/current_kernels/public_config.R
```

The old development file is not needed. Its five numerical helpers are extracted
without algorithm changes. Twelve original matching/RMST definitions are likewise
included without executing the old life-table main/setup/export. The read-only
Phase 2 helper retains the original cohort, identity, Distant/Unknown/T4 and risk-set
gates and original AJ point-estimate reconciliation; it cannot run a Phase 2
bootstrap or write a Phase 2 decision.

The twelve life-table definitions retain frozen provenance constants. The original
Phase 3 code did not call the old full-file `hashes()` setup, and the public entry
does not introduce or falsely claim a new hash-based certification. Original schema,
matching, key, count, probability and frozen numerical reconciliation checks remain.

## Algorithm and scope preservation

The migration changes code/data/output path resolution, explicit CLI invocation,
worker source lookup and aggregate delivery. It does not change risk sets,
diagnosis-based time zero, 36-month horizons, age proxies, cause coding, binary
pathology contrasts, common age/sex ranges, estimators, random seeds/streams,
bootstrap units, failure accounting or confidence-interval definitions.

Source patients are resampled before landmark expansion or time splitting. The
L0 models remain PH, PATH_TV (pathology by three periods in both cause models)
and AGE_TV (additional age and age-squared period effects in the GBC cause only).
The original patient-level coefficients/residual records are not exported by the
public aggregate delivery. L0/L5 comparisons use the frozen L5 estimates; the L0
entry never refits L1-L5.

During migration, static R/Python definition comparisons confirmed numerical
equivalence, allowing only declared path-assignment changes. Read-only cohort
gates reproduced source 7,007, dynamic 3,918, life-table 3,796, the original
landmark counts and all 30 main AJ point summaries within the original tolerance.
This is a code-transfer and lightweight reconciliation check, not a new full
bootstrap replication or a model-validity guarantee.

The estimand remains future mortality among diagnosis-origin survivors who were
ultimately registered as having resection. This does not establish surgery-date
postoperative survival, eliminate immortal-time selection, establish causal
pathology effects or identify code 60 with an R0 margin.
