# Figures

The final plotting code is in R/10_figures. The default GBC_FIGURE_SET=submission renders Figures 1–3 and eFigures 1–2 from existing frozen summary inputs; supplement renders only the two supplementary figures. Figure 2 also has a standalone entry point, figure2.R.

No patient-level files or estimators are used by these output entry points. Figure 3 reads the already frozen group-CIF display table. See R/12_submission_outputs/README.md for input schemas, dimensions and the final mapping. Missing data or incompatible packages stop the run; no automatic package installation or substitute data are used.
