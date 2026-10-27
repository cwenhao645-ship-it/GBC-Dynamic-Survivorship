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
| Table 1 demographic formatter | python/table1_demographics.py | Partial Table 1 formatter: age, sex, race/ethnicity, T, N and grade; the submission additionally has registered-surgery rows from the actual Phase 3 Surgery_Code_Audit results |
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

The supplied BMC Figure 1 PDF shows the updated source/dynamic/life-table populations and diagnosis-origin landmark design, not the old model-development/validation tracks. Its actual matching plotting source has not yet been located. The legacy Figure 1 source must not be represented as that final artwork. The full legacy plotting layer also reads old standardization/updating aggregates, so it is not a current default plotting entry point.

## Confirmed numbering and remaining limits

The supplied supplement confirms S1 cohort derivation; S2 population-referenced restricted survival; S3 conditional CIF by horizon; S4 crude pathology contrasts; S5 Summary Stage sensitivity; S6 age/sex-adjusted pathology risk differences; S7 shared-patient restricted-time decomposition; S8 descriptive registered-surgery groups; and S9 L0 PH-model-setting sensitivity. S6–S8 are no longer provisional. Exact titles, pages and code sources are in ../R/12_submission_outputs/README.md.

This confirms the displayed scientific structure, not independent reproduction of every number or final DOCX/PDF layout. Figure 1's matching source remains unresolved; the current Table 1 formatter does not yet include the registered-surgery rows. The full S1–S9 publication assembler and private Figure 3 formatting/QA backend are not supplied. Figure 2 still requires its frozen master CI schema. None of these limitations is repaired by relabelling an old exporter.

The supplied manuscript's Availability of data and materials paragraph still states that the revised Phase 3 code has not been integrated into the public repository. Once the remote update has been verified, the author must manually reconcile that sentence to the actual public version. The ZIP, manuscript and supplement are not modified by this code update.
