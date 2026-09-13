# Publication source copy. See docs/original_script_mapping.md and reproducibility_notes.md.

PROJECT_ROOT <- Sys.getenv("GBC_FINAL_RUN_ROOT", unset = getwd())
figure_set <- Sys.getenv("GBC_FIGURE_SET", "submission")
if (!figure_set %in% c("submission", "supplement")) stop("Use submission or supplement.")
full_figure_run <- identical(figure_set, "submission")

required_packages <- c(ggplot2 = "3.5.2", patchwork = "1.3.2",
                       readxl = "1.4.0", scales = "1.3.0", ragg = "1.3.0",
                       ggrepel = "0.9.5")
for (p in intersect(names(required_packages), loadedNamespaces())) {
  if (getNamespaceVersion(p) < package_version(required_packages[[p]])) {
    stop("An outdated namespace is already loaded: ", p,
         ". Restart R (RStudio: Ctrl+Shift+F10), then source this script again.", call. = FALSE)
  }
}
needs_install <- names(required_packages)[vapply(names(required_packages), function(p) {
  location <- find.package(p, quiet = TRUE)
  !length(location) || utils::packageVersion(p) < package_version(required_packages[[p]])
}, logical(1))]
if (length(needs_install)) {
  stop("Install/update these packages in a clean R session before running: ",
       paste(needs_install, collapse = ", "), call. = FALSE)
}
for (p in names(required_packages)) {
  if (!requireNamespace(p, quietly = TRUE) ||
      utils::packageVersion(p) < package_version(required_packages[[p]])) {
    stop("Missing/incompatible package: ", p, ". Restart R after updating packages.",
         call. = FALSE)
  }
}
suppressPackageStartupMessages({
  library(ggplot2)
  library(patchwork)
})
if (!capabilities("cairo")) stop("Cairo PDF support is required.", call. = FALSE)

formal_file <- function(name, master = FALSE) {
  candidates <- if (master) file.path(PROJECT_ROOT, name) else
    file.path(PROJECT_ROOT, c("outputs", "outputs/TABLES_INPUTS_REQUIRED"), name)
  found <- candidates[file.exists(candidates)]
  if (!length(found)) stop("Required frozen workbook not found: ",
                          paste(candidates, collapse = " or "), call. = FALSE)
  found[[1L]]
}
read_block <- function(path, sheet, header, columns = NA_integer_) {
  if (!sheet %in% readxl::excel_sheets(path)) {
    stop("Missing sheet '", sheet, "' in ", path, call. = FALSE)
  }
  d <- as.data.frame(readxl::read_excel(
    path, sheet = sheet,
    range = readxl::cell_limits(c(header, 1L), c(NA_integer_, columns)),
    col_types = "text", .name_repair = "minimal"), stringsAsFactors = FALSE)
  if (anyDuplicated(names(d)) || any(!nzchar(names(d)))) {
    stop("Unexpected/duplicate column names in ", basename(path), ": ", sheet,
         call. = FALSE)
  }
  blank <- apply(d, 1L, function(x) all(is.na(x) | trimws(x) == ""))
  if (any(blank)) d <- d[seq_len(which(blank)[[1L]] - 1L), , drop = FALSE]
  if (!nrow(d)) stop("Empty frozen table: ", sheet, call. = FALSE)
  rownames(d) <- NULL
  d
}
require_columns <- function(d, fields, context) {
  absent <- setdiff(fields, names(d))
  if (length(absent)) stop(context, ": missing columns ",
                           paste(absent, collapse = ", "), call. = FALSE)
  invisible(d)
}
numeric_columns <- function(d, fields, context, allow_na = FALSE) {
  require_columns(d, fields, context)
  for (field in fields) {
    raw <- d[[field]]
    value <- suppressWarnings(as.numeric(raw))
    missing <- is.na(raw) | trimws(as.character(raw)) %in% c("", "NA", "NaN")
    if (any(!missing & !is.finite(value)) || (!allow_na && any(!is.finite(value)))) {
      stop(context, ": missing/non-numeric value in ", field, call. = FALSE)
    }
    d[[field]] <- value
  }
  d
}
check_grid <- function(d, levels, context) {
  require_columns(d, names(levels), context)
  expected <- do.call(expand.grid, c(levels, stringsAsFactors = FALSE))
  key <- function(x) do.call(paste, c(x[names(levels)], sep = "|"))
  observed <- key(d)
  if (anyDuplicated(observed) || !setequal(observed, key(expected))) {
    stop(context, ": incomplete, duplicated, or unexpected frozen-result keys.",
         call. = FALSE)
  }
  invisible(d)
}
check_ci <- function(d, context) {
  if (any(!is.finite(d$estimate) | !is.finite(d$lower) | !is.finite(d$upper)) ||
      any(d$lower > d$upper)) {
    stop(context, ": required estimate/95% CI is missing or invalid.", call. = FALSE)
  }
  invisible(d)
}
interval_frame <- function(d, estimate, lower, upper, multiplier = 1) {
  d$estimate <- d[[estimate]] * multiplier
  d$lower <- d[[lower]] * multiplier
  d$upper <- d[[upper]] * multiplier
  d
}

