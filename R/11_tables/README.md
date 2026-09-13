# Publication tables

python/publication_tables.py exposes matrices(aggregates) and an output-only CLI. It consolidates existing frozen matrices into eTables 1–11, with two panels in eTables 5 and 8. The CLI copies the supplied final Table 1 matrix unchanged. No statistical estimator or patient-level module is imported.

The separate python/table1_demographics.py is retained as a source implementation for an explicitly planned analysis reproduction, not called by the default submission workflow. The complete upstream aggregate-master generator remains a documented limitation. See R/12_submission_outputs/README.md for mapping, input contract and commands.
