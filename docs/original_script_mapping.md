# Original-to-public source mapping

Paths below are project-relative labels, not personal filesystem paths. Source comments and I/O roots were adapted in copies only. Original source files remain unchanged.

| Original source | Public source | Role |
|---|---|---|
| scripts/run_development.R | R/06_models/development.R | Preserved R implementation; configured paths |
| scripts/02_validation.R | R/07_validation/temporal_validation.R | Preserved R implementation; configured paths |
| scripts/03_recalibration.R | R/08_updating/baseline_updating.R | Preserved R implementation; configured paths |
| scripts/04_standardization.R | R/05_standardization/standardization.R | Preserved R implementation; configured paths |
| scripts/05_lifetable_rmst_gap.R | R/09_lifetable/lifetable_rmst_gap.R | Preserved R implementation; configured paths |
| Figure2.R | R/10_figures/figure2.R | Preserved R implementation; configured paths |
| JNO_SUBMISSION_PACKAGE_CN/_build/closeout_efigures.R | R/10_figures/final_figures.R | Final display mapping and font repairs; frozen summary readers only |
| JNO_SUBMISSION_PACKAGE_CN/_build/closeout_followup.R | R/01_cohort/followup_summary.R | Preserved R implementation; configured paths |
| preparation/pipeline.py | python/scripts/pipeline.py | read_config, sha256, write_json, verify_inputs, coding_period, expand_codes, parse_stage, parse_size, parse_nodes, construct_outcome, harmonize |
| preparation/prepare.py | python/scripts/prepare.py | add_maturity, make_landmarks, reverse_km_median |
| preparation/run_v2_stage1.py | python/scripts/stage1_burden.py | build_cohort, long_data, AJSpec, event_counts, estimate, interval, result_tables |
| preparation/final_submission_build.py | python/publication_tables.py | cell, term, pvalue, matrices |

The final plotting layer keeps only the current submission displays. Its subgroup-CIF input is the existing frozen aggregate, with no patient-level calculation in the output workflow. python/table1_demographics.py extracts the existing demographic table formatting. No older Main Table2/3 generator is represented as final. Preparation and descriptive burden were actually implemented in Python; R/01–04 route to them rather than inventing an R pipeline.
