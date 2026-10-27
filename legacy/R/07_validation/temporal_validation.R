# Publication source copy. See docs/original_script_mapping.md and reproducibility_notes.md.

gbc_validation <- local({
  S <- new.env(parent = emptyenv())
  CFG <- list(seed = 20260905L, stream = 2L, tau = 3, knots = c(48, 65, 76, 87),
    models = c("A", "B", "C"), causes = c("GBC", "Other", "All-death"),
    files = c(patient = "data/analysis_patient_level_v2.parquet",
      landmark = "data/analysis_landmark_long_v2.parquet",
      sap = "spec/SAP_TECHNICAL_ADDENDUM_v1.1.md",
      models = "outputs/DEVELOPMENT_MODELS.rds",
      report = "outputs/DEVELOPMENT_REPORT.md", workbook = "outputs/DEVELOPMENT_RESULTS.xlsx"),
    versions = c(survival = "3.8.3", Hmisc = "5.2.3", riskRegression = "2023.12.21",
                 prodlim = "2025.4.28", jsonlite = "2.0.0", digest = "0.6.37"))
  CFG$hashes <- setNames(character(6), names(CFG$files))
  CFG$hashes[["patient"]] <- "b8bb4d6d7a5c00924aedd9383c3be4ba22c7b0c1060d72288be64207d88fd870"
  CFG$hashes[["landmark"]] <- "6d7ebcc62aa2da953ccdada3cce61ab366bcd0dfde0b24d7349bdafa5efe5da1"
  CFG$hashes[["sap"]] <- "9a5e363afb395fe86d12ddc94817b4d727af74dae0dc27946acb6d00c79c328d"
  CFG$hashes[["models"]] <- "7a331db957503af153aaf119a3d439b6f8e5edb56f769b1457a65ff9038af74f"
  CFG$hashes[["report"]] <- "0cdcc15e10ec777f69d961dbee4fedddc111f4bb3896cbbfeaa098ab9eb36852"
  CFG$hashes[["workbook"]] <- "9e5d7bb82ea62735d3015da605b4286f4bad6167de48e6b2fe3c0e79560244d4"
  script_candidates <- unlist(lapply(sys.frames(), function(f) f$ofile))
  script_candidates <- c(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)), script_candidates)
  S$script <- if(length(script_candidates)) tail(script_candidates, 1) else NA_character_
  assert <- function(ok, msg) { if(!isTRUE(ok)) stop(msg, call. = FALSE); invisible(TRUE) }
  say <- function(...) { cat(format(Sys.time(), "%H:%M:%S"), ..., "\n"); flush.console() }
  q7 <- function(x, probs) as.numeric(quantile(x, probs, type = 7, names = FALSE))
  mean_safe <- function(x) if(length(x) && all(is.finite(x))) mean(x) else NA_real_
  call_external <- function(exe, args) {
    z <- suppressWarnings(system2(exe, vapply(args, shQuote, character(1)), stdout = TRUE, stderr = TRUE))
    assert(is.null(attr(z, "status")), paste("External helper failed:", paste(z, collapse = "\n")))
    z
  }
  hash_inputs <- function() {
    z <- vapply(CFG$files, function(f) digest::digest(file = file.path(S$root, f), algo = "sha256"), character(1))
    assert(identical(unname(z), unname(CFG$hashes)), "STOP: frozen input hash mismatch; no repair/recleaning permitted.")
    z
  }
  setup <- function() {
    dirs <- c(if(!is.na(S$script)) dirname(dirname(normalizePath(S$script, winslash = "/", mustWork = TRUE))),
              getwd(), Sys.getenv("GBC_FINAL_RUN_ROOT", unset = getwd()))
    ok <- vapply(dirs, function(p) file.exists(file.path(p, CFG$files[["models"]])) &&
                   file.exists(file.path(p, "R/07_validation/temporal_validation.R")), logical(1))
    assert(any(ok), "Cannot locate gbc_final_run; open its R/07_validation/temporal_validation.R and Source.")
    S$root <- normalizePath(dirs[which(ok)[1]], winslash = "/", mustWork = TRUE)
    S$script <- file.path(S$root, "R/07_validation/temporal_validation.R")
    S$mode <- getOption("gbc.validation.mode", "final")
    assert(S$mode %in% c("final", "smoke"), "Mode must be final or smoke; prior qualification tests are not rerun.")
    S$B <- if(S$mode == "final") 1000L else 3L
    assert(as.character(getRversion()) == "4.4.3", "Use the locked R 4.4.3 in RStudio; no automatic upgrades.")
    for(p in names(CFG$versions)) {
      assert(requireNamespace(p, quietly = TRUE), paste("Required package missing:", p))
      assert(utils::compareVersion(as.character(utils::packageVersion(p)), CFG$versions[[p]]) == 0,
             paste("Locked package version mismatch:", p))
    }
    suppressPackageStartupMessages(library(survival))
    S$hashes <- hash_inputs()
    S$frozen <- readRDS(file.path(S$root, CFG$files[["models"]]))
    f <- S$frozen
    assert(identical(f$mode, "final") && isTRUE(f$formal_run) && f$bootstrap_attempts == 500L,
           "Final 500-draw development delivery required.")
    assert(identical(f$selected_C, "C_FULL") && all(f$C_decision$criterion_pass) &&
           all(f$stability$valid == 500L), "Frozen C FULL retention / stability mismatch.")
    assert(all(is.na(f$PH_selection)) && length(f$PH_sensitivity) == 0L,
           "Unexpected PH-sensitive delivery: do not silently substitute a model.")
    assert(identical(as.numeric(f$knots), CFG$knots), "Frozen age knots mismatch.")
    S$models <- f$models[c("A", "B", "C_FULL")]; names(S$models) <- CFG$models
    for(m in names(S$models)) for(k in 1:2) {
      fm <- S$models[[m]][[k]]
      assert(is.null(fm$tv) && fm$delta == 0 && fm$theta == 1 && all(is.finite(fm$beta)),
             "Unexpected frozen coefficient / interaction / penalty specification.")
      assert(length(fm$beta) == if(m == "C") c(17, 13)[k] else 12L, "Frozen coefficient count mismatch.")
      for(b in fm$baseline) assert(all(is.finite(as.matrix(b))) && all(b$hazard >= 0) &&
        !anyDuplicated(b$time) && !is.unsorted(b$time), "Invalid frozen baseline.")
    }
    S$model_digest <- digest::digest(S$models, algo = "sha256")
    runtime <- Sys.getenv("GBC_RUNTIME_ROOT")
    S$python <- Sys.getenv("GBC_PYTHON")
    S$audit_python <- file.path(runtime, "python/python.exe")
    S$node <- file.path(runtime, "node/bin/node.exe"); S$modules <- file.path(runtime, "node/node_modules")
    for(p in c(S$python, S$audit_python, S$node, S$modules)) assert(file.exists(p), paste("Missing dependency:", p))
    S$python_version <- call_external(S$python, c("-c", "import pyarrow,pandas; print(pyarrow.__version__,pandas.__version__)"))
    S$audit_version <- call_external(S$audit_python, c("-c", "import openpyxl; print(openpyxl.__version__)"))
    S$fingerprint <- digest::digest(list(code = digest::digest(file = S$script, algo = "sha256"),
      hashes = S$hashes, mode = S$mode, B = S$B, seed = CFG$seed, stream = CFG$stream,
      R = R.version.string, versions = CFG$versions, python = S$python_version, workbook_reader = S$audit_version), algo = "sha256")
    S$temp <- file.path(Sys.getenv("TEMP"), "gbc_validation", S$mode, S$fingerprint)
    dir.create(S$temp, recursive = TRUE, showWarnings = FALSE)
    S$outputs <- file.path(S$root, "outputs"); dir.create(S$outputs, showWarnings = FALSE)
    S$filenames <- c("VALIDATION_RESULTS.xlsx", "VALIDATION_REPORT.md")
    if(S$mode == "final") assert(!any(file.exists(file.path(S$outputs, S$filenames))),
      "A formal validation output already exists. STOP; archive it manually before an explicitly intended rerun.")
    say("Mode:", S$mode, "; frozen hashes PASS; aggregate-only staging:", S$temp)
  }

  read_validation <- function() {
    helper <- file.path(S$temp, "read_validation.py")
    writeLines(r"---(import json,sys,hashlib
from pathlib import Path
import pyarrow.parquet as pq
root=Path(sys.argv[1]); mode=sys.argv[2]
flt=[('year_dx','>=',2012),('year_dx','<=',2017)]
source=root/'data/analysis_patient_level_v2.parquet'
ids=pq.read_table(source,columns=['patient_id','year_dx'],filters=flt).to_pandas()
assert ids.patient_id.is_unique
source_n=len(ids)
if mode!='final':
    chosen=sorted(ids.patient_id.tolist(),key=lambda x:hashlib.sha256(('20260905|smoke|'+str(x)).encode()).hexdigest())[:90]
    flt=flt+[('patient_id','in',chosen)]
cols=['patient_id','record_id','year_dx','age_dx','age_90plus_flag','sex','T_model','N_model','grade_model','survival_days_analysis','event_competing','M_harmonized']
p=pq.read_table(source,columns=cols,filters=flt).to_pandas().sort_values('patient_id',kind='stable')
lc=['patient_id','record_id','year_dx','landmark_year','time_from_landmark','time_to_analysis_end','event_within_window','analysis_role']
l=pq.read_table(root/'data/analysis_landmark_long_v2.parquet',columns=lc,filters=flt+[('analysis_role','==','PREDICTION_PREP')]).to_pandas()
print(json.dumps({'patient':json.loads(p.to_json(orient='records')),'landmark':json.loads(l.to_json(orient='records')),'full_source_n':source_n},separators=(',',':')))
)---", helper, useBytes = TRUE)
    payload <- call_external(S$python, c(helper, S$root, S$mode))
    obj <- jsonlite::fromJSON(paste(payload, collapse = "")); d <- obj$patient; l <- obj$landmark
    assert(nrow(d) > 0 && !anyNA(d) && !anyDuplicated(d$patient_id) && !anyDuplicated(d$record_id), "Invalid source IDs/missing values.")
    assert(all(d$year_dx %in% 2012:2017) && all(d$M_harmonized == "M0"), "Validation year/M0 firewall failed.")
    d$time <- d$survival_days_analysis / 365.25; d$status <- as.integer(d$event_competing)
    d$T_core <- ifelse(d$T_model %in% c("Unknown", "Unknown/nonstandard"), "Unknown", d$T_model)
    assert(all(is.finite(d$time)) && all(d$time > 0) && all(d$status %in% 0:2), "Invalid frozen survival fields.")
    for(v in list(c("sex", "Female", "Male"), c("T_core", "T1", "T2", "T3/4", "Unknown"),
      c("N_model", "N0", "N+", "Unknown"), c("grade_model", "G1", "G2", "G3/4", "Unknown")))
      assert(all(d[[v[1]]] %in% v[-1]), paste("Unrecognized frozen level:", v[1]))
    assert(all(d$age_dx[d$age_90plus_flag] == 90), "Top-code handling mismatch.")
    d$source_index <- seq_len(nrow(d)); d$cluster <- d$source_index
    d$era <- ifelse(d$year_dx <= 2013, "2012-2013", ifelse(d$year_dx <= 2015, "2014-2015", "2016-2017"))
    d$age_group <- as.character(cut(d$age_dx, c(-Inf, 65, 80, Inf), right = FALSE,
                                  labels = c("<65", "65-79", ">=80")))
    rebuilt <- do.call(rbind, lapply(1:3, function(s) {
      z <- d[d$time > s, , drop = FALSE]; z$lm <- s; z$u <- z$time - s
      z$event <- ifelse(z$u <= 3, z$status, 0L); z
    }))
    key <- function(id, s) paste(id, s, sep = "|")
    assert(!anyDuplicated(key(l$record_id, l$landmark_year)) && nrow(rebuilt) == nrow(l), "Stored landmark count/key mismatch.")
    j <- match(key(rebuilt$record_id, rebuilt$lm), key(l$record_id, l$landmark_year))
    assert(!anyNA(j) && all(l$analysis_role == "PREDICTION_PREP") &&
      max(abs(l$time_from_landmark[j] / 365.25 - rebuilt$u)) < 1e-8 &&
      max(abs(l$time_to_analysis_end[j] / 365.25 - pmin(rebuilt$u, 3))) < 1e-8 &&
      all(l$event_within_window[j] == rebuilt$event), "Stored/rebuilt windows differ: STOP, no recleaning.")
    if(S$mode == "final") assert(nrow(rebuilt) == 3612 && nrow(d) == obj$full_source_n,
                                "Frozen validation denominator mismatch.")
    if(S$mode != "final") assert(nrow(d) <= 90, "SMOKE patient cap exceeded.")
    S$full_source_n <- obj$full_source_n
    say("Read/audit PASS:", nrow(d), "source patients;", nrow(rebuilt), "landmark rows.")
    d
  }

  design <- function(d, s, m, k) {
    a <- Hmisc::rcspline.eval(d$age_dx, knots = CFG$knots, inclx = TRUE, norm = 2)
    ref <- Hmisc::rcspline.eval(70, knots = CFG$knots, inclx = TRUE, norm = 2)
    a <- sweep(a, 2, as.numeric(ref), "-") / 10
    colnames(a) <- c("Age_linear", "Age_rcs1", "Age_rcs2")
    x <- cbind(a, Male = as.numeric(d$sex == "Male"), T2 = as.numeric(d$T_core == "T2"),
      T34 = as.numeric(d$T_core == "T3/4"), Nplus = as.numeric(d$N_model == "N+"),
      G2 = as.numeric(d$grade_model == "G2"), G34 = as.numeric(d$grade_model == "G3/4"),
      T_unknown = as.numeric(d$T_core == "Unknown"), N_unknown = as.numeric(d$N_model == "Unknown"),
      G_unknown = as.numeric(d$grade_model == "Unknown"))
    if(m == "C") {
      if(k == 1) {
        ii <- x[, c("T2", "T34", "Nplus", "G2", "G34"), drop = FALSE] * (s - 2)
        colnames(ii) <- paste0(colnames(ii), "_by_s")
      } else ii <- matrix((d$age_dx - 70) / 10 * (s - 2), ncol = 1,
                          dimnames = list(NULL, "Age10_by_s"))
      x <- cbind(x, ii)
    }
    x
  }
  integrate_jumps <- function(times, a1, a2, from, to) {
    n <- nrow(a1); F1 <- F2 <- numeric(n); surv <- rep(1, n)
    for(j in which(times > from & times <= to)) {
      a <- a1[, j] + a2[, j]; jump <- surv * (-expm1(-a))
      share <- numeric(n); positive <- a > 0; share[positive] <- a1[positive, j] / a[positive]
      old1 <- F1; old2 <- F2; oldS <- surv
      F1 <- F1 + jump * share; F2 <- F2 + jump * (1 - share); surv <- surv * exp(-a)
      assert(all(F1 >= old1 - 1e-12 & F2 >= old2 - 1e-12 & surv <= oldS + 1e-12), "Non-monotone frozen integration.")
    }
    p <- cbind(GBC = F1, Other = F2, Survival = surv)
    assert(all(is.finite(p)) && min(p) >= -1e-12 && max(abs(rowSums(p) - 1)) < 1e-10,
           "Probability coherence QC failed; never clip individual causes.")
    p
  }
  predict_frozen <- function(pair, d, s, m) {
    assert(all(d$time > s), "Prediction requires strict landmark survival.")
    origin <- if(m == "A") s else 0; end <- origin + 3
    stratum <- as.character(if(m == "A") 1 else s)
    base <- lapply(pair, function(f) f$baseline[[stratum]])
    supported <- all(vapply(pair, function(f) f$support[[stratum]] >= end, logical(1)))
    n <- nrow(d)
    if(!supported) return(list(p = matrix(NA_real_, n, 3), observed_hazard = matrix(NA_real_, n, 2),
      horizon_hazard = matrix(NA_real_, n, 2), unsupported = rep(TRUE, n), denominator = rep(NA_real_, n)))
    times <- sort(unique(c(base[[1]]$time, base[[2]]$time))); times <- times[times <= end]
    hazards <- lapply(1:2, function(k) {
      x <- design(d, s, m, k); beta <- pair[[k]]$beta
      assert(identical(colnames(x), names(beta)), "Design/coefficient names or order mismatch.")
      h <- base[[k]]$hazard[match(times, base[[k]]$time)]; h[is.na(h)] <- 0
      outer(exp(drop(x %*% beta)), h)
    })
    assert(all(is.finite(hazards[[1]])) && all(is.finite(hazards[[2]])), "Nonfinite frozen hazards.")
    p <- integrate_jumps(times, hazards[[1]], hazards[[2]], origin, end)
    den <- rep(1, n); unsupported <- rep(FALSE, n)
    if(m == "A") {
      before <- integrate_jumps(times, hazards[[1]], hazards[[2]], 1, s)
      after <- integrate_jumps(times, hazards[[1]], hazards[[2]], 1, s + 3)
      den <- before[, 3]; unsupported <- den <= 1e-6
      ii <- which(!unsupported)
      if(length(ii)) assert(max(abs((after[ii, 1:2, drop = FALSE] - before[ii, 1:2, drop = FALSE]) /
        den[ii] - p[ii, 1:2, drop = FALSE])) < 1e-10, "A conditional CIF identity failed.")
    }
    mask <- outer(origin + pmin(d$time - s, 3), times, ">=") &
            rep(times > origin & times <= end, each = n)
    eh <- cbind(rowSums(hazards[[1]] * mask), rowSums(hazards[[2]] * mask))
    hh <- do.call(cbind, lapply(hazards, function(a) rowSums(a[, times > origin, drop = FALSE])))
    p[unsupported, ] <- NA_real_; eh[unsupported, ] <- NA_real_; hh[unsupported, ] <- NA_real_
    list(p = p, observed_hazard = eh, horizon_hazard = hh, unsupported = unsupported, denominator = den)
  }
  cache_predictions <- function(d) {
    out <- list()
    for(s in 1:3) {
      ii <- which(d$time > s); out[[as.character(s)]] <- list()
      for(m in CFG$models) {
        pr <- predict_frozen(S$models[[m]], d[ii, , drop = FALSE], s, m)
        expand <- function(x) {z <- matrix(NA_real_, nrow(d), ncol(x)); z[ii, ] <- x; z}
        out[[as.character(s)]][[m]] <- list(p = expand(pr$p), observed_hazard = expand(pr$observed_hazard),
          horizon_hazard = expand(pr$horizon_hazard), unsupported = sum(pr$unsupported),
          closure = if(any(!pr$unsupported)) max(abs(rowSums(pr$p[!pr$unsupported, , drop = FALSE]) - 1)) else NA_real_,
          minimum = if(any(!pr$unsupported)) min(pr$p[!pr$unsupported, , drop = FALSE]) else NA_real_,
          min_denominator = min(pr$denominator))
      }
    }
    out
  }

  km_left <- function(time, censor, at) {
    jumps <- sort(unique(time[censor == 1]))
    if(!length(jumps)) return(rep(1, length(at)))
    nr <- vapply(jumps, function(t) sum(time >= t), numeric(1))
    dc <- vapply(jumps, function(t) sum(time == t & censor == 1), numeric(1))
    G <- cumprod(1 - dc / nr)
    j <- findInterval(at, jumps); exact <- match(at, jumps, nomatch = 0L)
    j[exact > 0] <- exact[exact > 0] - 1L
    c(1, G)[j + 1L]
  }
  weights_ipcw <- function(d, s, method = "marginal") {
    n <- nrow(d); t <- d$time - s; e <- d$status; known <- (t <= 3 & e > 0) | t >= 3
    early <- t < 3 & e == 0; at <- pmin(t, 3)
    empty <- list(w = rep(NA_real_, n), reliable = FALSE, truncate = FALSE,
      stats = c(G3_left = NA, early_censor = sum(early), known = sum(known), weight_p95 = NA,
                weight_p99 = NA, weight_max = NA, ESS = NA), note = "No censoring support")
    if(!n) return(empty)
    g <- km_left(t, as.integer(e == 0), at); g3 <- km_left(t, as.integer(e == 0), 3)
    note <- "Marginal reverse KM, strict left limits"
    if(method == "covariate") {
      if(sum(early) >= 30L) {
        frame <- data.frame(time = t, censor = as.integer(e == 0), age10 = d$age_dx / 10,
                            Male = as.integer(d$sex == "Male"), year = d$year_dx)
        cf <- tryCatch(withCallingHandlers(survival::coxph(survival::Surv(time, censor) ~ age10 + Male + year,
          data = frame, ties = "breslow", x = TRUE, y = TRUE, model = TRUE),
          warning = function(w) stop(conditionMessage(w))), error = function(e) NULL)
        if(is.null(cf) || any(!is.finite(stats::coef(cf)))) return(empty)
        bh <- survival::basehaz(cf, centered = TRUE)
        lp <- as.numeric(stats::predict(cf, type = "lp", reference = "sample"))
        Hleft <- function(at) {
          j <- findInterval(at, bh$time); ex <- match(at, bh$time, nomatch = 0L)
          j[ex > 0] <- ex[ex > 0] - 1L; c(0, bh$hazard)[j + 1L]
        }
        g <- exp(-Hleft(at) * exp(lp)); g3 <- exp(-Hleft(rep(3, n)) * exp(lp))
        note <- "Prespecified censor Cox age10 + Male + year; >=30 early censor events"
      } else {
        for(a in unique(d$age_group)) {
          ii <- which(d$age_group == a)
          if(max(t[ii]) < 3) return(empty)
          g[ii] <- km_left(t[ii], as.integer(e[ii] == 0), at[ii])
        }
        g3 <- vapply(unique(d$age_group), function(a) {
          ii <- which(d$age_group == a); km_left(t[ii], as.integer(e[ii] == 0), 3)
        }, numeric(1))
        note <- "<30 early censor events: covariate Cox unstable; age-stratified KM sensitivity"
      }
    }
    w <- numeric(n)
    if(any(!is.finite(g)) || any(g <= 0) || any(!is.finite(g3)) || any(g3 <= 0)) return(empty)
    w[known] <- 1 / g[known]; wk <- w[known]
    if(!length(wk)) return(empty)
    st <- c(G3_left = min(g3), early_censor = sum(early), known = sum(known),
      weight_p95 = q7(wk, .95), weight_p99 = q7(wk, .99), weight_max = max(wk), ESS = sum(wk)^2 / sum(wk^2))
    reliable <- min(g3) >= .1 && max(wk) <= 20 && st[["ESS"]] >= .5 * sum(known)
    list(w = w, stats = st, reliable = reliable, truncate = q7(wk, .99) > 10 || max(wk) > 20, note = note)
  }
  aj <- function(time, event) {
    if(!length(time)) return(c(GBC = NA_real_, Other = NA_real_, Survival = NA_real_))
    F <- c(0, 0); surv <- 1
    for(t in sort(unique(time[event > 0 & time <= 3]))) {
      nr <- sum(time >= t); dd <- c(sum(time == t & event == 1), sum(time == t & event == 2))
      F <- F + surv * dd / nr; surv <- surv * (1 - sum(dd) / nr)
    }
    if(max(time) < 3 && surv > 1e-12) return(c(GBC = NA_real_, Other = NA_real_, Survival = NA_real_))
    c(GBC = F[1], Other = F[2], Survival = surv)
  }
  auc2 <- function(p, y, w) {
    if(!length(p) || any(!is.finite(p)) || any(!is.finite(w))) return(NA_real_)
    ii <- order(p); p <- p[ii]; y <- y[ii]; w <- w[ii]
    g <- cumsum(c(TRUE, diff(p) != 0)); controls <- rowsum(w * (y == 0), g, reorder = FALSE)[, 1]
    cases <- rowsum(w * (y == 1), g, reorder = FALSE)[, 1]; den <- sum(cases) * sum(controls)
    if(den <= 0) return(NA_real_)
    sum(cases * (cumsum(controls) - controls + .5 * controls)) / den
  }
  glm_checked <- function(x, y, w, offset = NULL) {
    if(any(!is.finite(w)) || any(!is.finite(x)) || sum(w * y) <= 0 || sum(w * (1 - y)) <= 0) return(NULL)
    bad <- FALSE
    fit <- tryCatch(withCallingHandlers(stats::glm.fit(x = x, y = y, weights = w, offset = offset,
      family = quasibinomial(), control = glm.control(epsilon = 1e-9, maxit = 100)),
      warning = function(z) {bad <<- TRUE; invokeRestart("muffleWarning")}), error = function(e) NULL)
    if(is.null(fit) || bad || !fit$converged || fit$rank < ncol(x) || any(!is.finite(fit$coefficients))) return(NULL)
    if(any(fit$fitted.values[w > 0] <= 1e-12 | fit$fitted.values[w > 0] >= 1 - 1e-12)) return(NULL)
    fit
  }
  calibrate <- function(p, y, w, grid = numeric(), full = TRUE) {
    empty <- list(values = c(slope = NA_real_, intercept = NA_real_, offset_intercept = NA_real_, ICI = NA_real_),
                  curve = rep(NA_real_, length(grid)), knots = rep(NA_real_, 3), method = "UNESTIMABLE")
    if(!length(p) || any(!is.finite(p)) || any(!is.finite(w))) return(empty)
    z <- qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6)); x <- cbind(1, z)
    lin <- glm_checked(x, y, w); off <- glm_checked(matrix(1, length(p), 1), y, w, offset = z)
    v <- empty$values
    if(!is.null(lin)) v[1:2] <- unname(lin$coefficients[c(2, 1)])
    if(!is.null(off)) v[3] <- unname(off$coefficients[1])
    knots <- q7(z, c(.1, .5, .9))
    if(!full) return(list(values = v, curve = empty$curve, knots = knots, method = "Linear slope only"))
    use_spline <- length(unique(knots)) == 3L && sum(y == 1 & w > 0) >= 30L && sum(y == 0 & w > 0) >= 30L
    basis <- function(a) cbind(1, Hmisc::rcspline.eval(a, knots = knots, inclx = TRUE, norm = 2))
    smfit <- if(use_spline) glm_checked(basis(z), y, w) else lin
    method <- if(use_spline) "IPCW RCS: 2 df + intercept" else "Low-support linear calibration"
    curve <- empty$curve
    if(!is.null(smfit)) {
      smoother <- function(a) as.numeric(plogis((if(use_spline) basis(a) else cbind(1, a)) %*% smfit$coefficients))
      v[4] <- mean(abs(smoother(z) - p)) # All patients, INCLUDING early censored prediction positions.
      if(length(grid)) {
        curve <- smoother(qlogis(pmin(pmax(grid, 1e-6), 1 - 1e-6)))
        curve[grid < min(p) | grid > max(p)] <- NA_real_ # No bootstrap extrapolation beyond observed support.
      }
    }
    list(values = v, curve = curve, knots = knots, method = if(is.null(smfit)) "UNESTIMABLE" else method)
  }

  fixed_cuts <- function(x, probs) if(length(x) && all(is.finite(x))) unique(q7(x, probs)) else numeric()
  risk_bin <- function(x, cuts) findInterval(x, cuts) + 1L # Equal predictions always stay together.
  build_spec <- function(d, cache) {
    out <- list()
    for(s in 1:3) {
      ii <- which(d$time > s); out[[as.character(s)]] <- list()
      iw <- weights_ipcw(d[ii, , drop = FALSE], s)
      out[[as.character(s)]]$cap10 <- iw$truncate
      for(m in CFG$models) {
        pr <- cache[[as.character(s)]][[m]]; p <- pr$p[ii, , drop = FALSE]
        specs <- lapply(1:3, function(k) {
          v <- if(k == 3) rowSums(p[, 1:2, drop = FALSE]) else p[, k]
          finite <- all(is.finite(v))
          list(grid = if(finite) unique(q7(v, seq(0, 1, length.out = 61))) else numeric(),
            central = if(finite) q7(v, c(.01, .99)) else c(NA, NA),
            quintiles = fixed_cuts(v, c(.2, .4, .6, .8)),
            tertiles = fixed_cuts(v, c(1/3, 2/3)),
            hazard_quintiles = if(k <= 2) fixed_cuts(pr$horizon_hazard[ii, k], c(.2, .4, .6, .8)) else numeric())
        })
        out[[as.character(s)]][[m]] <- specs
      }
    }
    out
  }

  evaluate <- function(d, cache, spec, detailed = TRUE) {
    rows <- list(); counter <- 0L
    put <- function(sheet, scope, s, m, cause, type, metric, value, n, events,
                    group = "", x = NA_real_, other = NA_integer_, status = "OK", note = "") {
      counter <<- counter + 1L
      rows[[counter]] <<- data.frame(sheet = sheet, scope = scope, landmark = s, model = m,
        cause = cause, record_type = type, metric = metric, group = as.character(group), predicted = x,
        estimate = as.numeric(value), n = as.integer(n), events = as.integer(events), other_events = as.integer(other),
        status = status, note = note, stringsAsFactors = FALSE)
    }
    scope_names <- c("2012-2017", "2012-2013", "2014-2015", "2016-2017")
    for(scope in scope_names) for(s in 1:3) {
      dd <- d[d$time > s & (scope == "2012-2017" | d$era == scope), , drop = FALSE]
      n <- nrow(dd); u <- dd$time - s; e <- dd$status; primary <- scope == "2012-2017"
      iw <- weights_ipcw(dd, s); observed <- aj(u, e)
      ne <- c(sum(u <= 3 & e == 1), sum(u <= 3 & e == 2), sum(u <= 3 & e > 0))
      if(primary) {
        for(v in names(iw$stats)) put("performance", scope, s, "Shared", "All", "IPCW_QC", v,
          iw$stats[[v]], n, ne[3], status = if(iw$reliable) "OK" else "UNRELIABLE", note = iw$note)
        if(detailed) for(v in c("sex", "age_group", "era", "T_core", "N_model", "grade_model"))
          for(lev in sort(unique(dd[[v]]))) {
            jj <- dd[[v]] == lev
            put("performance", scope, s, "Shared", "All", "Censor_distribution", "early_censor_n",
              sum(jj & u < 3 & e == 0), sum(jj), sum(jj & u <= 3 & e > 0), group = paste(v, lev, sep = ":"))
          }
      }
      cw <- if(primary) weights_ipcw(dd, s, "covariate") else NULL
      for(m in CFG$models) {
        pr <- cache[[as.character(s)]][[m]]; pp <- pr$p[dd$source_index, , drop = FALSE]
        valid_p <- n > 0 && all(is.finite(pp))
        mstatus <- if(!valid_p) "PREDICTION_UNSUPPORTED" else if(!iw$reliable) "IPCW_UNRELIABLE" else "OK"
        if(primary) {
          put("performance", scope, s, m, "Three-state", "Probability_QC", "unsupported_n",
              if(n) sum(!is.finite(rowSums(pp))) else 0, n, ne[3])
          put("performance", scope, s, m, "Three-state", "Probability_QC", "closure_max_error",
              if(valid_p) max(abs(rowSums(pp) - 1)) else NA, n, ne[3], note = "Numerical coherence ONLY; not calibration")
          put("performance", scope, s, m, "Three-state", "Probability_QC", "minimum_probability",
              if(valid_p) min(pp) else NA, n, ne[3])
        }
        for(k in 1:3) {
          cause <- CFG$causes[k]; p <- if(k == 3) rowSums(pp[, 1:2, drop = FALSE]) else pp[, k]
          y <- as.integer(u <= 3 & if(k == 3) e > 0 else e == k)
          O <- if(k == 3) sum(observed[1:2]) else unname(observed[k]); E <- mean_safe(p)
          ps <- spec[[as.character(s)]][[m]][[k]]
          cal <- calibrate(p, y, iw$w, grid = if(primary) ps$grid else numeric(), full = primary)
          brier <- if(n && valid_p && all(is.finite(iw$w))) sum(iw$w * (y - p)^2) / n else NA_real_
          vals <- c(AUC2 = auc2(p, y, iw$w), Brier = brier, AJ_observed = O, mean_predicted = E,
            O_over_E = if(is.finite(E) && E > 0) O / E else NA_real_, O_minus_E_pp = 100 * (O - E),
            cal$values, abs_O_minus_E_pp = 100 * abs(O - E))
          keep <- if(primary) names(vals) else c("O_over_E", "O_minus_E_pp", "Brier", "slope", "abs_O_minus_E_pp")
          for(v in keep) put(if(!primary) "model_aging" else if(v %in% c("AUC2", "Brier")) "performance" else "calibration",
            scope, s, m, cause, "Primary", v, vals[[v]], n, ne[k], other = if(k < 3) ne[3 - k] else 0,
            status = mstatus, note = if(v %in% c("ICI", "slope", "intercept", "offset_intercept")) cal$method else "")
          if(!primary) next
          for(method in c("covariate", if(spec[[as.character(s)]]$cap10) "cap10")) {
            wi <- if(method == "covariate") cw else {z <- iw; z$w <- pmin(z$w, 10); z}
            cs <- calibrate(p, y, wi$w, full = TRUE)
            sv <- c(AUC2 = auc2(p, y, wi$w), Brier = if(n && valid_p && all(is.finite(wi$w))) sum(wi$w * (y - p)^2) / n else NA,
                    cs$values)
            for(v in names(sv)) put(if(v %in% c("AUC2", "Brier")) "performance" else "calibration",
              scope, s, m, cause, paste0("IPCW_", method), v, sv[[v]], n, ne[k],
              status = if(wi$reliable && valid_p) "OK" else "UNRELIABLE", note = wi$note)
          }
          for(j in seq_along(ps$grid)) put("calibration", scope, s, m, cause, "Curve", "smooth_observed",
            cal$curve[j], n, ne[k], group = as.character(j), x = ps$grid[j], status = mstatus,
            note = if(detailed) paste(cal$method, "; knots(logit)=", paste(signif(cal$knots, 8), collapse = "/"),
              if(ps$grid[j] < ps$central[1] || ps$grid[j] > ps$central[2]) "; SPARSE TAIL" else "; Central 1-99%") else "")
          if(detailed && valid_p) {
            breaks <- seq(0, 1, length.out = 21); histn <- hist(p, breaks = breaks, plot = FALSE)$counts
            for(j in seq_along(histn)) put("calibration", scope, s, m, cause, "Risk_distribution", "n",
              histn[j], n, ne[k], group = j, x = mean(breaks[j:(j + 1)]))
          }
          bin <- if(valid_p) risk_bin(p, ps$quintiles) else rep(NA_integer_, n)
          for(g in seq_len(length(ps$quintiles) + 1L)) {
            jj <- which(bin == g); gn <- length(jj); gdeaths <- sum(u[jj] <= 3 & e[jj] > 0)
            go <- aj(u[jj], e[jj]); gO <- if(k == 3) sum(go[1:2]) else go[k]; gE <- mean_safe(p[jj])
            supported <- gdeaths >= 10L && all(is.finite(go))
            for(v in c("AJ_observed", "mean_predicted")) put("calibration", scope, s, m, cause, "Grouped_AJ", v,
              if(v == "mean_predicted") gE else if(supported) gO else NA, gn, sum(y[jj]), group = g,
              x = gE, status = if(supported) "OK" else "SUPPORT_INSUFFICIENT", note = "Fixed prediction quintiles; >=10 any deaths for AJ")
          }
          if(k <= 2) {
            eh <- pr$observed_hazard[dd$source_index, k]; hh <- pr$horizon_hazard[dd$source_index, k]
            hb <- if(valid_p) risk_bin(hh, ps$hazard_quintiles) else rep(NA_integer_, n)
            for(g in 0:(length(ps$hazard_quintiles) + 1L)) {
              jj <- if(g == 0) seq_len(n) else which(hb == g); Ocount <- sum(y[jj]); Ecount <- sum(eh[jj])
              unsupported <- !length(jj) || any(!is.finite(eh[jj])) || any(eh[jj] == 0 & y[jj] > 0)
              for(v in c("hazard_process_O_over_E", "zero_E_zero_O_n", "zero_E_positive_O_n", "expected_hazard_sum")) {
                val <- switch(v, hazard_process_O_over_E = if(!unsupported && Ecount > 0) Ocount / Ecount else NA,
                  zero_E_zero_O_n = sum(eh[jj] == 0 & y[jj] == 0),
                  zero_E_positive_O_n = sum(eh[jj] == 0 & y[jj] > 0), expected_hazard_sum = Ecount)
                put("joint_calibration", scope, s, m, cause, "Hazard_process", v, val, length(jj), Ocount,
                  group = if(g == 0) "Overall" else paste0("Q", g),
                  status = if(unsupported || Ecount <= 0) "UNSUPPORTED" else "OK",
                  note = "Observed cause counts / risk-process cumulative hazard; NOT CIF O/E; no epsilon")
              }
            }
          }
        }
        if(primary) {
          b1 <- if(valid_p) risk_bin(pp[, 1], spec[[as.character(s)]][[m]][[1]]$tertiles) else rep(NA_integer_, n)
          b2 <- if(valid_p) risk_bin(pp[, 2], spec[[as.character(s)]][[m]][[2]]$tertiles) else rep(NA_integer_, n)
          for(g in 0:9) {
            i <- if(g == 0) seq_len(n) else which(b1 == ((g - 1) %/% 3 + 1) & b2 == ((g - 1) %% 3 + 1))
            dn <- c(sum(u[i] <= 3 & e[i] == 1), sum(u[i] <= 3 & e[i] == 2)); gn <- length(i)
            obs <- aj(u[i], e[i]); expct <- if(gn && all(is.finite(pp[i, , drop = FALSE]))) colMeans(pp[i, , drop = FALSE]) else rep(NA_real_, 3)
            supported <- all(is.finite(obs)) && (g == 0 || (gn >= 50 && all(dn >= 10)))
            obs4 <- c(obs, sum(obs[1:2])); exp4 <- c(expct, sum(expct[1:2]))
            for(k in 1:4) for(v in c("AJ_observed", "mean_predicted", "O_minus_E_pp"))
              put("joint_calibration", scope, s, m, c("GBC", "Other", "Survival", "All-death")[k],
                if(g == 0) "Joint_overall" else "Joint_cell", v,
                if(v == "mean_predicted") exp4[k] else if(!supported) NA else if(v == "AJ_observed") obs4[k] else 100 * (obs4[k] - exp4[k]),
                gn, if(k <= 2) dn[k] else sum(dn), group = if(g == 0) "Overall" else paste0("T", (g - 1) %/% 3 + 1, "xT", (g - 1) %% 3 + 1),
                other = if(k <= 2) dn[3 - k] else 0, status = if(supported) "OK" else "SUPPORT_INSUFFICIENT",
                note = "Cell AJ needs n>=50 and >=10 deaths of EACH cause; no merging; finite grouping is not full joint calibration")
          }
        }
      }
    }
    tab <- do.call(rbind, rows)
    pairbase <- tab[tab$record_type == "Primary" & tab$scope == "2012-2017" &
      tab$metric %in% c("AUC2", "Brier", "O_minus_E_pp", "abs_O_minus_E_pp", "ICI", "slope"), , drop = FALSE]
    pairs <- list(c("B", "A"), c("C", "A"), c("C", "B"))
    more <- lapply(pairs, function(ab) {
      a <- pairbase[pairbase$model == ab[1], ]; b <- pairbase[pairbase$model == ab[2], ]
      key <- function(z) paste(z$landmark, z$cause, z$metric)
      j <- match(key(a), key(b)); assert(!anyNA(j), "Paired metric keys mismatch.")
      a$estimate <- a$estimate - b$estimate[j]; a$model <- paste(ab, collapse = "-"); a$sheet <- "paired_differences"
      a$record_type <- "Paired_difference"; a$status <- ifelse(a$status == "OK" & b$status[j] == "OK", "OK", "UNRELIABLE")
      a$note <- ifelse(a$metric == "AUC2", "Positive favors first model", "Brier/ICI/absolute calibration error: negative favors first; slope/signed O-E are not rankings")
      a
    })
    aging <- tab[tab$sheet == "model_aging", , drop = FALSE]
    late <- aging[aging$scope == "2016-2017", ]; early <- aging[aging$scope == "2012-2013", ]
    jj <- match(paste(late$landmark, late$model, late$cause, late$metric),
                paste(early$landmark, early$model, early$cause, early$metric))
    late$estimate <- late$estimate - early$estimate[jj]; late$scope <- "2016-2017_minus_2012-2013"
    late$record_type <- "Era_difference"; late$n <- late$n + early$n[jj]; late$events <- late$events + early$events[jj]
    late$status <- ifelse(late$status == "OK" & early$status[jj] == "OK", "OK", "UNRELIABLE")
    late$note <- "Descriptive last-minus-first era contrast; same source-patient bootstrap; not coefficient aging or tuning"
    tab <- rbind(tab, do.call(rbind, more), late); tab$key <- row_key(tab)
    assert(!anyDuplicated(tab$key), "Duplicate output metric key.")
    tab
  }
  row_key <- function(z) paste(z$sheet, z$scope, z$landmark, z$model, z$cause, z$record_type, z$metric, z$group, sep = "|")

  synthetic_tests <- function() {
    tests <- list()
    check <- function(name, err, tol = 1e-10) {
      assert(is.finite(err) && err <= tol, paste("SYNTHETIC FAIL:", name, "error", err))
      tests[[length(tests) + 1L]] <<- data.frame(test = name, maximum_error = err, tolerance = tol, status = "PASS")
    }
    age <- c(30, 48, 60, 65, 70, 76, 87, 90, 95); kn <- CFG$knots
    basis <- function(v) cbind(v, do.call(cbind, lapply(kn[1:2], function(k)
      (pmax(v - k, 0)^3 - pmax(v - kn[3], 0)^3 * (kn[4] - k) / (kn[4] - kn[3]) +
       pmax(v - kn[4], 0)^3 * (kn[3] - k) / (kn[4] - kn[3])) / (kn[4] - kn[1])^2)))
    check("Age spline matches independent explicit basis",
          max(abs(Hmisc::rcspline.eval(age, knots = kn, inclx = TRUE, norm = 2) - basis(age))))
    t <- c(.5, 1, 1, 2, 3, 3); e <- c(1L, 1L, 0L, 2L, 1L, 0L)
    g <- km_left(t, as.integer(e == 0), pmin(t, 3))
    check("Left limits: tied deaths/censoring and exact horizon", max(abs(g - c(1, 1, 1, .8, .8, .8))))
    d <- data.frame(time = t + 1, status = e, age_group = "65-79")
    w <- weights_ipcw(d, 1)$w
    check("Early censor weight zero; competing/tau events known", max(abs(w - c(1, 1, 0, 1.25, 1.25, 1.25))))
    sf <- survival::survfit(survival::Surv(t, e == 0) ~ 1)
    pg <- vapply(pmin(t, 3), function(a) {ii <- which(sf$time < a); if(length(ii)) tail(sf$surv[ii], 1) else 1}, numeric(1))
    check("Reverse KM independently matches survival", max(abs(pg - g)))
    p <- c(.8, .6, .4, .3, .2, .2); y <- as.integer(e == 1 & t <= 3)
    brute <- sum(outer(w * y, w * (1 - y)) * (outer(p, p, ">") + .5 * outer(p, p, "=="))) /
             (sum(w * y) * sum(w * (1 - y)))
    check("Weighted AUC2 matches all case/control pairs including ties", abs(auc2(p, y, w) - brute))
    check("AUC is .5 for tied predictions", abs(auc2(rep(.4, 6), y, w) - .5))
    check("Brier retains all six patients in denominator", abs(sum(w * (y - p)^2) / nrow(d) - mean(w * (y - p)^2)))
    check("AJ includes competing death", max(abs(aj(t, e) - c(5/9, 2/9, 2/9))))
    check("No support after last censor returns NA", as.numeric(!all(is.na(aj(c(.2, .5), c(1L, 0L))))))
    check("All fail before tau remains identifiable", max(abs(aj(c(.2, .5), c(1L, 2L)) - c(.5, .5, 0))))
    grid <- c(.5, 1, 2, 3); a1 <- matrix(c(.2, .1, .3, .1), 1); a2 <- matrix(c(.1, .2, .2, .1), 1)
    z <- integrate_jumps(grid, a1, a2, 0, 3)
    check("Exponential simultaneous-cause probability closure", abs(sum(z) - 1))
    check("Single-cause exponential survival limit", abs(integrate_jumps(grid, a1, a2 * 0, 0, 3)[1, 1] - (1 - exp(-sum(a1)))))
    before <- integrate_jumps(grid, a1, a2, 0, 1); after <- integrate_jumps(grid, a1, a2, 0, 3)
    check("Conditional CIF identity", max(abs((after[1, 1:2] - before[1, 1:2]) / before[1, 3] -
                                                 integrate_jumps(grid, a1, a2, 1, 3)[1, 1:2])))
    check("Equal predictions never split bins", as.numeric(length(unique(risk_bin(rep(.2, 8), c(.2, .3)))) != 1L))
    score_data <- data.frame(u = seq(.1, 6, length.out = 60), status = rep(c(1L, 2L, 0L), 20))
    risk <- seq(.8, .1, length.out = 60); Hist <- prodlim::Hist
    wd <- data.frame(time = score_data$u + 1, status = score_data$status)
    ww <- weights_ipcw(wd, 1)$w
    for(k in 1:2) {
      score <- riskRegression::Score(list(frozen = risk), Hist(u, status) ~ 1, data = score_data,
        times = 3, cause = k, metrics = c("AUC", "Brier"), null.model = FALSE,
        split.method = "none", conf.int = FALSE, cens.model = "km", se.fit = FALSE)
      yy <- as.integer(score_data$u <= 3 & score_data$status == k)
      check(paste("Score independent AUC2 cause", k), abs(score$AUC$score$AUC[1] - auc2(risk, yy, ww)), 1e-8)
      check(paste("Score independent Brier cause", k), abs(score$Brier$score$Brier[1] - sum(ww * (yy - risk)^2) / 60), 1e-8)
    }
    pp <- rep(seq(.1, .9, .1), each = 100)
    yy <- unlist(lapply(seq(.1, .9, .1), function(v) c(rep(1, round(v * 100)), rep(0, 100 - round(v * 100)))))
    ca <- calibrate(pp, yy, rep(1, length(pp)), grid = c(.1, .5, .9))
    check("Perfect calibration slope=1", abs(ca$values[["slope"]] - 1), 1e-7)
    check("Perfect calibration intercept=0", abs(ca$values[["intercept"]]), 1e-7)
    check("Perfect smooth calibration ICI=0", abs(ca$values[["ICI"]]), 1e-7)
    ca2 <- calibrate(c(pp, .99), c(yy, 0), c(rep(1, length(pp)), 0), grid = c(.01, .5, .99))
    check("ICI evaluates early-censored prediction position", as.numeric(!is.finite(ca2$values[["ICI"]])))
    separated <- calibrate(rep(c(.2, .8), each = 20), rep(c(0, 1), each = 20), rep(1, 40))
    check("Separation does not silently produce a finite slope", as.numeric(is.finite(separated$values[["slope"]])))
    linear <- calibrate(rep(c(.2, .6), each = 40), rep(c(0, 1, 0, 0), 20), rep(1, 80))
    check("Repeated knots choose locked linear fallback", as.numeric(linear$method != "Low-support linear calibration"))
    toy <- data.frame(time = c(7, 5, 2), source_index = 1:3)
    dr <- toy[c(1, 1, 2, 3), ]; dr$cluster <- seq_len(nrow(dr))
    check("Patient copies have distinct cluster IDs", abs(length(unique(dr$cluster)) - 4))
    check("Both copies persist at L3", abs(sum(dr$time > 3 & dr$source_index == 1) - 2))
    set.seed(CFG$seed)
    nn <- 180L
    censor_fixture <- data.frame(age_dx = sample(45:88, nn, TRUE),
      sex = sample(c("Female", "Male"), nn, TRUE), year_dx = sample(2012:2017, nn, TRUE),
      status = rep(c(0L, 0L, 1L, 2L), length.out = nn), time = 1 + seq(.05, 5, length.out = nn))
    censor_fixture$age_group <- as.character(cut(censor_fixture$age_dx, c(-Inf, 65, 80, Inf), right = FALSE))
    cw <- weights_ipcw(censor_fixture, 1, "covariate")
    cfdata <- data.frame(time = censor_fixture$time - 1, censor = as.integer(censor_fixture$status == 0),
      age10 = censor_fixture$age_dx / 10, Male = as.integer(censor_fixture$sex == "Male"), year = censor_fixture$year_dx)
    cf <- survival::coxph(survival::Surv(time, censor) ~ age10 + Male + year, data = cfdata, ties = "breslow")
    cfs <- survival::survfit(cf, newdata = cfdata, stype = 2, ctype = 1)
    cg <- vapply(seq_len(nn), function(i) {
      jj <- which(cfs$time < min(cfdata$time[i], 3)); if(length(jj)) cfs$surv[max(jj), i] else 1
    }, numeric(1))
    cknown <- (cfdata$time <= 3 & censor_fixture$status > 0) | cfdata$time >= 3
    check("Censor nuisance Cox left-G matches package survival", max(abs(cw$w - ifelse(cknown, 1 / cg, 0))))
    ac <- data.frame(u = score_data$u, event = as.integer(score_data$status > 0))
    ascore <- riskRegression::Score(list(frozen = risk), Surv(u, event) ~ 1, data = ac, times = 3,
      metrics = c("AUC", "Brier"), null.model = FALSE, split.method = "none", conf.int = FALSE,
      cens.model = "km", se.fit = FALSE)
    ay <- as.integer(ac$u <= 3 & ac$event == 1)
    check("All-death dynamic AUC matches Score", abs(ascore$AUC$score$AUC[1] - auc2(risk, ay, ww)), 1e-8)
    check("All-death Brier matches Score", abs(ascore$Brier$score$Brier[1] - sum(ww * (ay - risk)^2) / 60), 1e-8)
    ajs <- survival::survfit(survival::Surv(t, factor(e, levels = 0:2)) ~ 1)
    ajsv <- ajs$pstate[max(which(ajs$time <= 3)), ]
    check("AJ matches independent multistate survfit", max(abs(aj(t, e) - ajsv[c(2, 3, 1)])))
    bad <- data.frame(time = c(1.2, 1.4, 4.5), status = c(0L, 0L, 1L), age_group = c("young", "young", "old"))
    check("Age-stratum without tau support gives NA, never pooled G", as.numeric(!all(is.na(weights_ipcw(bad, 1, "covariate")$w))))
    check("Required zero G gives NA, never a capped main weight", as.numeric(!all(is.na(weights_ipcw(bad[1:2, ], 1)$w))))
    say("Synthetic qualification PASS:", length(tests), "checks; no development model fitted.")
    do.call(rbind, tests)
  }

  initial_rng <- function() {
    RNGkind("L'Ecuyer-CMRG"); set.seed(CFG$seed)
    seed <- get(".Random.seed", envir = .GlobalEnv)
    for(j in seq_len(CFG$stream)) seed <- parallel::nextRNGStream(seed)
    seed
  }
  patient_bootstrap <- function(d, cache, spec, point) {
    ii <- which(!point$record_type %in% c("Censor_distribution", "Risk_distribution", "Probability_QC"))
    keys <- point$key[ii]; rng0 <- initial_rng()
    cp <- list(done = 0L, keys = keys, estimates = matrix(NA_real_, length(keys), S$B),
                             errors = rep("", S$B), rng = rng0, initial_rng = rng0)
    start <- Sys.time()
    if(cp$done < S$B) for(b in seq.int(cp$done + 1L, S$B)) {
      assign(".Random.seed", cp$rng, envir = .GlobalEnv)
      draw <- sample.int(nrow(d), size = nrow(d), replace = TRUE)
      cp$rng <- get(".Random.seed", envir = .GlobalEnv)
      dd <- d[draw, , drop = FALSE]; dd$cluster <- seq_len(nrow(dd))
      assert(length(unique(dd$cluster)) == nrow(d), "Resampled patient copies collapsed.")
      ev <- tryCatch(evaluate(dd, cache, spec, detailed = FALSE), error = function(e) e)
      if(inherits(ev, "error")) cp$errors[b] <- conditionMessage(ev) else {
        jj <- match(keys, ev$key); assert(!anyNA(jj), "Bootstrap output layout changed unexpectedly.")
        cp$estimates[, b] <- ev$estimate[jj]
      }
      cp$done <- b
      if(b %% 10L == 0L || b == S$B || b == 1L) {
        elapsed <- as.numeric(difftime(Sys.time(), start, units = "mins"))
        say("Paired patient bootstrap", b, "/", S$B, "; elapsed this session", round(elapsed, 1), "min.")
      }
    }
    assert(cp$done == S$B, "Bootstrap incomplete.")
    point$lower95 <- point$upper95 <- NA_real_; point$valid_bootstrap <- NA_integer_
    point$bootstrap_attempts <- NA_integer_
    smooth_types <- point$record_type == "Curve" | point$metric %in% c("slope", "intercept", "offset_intercept", "ICI")
    for(j in seq_along(ii)) {
      row <- ii[j]; v <- cp$estimates[j, ]; valid <- is.finite(v); nv <- sum(valid)
      point$valid_bootstrap[row] <- nv; point$bootstrap_attempts[row] <- S$B
      if(nv / S$B >= .95 && is.finite(point$estimate[row])) {
        point[row, c("lower95", "upper95")] <- q7(v[valid], c(.025, .975))
      } else {
        point$status[row] <- paste(point$status[row], "CI_UNSUPPORTED_<95%", sep = "; ")
        if(smooth_types[row]) point$estimate[row] <- NA_real_
      }
      if(!is.finite(point$estimate[row])) point$status[row] <- paste(point$status[row], "ESTIMATE_NA", sep = "; ")
    }
    list(table = point, initial_rng = cp$initial_rng, errors = cp$errors,
         complete_draws = sum(cp$errors == ""), attempted = S$B)
  }

  display_value <- function(est, lo, hi, digits = 3L) {
    if(!is.finite(est)) return("NA")
    p <- formatC(est, digits = digits, format = "f")
    if(is.finite(lo) && is.finite(hi)) paste0(p, " [", formatC(lo, digits = digits, format = "f"), ", ",
                                              formatC(hi, digits = digits, format = "f"), "]") else paste0(p, " [CI unsupported]")
  }
  contrast_for <- function(tab, first, second, metric) {
    direct <- paste(first, second, sep = "-"); reverse <- paste(second, first, sep = "-")
    z <- tab[tab$sheet == "paired_differences" & tab$metric == metric & tab$model %in% c(direct, reverse), ]
    if(nrow(z) && unique(z$model) == reverse) {
      z$estimate <- -z$estimate; tmp <- z$lower95; z$lower95 <- -z$upper95; z$upper95 <- -tmp
    }
    z
  }
  interpretation <- function(tab) {
    consistent <- function(m, metrics) {
      all(vapply(setdiff(CFG$models, m), function(other) all(vapply(metrics, function(metric) {
        z <- contrast_for(tab, m, other, metric)
        nrow(z) == 9L && all(is.finite(z$upper95)) && all(z$estimate < 0 & z$upper95 < 0 & z$status == "OK")
      }, logical(1))), logical(1)))
    }
    win <- function(metrics) {
      z <- CFG$models[vapply(CFG$models, consistent, logical(1), metrics = metrics)]
      if(length(z) == 1L) z else "NO UNIQUE MODEL"
    }
    bc <- win(c("abs_O_minus_E_pp", "ICI")); bb <- win("Brier")
    benefit <- if(bc == "C" && bb == "C") "YES" else "UNCERTAIN"
    if(bc %in% c("A", "B") && identical(bb, bc)) benefit <- "NO"
    list(best_calibrated = bc, lowest_brier = bb, auc_material = "NO",
      auc_qualification = "Material improvement NOT ESTABLISHED: SAP specifies no clinical/material delta-AUC margin; NO does not establish negligible effects or equivalence.",
      C_benefit = benefit,
      C_qualification = "Clear means consistent paired numerical improvement in Brier and both absolute O-E/ICI across endpoints and landmarks, NOT proven clinical utility. Mixed/unstable/imprecise comparisons remain UNCERTAIN.")
  }

  write_report <- function(tab, d, boot, path) {
    intr <- interpretation(tab); primary <- tab[tab$record_type == "Primary" & tab$scope == "2012-2017", ]
    value <- function(s, m, k, metric) {
      z <- primary[primary$landmark == s & primary$model == m & primary$cause == k & primary$metric == metric, ]
      if(nrow(z) != 1) return("NA")
      display_value(z$estimate, z$lower95, z$upper95)
    }
    lines <- c(paste0("# ", if(S$mode != "final") "SMOKE TEST / NOT FOR ARTICLE -- " else "", "2012-2017 temporal validation"), "",
      "NO MODEL TUNING ON VALIDATION DATA", "",
      paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "| Mode:", S$mode),
      "Frozen resection-selected M0 registry prognosis; horizon 3 years; strict survival beyond L1/L2/L3.",
      "The all-death endpoint here is the sum of the two adjudicated causes in the SAME competing-risk cohort; it is not the separate 7,100-person precursor/all-cause module.",
      "Temporal validation was withheld from model fitting and tuning. Some earlier era summaries were visible; this is neither completely blinded external validation nor a historical deployment simulation with all training follow-up known in 2011.", "",
      "## Cohort and follow-up", "", paste("Evaluated source patients:", nrow(d), "; frozen full 2012-2017 source:", S$full_source_n),
      paste("Source status over full recorded follow-up: GBC", sum(d$status == 1), "; Other", sum(d$status == 2), "; censored", sum(d$status == 0), ". These are NOT 3-year landmark event counts."), "",
      "| Landmark | n | GBC deaths by 3y | Other deaths by 3y | Early censored |", "|---|---:|---:|---:|---:|")
    for(s in 1:3) {
      nd <- d[d$time > s, ]; u <- nd$time - s
      lines <- c(lines, sprintf("| L%d | %d | %d | %d | %d |", s, nrow(nd), sum(u <= 3 & nd$status == 1),
        sum(u <= 3 & nd$status == 2), sum(u < 3 & nd$status == 0)))
    }
    lines <- c(lines, "", "These landmark populations overlap; do not add their counts as independent people/events.", "",
      "## Original frozen-model transportability", "",
      "Values are estimates [95% percentile CI]. O-E is in percentage points; all other probabilities/metrics use the 0-1 scale.", "",
      "| Cause / LM | Model | AUC2 | Brier | O/E | O-E (pp) | Slope | ICI |", "|---|---|---|---|---|---|---|---|")
    for(k in CFG$causes) for(s in 1:3) for(m in CFG$models)
      lines <- c(lines, paste0("| ", k, " / L", s, " | ", m, " | ", paste(vapply(c("AUC2", "Brier", "O_over_E", "O_minus_E_pp", "slope", "ICI"),
        function(v) value(s, m, k, v), character(1)), collapse = " | "), " |"))
    lines <- c(lines, "", "AJ risk, mean prediction, free intercept, offset intercept and slope are in calibration. Smooth curves, pointwise intervals, grouped AJ points and risk-distribution counts are in calibration_curve_data. Slopes are horizon-risk logit slopes, not cause-specific Cox LP slopes. Workbook model C_FULL is the frozen C; All_death is the sum of the two causes.", "",
      "## Paired comparisons: discrimination versus calibration/error", "",
      "All contrasts use the SAME source-patient draw across all models, causes and landmarks. Negative delta-Brier, delta-ICI and delta-absolute(O-E) favor the first model; positive delta-AUC2 favors it. No independent-SE subtraction or DeLong binary ROC is used.", "",
      "| Cause / LM | Contrast | Delta AUC2 | Delta Brier | Delta abs(O-E), pp | Delta ICI |", "|---|---|---|---|---|---|")
    pa <- tab[tab$sheet == "paired_differences", ]
    for(k in CFG$causes) for(s in 1:3) for(ab in c("B-A", "C-A", "C-B")) {
      vals <- vapply(c("AUC2", "Brier", "abs_O_minus_E_pp", "ICI"), function(metric) {
        z <- pa[pa$cause == k & pa$landmark == s & pa$model == ab & pa$metric == metric, ]
        display_value(z$estimate, z$lower95, z$upper95, 4)
      }, character(1))
      lines <- c(lines, paste0("| ", k, " / L", s, " | ", ab, " | ", paste(vals, collapse = " | "), " |"))
    }
    lines <- c(lines, "", "### Scientific interpretation", "",
      paste("BEST CALIBRATED MODEL =", intr$best_calibrated),
      paste("LOWEST BRIER MODEL =", intr$lowest_brier),
      paste("AUC DIFFERENCES MATERIAL =", intr$auc_material), intr$auc_qualification,
      paste("C FULL ADDS CLEAR VALIDATION BENEFIT =", intr$C_benefit), intr$C_qualification, "",
      if(intr$C_benefit == "UNCERTAIN") "NO CLEAR INCREMENTAL VALIDATION BENEFIT is established overall; endpoint-specific differences below remain reportable. This is not equivalence or proof of no benefit." else "",
      "A unique narrative label requires concordant paired evidence versus both alternatives over all nine endpoint/landmark cells: Brier for error, and both absolute O-E and ICI for calibration. This is a deliberately conservative descriptive summary, NOT an SAP-prespecified clinical threshold or validation-based selection for retraining. The detailed endpoint-specific estimates take precedence.")
    for(ab in c("B-A", "C-A", "C-B")) {
      counts <- vapply(c("AUC2", "Brier", "abs_O_minus_E_pp", "ICI"), function(metric) {
        z <- pa[pa$model == ab & pa$metric == metric & pa$status == "OK", ]
        better <- if(metric == "AUC2") sum(z$lower95 > 0, na.rm = TRUE) else sum(z$upper95 < 0, na.rm = TRUE)
        worse <- if(metric == "AUC2") sum(z$upper95 < 0, na.rm = TRUE) else sum(z$lower95 > 0, na.rm = TRUE)
        paste0(metric, ": ", better, " favorable / ", worse, " unfavorable paired intervals out of 9 planned cells")
      }, character(1))
      lines <- c(lines, "", paste0(ab, ": ", paste(counts, collapse = "; "), ". These correlated pointwise comparisons are not multiplicity-adjusted discovery tests."))
    }
    a <- primary[primary$model == "A" & primary$metric %in% c("O_over_E", "O_minus_E_pp", "slope"), ]
    range_text <- function(z) if(any(is.finite(z))) paste(formatC(range(z[is.finite(z)]), digits = 3, format = "f"), collapse = " to ") else "not estimable"
    for(ab in c("B-A", "C-A", "C-B")) {
      za <- pa[pa$model == ab & pa$metric == "AUC2", ]; zb <- pa[pa$model == ab & pa$metric == "Brier", ]
      lines <- c(lines, "", paste0(ab, ": observed delta-AUC2 ranges from ", range_text(za$estimate),
        ", with CI widths ", range_text(za$upper95 - za$lower95), "; delta-Brier ranges from ", range_text(zb$estimate),
        ", with CI widths ", range_text(zb$upper95 - zb$lower95), ". These magnitudes and interval widths, not a decimal-place rank, delimit the comparison."))
    }
    lines <- c(lines, "", paste0("For properly conditioned A, O/E spans ", range_text(a$estimate[a$metric == "O_over_E"]),
      ", O-E spans ", range_text(a$estimate[a$metric == "O_minus_E_pp"]), " pp, and slope spans ", range_text(a$estimate[a$metric == "slope"]),
      ". Judge transportation from these absolute deviations and their intervals, not its AUC rank alone."),
      "If B reduces calibration/error while AUC remains close, the supported interpretation is improved absolute-risk transport, not newly acquired discrimination. Dynamic interactions in C add value only to the extent supported by the C-A and C-B paired intervals above.",
      if(intr$best_calibrated == "NO UNIQUE MODEL" || intr$lowest_brier == "NO UNIQUE MODEL")
        "No uniformly superior strategy is established. A≈B≈C may be used only as a descriptive shorthand when the displayed effect sizes are close; nonsignificance alone does NOT establish similarity, equivalence or that all prognostic information has been captured." else
        "The concordant direction summarized above supports numerical transportability differences; lack of a clinical materiality margin and the displayed uncertainty prevent clinical superiority or deployment claims.", "",
      "## Model aging (descriptive, no updating)", "",
      "Predefined diagnosis blocks: 2012-2013, 2014-2015, 2016-2017. O/E, O-E, Brier and slope and paired last-minus-first era contrasts are in model_aging. Absolute O-E is a derived aid to distinguish a signed shift from worsening calibration. G is estimated within each era/landmark; all patients are still drawn from the complete validation source.", "",
      "| Model | Metric | Last-minus-first effect range | 95% CI above / below zero |", "|---|---|---|---|")
    for(m in CFG$models) for(metric in c("O_over_E", "O_minus_E_pp", "Brier", "slope", "abs_O_minus_E_pp")) {
      z <- tab[tab$record_type == "Era_difference" & tab$model == m & tab$metric == metric, ]
      lines <- c(lines, paste0("| ", m, " | ", metric, " | ", range_text(z$estimate), " | ",
        sum(z$lower95 > 0, na.rm = TRUE), " / ", sum(z$upper95 < 0, na.rm = TRUE), " (9 cells) |"))
    }
    for(m in CFG$models) {
      z <- tab[tab$record_type == "Era_difference" & tab$model == m & tab$metric == "abs_O_minus_E_pp", ]
      worse <- sum(z$lower95 > 0 & z$status == "OK", na.rm = TRUE)
      better <- sum(z$upper95 < 0 & z$status == "OK", na.rm = TRUE)
      lines <- c(lines, "", paste0(m, ": last-versus-first era absolute calibration error has ", worse,
        " cells with an interval wholly above zero (worsening) and ", better, " below zero (improving), among 9 planned cells. ",
        if(worse == 0 && better == 0) "A definite directional calibration-aging signal is not established; wide/unsupported intervals can still conceal drift." else
        "There is endpoint-specific evidence of change; inspect all three chronological blocks before describing a trend. This is not a uniform-aging or causal claim."))
    }
    lines <- c(lines, "", "Aging signals are heterogeneous if signs disagree across causes/landmarks. Even concordant change can reflect case-mix, coding, follow-up or baseline-risk changes; it does not identify coefficient drift. A Brier change alone is not deterioration in calibration. Wide/unsupported intervals mean aging is not resolved, not absent.", "",
      "## Censoring, numerical coherence and joint diagnostics", "",
      "Marginal reverse KM uses original untruncated follow-up; all weights use G(min(t,3)-). Censoring exactly at 3 years is a known horizon state; competing death remains a known control. Early censored observations have weight zero in scoring but stay in the Brier denominator and in G estimation.",
      "Raw IPCW is primary; p99>10 or max>20 triggers the cap10 sensitivity. G<0.1, max>20 or ESS<50% of known-state n flags unreliable evaluation. Any required zero G gives NA. The common covariate sensitivity uses censor Cox age10+Male+year only with >=30 early censors, otherwise age-stratified KM; absent age-stratum support gives NA, not pooled replacement.", "",
      "| LM | G(3-) | p99 weight | Max weight | ESS | Status |", "|---|---|---|---|---|---|")
    for(s in 1:3) {
      z <- tab[tab$record_type == "IPCW_QC" & tab$landmark == s, ]
      vv <- vapply(c("G3_left", "weight_p99", "weight_max", "ESS"), function(v) formatC(z$estimate[z$metric == v], digits = 3, format = "f"), character(1))
      lines <- c(lines, paste0("| L", s, " | ", paste(vv, collapse = " | "), " | ", z$status[1], " |"))
    }
    qc <- tab[tab$record_type == "Probability_QC", ]
    lines <- c(lines, "", paste("Maximum probability closure error:", range_text(qc$estimate[qc$metric == "closure_max_error"]),
      "; unsupported predictions across model/LM evaluations:", sum(qc$estimate[qc$metric == "unsupported_n"]), "."),
      "Coherence/monotonicity/nonnegativity are NUMERICAL QC ONLY, never evidence of calibration. Unsupported predictions stay in the denominator and invalidate that model/cell's scoring rather than silently dropping patients.",
      "Joint_overall shows predicted versus AJ GBC, Other, survival and all-death states. Joint_cell retains all nine risk-tertile cells; n<50 or either cause<10 suppresses observed AJ/differences. Ties are never split and no cells are adaptively merged. Prediction-only quantile boundaries are fixed from the original validation sample for interpretable fixed-bin diagnostics; pointwise bootstrap resamples membership, re-estimates AJ/G and applies support checks anew. Cutpoints do not use outcomes.",
      "Hazard_process is observed cause counts divided by cumulative frozen cause hazard over observed risk-process time, including the event-time jump. The overall multiplier equals exp(intercept) in a Poisson-offset working model; no independent Poisson SE is used. Zero-E positive-O is unsupported, with no epsilon. This is NOT the CIF O/E and not a new fit of A/B/C.", "",
      "## Analysis notes and limitations", "",
      paste("Fixed seed:", CFG$seed, "; RNG: L'Ecuyer-CMRG; independent module stream index:", CFG$stream,
            "; initial stream state:", paste(boot$initial_rng, collapse = ",")),
      paste("Patient bootstrap attempts:", boot$attempted, "; completed evaluator draws:", boot$complete_draws,
            ". Metric-specific valid counts are in the workbook. Failed attempts are not replaced."),
      "95% percentile intervals are conditional on the frozen development models, not development-model uncertainty. Repeated landmark records are never sampled independently. Fixed-risk predictions are cached (algebraically identical to re-prediction); each draw rebuilds eligible landmarks and re-estimates G and all calibration nuisances. No optimism correction is applied to validation.",
      "Smoother: weighted quasi-binomial logit RCS, 10/50/90% logit-risk knots (2 df + intercept), re-estimated each draw. <30 cases/controls or repeated knots uses the locked linear fallback. Fit failure/separation is NA, not Firth or a changed smoother. ICI averages all patient prediction positions. Link-only clipping is [1e-6,1-1e-6]; original predictions are unchanged. Free linear intercept/slope and a separate offset intercept are reported.",
      "Fewer than 95% finite bootstrap estimates suppress nuisance slopes/ICI/curves as appropriate; tail curve points without resample support are NA. Curve bands are pointwise, not simultaneous. Original 1-99% prediction support is the main interpretation range; full-range sparse tails are marked. Sparse-bin/curve NA is expected and explicitly retained.",
      "Development A/B/C FULL remain frozen, including coefficients, baselines, knots, ridge and interactions. C FULL met the 500/500 development gate and corrected-slope medians 0.9478/0.9205. No material PH departure met the locked probe criterion; this does NOT prove PH. No validation PH search, recalibration, standardization, life-table, contemporary analysis, feature selection or ML has been performed.",
      "Potential informative censoring, SEER cause-of-death misclassification, absent comorbidity/recurrence/treatment detail, top-coded ages, registry-state Unknowns and temporal coding shifts limit transport/deployment claims. Pure database results cannot establish treatment causality or clinical utility.", "",
      "Only the results workbook and this report are delivered. No drawing is performed. Bootstrap vectors remain in memory; there are no saved per-draw files or patient-level exports.", "")
    lines <- c(lines, "", "### Plot-ready data", "",
      "performance and paired_differences contain original and paired AUC2/Brier estimates with intervals. calibration_curve_data contains smooth_curve rows (predicted_risk, observed_smoothed_risk and pointwise 95% limits), risk_histogram rows (bin bounds, count and density) and grouped_AJ rows. Use record_type to distinguish them. A future plotting script needs only this workbook, not models, patient data or another bootstrap. The calibration reference is y=x; sparse tails and unsupported cells retain their flags. O_minus_E is in percentage points throughout the workbook.",
      if(S$mode != "final") "SMOKE ONLY: 90 or fewer source patients and 3 draws cannot support article estimates, winner judgments or intervals. This artifact tests software/export paths only." else "")
    if(any(nzchar(boot$errors))) lines <- c(lines, "", "Bootstrap evaluator failure messages:", unique(boot$errors[nzchar(boot$errors)]))
    writeLines(enc2utf8(lines), path, useBytes = TRUE)
    intr
  }

  bind_fill <- function(parts) {
    parts <- Filter(function(x) !is.null(x) && nrow(x) > 0L, parts)
    if(!length(parts)) return(data.frame())
    cols <- unique(unlist(lapply(parts, names)))
    do.call(rbind, lapply(parts, function(x) {
      for(k in setdiff(cols, names(x))) x[[k]] <- NA
      x[, cols, drop = FALSE]
    }))
  }
  wide_metrics <- function(d, ids, mapping) {
    d <- d[d$metric %in% names(mapping), , drop = FALSE]
    if(!nrow(d)) return(data.frame())
    key <- do.call(paste, c(d[ids], sep = "|"))
    parts <- split(seq_len(nrow(d)), factor(key, levels = unique(key)))
    out <- lapply(parts, function(ii) {
      z <- d[ii, , drop = FALSE]
      assert(!anyDuplicated(z$metric), "Duplicate summary metric while shaping output.")
      r <- z[1, ids, drop = FALSE]; r$n <- z$n[1]; r$events <- z$events[1]
      r$other_events <- z$other_events[1]
      for(k in names(mapping)) {
        j <- match(k, z$metric); dest <- mapping[[k]]
        r[[dest]] <- if(is.na(j)) NA_real_ else z$estimate[j]
        r[[paste0(dest, "_lower95")]] <- if(is.na(j)) NA_real_ else z$lower95[j]
        r[[paste0(dest, "_upper95")]] <- if(is.na(j)) NA_real_ else z$upper95[j]
        r[[paste0(dest, "_valid_bootstrap")]] <- if(is.na(j)) NA_integer_ else z$valid_bootstrap[j]
        r[[paste0(dest, "_status")]] <- if(is.na(j)) "NOT_APPLICABLE" else z$status[j]
      }
      r$support_flag <- paste(unique(z$status), collapse = "; ")
      r$note <- paste(unique(z$note[nzchar(z$note)]), collapse = "; ")
      r
    })
    do.call(rbind, out)
  }
  shape_sheets <- function(tab) {
    z <- tab
    z$model[z$model == "C"] <- "C_FULL"
    z$cause[z$cause == "All-death"] <- "All_death"
    ids <- c("model", "cause", "landmark", "scope", "record_type")
    fields <- c(ids, "metric", "estimate", "lower95", "upper95", "n", "events", "other_events",
                "valid_bootstrap", "bootstrap_attempts", "status", "note")
    performance <- z[z$sheet == "performance" & z$metric %in% c("AUC2", "Brier"), fields, drop = FALSE]
    performance$analysis <- ifelse(performance$record_type == "Primary", "primary", performance$record_type)
    performance <- performance[, c("model", "cause", "landmark", "metric", "estimate", "lower95", "upper95", "n", "events",
      "analysis", "scope", "other_events", "valid_bootstrap", "bootstrap_attempts", "status", "note")]
    paired <- z[z$sheet == "paired_differences" & z$metric %in% c("AUC2", "Brier"), fields, drop = FALSE]
    names(paired)[names(paired) == "model"] <- "comparison"
    paired <- paired[, c("comparison", "cause", "landmark", "metric", "estimate", "lower95", "upper95", "n", "events",
                         "valid_bootstrap", "bootstrap_attempts", "status", "note")]
    calmap <- c(AJ_observed = "observed_AJ", mean_predicted = "mean_predicted", O_over_E = "O_over_E",
      O_minus_E_pp = "O_minus_E", intercept = "calibration_intercept", slope = "calibration_slope",
      offset_intercept = "calibration_offset_intercept", ICI = "ICI", abs_O_minus_E_pp = "abs_O_minus_E")
    calibration <- wide_metrics(z[z$sheet == "calibration" & z$record_type %in% c("Primary", "IPCW_covariate", "IPCW_cap10"), ], ids, calmap)
    calibration$O_minus_E_unit <- "percentage_points"
    names(calibration)[names(calibration) == "record_type"] <- "analysis"
    calibration$analysis[calibration$analysis == "Primary"] <- "primary"
    curves <- z[z$record_type == "Curve", , drop = FALSE]
    curve <- data.frame(model = curves$model, cause = curves$cause, landmark = curves$landmark,
      record_type = "smooth_curve", predicted_risk = curves$predicted,
      observed_smoothed_risk = curves$estimate, lower95 = curves$lower95, upper95 = curves$upper95,
      observed_AJ = NA_real_, risk_bin = NA_integer_, bin_lower = NA_real_, bin_upper = NA_real_,
      count = NA_real_, density = NA_real_, n = curves$n, events = curves$events,
      interpretation_range = ifelse(grepl("SPARSE TAIL", curves$note, fixed = TRUE), "sparse_tail", "central_1_99_percent"),
      valid_bootstrap = curves$valid_bootstrap, bootstrap_attempts = curves$bootstrap_attempts,
      support_flag = curves$status, note = curves$note)
    hist <- z[z$record_type == "Risk_distribution", , drop = FALSE]
    histogram <- data.frame(model = hist$model, cause = hist$cause, landmark = hist$landmark,
      record_type = "risk_histogram", predicted_risk = hist$predicted, observed_smoothed_risk = NA_real_,
      lower95 = NA_real_, upper95 = NA_real_, observed_AJ = NA_real_, risk_bin = as.integer(hist$group),
      bin_lower = round(hist$predicted - .025, 8), bin_upper = round(hist$predicted + .025, 8),
      count = hist$estimate, density = hist$estimate / (hist$n * .05), n = hist$n, events = hist$events,
      interpretation_range = "full_prediction_range", valid_bootstrap = NA_integer_, bootstrap_attempts = NA_integer_,
      support_flag = hist$status, note = "Unweighted original-patient risk distribution; width=0.05; counts sum to n; density integrates to 1")
    grouped <- z[z$record_type == "Grouped_AJ" & z$metric == "AJ_observed", , drop = FALSE]
    grouped_curve <- data.frame(model = grouped$model, cause = grouped$cause, landmark = grouped$landmark,
      record_type = "grouped_AJ", predicted_risk = grouped$predicted, observed_smoothed_risk = NA_real_,
      lower95 = grouped$lower95, upper95 = grouped$upper95, observed_AJ = grouped$estimate,
      risk_bin = as.integer(grouped$group), bin_lower = NA_real_, bin_upper = NA_real_, count = grouped$n,
      density = NA_real_, n = grouped$n, events = grouped$events, interpretation_range = "fixed_risk_quintile",
      valid_bootstrap = grouped$valid_bootstrap, bootstrap_attempts = grouped$bootstrap_attempts,
      support_flag = grouped$status, note = grouped$note)
    curve_data <- rbind(curve, histogram, grouped_curve)
    aging <- wide_metrics(z[z$sheet == "model_aging", ], ids,
      c(O_over_E = "O_over_E", O_minus_E_pp = "O_minus_E", Brier = "Brier", slope = "calibration_slope", abs_O_minus_E_pp = "abs_O_minus_E"))
    names(aging)[names(aging) == "scope"] <- "period"
    aging$O_minus_E_unit <- "percentage_points"
    j <- z[z$record_type %in% c("Joint_overall", "Joint_cell"), , drop = FALSE]
    j$metric <- paste(j$cause, j$metric, sep = "__")
    mapping <- c(GBC__mean_predicted = "pred_GBC", GBC__AJ_observed = "obs_GBC", GBC__O_minus_E_pp = "GBC_O_minus_E",
      Other__mean_predicted = "pred_Other", Other__AJ_observed = "obs_Other", Other__O_minus_E_pp = "Other_O_minus_E",
      Survival__mean_predicted = "pred_survival", Survival__AJ_observed = "obs_survival", Survival__O_minus_E_pp = "survival_O_minus_E",
      All_death__mean_predicted = "pred_All_death", All_death__AJ_observed = "obs_All_death", All_death__O_minus_E_pp = "All_death_O_minus_E")
    joint <- wide_metrics(j, c("model", "landmark", "scope", "record_type", "group"), mapping)
    joint$GBC_events <- joint$events; joint$Other_events <- joint$other_events
    joint$events <- joint$GBC_events + joint$Other_events
    names(joint)[names(joint) == "group"] <- "risk_cell"
    hazard <- z[z$record_type == "Hazard_process", fields, drop = FALSE]
    hazard$risk_cell <- z$group[z$record_type == "Hazard_process"]
    names(hazard)[names(hazard) == "status"] <- "support_flag"
    qc <- z[z$record_type %in% c("IPCW_QC", "Probability_QC", "Censor_distribution"), fields, drop = FALSE]
    qc$risk_cell <- z$group[z$record_type %in% c("IPCW_QC", "Probability_QC", "Censor_distribution")]
    names(qc)[names(qc) == "status"] <- "support_flag"
    joint <- bind_fill(list(joint, hazard, qc))
    assert(all(performance$model %in% c("A", "B", "C_FULL")) &&
      all(performance$cause %in% c("GBC", "Other", "All_death")), "Plot-ready model/cause labels mismatch.")
    assert(sum(performance$analysis == "primary") == 54L && nrow(paired) == 54L, "Missing primary or paired AUC2/Brier cells.")
    assert(all(c("B-A", "C-A", "C-B") %in% paired$comparison), "Missing paired comparison.")
    assert(nrow(curve) > 0 && nrow(histogram) > 0 && all(c("2012-2013", "2014-2015", "2016-2017") %in% aging$period),
           "Curve, distribution or aging plot-ready records missing.")
    groups <- split(histogram, paste(histogram$model, histogram$cause, histogram$landmark))
    for(h in groups) assert(sum(h$count) == h$n[1] && abs(sum(h$density * (h$bin_upper - h$bin_lower)) - 1) < 1e-10,
                            "Histogram count/density normalization mismatch.")
    list(performance = performance, paired_differences = paired, calibration = calibration,
         calibration_curve_data = curve_data, model_aging = aging, joint_calibration = joint)
  }
  export_workbook <- function(tab, path) {
    sheets <- shape_sheets(tab)
    banner <- if(S$mode == "final") "2012-2017 TEMPORAL VALIDATION / FROZEN A-B-C FULL / NO MODEL TUNING" else
              "SMOKE TEST / NOT FOR ARTICLE / <=90 PATIENTS / 3 DRAWS"
    payload <- file.path(S$temp, "aggregate_workbook.json")
    jsonlite::write_json(list(banner = banner, sheets = sheets), payload, auto_unbox = TRUE,
                        dataframe = "rows", na = "null", digits = 16)
    builder <- file.path(S$temp, "export_workbook.mjs")
    writeLines(r"---(import fs from 'node:fs/promises';
import {Workbook,SpreadsheetFile} from '@oai/artifact-tool';
const p=JSON.parse(await fs.readFile(process.argv[2],'utf8'));
const wb=Workbook.create();
for(const [name,records] of Object.entries(p.sheets)) {
  const rows=Array.isArray(records)?records:[records];
  const fields=Object.keys(rows[0]);
  const sh=wb.worksheets.add(name); sh.showGridLines=false;
  sh.getRange('A2').values=[[name.replaceAll('_',' ').toUpperCase()]];
  sh.getRange('A2').format.font={name:'Arial',size:14,bold:true,color:'#23415B'};
  sh.getRange('A3').values=[[p.banner]];
  sh.getRange('A3').format.font={name:'Arial',size:10,bold:true,color:p.banner.startsWith('SMOKE')?'#A13726':'#23415B'};
  sh.getRange('A4').values=[['95% percentile CI | O-E: percentage points; probabilities: 0-1 | blanks = NA, never zero; see status/support.']];
  sh.getRange('A4').format.font={name:'Arial',size:9,color:'#555555'};
  sh.getRangeByIndexes(4,0,1,fields.length).values=[fields];
  sh.getRangeByIndexes(5,0,rows.length,fields.length).values=rows.map(r=>fields.map(k=>r[k]??null));
  const all=sh.getRangeByIndexes(4,0,rows.length+1,fields.length);
  all.format.font={name:'Arial',size:10,color:'#243347'};all.format.rowHeight=20;
  all.format.verticalAlignment='center';all.format.columnWidth=14;
  const header=sh.getRangeByIndexes(4,0,1,fields.length);
  header.format.fill='#304F70';header.format.font={name:'Arial',size:10,color:'#FFFFFF',bold:true};
  header.format.wrapText=true;header.format.rowHeight=34;header.format.horizontalAlignment='center';
  for(let j=0;j<fields.length;j++) {
    const key=fields[j];const col=sh.getRangeByIndexes(5,j,rows.length,1);
    const present=rows.map(r=>r[key]).filter(v=>v!==null && v!==undefined);
    const numeric=present.length>0 && present.every(v=>typeof v==='number');
    col.format.horizontalAlignment=numeric?'right':'left';
    if(numeric)col.setNumberFormat(/^(landmark|n|events|other_events|risk_bin|count|bootstrap_attempts|GBC_events|Other_events)$|valid_bootstrap/.test(key)?'0':'0.0000');
    let width=14;
    if(['landmark','model','n','events'].includes(key))width=10;
    if(['cause','estimate','lower95','upper95','predicted','other_events'].includes(key))width=13;
    if(key==='metric')width=28;if(key==='scope')width=25;if(key==='record_type')width=24;
    if(key==='group'||key==='risk_cell')width=20;if(/status|support_flag/.test(key))width=36;if(key==='note')width=85;
    if(key.length>18 && width===14)width=22;
    sh.getRangeByIndexes(4,j,rows.length+1,1).format.columnWidth=width;
  }
  sh.freezePanes.freezeRows(5);
}
wb.recalculate();
const out=await SpreadsheetFile.exportXlsx(wb);
// Save only the public XLSX byte payload, not the library's optional inspection sidecar.
await fs.writeFile(process.argv[3],out.data);
console.log('WORKBOOK EXPORT PASS: '+Object.keys(p.sheets).join(', '));
)---", builder, useBytes = TRUE)
    junction <- file.path(S$temp, "node_modules")
    if(!dir.exists(junction)) {
      ps <- sprintf("New-Item -ItemType Junction -Path '%s' -Target '%s' | Out-Null",
                    gsub("'", "''", junction, fixed = TRUE), gsub("'", "''", S$modules, fixed = TRUE))
      call_external("powershell.exe", c("-NoProfile", "-NonInteractive", "-Command", ps))
    }
    say(paste(call_external(S$node, c(builder, payload, path)), collapse = " "))
    verifier <- file.path(S$temp, "verify_workbook.py")
    writeLines(r"---(import json,sys,math,zipfile
import openpyxl
p=json.load(open(sys.argv[1],encoding='utf-8'))
expected_sheets=['performance','paired_differences','calibration','calibration_curve_data','model_aging','joint_calibration']
assert list(p['sheets'])==expected_sheets
perf=p['sheets']['performance']; primary=[r for r in perf if r['analysis']=='primary']
assert len(primary)==54
assert {r['model'] for r in perf}=={'A','B','C_FULL'}
assert {r['cause'] for r in perf}=={'GBC','Other','All_death'}
assert {r['metric'] for r in perf}=={'AUC2','Brier'}
paired=p['sheets']['paired_differences']
assert len(paired)==54 and {r['comparison'] for r in paired}=={'B-A','C-A','C-B'}
cal=p['sheets']['calibration']
assert sum(r['analysis']=='primary' for r in cal)==27
assert {'observed_AJ','mean_predicted','O_over_E','O_minus_E','calibration_intercept','calibration_slope','ICI'}<=set(cal[0])
curves=p['sheets']['calibration_curve_data']
smooth=[r for r in curves if r['record_type']=='smooth_curve']
assert {'predicted_risk','observed_smoothed_risk','lower95','upper95'}<=set(smooth[0])
assert len({(r['model'],r['cause'],r['landmark']) for r in smooth})==27
hist=[r for r in curves if r['record_type']=='risk_histogram']
assert len(hist)==540 and all(r['count']>=0 and r['density']>=0 for r in hist)
aging=p['sheets']['model_aging']
assert {'2012-2013','2014-2015','2016-2017'}<={r['period'] for r in aging}
assert {'O_over_E','O_minus_E','Brier','calibration_slope'}<=set(aging[0])
joint=p['sheets']['joint_calibration']
assert sum(r['record_type']=='Joint_cell' for r in joint)==81
assert {'risk_cell','pred_GBC','obs_GBC','pred_Other','obs_Other','pred_survival','obs_survival','support_flag'}<=set(joint[0])
with zipfile.ZipFile(sys.argv[2]) as archive:
    assert not any(n.startswith(('xl/media/','xl/drawings/','xl/charts/')) for n in archive.namelist()),'Unexpected drawing part'
w=openpyxl.load_workbook(sys.argv[2],read_only=True,data_only=True)
assert w.sheetnames==list(p['sheets']), 'Sheet names/order mismatch'
count=0
for name,records in p['sheets'].items():
    if not isinstance(records,list): records=[records]
    fields=list(records[0]); it=w[name].iter_rows(min_row=3,values_only=True)
    assert next(it)[0]==p['banner'];next(it)
    assert list(next(it)[:len(fields)])==fields
    for record in records:
        row=next(it)
        for j,key in enumerate(fields):
            exp=record[key]; got=row[j] if j<len(row) else None
            if exp=='': exp=None
            if isinstance(exp,(int,float)):
                assert isinstance(got,(int,float)) and math.isclose(got,exp,rel_tol=1e-11,abs_tol=1e-12),(name,key,'Numeric mismatch')
            else: assert got==exp,(name,key,'Value mismatch')
            count+=1
w.close();print('WORKBOOK READBACK PASS: 6 sheets, plot-ready schemas, no drawings; '+str(count)+' aggregate cells')
)---", verifier, useBytes = TRUE)
    say(paste(call_external(S$audit_python, c(verifier, payload, path)), collapse = " "))
  }


  run <- function() {
    old_rng_kind <- RNGkind(); had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
    old_seed <- if(had_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
    on.exit({do.call(RNGkind, as.list(old_rng_kind));
      if(had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv)
      else if(exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)}, add = TRUE)
    setup()
    d <- read_validation(); cache <- cache_predictions(d); spec <- build_spec(d, cache)
    say("Frozen predictions / conditional identity / coherence PASS. Starting", S$B, "validation-only patient draws.")
    point <- evaluate(d, cache, spec, detailed = TRUE)
    boot <- patient_bootstrap(d, cache, spec, point); tab <- boot$table
    assert(identical(digest::digest(S$models, algo = "sha256"), S$model_digest), "Frozen model object mutated.")
    hash_inputs()
    staging <- file.path(S$temp, "delivery"); dir.create(staging, showWarnings = FALSE)
    staged <- file.path(staging, S$filenames)
    intr <- write_report(tab, d, boot, staged[2])
    export_workbook(tab, staged[1])
    assert(all(file.exists(staged)) && all(file.info(staged)$size > 1000), "Missing/empty staged deliverable.")
    hash_inputs()
    if(S$mode == "final") {
      target <- file.path(S$outputs, S$filenames)
      assert(!any(file.exists(target)), "Formal validation output appeared during this run; refusing overwrite.")
      written <- character()
      tryCatch({for(j in seq_along(target)) {
        assert(file.copy(staged[j], target[j], overwrite = FALSE), paste("Publication failed:", S$filenames[j]))
        written <- c(written, target[j])
        assert(identical(digest::digest(file = staged[j], algo = "sha256"), digest::digest(file = target[j], algo = "sha256")), "Published checksum mismatch.")
      }}, error = function(e) {
        if(length(written)) unlink(written)
        stop("Publication failed; newly copied artifacts rolled back, TEMP originals retained: ", conditionMessage(e), call. = FALSE)
      })
    }
    say(if(S$mode == "final") "TEMPORAL VALIDATION COMPLETE" else "SMOKE TEST COMPLETE -- NOT FORMAL TEMPORAL VALIDATION")
    primary <- tab[tab$record_type == "Primary" & tab$scope == "2012-2017", ]
    for(s in 1:3) for(k in CFG$causes) for(metric in c("AUC2", "Brier", "O_over_E")) {
      z <- primary[primary$landmark == s & primary$cause == k & primary$metric == metric, ]
      z <- z[match(CFG$models, z$model), ]
      say(paste0("L", s), k, metric, paste(paste(z$model,
        mapply(display_value, z$estimate, z$lower95, z$upper95)), collapse = " | "))
    }
    say("BEST CALIBRATED MODEL =", intr$best_calibrated)
    say("LOWEST BRIER MODEL =", intr$lowest_brier)
    say("AUC DIFFERENCES MATERIAL =", intr$auc_material, "(material improvement not established; no SAP margin)")
    say("C FULL ADDS CLEAR VALIDATION BENEFIT =", intr$C_benefit)
    say("Artifacts:", if(S$mode == "final") S$outputs else staging)
    invisible(list(mode = S$mode, artifacts = if(S$mode == "final") file.path(S$outputs, S$filenames) else staged,
                   evaluator_draws = boot$complete_draws))
  }
  environment()
})
if(isTRUE(getOption("gbc.validation.autorun", FALSE))) gbc_validation$run()