master_path <- formal_file("FINAL_RESULTS_MASTER.xlsx", master = TRUE)
flow <- read_block(master_path, "Cohorts", 4L, 4L)
flow <- numeric_columns(flow, c("n_before", "n_excluded", "n_after"), "Cohorts")
require_columns(flow, "step", "Cohorts")
flow$id <- substr(flow$step, 1L, 2L)
flow_ids <- c("01", "03", "04", "06", "07", "08", "09", "11")
if (anyDuplicated(flow$id) || !all(flow_ids %in% flow$id)) {
  stop("Cohorts: the required S1 derivation steps are unavailable.", call. = FALSE)
}
flow <- flow[match(flow_ids, flow$id), , drop = FALSE]
burden <- read_block(master_path, "Dynamic_Burden", 4L)
burden <- numeric_columns(burden, c("LM", "CR_n"), "Dynamic_Burden")
check_grid(burden, list(LM = 0:5), "Dynamic_Burden")
life <- read_block(master_path, "LifeTable", 4L)
life <- numeric_columns(life, c("LM", "n"), "LifeTable")
check_grid(life, list(LM = 0:5), "LifeTable")

targets <- c("T", "N", "Grade")
models <- c("A", "B", "C_FULL")
causes <- c("GBC", "Other", "All_death")
cause_labels <- c(GBC = "GBC death", Other = "Other-cause death",
                  All_death = "All-cause death")
contrast_labels <- c(T = "T3/4 vs T1", N = "N+ vs N0", Grade = "G3/4 vs G1")
crude <- read_block(master_path, "Crude_Contrasts", 4L)
crude <- numeric_columns(crude, c("LM", "\u0394CIF", "L95", "U95"), "Crude_Contrasts")
check_grid(crude, list(Predictor = targets, LM = 0:5), "Crude_Contrasts")
crude <- interval_frame(crude, "\u0394CIF", "L95", "U95", 100)
check_ci(crude, "Crude_Contrasts")

standard_path <- formal_file("STANDARDIZATION_RESULTS.xlsx")
read_standard <- function(sheet, horizon) {
  d <- read_block(standard_path, sheet, 5L)
  require_columns(d, c("target", "cause", "support_status", "result_status"), sheet)
  fields <- c("landmark", "horizon_years", "delta_CIF", "delta_CIF_lower95",
              "delta_CIF_upper95", "delta_CIF_valid_fraction", "delta_RMTL_months",
              "delta_RMTL_months_lower95", "delta_RMTL_months_upper95",
              "delta_RMTL_months_valid_fraction")
  d <- numeric_columns(d, fields, sheet, allow_na = TRUE)
  d <- d[which(d$cause == "GBC" & d$horizon_years == horizon), , drop = FALSE]
  check_grid(d, list(target = targets, landmark = 0:5), sheet)
  if (anyNA(d$support_status) ||
      !all(d$support_status %in% c("PASS", "LIMITED", "FAIL"))) {
    stop(sheet, ": unknown common-support status.", call. = FALSE)
  }
  make_metric <- function(name, prefix, multiplier) {
    z <- interval_frame(d, prefix, paste0(prefix, "_lower95"),
                        paste0(prefix, "_upper95"), multiplier)
    z$metric <- name
    z$valid <- z[[paste0(prefix, "_valid_fraction")]]
    if (any(!is.finite(z$valid) | z$valid < 0 | z$valid > 1)) {
      stop(sheet, ": invalid metric-specific bootstrap validity fraction.", call. = FALSE)
    }
    z$reportable <- z$support_status != "FAIL" & z$valid >= 0.95
    z$point_only <- z$support_status != "FAIL" & z$valid < 0.95
    check_ci(z[z$reportable, , drop = FALSE], paste(sheet, name))
    if (any(z$point_only & !is.finite(z$estimate))) {
      stop(sheet, ": a supported point-only result has no frozen estimate.", call. = FALSE)
    }
    if (any(z$reportable & z$result_status != "OK", na.rm = TRUE)) {
      stop(sheet, ": CI validity and formal result status disagree.", call. = FALSE)
    }
    z
  }
  rbind(make_metric("CIF", "delta_CIF", 100),
        make_metric("RMTL", "delta_RMTL_months", 1))
}
standard3 <- read_standard("standardized_contrasts", 3)
grade_main <- standard3[standard3$target == "Grade" & standard3$metric == "CIF", ]
support <- read_block(standard_path, "support", 5L)
support <- numeric_columns(support, c("landmark", "coverage", "reference_n", "supported_n"), "support")
check_grid(support, list(target = targets, landmark = 0:5), "support")
expected_status <- ifelse(support$coverage >= .90, "PASS",
                          ifelse(support$coverage >= .70, "LIMITED", "FAIL"))
