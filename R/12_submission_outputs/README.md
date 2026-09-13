# Final submission outputs

The default workflow is output assembly from frozen summary inputs, not an analysis run. Run the figure command and table command in the main README. Both target a private output directory outside this repository.

## Output contract

- Main: Table 1 + Figures 1–3.
- Supplement: eTables 1–11 + eFigures 1–2.
- eFigure 1: standardized RMTL contrasts and common-support retention.
- eFigure 2: calibration/discrimination and observed-to-expected updating in the 2015–2017 updating evaluation period.
- Supplementary figures use Arial, a 10.2 pt floor for all visible text, and 12 pt panel labels. Export dimensions are 170 × 215 mm and 258 × 160 mm. Do not scale down below the 10 pt text floor.

## Frozen inputs

Set GBC_FINAL_RUN_ROOT to an authorized private frozen-results directory containing FINAL_RESULTS_MASTER.xlsx, outputs/STANDARDIZATION_RESULTS.xlsx and outputs/RECALIBRATION_RESULTS.xlsx. Figure 2 can also read the existing STAGE1_RESULTS_v2.xlsx and LIFETABLE_RESULTS.xlsx fallbacks when needed. The expected workbook sheet/header schemas remain enforced by the readers.

Figure 3 requires the pre-existing aggregate JNO_Figures/source_data/Figure3_Group_CIF.csv, or the GBC_FIGURE3_SOURCE override. Required columns: Predictor, Group, Landmark, n_at_landmark, 3y_GBC_CIF, contrast_check. It has 36 group-level rows: three pathology contrasts × two categories × six landmarks. No patient identifier column belongs in this input. Missing input fails rather than calculating subgroup CIF.

The table command accepts the existing frozen aggregate JSON schema: supp_tables is the 14-element predecessor input matrix list consumed by the preserved formatter, and table1 is the final 7-column display matrix. These are summary matrices, not patient records. This file is provided privately and is not bundled. The supplementary output comprises 11 CSV files; eTables 5 and 8 each contain panels A and B, with footnotes preserved.

## Input-to-submission mapping

Historical numbers below identify predecessor inputs only. They are not additional exports.

| Predecessor table | Final eTable |
|---|---|
| 1 | 1 |
| 2 + 3 | 2 (support is already carried by the contrast rows) |
| 4 | 3 |
| 5 | 4 |
| 6 | 5, panels A/B |
| 7 | 6 |
| 8 | 7 |
| 9 | Not exported |
| 10 + 11 | 8, panels A/B |
| 12 | 9 |
| 13 | 10 |
| 14 | 11 |

The previous fourth main display becomes supplementary display 2; previous main displays 1–3 retain their numbers. Only the first previous supplementary display is retained under its original number. No removed display is exported by the default workflow.

## Boundaries

No manuscript documents, submission forms, internal QA files or patient data are included. The workflow neither deletes historical files nor cleans a pre-existing output directory; use a dedicated private output location without obsolete display files. Source generation and full-analysis reproduction limitations remain documented in docs/reproducibility_notes.md.
