# Frozen matching/RMST definitions only. No setup/export/autorun.
# S is supplied by phase3_minimal/unified_cohort.R.
gbc_lifetable <- local({
CFG <- list(seed = 20260905L, stream = 5L, B = 1000L, year_days = 365.25, month_days = 30.4375, tau_days = 1095.75, landmarks = 0:5, verification_date = "2026-09-09")

files <- c(txt = "data_external/US_Annual_ExpectedSurvival_1970_2023.txt", dic = "data_external/US_Annual_ExpectedSurvival_1970_2023.dic", precursor = "../gallbladder_dynamic_competing_risk/data_clean/01_gallbladder_harmonized_all_2004_2023.parquet", main = "data/analysis_patient_level_v2.parquet", sap = "spec/SAP_TECHNICAL_ADDENDUM_v1.1.md")

frozen <- c(txt = "e7236cabb05fd77810b047a7295339b46f885aed0eeb2e3f8244b2eb02ce02e5", dic = "a431d992dfa9b14cbf331a292db587a193bd6372d5e609c92e1fb6e5df377433", precursor = "9bb26be6114084b7a3c41ceea5d09bf444121c9442ba42eda1a4f399b7eec237", main = "b8bb4d6d7a5c00924aedd9383c3be4ba22c7b0c1060d72288be64207d88fd870", sap = "9a5e363afb395fe86d12ddc94817b4d727af74dae0dc27946acb6d00c79c328d")

database_name <- paste0("Expected Survival - U.S. 1970-2023 by individual year ", "(White, Black, Other (AI/API), Ages 0-99, All races for Other Unspec 1991+ and Unknown)")

reasons <- c("missing_age", "missing_sex", "missing_year_key", "missing_age_key", "duplicate_key", "invalid_probability", "other")

assert <- function(ok, message) {
    if (!isTRUE(ok))
        stop(message, call. = FALSE)
    invisible(TRUE)
}

key <- function(age, year, sex) paste(age, year, sex, sep = "|")

match_status <- function(rate) if (!is.finite(rate) || rate < 0.9) "MODULE NO-GO" else if (rate < 0.95) "EXPLORATORY" else "REPORTABLE"

read_life_table <- function() {
    dic <- readLines(file.path(S$root, files[["dic"]]), warn = FALSE, encoding = "UTF-8")
    assert(any(dic == paste0("Database name=", database_name)) && any(dic == "Field delimiter=tab") && any(dic == "Var5Name=Expected rate") && any(dic == "Var5DisplayType=Unformatted"), "STOP: official dictionary schema changed.")
    d <- utils::read.delim(file.path(S$root, files[["txt"]]), header = TRUE, sep = "\t", quote = "\"", check.names = FALSE, stringsAsFactors = FALSE, colClasses = c("integer", "integer", "character", "character", "numeric"))
    fields <- c("Age", "Year", "Race recode (White, Black, Other)", "Sex", "Expected rate")
    races <- c("White", "Black", "Other (American Indian/AK Native, Asian/Pacific Islander)", "Other unspecified (1991+)", "Unknown")
    assert(identical(dim(d), c(54000L, 5L)) && identical(names(d), fields) && !anyNA(d) && setequal(unique(d[[fields[3]]]), races), "STOP: official life-table shape/fields/categories/missing values failed.")
    assert(all(d[["Expected rate"]] > 0 & d[["Expected rate"]] <= 1e+06), "STOP: invalid expected annual survivors per million.")
    take <- function(race) {
        z <- d[d[[fields[3]]] == race, c("Age", "Year", "Sex", "Expected rate")]
        z <- z[order(z$Age, z$Year, z$Sex), ]
        rownames(z) <- NULL
        z
    }
    z <- take("Unknown")
    other <- take("Other unspecified (1991+)")
    assert(nrow(z) == 10800L && identical(z, other), "STOP: Unknown vs Other unspecified differs; cannot infer all-races table.")
    assert(identical(sort(unique(z$Age)), 0:99) && identical(sort(unique(z$Year)), 1970:2023) && setequal(unique(z$Sex), c("Male", "Female")), "STOP: all-races age/year/sex coverage failed.")
    z$p <- z[["Expected rate"]]/1e+06
    z$q <- 1 - z$p
    z$key <- key(z$Age, z$Year, z$Sex)
    assert(!anyDuplicated(z$key) && all(z$p > 0 & z$p <= 1) && all(z$q >= 0 & z$q < 1), "STOP: duplicate keys or invalid p/q.")
    S$metadata <- data.frame(source = "NCI SEER official SEER*Stat Case Listing export", database_name = database_name, official_url = "https://seer.cancer.gov/expsurvival/", official_update = "February 2026", semantics_url = "https://seer.cancer.gov/seerstat/faq.html", filename = basename(files[["txt"]]), dictionary_filename = basename(files[["dic"]]), sha256 = frozen[["txt"]], dictionary_sha256 = frozen[["dic"]], download_date = "Not supplied; user provided export; filesystem date is not a download date",
        verification_date = CFG$verification_date, run_date = as.character(Sys.Date()), rows = 54000L, rows_used = nrow(z), column_names = paste(fields, collapse = "; "), age_min = min(z$Age), age_max = max(z$Age), unique_ages = length(unique(z$Age)), year_min = min(z$Year), year_max = max(z$Year), unique_years = length(unique(z$Year)), sex_levels = "Female; Male", unique_sex = 2L, probability_field = "Expected rate", probability_definition = "Annual survivors conditional on alive at interval start; p=Expected rate/1000000; q=1-p",
        expected_rate_scale = "per 1,000,000 annual conditional survivors", key_definition = "Age x Year x Sex", key_unique = TRUE, unknown_vs_other_unspecified_identical = TRUE, analysis_race_mode = "ALL_RACES_COMBINED_FROM_UNKNOWN_ROWS", missing_values = sum(is.na(z)), invalid_p_values = sum(!is.finite(z$p) | z$p <= 0 | z$p > 1), precursor_sha256 = frozen[["precursor"]], sap_sha256 = frozen[["sap"]], seed = CFG$seed, rng_stream_advance = CFG$stream, bootstrap_attempts = S$B, mode = S$mode)
    say("Life table QC PASS: 54000 exported rows; 10800 unique all-races keys; Unknown equals Other unspecified.")
    z
}

match_patients <- function(d, s, shift, lt) {
    n <- nrow(d)
    prob <- matrix(NA_real_, n, 3)
    why <- rep("", n)
    capped <- rep(FALSE, n)
    duplicates <- unique(lt$key[duplicated(lt$key) | duplicated(lt$key, fromLast = TRUE)])
    for (j in 0:2) {
        age <- floor(d$age_dx + s + j)
        year <- d$year_dx + s + j + shift
        capped <- capped | (!is.na(age) & age > 99)
        age <- pmin(age, 99)
        k <- key(age, year, d$sex)
        idx <- match(k, lt$key)
        p <- lt$p[idx]
        why_j <- rep("", n)
        tag <- function(test, label) {
            test[is.na(test)] <- FALSE
            why_j[test & why_j == ""] <<- label
        }
        tag(!is.finite(age), "missing_age")
        tag(is.na(d$sex) | !(d$sex %in% c("Male", "Female")), "missing_sex")
        tag(!is.finite(year) | !(year %in% lt$Year), "missing_year_key")
        tag(is.finite(age) & !(age %in% lt$Age), "missing_age_key")
        tag(k %in% duplicates, "duplicate_key")
        tag(is.na(idx), "other")
        tag(!is.finite(p) | p <= 0 | p > 1, "invalid_probability")
        why[why == "" & why_j != ""] <- why_j[why == "" & why_j != ""]
        prob[, j + 1L] <- p
    }
    mask <- why == ""
    rate <- if (n)
        mean(mask)
    else NA_real_
    qc <- data.frame(landmark = s, analysis_type = if (shift == 0)
        "PRIMARY"
    else "YEAR_PLUS_1", eligible_n = n, matched_n = sum(mask), unmatched_n = sum(!mask), match_rate = rate, status = match_status(rate), age99_capped_n = sum(capped))
    for (r in reasons) qc[[r]] <- sum(why == r)
    assert(sum(qc[reasons]) == qc$unmatched_n, "Unmatched reasons do not reconcile.")
    list(mask = mask, p = prob, qc = qc, reason = why)
}

expected_rmst <- function(p) {
    assert(is.matrix(p) && ncol(p) == 3 && !anyNA(p) && all(p > 0 & p <= 1), "Invalid three-segment survival probabilities.")
    surv <- rep(1, nrow(p))
    area <- rep(0, nrow(p))
    for (j in 1:3) {
        lambda <- -log(p[, j])
        factor <- rep(1, nrow(p))
        pos <- lambda > 0
        factor[pos] <- -expm1(-lambda[pos])/lambda[pos]
        area <- area + surv * factor
        surv <- surv * p[, j]
    }
    result <- 12 * area
    assert(all(is.finite(result)) && all(result > 0 & result <= 36 + 1e-10), "Expected RMST outside its allowed range.")
    result
}

observed_rmst <- function(time, event) {
    assert(length(time) > 0 && length(time) == length(event) && all(is.finite(time)) && all(time > 0) && all(event %in% 0:1), "Invalid matched all-cause observations.")
    x <- data.frame(time = pmin(time, CFG$tau_days), death = as.integer(event == 1 & time <= CFG$tau_days))
    fit <- survival::survfit(survival::Surv(time, death) ~ 1, data = x, se.fit = FALSE, conf.int = FALSE)
    assert(max(time) >= CFG$tau_days || utils::tail(fit$surv, 1) == 0, "KM has no three-year tail support; no extrapolation.")
    at <- fit$time <= CFG$tau_days
    area <- sum(diff(c(0, fit$time[at], CFG$tau_days)) * c(1, fit$surv[at]))
    value <- area/CFG$month_days
    assert(is.finite(value) && value >= 0 && value <= 36 + 1e-10, "Observed RMST integration failed.")
    value
}
})