stopifnot(all(support$status == expected_status),
          all(abs(support$coverage - support$supported_n / support$reference_n) < 1e-10))

recalibration_path <- formal_file("RECALIBRATION_RESULTS.xlsx")
evaluation_eras <- c("POST_2015_2017_ORIGINAL", "POST_2015_2017_UPDATED")
evaluation_states <- c("ORIGINAL", "UPDATED")
read_evaluation <- function(sheet, metric = "Brier") {
  d <- read_block(recalibration_path, sheet, 5L)
  require_columns(d, c("era", "status", "analysis", "model", "cause", "landmark", "n"), sheet)
  d <- d[which(d$analysis == "primary" & d$era %in% evaluation_eras), , drop = FALSE]
  if (sheet == "performance") {
    require_columns(d, "metric", sheet)
    d <- d[which(d$metric == metric), , drop = FALSE]
  }
  d <- numeric_columns(d, c("landmark", "n"), sheet)
  check_grid(d, list(model = models, cause = causes, landmark = 1:3,
                     status = evaluation_states), paste(sheet, "2015-2017 evaluation"))
  if (anyNA(d$status) || any(d$era != evaluation_eras[match(d$status, evaluation_states)])) {
    stop(sheet, ": evaluation era/state mismatch.", call. = FALSE)
  }
  original <- d[d$status == "ORIGINAL", c("model", "cause", "landmark", "n")]
  updated <- d[d$status == "UPDATED", c("model", "cause", "landmark", "n")]
  paired_n <- merge(original, updated, by = c("model", "cause", "landmark"),
                     suffixes = c("_original", "_updated"))
  if (any(paired_n$n_original != paired_n$n_updated)) {
    stop(sheet, ": original and updated evaluation counts differ.", call. = FALSE)
  }
  d
}
evaluation_calibration <- read_evaluation("calibration")
evaluation_calibration <- numeric_columns(evaluation_calibration,
  c("O_over_E", "O_over_E_lower95", "O_over_E_upper95"), "evaluation calibration")
evaluation_oe <- interval_frame(evaluation_calibration, "O_over_E",
                                "O_over_E_lower95", "O_over_E_upper95")
check_ci(evaluation_oe, "eFigure 2B original/updated O/E")

evaluation_calibration <- numeric_columns(evaluation_calibration,
  c("abs_O_minus_E_pp", "O_minus_E_pp"), "evaluation errors")
evaluation_auc <- numeric_columns(read_evaluation("performance", "AUC2"),
  c("estimate", "lower95", "upper95"), "evaluation AUC")
evaluation_brier <- numeric_columns(read_evaluation("performance", "Brier"),
  c("estimate", "lower95", "upper95"), "evaluation Brier")
keys <- c("model", "cause", "landmark", "status")
evaluation <- merge(evaluation_calibration,
  setNames(evaluation_auc[c(keys, "estimate")], c(keys, "AUC")), by = keys)
evaluation <- merge(evaluation,
  setNames(evaluation_brier[c(keys, "estimate")], c(keys, "Brier")), by = keys)
check_grid(evaluation, list(model = models, cause = causes, landmark = 1:3,
                            status = evaluation_states), "evaluation plane")


# Figure 3 reads the already frozen group-specific CIF display table.
# This output-only entry point never reads patient records or estimates CIF.
if (full_figure_run) {
  group_path <- Sys.getenv("GBC_FIGURE3_SOURCE", unset =
    file.path(PROJECT_ROOT, "JNO_Figures", "source_data", "Figure3_Group_CIF.csv"))
  if (!file.exists(group_path)) stop("Missing frozen Figure 3 group-CIF table.")
  group_cif <- utils::read.csv(group_path, check.names = FALSE, stringsAsFactors = FALSE)
  require_columns(group_cif, c("Predictor", "Group", "Landmark", "n_at_landmark",
                               "3y_GBC_CIF", "contrast_check"), "Figure 3 source")
  names(group_cif)[names(group_cif) == "3y_GBC_CIF"] <- "CIF"
  group_cif <- numeric_columns(group_cif, c("Landmark", "n_at_landmark", "CIF"), "Figure 3 source")
  group_spec <- list(T = c("T1", "T3/4"), N = c("N0", "N+"), Grade = c("G1", "G3/4"))
  stopifnot(nrow(group_cif) == 36L, all(group_cif$CIF >= 0 & group_cif$CIF <= 1),
            all(group_cif$contrast_check == "PASS"),
            setequal(group_cif$Predictor, targets))
  for (target in targets)
    check_grid(group_cif[group_cif$Predictor == target, ],
               list(Group = group_spec[[target]], Landmark = 0:5), "Figure 3 source")
}

