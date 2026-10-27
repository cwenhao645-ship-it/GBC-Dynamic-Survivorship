# Phase 3 display only. Estimates and patient-level bootstrap intervals are
# supplied by run_phase3.R; no statistics are estimated in this file.
# Figure contract: compare the unadjusted and age/sex-adjusted 36-month
# prognostic risk differences across the three prespecified pathology contrasts.
# Quantitative-grid architecture: three equally weighted predefined contrasts,
# identical axes and uncertainty encoding. No causal or attenuation claim is
# encoded by the titles. Drawing, previewing and export use R exclusively.

figure3_output_path <- function(path) {
  config <- file.path(Sys.getenv('GBC_CODE_ROOT',getwd()),
    'scripts/current_kernels/public_config.R')
  if (!file.exists(config)) stop('Set GBC_CODE_ROOT to the public checkout root.',call.=FALSE)
  e <- new.env(parent=.GlobalEnv)
  sys.source(config,envir=e)
  e$gbc_new_output_path(path)
}

phase3_figure3 <- function(summary, output_pdf) {
  output_pdf <- figure3_output_path(output_pdf)
  packages <- c("ggplot2", "patchwork", "jsonlite")
  for (p in packages) {
    if (!requireNamespace(p, quietly = TRUE))
      stop("Phase 3 plotting dependency unavailable: ", p, call. = FALSE)
  }
  if (!isTRUE(capabilities("cairo")))
    stop("Cairo is required for the vector PDF export.", call. = FALSE)
  fields <- c("target", "landmark", "crude_rd_pp", "crude_lower95_pp",
    "crude_upper95_pp", "adjusted_rd_pp", "adjusted_lower95_pp", "adjusted_upper95_pp")
  if (!is.data.frame(summary) || !all(fields %in% names(summary)))
    stop("Phase 3 plotting input does not match its aggregate-data contract.", call. = FALSE)
  d <- summary[, fields, drop = FALSE]
  target_order <- c("T", "N", "Grade")
  if (nrow(d) != 18L || anyDuplicated(paste(d$target, d$landmark)) ||
      !all(d$target %in% target_order) || !all(d$landmark %in% 0:5) ||
      !all(vapply(target_order, function(t) setequal(d$landmark[d$target == t], 0:5), logical(1))))
    stop("All three contrasts and all six landmarks are required, exactly once.", call. = FALSE)
  for (prefix in c("crude", "adjusted")) {
    value <- d[[paste0(prefix, "_rd_pp")]]
    lower <- d[[paste0(prefix, "_lower95_pp")]]
    upper <- d[[paste0(prefix, "_upper95_pp")]]
    if (any(xor(is.finite(lower), is.finite(upper))) ||
        any(is.finite(lower) & (!is.finite(value) | lower > upper)))
      stop("Invalid or unpaired confidence-interval endpoints in plotting data.", call. = FALSE)
  }

  long <- do.call(rbind, lapply(c("crude", "adjusted"), function(method) {
    data.frame(target = d$target, landmark = d$landmark,
      method = if (method == "crude") "Unadjusted AJ" else "Age/sex adjusted",
      estimate = d[[paste0(method, "_rd_pp")]],
      lower95 = d[[paste0(method, "_lower95_pp")]],
      upper95 = d[[paste0(method, "_upper95_pp")]], stringsAsFactors = FALSE)
  }))
  method_order <- c("Unadjusted AJ", "Age/sex adjusted")
  long$method <- factor(long$method, levels = method_order)
  long$x <- long$landmark + ifelse(long$method == method_order[1], -.09, .09)
  # All requested rows remain in the returned input. Unavailable estimates or
  # intervals are not replaced, and no simulated/demo values are generated.
  missing_points <- long[!is.finite(long$estimate), c("target", "landmark", "method"), drop = FALSE]
  missing_intervals <- long[!is.finite(long$lower95) | !is.finite(long$upper95),
    c("target", "landmark", "method"), drop = FALSE]
  envelope <- c(0, long$estimate, long$lower95, long$upper95)
  envelope <- envelope[is.finite(envelope)]
  if (!length(envelope) || diff(range(envelope)) <= 0)
    stop("The risk-difference axis cannot be determined from real finite results.", call. = FALSE)
  span <- diff(range(envelope))
  limits <- range(envelope) + c(-1, 1) * max(1.5, .075 * span)
  ticks <- pretty(limits, n = 5)
  ticks <- ticks[ticks >= limits[1] & ticks <= limits[2]]

  common_theme <- ggplot2::theme_classic(base_size = 8, base_family = "Arial") +
    ggplot2::theme(
      text = ggplot2::element_text(family = "Arial", size = 8, colour = "#222222"),
      axis.title = ggplot2::element_text(size = 8),
      axis.title.x = ggplot2::element_text(margin = ggplot2::margin(t = 5)),
      axis.title.y = ggplot2::element_text(margin = ggplot2::margin(r = 6)),
      axis.text = ggplot2::element_text(size = 7.5, colour = "#333333"),
      axis.line = ggplot2::element_line(linewidth = .3, colour = "#333333"),
      axis.ticks = ggplot2::element_line(linewidth = .3, colour = "#333333"),
      axis.ticks.length = grid::unit(1.3, "mm"),
      panel.grid = ggplot2::element_blank(),
      panel.background = ggplot2::element_rect(fill = "white", colour = NA),
      plot.background = ggplot2::element_rect(fill = "white", colour = NA),
      plot.title = ggplot2::element_text(size = 8.5, face = "bold", hjust = 0,
        margin = ggplot2::margin(b = 6)),
      plot.title.position = "panel",
      plot.tag = ggplot2::element_text(size = 8.5, face = "bold"),
      plot.margin = ggplot2::margin(4, 5, 3, 4, unit = "pt"),
      legend.position = "bottom", legend.direction = "horizontal",
      legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = 7.5),
      legend.key.width = grid::unit(8, "mm"),
      legend.key.height = grid::unit(4, "mm"),
      legend.spacing.x = grid::unit(2, "mm"),
      legend.margin = ggplot2::margin(t = 4, b = 0))

  titles <- c(T = "T3/4 vs T1", N = "N+ vs N0", Grade = "G3/4 vs G1")
  plots <- lapply(target_order, function(target) {
    z <- long[long$target == target, , drop = FALSE]
    marks <- z[is.finite(z$estimate), , drop = FALSE]
    intervals <- z[is.finite(z$estimate) & is.finite(z$lower95) & is.finite(z$upper95), , drop = FALSE]
    ggplot2::ggplot(z, ggplot2::aes(x = x, y = estimate, colour = method,
      shape = method, linetype = method, group = method)) +
      ggplot2::geom_hline(yintercept = 0, colour = "#B8B8B8", linewidth = .3) +
      ggplot2::geom_errorbar(data = intervals,
        ggplot2::aes(ymin = lower95, ymax = upper95),
        width = .12, linewidth = .3, linetype = "solid", show.legend = FALSE) +
      ggplot2::geom_line(linewidth = .36, na.rm = TRUE) +
      ggplot2::geom_point(data = marks, size = 1.7, stroke = .42) +
      ggplot2::scale_colour_manual(values = c("Unadjusted AJ" = "#7A7A7A",
        "Age/sex adjusted" = "#111111"), drop = FALSE) +
      ggplot2::scale_shape_manual(values = c("Unadjusted AJ" = 0,
        "Age/sex adjusted" = 16), drop = FALSE) +
      ggplot2::scale_linetype_manual(values = c("Unadjusted AJ" = "22",
        "Age/sex adjusted" = "solid"), drop = FALSE) +
      ggplot2::scale_x_continuous(breaks = 0:5, labels = paste0("L", 0:5),
        limits = c(-.4, 5.4), expand = c(0, 0)) +
      ggplot2::scale_y_continuous(breaks = ticks, limits = limits, expand = c(0, 0)) +
      ggplot2::labs(title = titles[[target]], x = "Landmark",
        y = if (target == "T") "36-month GBC CIF difference, pp" else NULL) +
      ggplot2::guides(colour = ggplot2::guide_legend(nrow = 1,
        override.aes = list(linewidth = .45, size = 1.9))) + common_theme
  })
  figure <- patchwork::wrap_plots(plots, nrow = 1, widths = c(1, 1, 1), guides = "collect") +
    patchwork::plot_annotation(tag_levels = "a") &
    ggplot2::theme(legend.position = "bottom")


  # Public I/O adapter only: keep frozen data/layers/axes; private skill QA and
  # preview packaging are not required to export this vector PDF.
  output_pdf <- figure3_output_path(output_pdf)
  grDevices::cairo_pdf(output_pdf, width = 180 / 25.4, height = 85 / 25.4,
    family = "Arial", bg = "white", onefile = TRUE)
  on.exit(grDevices::dev.off(), add = TRUE)
  print(figure)
  invisible(output_pdf)
}

