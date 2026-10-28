# Current analysis workflow: BMC Gastroenterology

This document describes the code scope of the 2026-10-27 submission update. It does not certify a complete independent rerun. The author subsequently supplied the October 27 BMC near-submission ZIP with integrated L0 non-PH results. Its main manuscript, 14-page Supplementary Information and three figures were read in memory without extraction or modification. Table 1/Figures 1–3 and S1–S9 scientific roles are confirmed; the existing frozen Phase 1/2/3/3B sources remain the analysis basis.

## Scientific scope

Authorized SEER export and dictionary → year-specific harmonization → explicit M0 and recorded resection → 7,007 competing-risk source patients → fixed 2004–2015 dynamic cohort of 3,918 → L0–L5 survivor risk sets → future 36-month AJ CIF and RMTL.

A separate all-cause life-table cohort contains 3,796 at L0 and retains eligible unresolved cause-of-death records. It is not the competing-risk cohort. Its observed and general-population expected RMST must always be calculated on the same matched patients.

Time is measured from diagnosis. Inclusion uses the eventual registry resection status, which is postdiagnosis information; these estimates are descriptive conditional outcomes in patients ultimately recorded as resected, not strictly postoperative survival or a causal surgery effect. No actual surgery date is reconstructed.

## Sources and execution boundaries

| Component | Code source | Boundary |
|---|---|---|
| Raw field harmonization | python/scripts/pipeline.py | Requires an independently authorized labels-format export, matching dictionary and verified private configuration |
| Final source cohort | python/scripts/stage1_burden.py: build_cohort | Explicit M0; Summary Stage Distant and Unknown are not excluded from the frozen main cohort |
| Landmark construction | python/scripts/prepare.py: make_landmarks; stage1_burden.long_data | Survival strictly exceeds landmark; original event, early censoring and 36-month truncation rules |
| Main burden and crude contrasts | stage1_burden.AJSpec, estimate, interval, result_tables | Original exact-time AJ implementation and source-patient bootstrap |
| Official life-table benchmark | R/09_lifetable/lifetable_rmst_gap.R | Separate matched all-cause cohort; original guarded export entry point is not run by inspection |
| Phase 2 stage-discordance sensitivity | gbc_transfer_gate/phase2/run_phase2.py + phase2_lifetable.R | Actual S5 calculation: exclude Summary Stage Distant only, retain Unknown; does not replace the main cohort. Separate phase2.py is a read-only gate helper |
| Phase 3 A/B/C | phase3_minimal/run_phase3.R and its local helpers | S6 age/sex pathology standardization, S7 actual cohort intersection, S8 descriptive surgery-code groups |
| Shared current mathematical kernels | scripts/current_kernels | Isolated original CSC/AJ/life-table definitions used by the current wrappers, not old model development |
| Phase 3B L0 sensitivity | phase3_l0_ph_check/run_L0_PH_check.R and its local helpers | S9 original PH, PATH_TV and exploratory AGE_TV; L0 only |
| Current pathology display | R/10_figures/current_figure3.R | Draws the 18-row Adjusted_Pathology aggregate; no new estimation in the plotting function |
| Frozen Figure 2 source | R/10_figures/figure2.R | Confirmed CIF/RMTL/RMST/horizon-difference scientific content; master CI input required; no pixel-certified re-export claimed |
| Complete Table 1 display | python/table1_demographics.py and python/export_table1.py | Original age/sex/race/pathology blocks plus actual frozen surgery partition; all 203 cells checked against the real private template, with optional new manuscript-copy export and no models/bootstrap |
| Reconstructed Figure 1 | R/10_figures/figure1.R | Display-only reconstruction from cohort QC, life matching QC and Phase 3 Unified_Cohort; original plotting source was not recovered |

R/01–04 document original Python implementations rather than claiming an invented R pipeline. The supplied Figure 1 PDF confirms cohort derivation and the diagnosis-origin source/dynamic/life-table design. Its original source was not recovered; the public reconstructed source now reads and cross-checks frozen aggregates without hardcoded fallbacks. The older legacy source with prediction-model tracks is not its approved replacement.

## Three different kinds of use

### A. Public inspection and syntax checks

Python AST parsing, R parse checks and relative dependency inspection do not require SEER data. Parsing is not sourcing: do not source plotting files or run an analysis entry point merely to inspect it. Successful syntax checks do not establish numerical reproducibility.

### B. Authorized analysis reproduction

The current Phase 3 and Phase 3B entry points support their documented smoke/formal modes. Inspect their argument handling and configure all private paths and installed runtimes before running. A smoke analysis is still a patient-data analysis; it is not part of the data-free syntax checks.

The original main preparation/AJ functions are a library rather than a complete public raw-to-submission launcher. Required historical audit inputs, frozen summaries and official life-table exports are described in reproducibility_notes.md. Do not silently replace missing inputs or relax cohort gates. Formal modes use their original 1,000 patient bootstrap attempts and are not executed as part of this repository update.

### C. Submission figure/table export

Plotting or formatting existing aggregates is separate from estimating those aggregates. Figure 1 now has a clearly labelled aggregate-driven reconstruction, with PDF, PNG and actual-viewport alignment JSON outputs; all three must be absent before export. Complete Table 1 combines authorized descriptive records, actual frozen surgery summaries and the real private manuscript ZIP; no models or bootstrap are invoked. Its export creates new files and refuses overwriting inputs/existing outputs. The engineering check included page-by-page native Word review of the 13-page assembled manuscript and one-page Table 1 without clipping. New exports still require author-specific native visual QA. Figure 3 can use the Phase 3 Adjusted_Pathology output; its public adapter does not reproduce private typesetting/QA or certify pixel identity. Figure 2 requires its frozen summary workbook schemas. The actual supplement confirms S6 adjusted pathology, S7 shared-cohort decomposition, S8 surgery groups and S9 L0 PH sensitivity; the full current S1–S9 document assembler is still not independently recovered. See R/12_submission_outputs/README.md.

The supplied October 28 manuscript template already cites analysis version a087042 and restricted-input requirements. The engineering follow-up preserves that original analysis citation and all other manuscript text; the source manuscript, ZIP and supplementary PDF are unchanged. The optional Table 1 assembly is a separate copy with the declared local table-border changes only.

## Historical analyses

Model A/B/C, temporal validation, baseline-hazard updating and the old higher-dimensional common-support standardization are retained under legacy/. They are not current BMC manuscript analyses, are not called by the current workflow, and must not be interpreted as current supplementary results.