font_family <- "Arial"
ink <- "#33363A"
population_ink <- "#858780"
reference_ink <- "#D2D3D1"
axis_ink <- "#797D80"
cause_colours <- c(GBC = "#A34E5D", Other = "#5B7F9A")
cause_shapes <- c(GBC = 16, Other = 0)
pathology_colours <- c(T = ink, N = "#70777C", Grade = cause_colours[["GBC"]])
pathology_shapes <- c(T = 16, N = 0, Grade = 2)
model_shapes <- c(A = 21, B = 22, C_FULL = 24)
model_offsets <- c(A = -0.17, B = 0, C_FULL = 0.17)
support_colours <- c(PASS = "#858780", LIMITED = "#D9DAD7", FAIL = "#FFFFFF")
point_size <- 1.7
point_stroke <- 0.55
ci_width <- 0.14
ci_linewidth <- 0.25

theme_jno <- function() {
  theme_classic(base_size = 8, base_family = font_family) +
    theme(text = element_text(colour = ink),
          axis.text = element_text(size = 7.5, colour = ink),
          axis.title = element_text(size = 8, face = "plain"),
          axis.line = element_line(colour = axis_ink, linewidth = 0.25),
          axis.ticks = element_line(colour = axis_ink, linewidth = 0.25),
          axis.ticks.length = grid::unit(1.2, "mm"),
          plot.title = element_text(size = 9, face = "plain", hjust = 0,
                                    margin = margin(b = 3)),
          plot.title.position = "plot",
          plot.tag = element_text(size = 10, face = "bold", family = font_family),
          plot.tag.position = "topleft",
          legend.position = "bottom", legend.direction = "horizontal",
          legend.justification = "center",
          legend.title = element_text(size = 7.5, face = "plain"),
          legend.text = element_text(size = 7.5),
          legend.key.width = grid::unit(6, "mm"),
          legend.key.height = grid::unit(2.5, "mm"),
          legend.key.spacing.x = grid::unit(3, "mm"),
          legend.margin = margin(0, 0, 0, 0),
          legend.box.spacing = grid::unit(0.7, "mm"),
          strip.background = element_blank(),
          strip.text = element_text(size = 7.5, face = "plain", colour = ink),
          panel.spacing = grid::unit(3, "mm"),
          panel.grid = element_blank(),
          panel.background = element_rect(fill = "white", colour = NA),
          plot.background = element_rect(fill = "white", colour = NA),
          plot.margin = margin(3, 5, 3, 4))
}
lm_axis <- function(last = 5L) {
  scale_x_continuous(breaks = 0:last, labels = paste0("L", 0:last),
                     limits = c(-0.5, last + 0.5), expand = expansion(mult = 0))
}
zero_horizontal <- function() geom_hline(yintercept = 0, colour = reference_ink, linewidth = 0.25)
zero_vertical <- function() geom_vline(xintercept = 0, colour = reference_ink, linewidth = 0.25)
model_scale <- function() {
  scale_shape_manual(name = "Model", values = model_shapes, breaks = models,
                     labels = c("A", "B", "C"), drop = FALSE)
}
vertical_ci <- function(...) {
  geom_errorbar(aes(ymin = lower, ymax = upper), width = ci_width,
                linewidth = ci_linewidth, ...)
}
horizontal_ci <- function(...) {
  geom_errorbar(aes(xmin = lower, xmax = upper), orientation = "y",
                width = ci_width, linewidth = ci_linewidth, ...)
}
combine_panels <- function(plots, ncol, widths = NULL) {
  wrap_plots(plots, ncol = ncol, widths = widths, guides = "collect") +
    plot_annotation(tag_levels = "A", theme = theme_jno()) &
    theme(legend.position = "bottom")
}
plot_limits <- function(d, reference = 0, pad = 0.07) {
  r <- range(c(d$estimate, d$lower, d$upper, reference), finite = TRUE)
  span <- diff(r)
  if (!is.finite(span) || span == 0) span <- 1
  r + c(-1, 1) * span * pad
}