figure3_main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (!length(args) || "--help" %in% args) {
    cat("Output-only Figure3 adapter; never fits a statistical model.\n",
      "--input <frozen Phase3 xlsx or Adjusted_Pathology CSV> --output <private PDF>\n",
      "--input <file> --validate-only : inspect aggregate schema without plotting\n")
    return(invisible(NULL))
  }
  value <- function(flag) {
    i <- match(flag,args)
    if (is.na(i) || i == length(args) || startsWith(args[i+1L],"--"))
      stop("Missing argument: ",flag,call.=FALSE)
    args[i+1L]
  }
  input <- value("--input")
  if (!file.exists(input)) stop("Frozen aggregate input is missing",call.=FALSE)
  if (tolower(tools::file_ext(input)) == "xlsx") {
    if (!requireNamespace("readxl",quietly=TRUE)) stop("readxl is required for XLSX input")
    d <- as.data.frame(readxl::read_excel(input,sheet="Adjusted_Pathology",skip=4))
  } else if (tolower(tools::file_ext(input)) == "csv") {
    d <- utils::read.csv(input,check.names=FALSE,stringsAsFactors=FALSE)
  } else stop("Use the actual frozen XLSX or computed aggregate CSV",call.=FALSE)
  fields <- c("target","landmark","crude_rd_pp","crude_lower95_pp",
    "crude_upper95_pp","adjusted_rd_pp","adjusted_lower95_pp","adjusted_upper95_pp")
  if (!all(fields %in% names(d)) || nrow(d)!=18L ||
      anyDuplicated(paste(d$target,d$landmark)) ||
      !all(vapply(c("T","N","Grade"),function(t) setequal(d$landmark[d$target==t],0:5),logical(1))))
    stop("The actual18-row three-contrast/six-landmark summary is required",call.=FALSE)
  numeric_fields <- setdiff(fields,"target")
  if (!all(vapply(d[,numeric_fields,drop=FALSE],is.numeric,logical(1))) ||
      !all(is.finite(as.matrix(d[,numeric_fields,drop=FALSE]))))
    stop("A requested estimate/interval is unavailable; no replacement is made",call.=FALSE)
  for (p in c("crude","adjusted")) if (any(d[[paste0(p,"_lower95_pp")]]>d[[paste0(p,"_upper95_pp")]]))
    stop("Reversed interval",call.=FALSE)
  if ("--validate-only" %in% args) {
    cat("PASS: actual18 aggregate rows; three contrasts; six landmarks; matched estimate/CI columns; no estimation or figure export.\n")
    return(invisible(TRUE))
  }
  output <- value("--output")
  if (tolower(tools::file_ext(output))!="pdf") stop("Use vector PDF output",call.=FALSE)
  output <- figure3_output_path(output)
  # Block implicit devices. The renderer explicitly opens Cairo before print().
  options(device=function(...)stop("Open an explicit graphics device"))
  phase3_figure3(d,output)
  cat("Vector PDF exported from frozen summaries; no model fitting.\n")
}

if (sys.nframe()==0L) figure3_main()
