# Frozen numerical definitions extracted without algorithm changes from original
# scripts/run_development.R. Legacy models and autorun are absent.
assert <- function(ok, message) {
    if (length(ok) != 1L || is.na(ok) || !ok)
        stop(message, call. = FALSE)
    invisible(TRUE)
}

fit_failure <- function(message) {
    stop(structure(list(message = message, call = NULL), class = c("fit_failure", "error", "condition")))
}

cox_checked <- function(formula, frame, tv = FALSE, origin = 0) {
    warnings <- character()
    fit <- withCallingHandlers(coxph(formula, data = frame, ties = "breslow", x = TRUE, y = TRUE, model = !tv, robust = FALSE, singular.ok = FALSE, control = coxph.control(iter.max = 60, eps = 1e-09), tt = if (tv)
        function(x, t, ...) x * log(pmax(t - origin, 0.25))
    else NULL), warning = function(w) {
        msg <- conditionMessage(w)
        if (grepl("converg|infinite|singular|overflow|NaN", msg, ignore.case = TRUE))
            fit_failure(msg)
        warnings <<- c(warnings, msg)
        invokeRestart("muffleWarning")
    })
    if (any(!is.finite(coef(fit))) || any(!is.finite(fit$var)))
        fit_failure("Nonfinite Cox coefficient/information")
    fit$captured_warnings <- warnings
    fit
}

baseline_information <- function(md, x, beta, cause, tv = NULL, delta = 0, information = FALSE) {
    base <- list()
    p <- ncol(x)
    info <- matrix(0, p + as.integer(!is.null(tv)), p + as.integer(!is.null(tv)))
    score <- numeric(nrow(info))
    eta <- drop(x %*% beta)
    for (s in sort(unique(md$lm))) {
        ids <- which(md$lm == s)
        stop <- md$stop[ids]
        start <- md$start[ids]
        e <- md$event[ids] == cause
        times <- sort(unique(stop[e]))
        if (!length(times))
            fit_failure("No baseline events in a required stratum")
        xx <- x[ids, , drop = FALSE]
        lp <- eta[ids]
        count <- tabulate(match(stop[e], times), length(times))
        haz <- numeric(length(times))
        origin <- if (all(start == 1))
            1
        else 0
        z <- if (!is.null(tv))
            if (tv == "age")
                (md$age_dx[ids] - 70)/10
            else as.numeric(md$T_core[ids] == "T3/4")
        else rep(0, length(ids))
        if (is.null(tv) && !information) {
            ord <- order(stop, decreasing = TRUE)
            sums <- cumsum(exp(lp[ord]))
            unique_stop <- !duplicated(stop[ord], fromLast = TRUE)
            lookup <- setNames(sums[unique_stop], as.character(stop[ord][unique_stop]))
            den <- unname(lookup[as.character(times)])
            haz <- count/den
        }
        else for (j in seq_along(times)) {
            risk <- which(start < times[j] & stop >= times[j])
            q <- log(pmax(times[j] - origin, 0.25))
            xr <- xx[risk, , drop = FALSE]
            if (!is.null(tv))
                xr <- cbind(xr, z[risk] * q)
            w <- exp(lp[risk] + delta * z[risk] * q)
            den <- sum(w)
            haz[j] <- count[j]/den
            if (information) {
                m <- colSums(xr * w)/den
                info <- info + count[j] * (crossprod(xr, xr * w)/den - tcrossprod(m))
                event_rows <- which(stop == times[j] & e)
                xe <- xx[event_rows, , drop = FALSE]
                if (!is.null(tv))
                  xe <- cbind(xe, z[event_rows] * q)
                score <- score + colSums(xe) - count[j] * m
            }
        }
        if (any(!is.finite(haz)) || any(haz < 0))
            fit_failure("Nonfinite/negative Breslow increment")
        base[[as.character(s)]] <- data.frame(time = times, hazard = haz, events = count)
    }
    list(baseline = base, information = info, score = score)
}

integrate_grid <- function(times, a1, a2, lower, upper, observed_end = NULL) {
    n <- nrow(a1)
    S <- rep(1, n)
    F1 <- F2 <- L1 <- L2 <- rep(0, n)
    before <- lower
    for (j in which(times > lower & times <= upper)) {
        dt <- times[j] - before
        L1 <- L1 + F1 * dt
        L2 <- L2 + F2 * dt
        before <- times[j]
        a <- a1[, j] + a2[, j]
        share <- ifelse(a > 0, -expm1(-a)/a, 1)
        F1 <- F1 + S * share * a1[, j]
        F2 <- F2 + S * share * a2[, j]
        S <- S * exp(-a)
    }
    L1 <- L1 + F1 * (upper - before)
    L2 <- L2 + F2 * (upper - before)
    ans <- cbind(GBC = F1, Other = F2, Survival = S, RMTL_GBC = L1, RMTL_Other = L2)
    if (any(!is.finite(ans)) || any(ans < -1e-12) || max(abs(rowSums(ans[, 1:3, drop = FALSE]) - 1)) >= 1e-10)
        fit_failure("Competing-risk probability closure/nonnegative check failed")
    ans
}