if (full_figure_run) {
count_label <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
flow$y <- 8:1
flow_labels <- c("Malignant gallbladder tumors", "Age \u226518 y",
                 "Adenocarcinoma, 8140/3", "Positive histologic confirmation",
                 "Primary under international rules", "Strict resection",
                 "Explicit harmonized M0", "Valid competing-risk cause of death")
flow$label <- paste0(flow_labels, "\nn = ", count_label(flow$n_after))
flow_links <- data.frame(y = 8:2 - 0.33, yend = 7:1 + 0.33,
                         excluded = flow$n_excluded[-1L])
p1a <- ggplot() +
  geom_rect(data = flow, aes(xmin = 0, xmax = 0.76, ymin = y - 0.33, ymax = y + 0.33),
            fill = "white", colour = axis_ink, linewidth = 0.25) +
  geom_segment(data = flow_links, aes(x = 0.38, xend = 0.38, y = y, yend = yend),
               colour = axis_ink, linewidth = 0.25,
               arrow = grid::arrow(length = grid::unit(1.2, "mm"), type = "closed")) +
  geom_segment(data = flow_links, aes(x = 0.38, xend = 0.80,
                                     y = (y + yend) / 2, yend = (y + yend) / 2),
               colour = axis_ink, linewidth = 0.25) +
  geom_text(data = flow, aes(x = 0.38, y = y, label = label),
            family = font_family, size = 7.5 / ggplot2::.pt, lineheight = 0.95, colour = ink) +
  geom_text(data = flow_links,
            aes(x = 0.81, y = (y + yend) / 2,
                label = paste0("Excluded\nn = ", count_label(excluded))),
            hjust = 0, family = font_family, size = 7 / ggplot2::.pt,
            lineheight = 0.95, colour = ink) +
  coord_cartesian(xlim = c(-0.02, 1.10), ylim = c(0.60, 8.4), expand = FALSE, clip = "off") +
  labs(title = "Cohort derivation") + theme_jno() +
  theme(axis.line = element_blank(), axis.ticks = element_blank(),
        axis.text = element_blank(), axis.title = element_blank())
get_count <- function(d, field, lm) d[[field]][match(lm, d$LM)]
tracks <- data.frame(
  start = c(2004, 2004, 2004, 2012, 2012, 2015, 2004),
  end = c(2023, 2015, 2011, 2017, 2014, 2017, 2015),
  y = 7:1, colour = c(ink, ink, rep("#6D7E89", 4), population_ink),
  label = c(
    paste0("Competing-risk source cohort\nn = ", count_label(tail(flow$n_after, 1))),
    paste0("Dynamic survivorship analyses\nL0 n = ", count_label(get_count(burden, "CR_n", 0)),
           "; L5 n = ", count_label(get_count(burden, "CR_n", 5))),
    "Prediction development", "Temporal validation", "Baseline-hazard updating",
    "Updating evaluation period",
    paste0("General-population RMST benchmark\nAge <90 y; L0 n = ",
           count_label(get_count(life, "n", 0)), "; L5 n = ", count_label(get_count(life, "n", 5)))))
p1b <- ggplot(tracks) +
  geom_segment(aes(x = start, xend = end, y = y - 0.27, yend = y - 0.27, colour = colour),
               linewidth = 0.65, lineend = "butt") +
  geom_point(aes(x = start, y = y - 0.27, colour = colour), size = 0.8) +
  geom_point(aes(x = end, y = y - 0.27, colour = colour), size = 0.8) +
  geom_text(aes(x = 2004, y = y + 0.15, label = label),
            hjust = 0, family = font_family, size = 7.5 / ggplot2::.pt,
            lineheight = 0.98, colour = ink) +
  scale_colour_identity() +
  scale_x_continuous(breaks = c(2004, 2008, 2012, 2016, 2020, 2023),
                     expand = expansion(mult = 0)) +
  coord_cartesian(xlim = c(2003.6, 2023.7), ylim = c(0.45, 7.6), clip = "off") +
  labs(title = "Analytic architecture", x = "Year of diagnosis", y = NULL) +
  theme_jno() + theme(axis.text.y = element_blank(), axis.ticks.y = element_blank(),
                      axis.line.y = element_blank())
figure1 <- combine_panels(list(p1a, p1b), 2, widths = c(1.05, 1))


}

