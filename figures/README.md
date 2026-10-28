# Figures: current and historical sources

No figure binaries or source-data tables are distributed. The October 27, 2026 BMC near-submission package and its three single-page figure PDFs were inspected in memory, without extraction or modification. Scientific roles and displayed labels are confirmed; this is not a new rendering or pixel-level certification.

Figure 3, Crude and age–sex-adjusted pathologic risk differences, is the three-contrast crude AJ versus age/sex-adjusted 36-month pathology-risk-difference display. Its public drawing adapter is R/10_figures/current_figure3.R and its frozen aggregate input is the Adjusted_Pathology sheet of phase3_results.xlsx. The supplied figure shows T, N and grade panels with matching points/95% CIs. Plotting does not rerun models or bootstrap; private typography and QA backends are not bundled or promised as pixel-identical outputs.

Figure 2, Conditional mortality, time lost and population-referenced restricted survival, has scientific content matching R/10_figures/figure2.R: conditional CIF, cause-specific RMTL, observed/expected RMST connectors and other-cause-minus-GBC CIF across horizons. It reads existing summaries; the master workbook remains required for frozen confidence intervals. Scientific-content confirmation is not a complete pixel-certified re-export.

Figure 1, Cohort derivation and analysis timeline, is present in the supplied package. Its updated PDF shows source n=7,007, dynamic L0/L5 n=3,918/1,047 and life-table L0/L5 n=3,796/1,048, with diagnosis-origin L0–L5 and subsequent three-year windows. A comprehensive source search did not recover the original plotting file. The public `R/10_figures/figure1.R` is therefore explicitly **reconstructed**, not falsely labelled recovered original code or substituted with the historical legacy model-development display. It reads frozen aggregates, adds the explicitly labelled intersection sensitivity counts and does not change cohort membership, estimate survival or fit models.

## Figure 1 reconstruction inputs and CLI

Three existing private workbooks are required; none is bundled:

- `--cohort-qc`: `cohort_flow` sheet, first header `step`, fields `step`, `n_before`, `n_excluded`, `n_after`; the actual 12 sequential frozen rows must reconcile. Only the prespecified zero-exclusion auxiliary rows may be omitted from the eight-node display. Its `landmark_counts` sheet supplies `family`, `group`, `landmark_year`, `n_at_risk`, selecting Overall/All.
- `--life-summary`: `matching_qc`, first header `landmark`, fields `analysis_type`, `landmark`, `eligible_n`, `matched_n`, `match_rate`; select PRIMARY. All six landmarks must have complete matching.
- `--phase3-summary`: `Unified_Cohort`, first header `landmark`, fields `landmark`, `n`, `original_cr_n`, `original_life_n`. Cross-population original counts must agree with the two preceding sources; intersection counts cannot exceed either population.
- Optional `--master-check`: actual frozen `Cohorts` sheet with `step`, `n_before`, `n_excluded`, `n_after`, for an additional independent count check.

All three risk-set series must cover L0–L5 exactly once. Fixed original counts in source are stop-on-mismatch gates, never fallback plot data. Missing files, changed schema, nonzero auxiliary exclusions or inconsistent counts stop export.

```sh
Rscript --vanilla R/10_figures/figure1.R --cohort-qc /private/outputs/TABLES_INPUTS_REQUIRED/DATA_QC_AND_COHORT_v2.xlsx --life-summary /private/outputs/LIFETABLE_RESULTS.xlsx --phase3-summary /private/phase3_minimal/phase3_results.xlsx --validate-only
Rscript --vanilla R/10_figures/figure1.R --cohort-qc /private/outputs/TABLES_INPUTS_REQUIRED/DATA_QC_AND_COHORT_v2.xlsx --life-summary /private/outputs/LIFETABLE_RESULTS.xlsx --phase3-summary /private/phase3_minimal/phase3_results.xlsx --output-dir /private/new-display-output
```

No arguments or `--help` only prints usage. `--validate-only` reads aggregate counts and creates no figure. Export requires `GBC_CODE_ROOT`, a pre-existing private `GBC_OUTPUT_ROOT` and an existing `--output-dir` inside it, outside the checkout and configured input roots. All three target filenames must be absent before export. R/readxl/ggplot2/patchwork/ragg/jsonlite and Cairo are required. Outputs are a 170×180 mm vector `Figure1.pdf`, a 300-dpi `Figure1_preview.png` and `Figure1_alignment.json`, generated through R without private skill dependencies. The self-contained alignment gate measures the actual Cairo/grid panel viewports, requires finite positive nonoverlapping panel bounds and shared top/bottom edges within 1.5 pt, and records its measurements in JSON.

The inspected Figure 1 output passed actual physical Cairo bounding-box and transformed-glyph checks. Generic raw-Tf-only sizing and merged-span box checks produced false alarms and were checked against real glyph transforms/geometry rather than used to claim a text-size defect or bypass the physical test. This confirms the tested output's stated geometry checks, not recovery of the original source, pixel identity or independent replication of the analysis. New author-specific exports still require native visual inspection.

The historical final_figures.R set is not a current plotting launcher: it draws the old group-CIF/complex-support Figure 3 and reads old standardization/updating outputs. Do not present its old eFigures as current BMC displays.

Phase 3B's L0_PH_diagnostic.pdf is a targeted author-review sensitivity/diagnostic output, not an automatically added main figure. The current public calculation entry does not require the private diagnostic-PDF backend. Confirmed submission numbering and remaining limitations are in R/12_submission_outputs/README.md.
