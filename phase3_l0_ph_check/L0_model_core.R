# L0-only PH sensitivity. Date: 2026-10-27; R4.4.3/survival3.8.3.
# Pure functions; no autorun or file writes. Original source is read-only.

l0_split <- function(d, cuts) {
  base <- data.frame(start = 0, stop = d$stop,
    any_event = as.integer(d$event > 0), original_event = d$event,
    High = d$High, Age10 = (d$age_attained - 70) / 10,
    Age10_squared = ((d$age_attained - 70) / 10)^2,
    Male = as.numeric(d$sex == "Male"), copy_id = seq_len(nrow(d)))
  split <- survival::survSplit(Surv(start, stop, any_event) ~ .,
    data = base, cut = cuts, episode = "period", start = "start", end = "stop", event = "any_event")
  split$event <- ifelse(split$any_event == 1, split$original_event, 0L)
  lower <- c(0, cuts)
  require_ok(all(split$start < split$stop) && all(split$start == lower[split$period]),
    "Invalid counting-process interval boundaries")
  require_ok(all(split$period == 1L + vapply(split$stop, function(t) sum(t > cuts), integer(1))),
    "An event at a boundary was assigned to the wrong period")
  totals <- rowsum(cbind(all = split$any_event, GBC = as.integer(split$event == 1),
    Other = as.integer(split$event == 2), duration = split$stop - split$start),
    split$copy_id, reorder = TRUE)
  require_ok(nrow(totals) == nrow(d) && all(totals[, "all"] == as.integer(d$event > 0)) &&
    all(totals[, "GBC"] == as.integer(d$event == 1)) &&
    all(totals[, "Other"] == as.integer(d$event == 2)) &&
    max(abs(totals[, "duration"] - d$stop)) < 1e-12 &&
    all(totals[, "all"] <= 1), "Split records duplicate/lose an event or patient duration")
  split
}

l0_design <- function(z, mode, periods) {
  if (mode == "PH") return(cbind(High = z$High, Age10 = z$Age10,
    Age10_squared = z$Age10_squared, Male = z$Male))
  indicator <- outer(z$period, seq_len(periods), `==`) * 1
  high <- indicator * z$High
  colnames(high) <- paste0("High_p", seq_len(periods))
  if (mode == "AGE_TV") {
    age <- indicator * z$Age10; square <- indicator * z$Age10_squared
    colnames(age) <- paste0("Age10_p", seq_len(periods))
    colnames(square) <- paste0("Age10_squared_p", seq_len(periods))
    cbind(high, age, square, Male = z$Male)
  } else cbind(high, Age10 = z$Age10, Age10_squared = z$Age10_squared, Male = z$Male)
}