if (full_figure_run) {
group_cif$Predictor <- factor(group_cif$Predictor, levels = targets)
group_cif$risk_group <- ifelse(
  group_cif$Group %in% c("T3/4", "N+", "G3/4"), "Higher category", "Reference")
group_cif$risk_group <- factor(group_cif$risk_group,
                              levels = c("Higher category", "Reference"))
bands <- merge(group_cif[group_cif$risk_group == "Higher category",
                         c("Predictor", "Landmark", "CIF")],
               group_cif[group_cif$risk_group == "Reference",
                         c("Predictor", "Landmark", "CIF")],
               by = c("Predictor", "Landmark"), suffixes = c("_high", "_low"))
cif_ceiling <- ceiling(max(group_cif$CIF) * 10) * 10
p3a <- ggplot(group_cif, aes(Landmark, CIF * 100)) +
  geom_ribbon(data = bands,
    aes(x = Landmark, ymin = CIF_low * 100, ymax = CIF_high * 100),
    inherit.aes = FALSE, fill = cause_colours[["GBC"]], alpha = .10) +
  geom_line(aes(colour = risk_group, linewidth = risk_group, group = risk_group)) +
  geom_point(aes(colour = risk_group, fill = risk_group), shape = 21,
             size = 1.5, stroke = .45) +
  scale_colour_manual(NULL, values = c("Higher category" = cause_colours[["GBC"]],
                                       Reference = ink)) +
  scale_fill_manual(NULL, values = c("Higher category" = cause_colours[["GBC"]],
                                     Reference = "white")) +
  scale_linewidth_manual(values = c("Higher category" = .50, Reference = .35), guide = "none") +
  facet_wrap(~Predictor, nrow = 1, labeller = as_labeller(
    c(T = "T\nT3/4 vs T1", N = "N\nN+ vs N0", Grade = "Grade\nG3/4 vs G1"))) +
  lm_axis() + scale_y_continuous(limits = c(0, cif_ceiling),
                                breaks = seq(0, cif_ceiling, 20), expand = expansion(mult = c(0, .03))) +
  labs(title = "Group-specific risk separation", x = "Survivorship landmark",
       y = "3-year GBC cumulative incidence, %") + theme_jno() +
  theme(panel.spacing.x = grid::unit(2.5, "mm"), legend.key.width = grid::unit(4, "mm"))

grade_main$y <- 5 - grade_main$landmark
grade_supported <- grade_main[grade_main$support_status != "FAIL", ]
p3b <- ggplot(grade_main, aes(estimate, y)) + zero_vertical() +
  geom_segment(data = grade_supported, aes(x = 0, xend = estimate, yend = y),
               colour = "#B4B6B7", linewidth = .35) +
  horizontal_ci(data = grade_main[grade_main$reportable, ], colour = cause_colours[["GBC"]]) +
  geom_point(data = grade_supported, aes(fill = support_status),
             shape = 21, colour = cause_colours[["GBC"]], size = 2, stroke = .55) +
  scale_fill_manual(NULL, values = c(PASS = cause_colours[["GBC"]], LIMITED = "white"),
                    breaks = c("PASS", "LIMITED"), drop = FALSE) +
  geom_text(data = grade_main[grade_main$point_only, ],
            aes(label = "a"), nudge_y = .15, hjust = -.8,
            size = 6 / ggplot2::.pt, family = font_family) +
  geom_text(data = grade_main[grade_main$support_status == "FAIL", ],
    aes(x = 0, label = "\u2014"), colour = "#B8BBBD", family = font_family,
    size = 8 / ggplot2::.pt) +
  scale_y_continuous(breaks = 5:0, labels = paste0("L", 0:5),
                     limits = c(-.45, 5.45), expand = expansion(mult = 0)) +
  scale_x_continuous(breaks = scales::breaks_pretty(n = 3)) +
  labs(title = "Standardized grade contrast",
       x = "Difference in 3-year GBC CIF,\npercentage points", y = NULL) + theme_jno()
if (any(grade_main$support_status == "FAIL")) {
  p3b <- p3b + annotate("text", x = max(grade_supported$upper, na.rm = TRUE),
    y = min(grade_main$y[grade_main$support_status == "FAIL"]),
    label = "Insufficient\ncommon support", hjust = 1, colour = population_ink,
    size = 6.5 / ggplot2::.pt, family = font_family)
}
figure3 <- wrap_plots(p3a, p3b, widths = c(.68, .32), guides = "keep") +
  plot_annotation(tag_levels = "A", theme = theme_jno())

}

lm_tones <- c(L1 = "#424A50", L2 = "#7E878C", L3 = "#ABB1B4")
model_colours <- c(A = ink, B = cause_colours[["Other"]], C_FULL = cause_colours[["GBC"]])
evaluation$LM_label <- factor(paste0("L", evaluation$landmark), levels = names(lm_tones))
evaluation$model <- factor(evaluation$model, levels = models)
evaluation$cause <- factor(evaluation$cause, levels = causes)
paired_states <- function(d, x, y) {
  fields <- c("model", "cause", "landmark", "LM_label", x, y)
  merge(d[d$status == "ORIGINAL", fields], d[d$status == "UPDATED", fields],
        by = c("model", "cause", "landmark", "LM_label"), suffixes = c("_original", "_updated"))
}
all_evaluation <- evaluation[evaluation$cause == "All_death", ]
arrow_data <- paired_states(all_evaluation, "abs_O_minus_E_pp", "AUC")
arrow_fraction <- .75
arrow_data$x_arrow <- with(arrow_data,
  abs_O_minus_E_pp_original + arrow_fraction * (abs_O_minus_E_pp_updated - abs_O_minus_E_pp_original))
arrow_data$y_arrow <- with(arrow_data,
  AUC_original + arrow_fraction * (AUC_updated - AUC_original))
stopifnot(nrow(arrow_data) == 9L)
endpoint_labels <- data.frame(x = all_evaluation$abs_O_minus_E_pp,
  y = all_evaluation$AUC, model = all_evaluation$model,
  label = ifelse(all_evaluation$status == "UPDATED", as.character(all_evaluation$LM_label), ""))
endpoint_labels <- rbind(endpoint_labels, data.frame(x = arrow_data$x_arrow,
  y = arrow_data$y_arrow, model = arrow_data$model, label = ""))
