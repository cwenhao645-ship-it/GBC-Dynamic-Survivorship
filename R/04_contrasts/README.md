# Pathology contrasts
The same original estimate()/result_tables() functions return high-minus-reference contrasts and within-draw changes from L0. They are not a newly written R estimator. The same source-patient draw is used across landmarks and contrasts.

These are the unadjusted AJ contrasts. Current age/sex-adjusted T/N/Grade contrasts are implemented in phase3_minimal/run_phase3.R, not the retired complex-support standardization. The targeted L0 PH sensitivity is in phase3_l0_ph_check/; none of these differences is interpreted as a causal pathology effect.

