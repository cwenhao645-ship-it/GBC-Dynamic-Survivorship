# Analysis-source workflow (not the default submission entry point)
Authorized SEER CSV + dictionary → verify schema and fingerprints → harmonize source fields → explicit M0 eligibility → 7007 competing-risk patients → fixed 2004–2015 flag → 3918 dynamic survivors → overlapping L0–L5 future windows → conditional AJ CIF/RMTL → paired pathology contrasts → landmark-specific measured-covariate standardization → prediction development → temporal validation → baseline-hazard updating → separate all-cause expected-survival benchmark → final figure/table formatting.

## Module entry points
| Stage | Public implementation | Execution boundary |
|---|---|---|
| Harmonization | python/scripts/pipeline.py: verify_inputs, harmonize | Independent authorized input required |
| Eligibility | python/scripts/stage1_burden.py: build_cohort | Explicit M0 only; original comparison audit retained |
| Landmarks | python/scripts/prepare.py: make_landmarks; stage1_burden.long_data | Survived strictly beyond landmark |
| Burden and contrasts | stage1_burden.estimate, result_tables | Formal 1000-draw patient bootstrap; not run at closeout |
| Standardization | R/05_standardization/standardization.R | Explicit gbc_standardization$run() |
| Development | R/06_models/development.R | Original main() command-line parser; final = 500 draws |
| Validation | R/07_validation/temporal_validation.R | Explicit gbc_validation$run() |
| Updating | R/08_updating/baseline_updating.R | Explicit gbc_recalibration$run() |
| Life-table gap | R/09_lifetable/lifetable_rmst_gap.R | Explicit gbc_lifetable$run("formal") |
| Follow-up | R/01_cohort/followup_summary.R | Descriptive reverse KM; separate from outcome analysis |
| Figures | R/10_figures | Frozen summary readers only; default exports Figures 1–3 and eFigures 1–2 |
| Tables | python/publication_tables.py: matrices(aggregates) and CLI | Frozen matrices only; Table 1 and eTables 1–11 |

R/01–04 are routing documentation because the original preparation and descriptive estimators were written in Python, not R. They are not presented as invented R implementations. No placeholder function silently replaces a missing estimator.


The default submission workflow is the pair of output-only commands in the main README; none of the analysis stages above are called automatically. The full source workflow is available for inspection and future authorized reproduction, subject to the documented execution limitations.