l0_fit <- function(d, split, cause, mode, kernels, cuts, verify = FALSE) {
  periods <- length(cuts) + 1L
  z <- if (mode == "PH") data.frame(start = 0, stop = d$stop, event = d$event,
    High = d$High, Age10 = (d$age_attained - 70) / 10,
    Age10_squared = ((d$age_attained - 70) / 10)^2, Male = as.numeric(d$sex == "Male"), period = 1L) else split
  x <- l0_design(z, mode, periods)
  require_ok(sum(z$event == cause) > 0 && any(z$stop >= 3), "No cause event or horizon support")
  require_ok(qr(sweep(x, 2, colMeans(x), "-"), tol = 1e-9)$rank == ncol(x), "Rank-deficient fixed design")
  frame <- data.frame(start = z$start, stop = z$stop, death = as.integer(z$event == cause))
  frame$X <- I(x)
  fit <- kernels$cox_checked(survival::Surv(start, stop, death) ~ X, frame)
  require_ok(length(coef(fit)) == ncol(x) && max(fit$iter) < 60 &&
    is.finite(rcond(fit$var)) && rcond(fit$var) >= 1e-12 &&
    max(abs(unname(fit$x) - unname(x))) < 1e-10, "Cox convergence/design/information gate failed")
  beta <- setNames(as.numeric(coef(fit)), colnames(x))
  lp <- drop(x %*% beta)
  baseline <- list(); risk_error <- 0L
  # Each period has a common entry boundary. Reverse cumulative risk sums are
  # valid WITHIN a period, not over the entire split dataset.
  for (p in if (mode == "PH") 1L else seq_len(periods)) {
    ids <- which(z$period == p)
    times <- sort(unique(z$stop[ids][z$event[ids] == cause]))
    require_ok(length(times) > 0, "No cause events in a required time period")
    ord <- order(z$stop[ids], decreasing = TRUE)
    stops <- z$stop[ids][ord]
    sums <- cumsum(exp(lp[ids][ord])); keep <- !duplicated(stops, fromLast = TRUE)
    denominator <- unname(setNames(sums[keep], as.character(stops[keep]))[as.character(times)])
    count <- tabulate(match(z$stop[ids][z$event[ids] == cause], times), length(times))
    require_ok(all(is.finite(denominator) & denominator > 0), "Invalid split Breslow risk denominator")
    if (verify) for (j in seq_along(times)) {
      risk <- z$start < times[j] & z$stop >= times[j]
      direct <- sum(exp(lp[risk]))
      require_ok(abs(direct - denominator[j]) <= 1e-8 * max(1, direct), "Counting-process risk denominator mismatch")
      if (mode != "PH") {
        require_ok(sum(risk) == length(unique(z$copy_id[risk])), "A patient copy appears twice in a risk set")
        require_ok(all(z$period[risk] == p), "Incorrect period in event risk set")
      }
    }
    baseline[[length(baseline) + 1L]] <- data.frame(time = times,
      hazard = count / denominator, period = p)
  }
  baseline <- do.call(rbind, baseline); baseline <- baseline[order(baseline$time), ]
  require_ok(all(is.finite(baseline$hazard) & baseline$hazard >= 0), "Nonfinite baseline increment")
  basehaz_error <- lp_error <- NA_real_
  if (verify) {
    independent <- survival::basehaz(fit, centered = FALSE)
    j <- match(baseline$time, independent$time)
    require_ok(!anyNA(j), "basehaz event times missing")
    basehaz_error <- max(abs(cumsum(baseline$hazard) - independent$hazard[j]))
    lp_error <- max(abs(as.numeric(predict(fit, type = "lp", reference = "zero")) - lp))
    require_ok(basehaz_error < 1e-8 && lp_error < 1e-8, "Independent basehaz/linear predictor audit failed")
  }
  list(beta = beta, baseline = baseline, mode = mode, periods = periods,
    cuts = cuts, fit = if (verify) fit else NULL,
    basehaz_error = basehaz_error, lp_error = lp_error, risk_error = risk_error,
    warnings = paste(fit$captured_warnings, collapse = "; "))
}

l0_predict <- function(pair, reference, high = NULL, kernels, horizon = 3) {
  # Exact aggregation of identical prediction profiles; no patient subsampling.
  high_value <- if (is.null(high)) reference$High else rep(as.numeric(high), nrow(reference))
  profile <- data.frame(High = high_value, Age10 = (reference$age_attained - 70) / 10,
    Age10_squared = ((reference$age_attained - 70) / 10)^2, Male = as.numeric(reference$sex == "Male"))
  key <- do.call(paste, c(profile, sep = "|")); take <- which(!duplicated(key))
  weights <- tabulate(match(key, key[take]), nbins = length(take)); profile <- profile[take, ]
  times <- sort(unique(c(pair[[1]]$baseline$time, pair[[2]]$baseline$time)))
  times <- times[times <= horizon]
  require_ok(length(times) > 0 && nrow(profile) > 0, "Empty prediction support")
  hazards <- lapply(pair, function(f) {
    h <- f$baseline$hazard[match(times, f$baseline$time)]; h[is.na(h)] <- 0
    out <- matrix(0, nrow(profile), length(times))
    period <- 1L + vapply(times, function(t) sum(t > f$cuts), integer(1))
    for (p in unique(period)) {
      ref <- profile; ref$period <- p
      x <- l0_design(ref, f$mode, f$periods)
      require_ok(identical(colnames(x), names(f$beta)), "Prediction coefficient order changed")
      ii <- which(period == p)
      out[, ii] <- outer(exp(drop(x %*% f$beta)), h[ii])
    }
    out
  })
  result <- kernels$integrate_grid(times, hazards[[1]], hazards[[2]], 0, horizon)
  # Independently audit every CIF jump and all three step-function integrals.
  S <- rep(1, nrow(profile)); F1 <- F2 <- A0 <- A1 <- A2 <- rep(0, nrow(profile)); before <- 0
  closure <- identity <- monotonic_error <- 0
  for (j in seq_along(times)) {
    dt <- times[j] - before; before <- times[j]
    A0 <- A0 + S * dt; A1 <- A1 + F1 * dt; A2 <- A2 + F2 * dt
    a <- hazards[[1]][, j] + hazards[[2]][, j]
    share <- ifelse(a > 0, -expm1(-a) / a, 1)
    delta1 <- S * share * hazards[[1]][, j]; delta2 <- S * share * hazards[[2]][, j]
    monotonic_error <- max(monotonic_error, -min(c(delta1, delta2)))
    F1 <- F1 + delta1; F2 <- F2 + delta2; S <- S * exp(-a)
    closure <- max(closure, max(abs(F1 + F2 + S - 1)))
    require_ok(all(F1 >= -1e-12 & F2 >= -1e-12 & F1 + F2 <= 1 + 1e-10), "CIF bounds/monotonicity failed")
  }
  dt <- horizon - before; A0 <- A0 + S * dt; A1 <- A1 + F1 * dt; A2 <- A2 + F2 * dt
  identity <- max(abs(A0 + A1 + A2 - horizon)) * 12
  integral_error <- max(abs(cbind(F1, F2, A1, A2) -
    result[, c("GBC", "Other", "RMTL_GBC", "RMTL_Other")]))
  require_ok(closure < 1e-10 && identity < 1e-8 && integral_error < 1e-10 && monotonic_error < 1e-12,
    "Independent competing-risk integration audit failed")
  values <- colSums(result * weights) / sum(weights)
  list(values = values, closure_error = closure, identity_error_months = identity,
    integral_error = integral_error, monotonic_error = monotonic_error)
}

