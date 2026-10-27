# Current table sources and limits

The current requested display set is Table1 plus Supplementary Tables S1–S9, not the old11-eTable assembly.

- Table1: `python/table1_demographics.py:build_table1` retains the patient-level formatter and original six-landmark count gate. Its input is a legitimately prepared descriptive landmark dataset, not supplied here.
- S1–S5: frozen cohort derivation, life-table comparison, prediction-horizon CIF differences, crude pathology and exclusion-of-Distant sources. Exact input/source mapping is in `docs/original_script_mapping.md`.
- Phase3 exports `Adjusted_Pathology.csv`, `Unified_Cohort.csv`, `Surgery_Code_Audit.csv`. Assignment of these analyses to S6–S8 is provisional until the unavailable current manuscript is checked.
- S9: L0 non-PH `Model_Comparison.csv` with same-resample paired differences; diagnostics/QC are separate supporting exports.

The old `python/publication_tables.py` is preserved under `legacy/python/`. Its predecessor-to11-eTable mapping is not the BMC workflow. No current Word/Supplement assembler or exact S1–S9 typography is claimed when the latest manuscript/master is absent. Aggregate formatting does not estimate risks or replace missing data.
