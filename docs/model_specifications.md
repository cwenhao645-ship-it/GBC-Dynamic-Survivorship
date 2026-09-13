# Frozen statistical specifications

## Populations and windows
Development diagnoses2004–2011; validation2012–2017. Baseline updating uses2012–2014; updating evaluation period2015–2017. Prediction landmarks are L1,L2,L3, with a3-year future horizon. Dynamic burden and standardization use L0–L5 in the fixed2004–2015 source; L4/L5 are exploratory. Time origin is diagnosis. Membership requires survival strictly beyond a landmark.

## Model A
Cause-specific Cox models fitted once among L1 survivors, delayed entry at year1 on time since diagnosis, using available follow-up without the B/C 3-year truncation. Predictions at later landmarks use frozen coefficients and appropriate conditional baseline increments.

## Model B
Stacked L1–L3 3-year windows, cause-specific Cox with landmark-stratified baseline hazards and common coefficients. The same patient may contribute multiple rows; uncertainty resamples source patients, not landmark rows independently.

## Model C
Model B plus prespecified interactions with centered landmark s−2. GBC interactions are T2,T3/4,N+,G2,G3/4; other-cause interaction is ((age−70)/10)×(s−2). The frozen final delivery retained the full specification:17 GBC and13 other-cause coefficients. A/B have12 coefficients per cause. Original stability/PH diagnostic code remains for provenance; it was not rerun during closeout.

## Coding and penalties
Age RCS knots48,65,76,87, Hmisc normalization2, including the linear term; centered at age70 and divided by10. Female,T1,N0,G1 are reference categories. T3/T4 and G3/G4 are combined. Unknown T/N/grade indicators remain explicit. Ridge theta=1, scale=FALSE applies only to Unknown indicators and C interaction terms; known main effects are unpenalized. Breslow ties; original convergence/singularity guards retained. No imputation or validation-driven tuning.

## Measured-covariate standardization
At each landmark and cause, model age RCS, sex,T,N,grade and diagnosis year (year−2009.5)/5. Contrasts: T3/4−T1,N+−N0,G3/4−G1. Common support requires ≥5 independent source identities in each target group within the sex/other-pathology cell, plus intersecting age ranges. Coverage≥90% PASS,70%–<90% LIMITED,<70% FAIL. Unknown indicators alone are penalized at theta1. Reference population is the supported subset at that landmark, not a fixed L0 standard.

## Validation and updating
Frozen risks are evaluated without refitting the prognostic coefficients. IPCW nuisance estimation, AUC2, Brier, calibration slope, ICI, AJ observed risk, O/E and O−E retain the original code definitions. Calibration risk transform clips probabilities to[1e−6,1−1e−6]; flexible calibration uses prespecified support guards and low-support fallback. Updating changes baseline hazards only; beta,coding,age knots,ridge and interactions remain fixed. Updating and evaluation bootstrap samples are independent; within-evaluation comparisons are paired.

## Randomness
Stage1: seed20260904,1000 patient draws. Development: seed20260905,500 formal draws. Validation/updating/standardization/life-table: seed20260905,1000 draws, original independent L'Ecuyer-CMRG streams2/3/4/5 respectively. Failed draws are not redrawn. No seeds, draw counts or decisions were changed in public copies.

## General-population comparison
Separate all-cause cohort, including unresolved cause of death, restricted to diagnosis age<90; n3796. Sex×attained age×calendar-year expected survival, 3-year observed versus expected RMST; expected minus observed defines deficit. Life tables remain fixed in patient bootstrap. Year+1 key shift is the prespecified sensitivity. This is not a competing-risk or causal treatment estimand.