label_nudge_y <- ifelse(endpoint_labels$model == "C_FULL" & endpoint_labels$label == "L3", .004, 0)
p4a <- ggplot(all_evaluation, aes(abs_O_minus_E_pp, AUC)) +
  geom_vline(xintercept = 0, colour = reference_ink, linewidth = .25) +
  geom_segment(data = arrow_data, inherit.aes = FALSE,
    aes(x = abs_O_minus_E_pp_original, xend = x_arrow,
        y = AUC_original, yend = y_arrow, colour = model),
    linewidth = .35, show.legend = FALSE,
    arrow = grid::arrow(length = grid::unit(1.5, "mm"), type = "open", angle = 25)) +
  geom_point(data = all_evaluation[all_evaluation$status == "ORIGINAL", ],
    aes(shape = model, colour = model), fill = "white", size = 1.8, stroke = .45) +
  geom_point(data = all_evaluation[all_evaluation$status == "UPDATED", ],
    aes(shape = model, colour = model, fill = model), size = 1.8, stroke = .45) +
  ggrepel::geom_text_repel(data = endpoint_labels, inherit.aes = FALSE,
    aes(x = x, y = y, label = label, colour = model), family = font_family, size = 10.2 / ggplot2::.pt,
    seed = 42, max.overlaps = Inf, max.time = 3, max.iter = 20000,
    box.padding = .3, point.padding = .3, min.segment.length = Inf,
    xlim = c(0, NA), nudge_x = .16, nudge_y = label_nudge_y, show.legend = FALSE) +
  model_scale() +
  scale_colour_manual("Model", values = model_colours, breaks = models, labels = c("A", "B", "C")) +
  scale_fill_manual(values = model_colours, guide = "none") +
  scale_x_continuous(limits = c(0, NA), expand = expansion(mult = c(.04, .08))) +
  scale_y_continuous(labels = scales::label_number(accuracy = .01)) +
  labs(title = "Calibration and discrimination",
       x = "Absolute O\u2212E error, percentage points", y = "3-year all-cause AUC") + theme_jno()
all_evaluation$state <- factor(all_evaluation$status, levels = evaluation_states,
                               labels = c("Original", "Updated"))
p4b_model_offsets <- c(A = -.16, B = 0, C_FULL = .16)
all_evaluation$state_x <- as.numeric(all_evaluation$state) +
  unname(p4b_model_offsets[as.character(all_evaluation$model)])
p4b <- ggplot(all_evaluation, aes(state_x, O_over_E, group = model)) +
  geom_hline(yintercept = 1, colour = reference_ink, linewidth = .25) +
  geom_line(aes(colour = model), linewidth = .35) +
  geom_point(data = all_evaluation[all_evaluation$status == "ORIGINAL", ],
    aes(shape = model, colour = model), fill = "white", size = 1.9, stroke = .5) +
  geom_point(data = all_evaluation[all_evaluation$status == "UPDATED", ],
    aes(shape = model, colour = model, fill = model), size = 1.9, stroke = .5) +
  model_scale() + scale_colour_manual(values = model_colours, guide = "none") +
  scale_fill_manual(values = model_colours, guide = "none") +
  facet_wrap(~LM_label, nrow = 1) +
  scale_x_continuous(breaks = c(1, 2), labels = c("Original", "Updated"),
                     limits = c(.68, 2.32), expand = expansion(mult = 0)) +
  labs(title = "Observed-to-expected updating", x = NULL, y = "Observed-to-expected ratio") +
  theme_jno() + theme(panel.spacing.x = grid::unit(2, "mm")) +
  guides(colour = "none", shape = "none", fill = "none")


{
rmtl <- standard3[standard3$metric == "RMTL", ]
rmtl$target <- factor(rmtl$target, levels = targets)
rmtl$y <- 5 - rmtl$landmark
rmtl$LM_label <- factor(paste0("L", rmtl$landmark), levels = paste0("L", 0:5))
rmtl_tones <- setNames(c("#763E48", "#91535E", "#A46C75", "#B88990", "#CAABB0", "#DBC5C8"),
                       paste0("L", 0:5))
e1a <- ggplot(rmtl, aes(estimate, y, colour = LM_label)) + zero_vertical() +
  horizontal_ci(data = rmtl[rmtl$reportable, ], show.legend = FALSE) +
  geom_point(data = rmtl[rmtl$support_status != "FAIL", ], aes(fill = support_status),
             shape = 21, size = 1.9, stroke = .5, show.legend = FALSE) +
  scale_fill_manual(values = c(PASS = cause_colours[["GBC"]], LIMITED = "white"), guide = "none") +
  scale_colour_manual(values = rmtl_tones, guide = "none") +
  geom_text(data = rmtl[rmtl$support_status == "FAIL", ],
    aes(x = 0, label = "\u2014"), hjust = 1.6, colour = "#B8BBBD", family = font_family, size = 10.2 / ggplot2::.pt) +
  geom_text(data = rmtl[rmtl$point_only, ], aes(label = "a"), nudge_y = .14, hjust = -.6,
             colour = ink, size = 10.1 / ggplot2::.pt, family = font_family) +
  facet_wrap(~target, ncol = 1, labeller = as_labeller(contrast_labels)) +
  scale_y_continuous(breaks = 5:0, labels = paste0("L", 0:5), limits = c(-.45, 5.45)) +
  labs(title = "Standardized RMTL contrasts",
       x = "GBC RMTL difference, mo", y = NULL) + theme_jno()
support$target <- factor(support$target, levels = targets)
e1b <- ggplot(support, aes(landmark, coverage * 100)) +
  geom_hline(yintercept = c(70, 90), colour = "#D2D3D1", linewidth = .25) +
  geom_step(direction = "hv", colour = cause_colours[["GBC"]], linewidth = .45) +
  geom_point(aes(fill = status), shape = 21, size = 1.8,
             colour = cause_colours[["GBC"]], stroke = .45) +
  scale_fill_manual("Support", values = c(PASS = cause_colours[["GBC"]],
                     LIMITED = "white", FAIL = "#D7DADD"),
                     breaks = c("PASS", "LIMITED", "FAIL")) +
  facet_wrap(~target, ncol = 1, labeller = as_labeller(contrast_labels)) +
  lm_axis() + scale_y_continuous(limits = c(0, 102), breaks = c(0, 70, 90, 100)) +
  labs(title = "Common-support retention", x = "Survivorship landmark", y = "Coverage, %") +
  theme_jno()
efigure1 <- combine_panels(list(e1a, e1b), 2, widths = c(1.12, 1))

}

