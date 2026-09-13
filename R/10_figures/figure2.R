# Publication source copy. See docs/original_script_mapping.md and reproducibility_notes.md.
PROJECT_ROOT <- Sys.getenv("GBC_FINAL_RUN_ROOT", unset = getwd())

local({
  packages <- c("ggplot2", "patchwork", "readxl", "scales", "ragg")
  minimum <- c(ggplot2 = "3.5.2", patchwork = "1.3.2")
  installed_version <- function(p) {
    location <- find.package(p, quiet = TRUE)
    if (!length(location) || !nzchar(location[1L])) return(NA_character_)
    as.character(utils::packageVersion(p))
  }
  versions <- setNames(vapply(packages, installed_version, character(1)), packages)
  missing <- packages[vapply(packages, function(p)
    is.na(versions[[p]]) || (p %in% names(minimum) &&
      utils::compareVersion(versions[[p]], minimum[[p]]) < 0L), logical(1))]
  stale <- names(minimum)[vapply(names(minimum), function(p)
    p %in% loadedNamespaces() &&
      utils::compareVersion(as.character(getNamespaceVersion(p)), minimum[[p]]) < 0L,
    logical(1))]
  if (length(stale) || any(missing %in% loadedNamespaces()))
    stop("Restart R first (RStudio: Ctrl+Shift+F10), then source Figure2.R again. Old plotting packages are still loaded.")
  if (length(missing)) stop("Install required plotting packages in a clean R session: ", paste(missing, collapse = ", "))
  for (p in names(minimum)) {
    v <- installed_version(p)
    if (is.na(v) || utils::compareVersion(v, minimum[[p]]) < 0L)
      stop("Package update did not complete: ", p, " >= ", minimum[[p]], " is required.")
  }
  for (p in packages) suppressPackageStartupMessages(library(p, character.only = TRUE))
  if (!capabilities("cairo")) stop("This R installation needs Cairo PDF support.")

  master <- file.path(PROJECT_ROOT, "FINAL_RESULTS_MASTER.xlsx")
  source_file <- function(name) {
    paths <- file.path(PROJECT_ROOT, c("outputs", "outputs/TABLES_INPUTS_REQUIRED"), name)
    found <- paths[file.exists(paths)]
    if (!length(found)) stop("Missing formal result file: ", name)
    found[1L]
  }
  clean <- function(x) gsub("[^a-z0-9]", "", tolower(trimws(x)))
  read_table <- function(path, preferred, keys, optional = FALSE) {
    if (!file.exists(path)) {
      if (optional) return(NULL)
      stop("Missing workbook: ", path)
    }
    sheets <- readxl::excel_sheets(path)
    sheets <- unique(c(intersect(preferred, sheets), sheets))
    for (sheet in sheets) {
      top <- suppressMessages(readxl::read_excel(path, sheet = sheet,
        col_names = FALSE, col_types = "text", n_max = 12, .name_repair = "minimal"))
      hits <- which(vapply(seq_len(nrow(top)), function(i)
        all(clean(keys) %in% clean(unlist(top[i, ], use.names = FALSE))), logical(1)))
      if (!length(hits)) next
      z <- suppressMessages(readxl::read_excel(path, sheet = sheet,
        skip = hits[1L] - 1L, col_types = "text", .name_repair = "minimal"))
      blank <- which(vapply(seq_len(nrow(z)), function(i)
        all(is.na(unlist(z[i, ], use.names = FALSE))), logical(1)))
      if (length(blank)) z <- z[seq_len(blank[1L] - 1L), , drop = FALSE]
      names(z) <- clean(names(z))
      return(as.data.frame(z, stringsAsFactors = FALSE))
    }
    if (optional) return(NULL)
    stop("Required columns not found in ", basename(path), ": ", paste(keys, collapse = ", "))
  }
  num <- function(z, field) {
    if (is.null(z) || !clean(field) %in% names(z)) return(rep(NA_real_, NROW(z)))
    suppressWarnings(as.numeric(z[[clean(field)]]))
  }
  by_lm <- function(z, field = "LM") {
    lm <- num(z, field)
    z <- z[!is.na(lm) & lm %in% 0:5, , drop = FALSE]
    lm <- num(z, field)
    if (anyDuplicated(lm)) stop("Duplicate landmark rows in a selected result table.")
    z[match(0:5, lm), , drop = FALSE]
  }
  d <- data.frame(LM = 0:5)
  put <- function(target, value) {
    if (length(value) != 6L) stop("Incomplete six-landmark result: ", target)
    if (!target %in% names(d)) d[[target]] <<- rep(NA_real_, 6L)
    use <- is.na(d[[target]])
    d[[target]][use] <<- value[use]
  }
  m <- read_table(master, "Dynamic_Burden", c("LM", "CR_n"), optional = TRUE)
  if (!is.null(m)) {
    m <- by_lm(m)
    for (field in c("CR_n", "GBC_CIF_1y", "Other_CIF_1y", "GBC_CIF_2y", "Other_CIF_2y",
                    "GBC_CIF_3y", "Other_CIF_3y", "GBC_RMTL_mo", "Other_RMTL_mo",
                    "LT_n", "LT_observed_RMST_mo", "LT_expected_RMST_mo"))
      put(field, num(m, field))
  }
  need <- function(fields) any(vapply(fields, function(f)
    !f %in% names(d) || anyNA(d[[f]]), logical(1)))
  cif_fields <- c("CR_n", paste0(rep(c("GBC", "Other"), each = 3), "_CIF_", rep(1:3, 2), "y"))
  if (need(cif_fields)) {
    z <- read_table(source_file("STAGE1_RESULTS_v2.xlsx"), "AJ_CIF",
                    c("family", "group", "landmark_year", "horizon_years", "cause", "estimate"))
    z <- z[z$family == "Overall" & z$group == "All" & z$sourceyears == "2004-2015", , drop = FALSE]
    for (cause in c("Cancer", "Other")) for (h in 1:3) {
      a <- by_lm(z[z$cause == cause & num(z, "horizon_years") == h, , drop = FALSE], "landmark_year")
      put(paste0(if (cause == "Cancer") "GBC" else "Other", "_CIF_", h, "y"), num(a, "estimate"))
      if ("CR_n" %in% names(d) && any(is.finite(d$CR_n) & d$CR_n != num(a, "n_at_risk"), na.rm = TRUE))
        stop("CIF source populations do not agree.")
      put("CR_n", num(a, "n_at_risk"))
    }
  }
  if (need(c("GBC_RMTL_mo", "Other_RMTL_mo"))) {
    z <- read_table(source_file("STAGE1_RESULTS_v2.xlsx"), "RMTL",
                    c("family", "landmark_year", "cause", "rmtl_months"))
    z <- z[z$family == "Overall" & z$group == "All" & num(z, "horizon_years") == 3 &
             z$sourceyears == "2004-2015", , drop = FALSE]
    for (cause in c("Cancer", "Other")) {
      a <- by_lm(z[z$cause == cause, , drop = FALSE], "landmark_year")
      if (any(d$CR_n != num(a, "n_at_risk"), na.rm = TRUE)) stop("CIF/RMTL cohort mismatch.")
      put(if (cause == "Cancer") "GBC_RMTL_mo" else "Other_RMTL_mo", num(a, "rmtl_months"))
    }
  }
  lt_fields <- c("LT_n", "LT_observed_RMST_mo", "LT_expected_RMST_mo")
  if (need(lt_fields)) {
    z <- read_table(master, "LifeTable", c("LM", "Observed RMST", "Expected RMST"), optional = TRUE)
    if (!is.null(z)) {
      z <- by_lm(z)
      put("LT_n", num(z, "n"))
      put("LT_observed_RMST_mo", num(z, "Observed RMST"))
      put("LT_expected_RMST_mo", num(z, "Expected RMST"))
    }
  }
  if (need(lt_fields)) {
    z <- read_table(source_file("LIFETABLE_RESULTS.xlsx"), "rmst_gap",
                    c("landmark", "analysis_type", "observed_RMST_months", "expected_RMST_months"))
    z <- by_lm(z[z$analysistype == "PRIMARY", , drop = FALSE], "landmark")
    put("LT_n", num(z, "n"))
    put("LT_observed_RMST_mo", num(z, "observed_RMST_months"))
    put("LT_expected_RMST_mo", num(z, "expected_RMST_months"))
  }
  required <- c(cif_fields, "GBC_RMTL_mo", "Other_RMTL_mo", lt_fields)
  if (need(required) || any(!is.finite(as.matrix(d[required])))) stop("Required formal estimates are missing or nonnumeric.")

  cr_ci_fields <- c("GBC_3y_L95", "GBC_3y_U95", "Other_3y_L95", "Other_3y_U95",
                    "GBC_RMTL_L95", "GBC_RMTL_U95", "Other_RMTL_L95", "Other_RMTL_U95")
  if (is.null(m)) stop("FINAL_RESULTS_MASTER.xlsx is required for the frozen 95% CIs.")
  for (field in cr_ci_fields) put(field, num(m, field))
  lt_ci <- by_lm(read_table(master, "LifeTable",
    c("LM", "n", "Observed RMST", "Obs L95", "Obs U95", "Expected RMST", "Exp L95", "Exp U95",
      "Gap", "Gap L95", "Gap U95")))
  same_values <- function(x, y) length(x) == length(y) &&
    all(is.finite(x) & is.finite(y)) && all(abs(x - y) < 1e-8)
  if (!same_values(d$LT_n, num(lt_ci, "n")) ||
      !same_values(d$LT_observed_RMST_mo, num(lt_ci, "Observed RMST")) ||
      !same_values(d$LT_expected_RMST_mo, num(lt_ci, "Expected RMST")))
    stop("Life-table point estimates and CI source do not identify the same results.")
  lt_ci_map <- c(LT_observed_L95 = "Obs L95", LT_observed_U95 = "Obs U95",
                 LT_expected_L95 = "Exp L95", LT_expected_U95 = "Exp U95",
                 Gap = "Gap", Gap_L95 = "Gap L95", Gap_U95 = "Gap U95")
  for (field in names(lt_ci_map)) put(field, num(lt_ci, lt_ci_map[[field]]))
  interval_fields <- c(cr_ci_fields, names(lt_ci_map))
  if (need(interval_fields) || any(!is.finite(as.matrix(d[interval_fields]))))
    stop("Frozen 95% CIs are incomplete; no point-estimate-only fallback is used.")
  check_interval <- function(value, lower, upper, ceiling) {
    if (any(lower < 0 | upper > ceiling | lower > value | value > upper))
      stop("A frozen interval is invalid or does not bracket its point estimate.")
  }
  check_interval(d$GBC_CIF_3y, d$GBC_3y_L95, d$GBC_3y_U95, 1)
  check_interval(d$Other_CIF_3y, d$Other_3y_L95, d$Other_3y_U95, 1)
  check_interval(d$GBC_RMTL_mo, d$GBC_RMTL_L95, d$GBC_RMTL_U95, 36)
  check_interval(d$Other_RMTL_mo, d$Other_RMTL_L95, d$Other_RMTL_U95, 36)
  check_interval(d$LT_observed_RMST_mo, d$LT_observed_L95, d$LT_observed_U95, 36)
  check_interval(d$LT_expected_RMST_mo, d$LT_expected_L95, d$LT_expected_U95, 36)
  probs <- d[grep("_CIF_", names(d))]
  if (any(as.matrix(probs) < 0 | as.matrix(probs) > 1)) stop("CIF values must be probabilities, not percentages.")
  for (h in 1:3) if (any(d[[paste0("GBC_CIF_", h, "y")]] + d[[paste0("Other_CIF_", h, "y")]] > 1 + 1e-10))
    stop("Competing-risk probabilities do not close.")
  if (!same_values(d$Gap, d$LT_expected_RMST_mo - d$LT_observed_RMST_mo))
    stop("Frozen RMST deficit does not match the corresponding point estimates.")
  if (any(d$Gap_L95 > d$Gap_U95 | d$Gap_L95 < -36 | d$Gap_U95 > 36))
    stop("Frozen RMST-deficit confidence limits are invalid.")
  if (any(d$GBC_RMTL_mo < 0 | d$Other_RMTL_mo < 0)) stop("Invalid frozen RMTL estimate.")
  if (any(d$LT_observed_RMST_mo < 0 | d$LT_observed_RMST_mo > 36 |
          d$LT_expected_RMST_mo < 0 | d$LT_expected_RMST_mo > 36)) stop("RMST is outside 0-36 months.")
  d$Landmark <- factor(paste0("L", d$LM), levels = paste0("L", 0:5))
  colours <- c(GBC = "#A34E5D", Other = "#5B7F9A")
  ink <- "#33363A"
  base <- theme_classic(base_size = 8, base_family = "Arial") +
    theme(text = element_text(colour = ink),
          panel.background = element_rect(fill = "white", colour = NA),
          plot.background = element_rect(fill = "white", colour = NA),
          panel.grid = element_blank(),
          axis.line = element_line(colour = "#797D80", linewidth = 0.25),
          axis.ticks = element_line(colour = "#797D80", linewidth = 0.25),
          axis.ticks.length = grid::unit(1, "mm"),
          axis.text = element_text(size = 7.5, colour = ink),
          axis.title = element_text(size = 8, face = "plain"),
          plot.title = element_text(size = 9, face = "plain", hjust = 0,
                                    margin = margin(b = 3)),
          plot.title.position = "plot",
          legend.position = "bottom", legend.direction = "horizontal",
          legend.justification = "center",
          legend.title = element_text(size = 7.5, face = "plain"),
          legend.text = element_text(size = 7.5),
          legend.key.width = grid::unit(6, "mm"),
          legend.key.height = grid::unit(2.5, "mm"),
          legend.key.spacing.x = grid::unit(3, "mm"),
          legend.margin = margin(0, 0, 0, 0),
          legend.box.spacing = grid::unit(0.7, "mm"),
          plot.margin = margin(3, 5, 3, 4))

  lm_axis <- function() scale_x_continuous(
    breaks = 0:5, labels = paste0("L", 0:5),
    limits = c(-0.5, 5.5), expand = expansion(mult = 0))
  row_axis <- function() scale_y_continuous(
    breaks = 5:0, labels = paste0("L", 0:5),
    limits = c(-0.5, 5.5), expand = expansion(mult = 0))
  cause_levels <- c("GBC", "Other")
  cause_labels <- c("GBC", "Other cause")

  a <- data.frame(LM = rep(d$LM, 2),
    Cause = factor(rep(cause_levels, each = 6), levels = cause_levels),
    Value = c(d$GBC_CIF_3y, d$Other_CIF_3y),
    Lower = c(d$GBC_3y_L95, d$Other_3y_L95),
    Upper = c(d$GBC_3y_U95, d$Other_3y_U95))
  a$Position <- a$LM + ifelse(a$Cause == "GBC", -0.18, 0.18)
  a_top <- max(0.55, ceiling(max(a$Upper) * 20) / 20)
  pA <- ggplot(a, aes(Position, Value)) +
    geom_col(aes(fill = Cause), width = 0.30, colour = NA) +
    geom_errorbar(aes(ymin = Lower, ymax = Upper), width = 0.11,
                  linewidth = 0.25, colour = ink, show.legend = FALSE) +
    scale_fill_manual(name = NULL, values = colours,
                      breaks = cause_levels, labels = cause_labels) +
    guides(fill = guide_legend(nrow = 1)) + lm_axis() +
    scale_y_continuous(breaks = seq(0, a_top, 0.1),
                       labels = scales::label_number(scale = 100, accuracy = 1),
                       limits = c(0, a_top), expand = expansion(mult = 0)) +
    labs(title = "Three-year mortality composition", x = "Survivorship landmark",
         y = "3-year cumulative incidence, %") + base

  b <- data.frame(LM = rep(d$LM, 2),
    Cause = factor(rep(cause_levels, each = 6), levels = cause_levels),
    Value = c(d$GBC_RMTL_mo, d$Other_RMTL_mo),
    Lower = c(d$GBC_RMTL_L95, d$Other_RMTL_L95),
    Upper = c(d$GBC_RMTL_U95, d$Other_RMTL_U95))
  b$Row <- 5 - b$LM + ifelse(b$Cause == "GBC", 0.15, -0.15)
  b_right <- max(13, ceiling(max(b$Upper) + 0.5))
  pB <- ggplot(b, aes(Value, Row, colour = Cause)) +
    geom_segment(aes(x = Lower, xend = Upper, yend = Row),
                 linewidth = 0.30, show.legend = FALSE) +
    geom_point(aes(shape = Cause), size = 1.8, stroke = 0.55) +
    scale_colour_manual(name = NULL, values = colours,
                        breaks = cause_levels, labels = cause_labels) +
    scale_shape_manual(name = NULL, values = c(GBC = 16, Other = 0),
                       breaks = cause_levels, labels = cause_labels) +
    guides(colour = guide_legend(nrow = 1), shape = guide_legend(nrow = 1)) +
    scale_x_continuous(breaks = seq(0, b_right, 3), limits = c(0, b_right),
                       expand = expansion(mult = 0)) + row_axis() +
    labs(title = "Cause-specific time lost", x = "3-year restricted mean time lost, mo",
         y = "Survivorship landmark") + base +
    theme(axis.line.y = element_blank(), axis.ticks.y = element_blank())

  rmst <- data.frame(LM = rep(d$LM, 2),
    Series = factor(rep(c("Observed", "Expected population"), each = 6),
                    levels = c("Observed", "Expected population")),
    Value = c(d$LT_observed_RMST_mo, d$LT_expected_RMST_mo),
    Lower = c(d$LT_observed_L95, d$LT_expected_L95),
    Upper = c(d$LT_observed_U95, d$LT_expected_U95))
  rmst$Row <- 5 - rmst$LM
  c_end <- d[d$LM %in% c(0, 5), , drop = FALSE]
  c_end$Midpoint <- (c_end$LT_observed_RMST_mo + c_end$LT_expected_RMST_mo) / 2
  pC <- ggplot(rmst, aes(Value, Row, colour = Series)) +
    geom_segment(data = d, aes(x = LT_observed_RMST_mo, xend = LT_expected_RMST_mo,
                              y = 5 - LM, yend = 5 - LM),
                 inherit.aes = FALSE, colour = "#BFC3C5", linewidth = 0.40) +
    geom_segment(aes(x = Lower, xend = Upper, yend = Row),
                 linewidth = 0.25, show.legend = FALSE) +
    geom_point(aes(shape = Series), size = 1.9, stroke = 0.55, fill = "white") +
    geom_text(data = c_end, aes(x = Midpoint, y = 5 - LM + 0.20,
                               label = sprintf("%.2f mo", Gap)),
              inherit.aes = FALSE, vjust = 0, size = 2.6,
              family = "Arial", colour = ink) +
    scale_colour_manual(name = NULL,
      values = c(Observed = ink, "Expected population" = "#858780")) +
    scale_shape_manual(name = NULL, values = c(Observed = 16, "Expected population" = 21)) +
    guides(colour = guide_legend(nrow = 1), shape = guide_legend(nrow = 1)) +
    scale_x_continuous(breaks = c(20, 24, 28, 32, 36),
                       limits = c(20, 36), expand = expansion(mult = c(0.01, 0.02))) +
    row_axis() + labs(title = "Restricted-survival gap", x = "3-year RMST, mo",
                      y = "Survivorship landmark") + base +
    theme(axis.line.y = element_blank(), axis.ticks.y = element_blank())

  heat <- do.call(rbind, lapply(1:3, function(h) data.frame(
    LM = d$LM, Horizon = factor(h, levels = 3:1, labels = c("3-year", "2-year", "1-year")),
    Difference = 100 * (d[[paste0("Other_CIF_", h, "y")]] - d[[paste0("GBC_CIF_", h, "y")]]))))
  span <- max(5, 5 * ceiling(max(abs(heat$Difference)) / 5))
  pD <- ggplot(heat, aes(LM, Horizon, fill = Difference)) +
    geom_tile(colour = "white", linewidth = 0.3, width = 0.97, height = 0.97) +
    geom_text(aes(label = sprintf("%.1f", Difference),
                  colour = abs(Difference) > 0.7 * span),
              size = 2.6, family = "Arial", show.legend = FALSE) +
    scale_colour_manual(values = c("FALSE" = ink, "TRUE" = "white"), guide = "none") +
    scale_fill_gradient2(low = colours[["GBC"]], mid = "#FAFAF8", high = colours[["Other"]],
                         midpoint = 0, limits = c(-span, span), breaks = c(-span, 0, span),
                         name = "Other-cause \u2212 GBC CIF,\npercentage points") +
    lm_axis() + scale_y_discrete(expand = expansion(add = 0)) +
    labs(title = "Cause-specific CIF difference\nby prediction horizon",
         x = "Survivorship landmark", y = "Prediction horizon") + base +
    theme(axis.line = element_blank(), axis.ticks = element_blank()) +
    guides(fill = guide_colourbar(title.position = "top", display = "rectangles",
      nbin = 64, barwidth = grid::unit(36, "mm"), barheight = grid::unit(2, "mm")))

  figure <- (pA + pB + pC + pD) +
    plot_layout(design = "AB\nCD", widths = c(1.1, 1),
                heights = c(1, 1), guides = "keep") +
    plot_annotation(tag_levels = "A",
      theme = theme(plot.margin = margin(3, 3, 3, 3),
                    plot.background = element_rect(fill = "white", colour = NA)))
  figure <- figure & theme(plot.tag = element_text(size = 10, face = "bold",
                                                   family = "Arial", colour = ink),
                           plot.tag.position = "topleft",
                           plot.margin = margin(5, 7, 6, 5))

  OUTPUT_DIR <- file.path(Sys.getenv("GBC_SUBMISSION_OUTPUT", unset = file.path(PROJECT_ROOT, "submission")), "Main")
  if (!dir.exists(OUTPUT_DIR)) {
    dir.create(OUTPUT_DIR, recursive = TRUE)
  }
  save_plot <- function(path, type) {
    if (type == "pdf") {
      grDevices::cairo_pdf(path, width = 180 / 25.4, height = 165 / 25.4,
                          family = "Arial", bg = "white", onefile = TRUE)
    } else if (type == "tiff") {
      ragg::agg_tiff(path, width = 180, height = 165, units = "mm", res = 600,
                     compression = "lzw", background = "white", bitsize = 8)
    } else if (type == "png") {
      ragg::agg_png(path, width = 180, height = 165, units = "mm", res = 300,
                    background = "white", bitsize = 8)
    } else stop("Unsupported figure format: ", type)
    on.exit(grDevices::dev.off(), add = TRUE)
    print(figure)
  }
  save_plot(file.path(OUTPUT_DIR, "Figure2_Final.pdf"), "pdf")
  save_plot(file.path(OUTPUT_DIR, "Figure2_Final.tiff"), "tiff")
  save_plot(file.path(OUTPUT_DIR, "Figure2_preview.png"), "png")
  cat("Figure 2 completed in the configured Main output directory.\n")
})

