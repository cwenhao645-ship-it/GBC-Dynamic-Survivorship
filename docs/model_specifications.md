# Current statistical specifications

Version scope: BMC Gastroenterology submission update, 2026-10-27. Statistical definitions below describe existing frozen implementations, not new analysis choices. Historical prediction-model specifications remain with the legacy sources.

## Populations, time and events

The source competing-risk cohort is 7,007, with a fixed 2004–2015 dynamic cohort of 3,918. Its L0–L5 risk-set sizes are 3,918/2,496/1,786/1,423/1,192/1,047. The separate age-under-90 all-cause life-table cohort has 3,796/2,469/1,775/1,420/1,191/1,048. The difference is substantive, not a rounding error.

Time zero is diagnosis, not surgery. Recorded eventual resection selects the population; absent a surgery date, the analysis cannot establish that guarantee-time selection has been eliminated. It does not estimate the causal benefit of surgery or prognosis beginning at the operation.

Risk-set membership requires survival strictly beyond the landmark. The future window is 36 months = 1,095.75 days, using 365.25 days/year and 30.4375 days/month. Original zero-day survival values remain corrected to 0.5 days. Event codes are mutually exclusive: 0 censoring, 1 GBC death and 2 other-cause death. Unresolved cause of death is not recoded to other-cause death.

Explicit harmonized M0 defines the frozen main cohort. Summary Stage is a cross-system descriptor. Main source/dynamic/life-table Distant counts are 354/205/204. The Phase 2 sensitivity excludes these records but retains Unknown; it does not overwrite main estimates.

## AJ CIF, RMTL and expected-survival deficit

Cause-specific CIF is estimated with the Aalen–Johansen product integral, not 1−KM. RMTL is the integral of each cause-specific CIF over the future window. Original source-patient multiplicities are shared across landmarks and contrasts in each bootstrap repeat. Stage 1 uses NumPy default_rng seed 20260904 and 1,000 repeats.

The general-population comparison matches sex, attained age and calendar year to the authorized official SEER expected-survival export. Expected rate is annual conditional survivors per million; it is divided by 1,000,000 to obtain survival probability. Expected RMST integrates three piecewise-exponential annual segments and averages them over matched patients. Observed all-cause RMST integrates KM on exactly the same matched individuals. Deficit = expected minus observed RMST. This is not a recurrence measure or a causal treatment effect.

Original life-table uncertainty uses 1,000 patient bootstrap attempts, L'Ecuyer-CMRG seed 20260905, stream advance 5. Fixed life-table probabilities are not resampled. Unsupported positive survival tails and missing future-year keys are not extrapolated.

## Phase 3 A: age/sex-adjusted pathology risk differences

Prespecified contrasts are T3/4 vs T1, N+ vs N0 and G3/4 vs G1. Each landmark uses a new survivor reference population. The frozen implementation fits the two comparison arms, while other pathology categories can remain in the eligible standardization reference. It does not fit the old multivariable T/N/grade/diagnosis-year model.

Each cause-specific Cox model includes the target binary pathology variable, continuous attained-age proxy centered at 70 and divided by 10, its square, and sex. Attained age is recorded diagnosis age plus landmark; the original 90+ diagnosis category is topcoded at 90, not an exact reconstructed age.

Within each sex, the reference retains the intersection of observed age ranges of the comparison arms. This is not the old sex × other-pathology cell rule. Joint prediction from both cause-specific hazards reconstructs CIF. Standardized high-minus-low 36-month GBC CIF differences are reported in percentage points. They are conditional prognostic contrasts, not causal pathology effects.

Phase 3 A uses 1,000 source-patient draws, seed 20261027, L'Ecuyer-CMRG stream advance 1. The same draw is used across landmarks and contrasts. Failed repeats are recorded, not redrawn or trimmed; interval availability follows the frozen validity gates.

## Phase 3 B: unified cohort

The intersection is calculated from patient linkage, known cause of death and life-table applicability, rather than inferred by subtraction. Actual L0 n = 3,736. Both observed and expected RMST and the two CIF/RMTL estimates are recalculated on this same subset.

The unrounded check is RMST_observed + RMTL_GBC + RMTL_other = 36 months, subject only to numerical tolerance. Values are not forced to add to 36. This is a sensitivity analysis, not replacement of the original main cohorts. The original seed 20261027 and L'Ecuyer-CMRG stream advance 2 are retained.

## Phase 3 C: registry surgery codes

Before 2023 the source field is RX Summ--Surg Prim Site (1998-2022); in 2023 it is RX Summ--Surg Prim Site 2023 (2023+). Relevant representations are 30/40/60 and A300/A400/A600. Dictionary sources are retained in surgery_audit.py.

The dynamic comparison groups are 30/40 versus 60, with descriptive AJ CIF/RMTL and patient-bootstrap intervals subject to the original sample/event/follow-up feasibility gates. NumPy seed 20261030 is retained. Code 60 denotes a registry resection-extent category; it does not establish R0 margin status, standardized radical surgery or a causal treatment comparison.

## Phase 3B: L0 model-setting sensitivity

Original PH is compared with PATH_TV, allowing the target pathology coefficient to vary over (0,12], (12,24] and (24,36] months in both cause-specific models. Counting-process split rows retain one terminal event per patient copy. Prediction applies each period's coefficients and baseline hazard before the two hazards are jointly integrated.

AGE_TV is one separately reported exploratory model: pathology time variation remains in both causes; the linear and quadratic age terms additionally vary by period in the GBC model only. Sex is unchanged. This is not a search for the smallest PH p value.

The original age/sex reference and source-patient bootstrap are retained. A 50-repeat technical test precedes 1,000 formal repeats. Original PH and time-varying models share repeats, so model RD changes use paired bootstrap differences. A 3-percentage-point change is a manual review prompt, not an equivalence margin. L1–L5 are not refitted by this module.

A global Schoenfeld warning does not imply that every variable violates PH. Individual coefficient and joint-age diagnostics, including both cause models, must be interpreted with their multiplicity context. Similar marginal CIF estimates do not prove the models unbiased or fully validated.

## Legacy boundary

Model A/B/C, model performance validation, baseline-hazard updating, four-knot age RCS and the old high-dimensional support threshold system belong to legacy/. They are not the methods of the current age/sex-only analysis.
