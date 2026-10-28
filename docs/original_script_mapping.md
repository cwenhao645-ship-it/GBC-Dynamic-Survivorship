# Source-to-public mapping

All original private project sources remain unchanged. This repository contains code copies and necessary path/I/O adaptations. No patient records, manuscript files or frozen result workbooks are included. After the initial inventory, the author supplied the 2026-10-27 BMC near-submission ZIP integrating the L0 non-PH analysis. Its Submission_Files/Main_Manuscript_BMC_Gastroenterology.docx, 14-page Additional_file_1_Supplementary_Information.pdf and three figure PDFs were read in memory, without extraction or modification. The current display numbering and scientific content below are now confirmed against that package; no pixel-level or complete manuscript-production certification is implied.

## Current mathematical sources

| Private source label | Public source | Role |
|---|---|---|
| preparation/scripts/pipeline.py | python/scripts/pipeline.py | Original year-specific harmonization and event construction |
| preparation/scripts/prepare.py | python/scripts/prepare.py | add_maturity, make_landmarks and reverse_km_median |
| preparation/scripts/run_v2_stage1.py | python/scripts/stage1_burden.py | build_cohort, long_data, AJSpec, estimate, interval and result_tables |
| scripts/05_lifetable_rmst_gap.R | R/09_lifetable/lifetable_rmst_gap.R | Original official-life-table matching and RMST benchmark |
| scripts/run_development.R, selected definitions only | scripts/current_kernels | assert, fit_failure, cox_checked, baseline_information and integrate_grid; shared mathematics, not model A/B/C execution |
| gbc_transfer_gate/phase2/phase2.py + phase2_lifetable.R | gbc_transfer_gate/phase2/run_phase2.py + phase2_lifetable.R | Actual finite stage-discordance sensitivity; public phase2.py separately retains read-only intake/reconciliation functions |
| phase3_minimal | phase3_minimal | Actual Phase 3 A/B/C entry point and required helpers |
| phase3_l0_ph_check | phase3_l0_ph_check | L0 PH/PATH_TV/AGE_TV analysis, diagnostics and output helpers |
| Phase 3 plotting helper | R/10_figures/current_figure3.R | Confirmed Figure 3 scientific content: crude and age/sex-adjusted pathology risk differences; public PDF adapter, not private typography/QA reproduction |
| Figure2.R | R/10_figures/figure2.R | Confirmed Figure 2 scientific content: conditional CIF, RMTL, observed/expected RMST and horizon-specific CIF differences; frozen master-workbook CI input remains required |
| Reconstructed Figure 1 | R/10_figures/figure1.R | New public display-only reconstruction from frozen QC/life/Phase 3 summaries; the original plotting source was not recovered |
| Table 1 demographic formatter, minimally extended | python/table1_demographics.py | Original demographic/pathology rows preserved; optional surgery_summary adds the actual Dynamic LANDMARK_ESTIMATE 30/40-versus-60 partition |
| Actual submission Table 1 template and complete formatter | python/export_table1.py | Validates all 203 cells against the real private ZIP template; exports complete CSV/DOCX, validation Markdown and optional separately assembled manuscript DOCX without models/bootstrap |
| Follow-up summary source | R/01_cohort/followup_summary.R | Separate descriptive reverse-KM implementation |

During source inspection, the public Stage 1 AJSpec/estimate/interval/result_tables/build_cohort/long_data definitions and the listed preparation/harmonization functions were AST-identical to their original private counterparts. This establishes source correspondence, not an end-to-end rerun.

## Historical sources retained, not current submission methods

| Historical source | Preserved location | Reason for separation |
|---|---|---|
| scripts/04_standardization.R | legacy/R/05_standardization/standardization.R | Older high-dimensional adjustment and common-support cells |
| scripts/run_development.R, full historical module | legacy/R/06_models/development.R | Model A/B/C development and historical numerical diagnostics |
| scripts/02_validation.R | legacy/R/07_validation/temporal_validation.R | Temporal prediction validation |
| scripts/03_recalibration.R | legacy/R/08_updating/baseline_updating.R | Baseline-hazard updating |
| Old JNO final figure layer | legacy/R/10_figures/final_figures.R | Old Figure 1 architecture, old Figure 3 and old supplementary displays |
| Old submission table assembler | legacy/python/publication_tables.py | Old 14-matrix predecessor to 11-eTable mapping |

The supplied BMC Figure 1 PDF shows the updated source/dynamic/life-table populations and diagnosis-origin landmark design, not the old model-development/validation tracks. A comprehensive source inventory did not recover its original plotting source. R/10_figures/figure1.R is therefore explicitly reconstructed from the confirmed design and frozen cohort summaries, including an independently identified intersection sensitivity population; it is not passed off as recovered original code. The legacy plotting layer also reads old standardization/updating aggregates and is not a current default plotting entry point.

## Confirmed numbering and remaining limits

The supplied supplement confirms S1 cohort derivation; S2 population-referenced restricted survival; S3 conditional CIF by horizon; S4 crude pathology contrasts; S5 Summary Stage sensitivity; S6 age/sex-adjusted pathology risk differences; S7 shared-patient restricted-time decomposition; S8 descriptive registered-surgery groups; and S9 L0 PH-model-setting sensitivity. S6–S8 are no longer provisional. Exact titles, pages and code sources are in ../R/12_submission_outputs/README.md.

This confirms the displayed scientific structure, not independent reproduction of every analysis. Figure 1 now has an operational, clearly labelled reconstruction; original-source recovery is not claimed. Its three outputs are Figure1.pdf, Figure1_preview.png and Figure1_alignment.json, all required to be absent before export. The JSON records the self-contained actual Cairo/grid viewport alignment gate. Complete Table 1 is connected through actual landmark data, frozen Surgery_Code_Audit and the actual manuscript ZIP template. Its original 26 demographic/pathology rows are preserved and three surgery-section rows are appended; all 29×7 cells must match the template. Only local Table 1 borders change to the requested three-line format; caption, values, fonts, indentation, notes and non-document DOCX parts are preserved. An optional manuscript copy changes only the validated Table 1 region. The engineering check included page-by-page review of a 13-page Word-native manuscript PDF and a one-page standalone Table 1 PDF without clipping; future DOCX outputs still require author-specific native visual QA.

The full S1–S9 publication assembler and private Figure 3 formatting/QA backend are not supplied. Figure 2 still requires its frozen master CI schema. Authorized private patient data, aggregate workbooks and the actual template are not bundled. Public reconstruction and output-layer integration do not turn those absent inputs into a raw-to-submission pipeline.

The supplied October 28 manuscript template already cites the public analysis version a087042 and explains restricted input requirements. The new display-engineering follow-up does not alter that original analysis citation or other manuscript text. The source ZIP, manuscript and supplement are not modified; optional Table 1 assembly creates a separate copy with only its declared local table-formatting changes.
