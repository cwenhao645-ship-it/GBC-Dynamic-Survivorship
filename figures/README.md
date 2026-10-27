# Figures: current and historical sources

No figure binaries or source-data tables are distributed. The October 27, 2026 BMC near-submission package and its three single-page figure PDFs were inspected in memory, without extraction or modification. Scientific roles and displayed labels are confirmed; this is not a new rendering or pixel-level certification.

Figure 3, Crude and age–sex-adjusted pathologic risk differences, is the three-contrast crude AJ versus age/sex-adjusted 36-month pathology-risk-difference display. Its public drawing adapter is R/10_figures/current_figure3.R and its frozen aggregate input is the Adjusted_Pathology sheet of phase3_results.xlsx. The supplied figure shows T, N and grade panels with matching points/95% CIs. Plotting does not rerun models or bootstrap; private typography and QA backends are not bundled or promised as pixel-identical outputs.

Figure 2, Conditional mortality, time lost and population-referenced restricted survival, has scientific content matching R/10_figures/figure2.R: conditional CIF, cause-specific RMTL, observed/expected RMST connectors and other-cause-minus-GBC CIF across horizons. It reads existing summaries; the master workbook remains required for frozen confidence intervals. Scientific-content confirmation is not a complete pixel-certified re-export.

Figure 1, Cohort derivation and analysis timeline, is present in the supplied package. Its updated PDF shows source n=7,007, dynamic L0/L5 n=3,918/1,047 and life-table L0/L5 n=3,796/1,048, with diagnosis-origin L0–L5 and subsequent three-year windows. The matching current plotting source remains to be located. The historical legacy Figure 1 is not approved as a substitute for that updated artwork.

The historical final_figures.R set is not a current plotting launcher: it draws the old group-CIF/complex-support Figure 3 and reads old standardization/updating outputs. Do not present its old eFigures as current BMC displays.

Phase 3B's L0_PH_diagnostic.pdf is a targeted author-review sensitivity/diagnostic output, not an automatically added main figure. The current public calculation entry does not require the private diagnostic-PDF backend. Confirmed submission numbering and remaining limitations are in R/12_submission_outputs/README.md.
