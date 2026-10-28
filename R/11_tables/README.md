# Current table sources and complete Table 1 export

The actual October 27, 2026 near-submission manuscript and its 14-page supplement confirm Table 1 and S1–S9. S6 is age/sex-adjusted pathology, S7 shared-patient time decomposition, S8 descriptive surgery groups and S9 L0 PH/PATH_TV/AGE_TV sensitivity. These are not the historical 11-eTable assembly. See [confirmed display map](../12_submission_outputs/README.md).

## Table 1 inputs

`python/table1_demographics.py:build_table1(landmarks, surgery_summary=None)` preserves the original 26 demographic/pathology rows and count gates. Supplying the actual surgery summary adds the registered-surgery section and its two groups, giving 29 rows × 7 columns, including headers. `python/export_table1.py` connects this complete table to the actual submission template without models, survival estimation or bootstrap.

Required authorized inputs are not included in this repository:

- Descriptive landmark Parquet: `patient_id`, `landmark_year`, `age_dx`, `sex`, `race_ethnicity`, `T_model`, `N_model`, `grade_model`. When `analysis_role` exists, only DESCRIPTIVE rows are read. Patient/landmark pairs must be unique, all patients must belong to L0, and L0–L5 denominators must be 3918/2496/1786/1423/1192/1047.
- Actual Phase 3 surgery summary: XLSX sheet `Surgery_Code_Audit` with headers at row 5, or its aggregate CSV; required fields `row_type`, `cohort`, `surgery_group`, `landmark`, `n`. Only the 12 `LANDMARK_ESTIMATE` / `Dynamic` rows enter Table 1. The two groups must be exactly `30/40` and `60`, once per landmark, and sum to that landmark's actual denominator. No Unknown surgery group is inferred or imputed. Percentages use those denominators with one decimal.
- Actual near-submission ZIP: exactly one unambiguous manuscript Table 1 whose first row has seven cells beginning with `Characteristic`, its immediately preceding Table 1 caption and immediately following `Notes:` paragraph. The template is read in memory; neither the archive nor its documents are overwritten or executed.

The exporter inspects the included `phase3_minimal/surgery_audit.py` constants/grouping by Python AST for provenance; it never runs the surgery analysis. Code 60 remains a registry extent category, not evidence of R0 margins or a causal treatment comparison.

## CLI and preservation

Run from the public checkout with an existing interpreter containing lxml and the declared data packages:

```sh
python python/export_table1.py --landmarks /private/final-run-inputs/data/analysis_landmark_long_v2.parquet --surgery-summary /private/final-run-inputs/phase3_minimal/phase3_results.xlsx --submission-zip /private/BMC-near-submission.zip --validate-only
python python/export_table1.py --landmarks /private/final-run-inputs/data/analysis_landmark_long_v2.parquet --surgery-summary /private/final-run-inputs/phase3_minimal/phase3_results.xlsx --submission-zip /private/BMC-near-submission.zip --output-dir /private/new-display-output --main-output /private/new-display-output/Main_Manuscript_Table1_assembled.docx
```

No arguments or `--help` prints usage only. `--validate-only` compares all 203 cells against the real template and creates no files. A read-only check against the supplied manuscript found all 203 cells identical under the declared typography normalization; no mismatching number is silently repaired. Original demographic/pathology rows must remain unchanged.

Export requires a pre-existing private `--output-dir` outside the checkout and configured `GBC_FINAL_RUN_ROOT`/`GBC_PREPARATION_ROOT`. Existing files and input/output collisions are rejected. Outputs are `Table1.csv`, `Table1.docx`, `Table1_VALIDATION.md` and, only with `--main-output`, a new assembly DOCX in the same output directory. The optional copy binds the validated Table 1; XML outside that table and every package part except `word/document.xml` are checked unchanged. It does not alter data-availability statements or other manuscript text.

The real template inherits TableGrid. To meet the requested three-line-table format, only local Table 1 borders are overridden: top/bottom and header-bottom rules, without body/vertical grid lines. The global style, caption, data cells, column geometry, indentation, fonts, header text and footnotes are retained. Standalone output keeps caption/table/notes and the original section geometry. In the engineering check, Word-native PDFs of the assembled manuscript (13 pages) and standalone Table 1 (one page) were reviewed page by page without clipping. These observations supplement the 203-cell/structural checks for those outputs; new exports still require author-specific native visual QA, and no independent full analysis reproduction or blanket final-package approval is claimed.

The actual October 28 template already cites the public analysis version a087042 and explains restricted input access. Table 1 engineering does not replace that original analysis citation or rewrite any other manuscript text. Optional assembly writes a new copy; the source template/ZIP stay unchanged.

Authoring uses lxml, not python-docx. If the authoring interpreter lacks data dependencies, append `--data-python /path/to/existing-data-python` for a read-only pandas/pyarrow/openpyxl aggregate bridge. It returns aggregate cells and provenance only, receives no DOCX-writing job and does not create an environment or run analysis. lxml remains required in the authoring interpreter.

## Supplement sources and remaining limits

S1–S5 retain the frozen cohort, life-table, CIF, crude pathology and exclusion-of-Distant sources. Phase 3 exports `Adjusted_Pathology.csv`, `Unified_Cohort.csv` and `Surgery_Code_Audit.csv` for confirmed S6–S8. S9 uses L0 `Model_Comparison.csv` with same-resample paired differences; diagnostics/QC remain supporting outputs.

The old assembler is preserved under `legacy/python/publication_tables.py`. It is not the current BMC workflow. Complete Table 1/template binding is now available, but the full S1–S9 Word/PDF assembler, private frozen inputs and exact submission typography are not thereby recovered. Formatting does not estimate risks or replace missing data.