output_root <- Sys.getenv("GBC_SUBMISSION_OUTPUT", unset = file.path(PROJECT_ROOT, "submission"))
main_dir <- file.path(output_root, "Main")
supp_dir <- file.path(output_root, "Supplement")
dir.create(main_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(supp_dir, recursive = TRUE, showWarnings = FALSE)
draw_to_device <- function(plot, open_device) {
  open_device()
  on.exit(grDevices::dev.off(), add = TRUE)
  print(plot)
  invisible(NULL)
}
save_main_figure <- function(plot, number, height_mm) {
  if (!number %in% c(1L, 3L)) stop("This script exports only main Figures 1 and 3.")
  prefix <- file.path(main_dir, paste0("Figure", number))
  draw_to_device(plot, function() grDevices::cairo_pdf(
    paste0(prefix, "_Final.pdf"), width = 180 / 25.4, height = height_mm / 25.4,
    family = font_family, bg = "white"))
  draw_to_device(plot, function() ragg::agg_tiff(
    paste0(prefix, "_Final.tiff"), width = 180, height = height_mm, units = "mm",
    res = 600, background = "white", compression = "lzw", bitsize = 8))
  draw_to_device(plot, function() ragg::agg_png(
    paste0(prefix, "_preview.png"), width = 180, height = height_mm, units = "mm",
    res = 300, background = "white", bitsize = 8))
}
# Enforce the font floor for both theme text and explicit text geoms.
supp_theme <- theme(text = element_text(family = "Arial", size = 10.2),
  axis.text = element_text(family = "Arial", size = 10.2),
  axis.title = element_text(family = "Arial", size = 10.2),
  strip.text = element_text(family = "Arial", size = 10.2),
  plot.title = element_text(family = "Arial", size = 10.2),
  legend.text = element_text(family = "Arial", size = 10.2),
  legend.title = element_text(family = "Arial", size = 10.2),
  plot.tag = element_text(family = "Arial", size = 12, face = "bold"),
  panel.spacing.y = grid::unit(6, "mm"), plot.margin = margin(4, 6, 4, 4))
supp_panel <- function(p) {
  for (i in seq_along(p$layers)) {
    if (inherits(p$layers[[i]]$geom, c("GeomText", "GeomTextRepel"))) {
      p$layers[[i]]$aes_params$size <- 10.2 / ggplot2::.pt
      p$layers[[i]]$aes_params$family <- "Arial"
    }
  }
  p + supp_theme
}
efigure1 <- combine_panels(lapply(list(e1a, e1b), supp_panel), 2,
                           widths = c(1.12, 1)) & supp_theme
efigure2 <- combine_panels(lapply(list(p4a, p4b), supp_panel), 2,
                           widths = c(1, 1.05)) & supp_theme
save_supp_figure <- function(plot, number, width_mm, height_mm) {
  if (!number %in% 1:2) stop("Unexpected supplementary figure number.")
  prefix <- file.path(supp_dir, paste0("eFigure", number))
  draw_to_device(plot, function() grDevices::cairo_pdf(
    paste0(prefix, ".pdf"), width = width_mm / 25.4, height = height_mm / 25.4,
    family = font_family, bg = "white"))
  draw_to_device(plot, function() ragg::agg_png(
    paste0(prefix, "_preview.png"), width = width_mm, height = height_mm, units = "mm",
    res = 300, background = "white", bitsize = 8))
}
save_supp_figure(efigure1, 1L, 170, 215)
save_supp_figure(efigure2, 2L, 258, 160)
if (full_figure_run) {
  save_main_figure(figure1, 1L, 120)
  save_main_figure(figure3, 3L, 95)
  sys.source(file.path(Sys.getenv("GBC_CODE_ROOT", getwd()), "R/10_figures/figure2.R"),
             envir = new.env(parent = globalenv()))
}
cat("Completed final submission figure set: ", figure_set, ".\n", sep = "")