l0_evaluate <- function(data, original, kernels, cuts = c(1, 2), verify = FALSE) {
  z <- original$phase3_landmark(data, 0)
  rows <- list(); models <- diagnostics <- residuals <- events <- calibration <- list()
  for (target in names(original$phase3_targets)) {
    t <- original$phase3_targets[[target]]
    support <- original$age_sex_support(z, target)
    ref <- z[support$mask, , drop = FALSE]
    d <- z[z[[t$variable]] %in% c(t$low, t$high), , drop = FALSE]
    d$High <- as.numeric(d[[t$variable]] == t$high)
    split <- l0_split(d, cuts)
    fitted <- list()
    for (mode in c("PH", "PATH_TV", "AGE_TV")) {
      attempt <- tryCatch({
        if (mode == "AGE_TV") {
          require_ok(!is.null(fitted$PATH_TV), "Required other-cause PATH_TV model unavailable")
          pair <- list(l0_fit(d, split, 1, mode, kernels, cuts, verify), fitted$PATH_TV[[2]])
        } else pair <- lapply(1:2, function(cause) l0_fit(d, split, cause, mode, kernels, cuts, verify))
        low <- l0_predict(pair, ref, FALSE, kernels)
        high <- l0_predict(pair, ref, TRUE, kernels)
        list(pair = pair, low = low, high = high)
      }, error = function(e) e)
      row <- data.frame(target = target, contrast = t$label, model = mode,
        source_n = nrow(z), fit_n = nrow(d), reference_n = nrow(ref),
        reference_coverage = nrow(ref) / nrow(z), high_n = sum(d$High == 1), low_n = sum(d$High == 0),
        high_gbc_events = sum(d$High == 1 & d$event == 1), low_gbc_events = sum(d$High == 0 & d$event == 1),
        high_cif = NA_real_, low_cif = NA_real_, rd_pp = NA_real_, closure_error = NA_real_,
        identity_error_months = NA_real_, integral_error = NA_real_, monotonic_error = NA_real_,
        status = "NOT_ESTIMABLE", reason = "")
      if (inherits(attempt, "error")) row$reason <- conditionMessage(attempt) else {
        fitted[[mode]] <- attempt$pair
        row$high_cif <- attempt$high$values["GBC"]
        row$low_cif <- attempt$low$values["GBC"]
        row$rd_pp <- 100 * (row$high_cif - row$low_cif)
        for (f in c("closure_error", "identity_error_months", "integral_error", "monotonic_error"))
          row[[f]] <- max(attempt$high[[f]], attempt$low[[f]])
        row$status <- "OK"
      }
      rows[[length(rows) + 1L]] <- row
    }
    if (verify) {
      require_ok(length(fitted) == 3L, "Point model failure; no formal inference")
      models[[target]] <- fitted
      for (cause in 1:2) {
        fit <- fitted$PH[[cause]]$fit
        ph <- survival::cox.zph(fit, transform = "km", terms = FALSE, singledf = FALSE)
        tab <- as.data.frame(ph$table); tab$term <- rownames(tab)
        tab$term <- sub("^X", "", tab$term)
        names(tab)[1:3] <- c("chisq", "df", "p")
        tab$target <- target; tab$cause <- c("GBC", "Other")[cause]; tab$test <- "coefficient_or_global"
        frame <- data.frame(start = 0, stop = d$stop, death = as.integer(d$event == cause),
          High = d$High, Male = as.numeric(d$sex == "Male"))
        frame$Age <- I(cbind(Age10 = (d$age_attained - 70) / 10,
          Age10_squared = ((d$age_attained - 70) / 10)^2))
        jointfit <- kernels$cox_checked(survival::Surv(start, stop, death) ~ High + Age + Male, frame)
        require_ok(max(abs(unname(coef(jointfit)) - unname(coef(fit)))) < 1e-8, "Age-grouped equivalent fit changed")
        joint <- survival::cox.zph(jointfit, transform = "km", terms = TRUE)$table["Age", ]
        tab <- rbind(tab, data.frame(chisq = joint[1], df = joint[2], p = joint[3], term = "Age_joint_2df",
          target = target, cause = c("GBC", "Other")[cause], test = "joint_age"))
        diagnostics[[length(diagnostics) + 1L]] <- tab
        if (cause == 1) for (variable in c("High", "Age10")) {
          column <- match(paste0("X", variable), colnames(ph$y))
          require_ok(!is.na(column), "Scaled Schoenfeld residual column missing")
          residuals[[length(residuals) + 1L]] <- data.frame(target = target, variable = variable,
            time_months = ph$time * 12, scaled_residual = ph$y[, column] - fitted$PH[[cause]]$beta[variable])
        }
      }
      for (p in seq_len(length(cuts) + 1L)) for (high in 0:1) {
        take <- split$period == p & split$High == high
        events[[length(events) + 1L]] <- data.frame(row_type = "PERIOD_EVENT_COUNTS", target = target,
          period = p, group = if (high) t$high else t$low,
          n_at_period_start = sum(take), gbc_events = sum(split$event[take] == 1),
          other_events = sum(split$event[take] == 2), split_rows = sum(take), status = "PASS")
      }
      # Apparent calibration compares factual predictions and AJ in exactly the
      # binary FITTING cohort, never standardized all-high/all-low profiles or all3918.
      for (mode in names(fitted)) for (h in 1:3) {
        dz <- d; dz$stop <- pmin(d$stop, h); dz$event[d$stop > h] <- 0L
        dz$u <- d$u
        aj <- l0_aj_at(d, h)
        predicted <- l0_predict(fitted[[mode]], d, NULL, kernels, h)$values
        calibration[[length(calibration) + 1L]] <- data.frame(row_type = "APPARENT_CALIBRATION",
          target = target, model = mode, horizon_months = 12 * h, fit_n = nrow(d),
          aj_gbc_cif = aj[1], predicted_gbc_cif = predicted["GBC"],
          aj_other_cif = aj[2], predicted_other_cif = predicted["Other"],
          aj_allcause = sum(aj), predicted_allcause = sum(predicted[c("GBC", "Other")]),
          gbc_difference_pp = 100 * (predicted["GBC"] - aj[1]),
          other_difference_pp = 100 * (predicted["Other"] - aj[2]),
          allcause_difference_pp = 100 * (sum(predicted[c("GBC", "Other")]) - sum(aj)), status = "DESCRIPTIVE_IN_SAMPLE")
      }
    }
  }
  summary <- do.call(rbind, rows)
  out <- list(summary = summary)
  if (verify) {
    diagnostic <- do.call(rbind, diagnostics); diagnostic$q <- NA_real_
    i <- diagnostic$test == "coefficient_or_global" & diagnostic$term != "GLOBAL"
    diagnostic$q[i] <- p.adjust(diagnostic$p[i], "BH")
    diagnostic$correction <- ifelse(i, "BH within24 coefficient tests", "Not included in coefficient family")
    out$diagnostics <- diagnostic; out$residuals <- do.call(rbind, residuals)
    out$events <- do.call(rbind, events); out$calibration <- do.call(rbind, calibration)
    out$models <- models
  }
  out
}

l0_aj_at <- function(d, horizon) {
  time <- pmin(d$stop, horizon); event <- ifelse(d$stop <= horizon, d$event, 0L)
  values <- sort(unique(time)); group <- match(time, values)
  counts <- rowsum(cbind(n = rep(1, nrow(d)), d1 = as.integer(event == 1), d2 = as.integer(event == 2)), group)
  risk <- rev(cumsum(rev(counts[, "n"]))); hazard <- counts[, c("d1", "d2")] / risk
  S <- cumprod(1 - rowSums(hazard)); before <- c(1, head(S, -1))
  result <- colSums(hazard * before)
  require_ok(all(result >= 0) && sum(result) <= 1 + 1e-10, "AJ calibration endpoint invalid")
  result
}
