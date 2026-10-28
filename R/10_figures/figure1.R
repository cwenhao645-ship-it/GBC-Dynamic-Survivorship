# Reconstructed public plotting source based on the frozen manuscript figure and verified cohort counts; original plotting source was not recovered.
# Display-only engineering, 2026-10-28. No model fitting or patient data required.
# Requires R, readxl, ggplot2, patchwork, jsonlite and ragg; PDF uses Cairo.

figure1_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(message, call.=FALSE)
}

figure1_sheet <- function(path, sheet, first_header) {
  figure1_require(file.exists(path),paste('Missing frozen aggregate input:',basename(path)))
  figure1_require(requireNamespace('readxl',quietly=TRUE),'readxl is required')
  raw <- as.data.frame(readxl::read_excel(path,sheet=sheet,col_names=FALSE,
    col_types='text',.name_repair='minimal'),stringsAsFactors=FALSE)
  at <- which(!is.na(raw[[1]]) & raw[[1]]==first_header)
  figure1_require(length(at)==1L && at<nrow(raw),paste('Unrecognized aggregate sheet:',sheet))
  headers <- as.character(unlist(raw[at,,drop=FALSE],use.names=FALSE))
  keep <- which(!is.na(headers) & nzchar(headers))
  figure1_require(identical(keep,seq_along(keep)) && !anyDuplicated(headers[keep]),
    paste('Invalid aggregate column names:',sheet))
  raw <- raw[,keep,drop=FALSE]; headers <- headers[keep]
  out <- raw[seq.int(at+1L,nrow(raw)),,drop=FALSE]; names(out) <- headers
  out[!is.na(out[[1]]) & nzchar(out[[1]]),,drop=FALSE]
}

figure1_integers <- function(x) {
  out <- suppressWarnings(as.numeric(x))
  figure1_require(all(is.finite(out) & out>=0 & out==floor(out)),'Invalid frozen count')
  as.integer(out)
}

figure1_inputs <- function(cohort_qc,life_summary,phase3_summary,master_check=NULL) {
  flow <- figure1_sheet(cohort_qc,'cohort_flow','step')
  figure1_require(all(c('step','n_before','n_excluded','n_after') %in% names(flow)),
    'Missing cohort-flow columns')
  for (k in c('n_before','n_excluded','n_after')) flow[[k]] <- figure1_integers(flow[[k]])
  figure1_require(nrow(flow)==12L && identical(substr(flow$step,1,2),sprintf('%02d',1:12)),
    'The frozen twelve-step cohort flow is required')
  figure1_require(all(flow$n_before-flow$n_excluded==flow$n_after) &&
    all(flow$n_before[-1]==head(flow$n_after,-1)),'Sequential flow does not reconcile')
  # S1 omits only the original zero-exclusion auxiliary gates. Verify them,
  # rather than silently dropping any newly nonzero exclusion.
  figure1_require(all(flow$n_excluded[c(2,5,10,12)]==0L),
    'An auxiliary eligibility gate is nonzero: do not use the frozen S1 display')
  selected <- c(1,3,4,6,7,8,9,11)
  flow <- flow[selected,,drop=FALSE]
  # Published S1 values are cross-checks only; displayed values still come
  # exclusively from the supplied, validated frozen workbook.
  figure1_require(identical(flow$n_after,c(21219L,21215L,14052L,13269L,
    13247L,9014L,7100L,7007L)) &&
    identical(flow$n_excluded,c(0L,4L,7163L,783L,22L,4233L,1914L,93L)),
    'Frozen S1 eligibility counts changed: stop instead of replacing the figure')
  if (!is.null(master_check)) {
    master <- figure1_sheet(master_check,'Cohorts','step')
    j <- match(flow$step,master$step)
    figure1_require(!anyNA(j),'Master cohort-flow keys differ')
    for (k in c('n_before','n_excluded','n_after'))
      figure1_require(identical(flow[[k]],figure1_integers(master[[k]][j])),
        'Independent master/QC cohort counts disagree')
  }
  cr <- figure1_sheet(cohort_qc,'landmark_counts','family')
  figure1_require(all(c('family','group','landmark_year','n_at_risk') %in% names(cr)),
    'Missing competing-risk landmark columns')
  cr <- cr[which(cr$family=='Overall' & cr$group=='All'),,drop=FALSE]
  life <- figure1_sheet(life_summary,'matching_qc','landmark')
  figure1_require(all(c('landmark','analysis_type','eligible_n','matched_n','match_rate') %in% names(life)),
    'Missing life-table matching columns')
  life <- life[which(life$analysis_type=='PRIMARY'),,drop=FALSE]
  unified <- figure1_sheet(phase3_summary,'Unified_Cohort','landmark')
  figure1_require(all(c('landmark','n','original_cr_n','original_life_n') %in% names(unified)),
    'Missing unified-cohort reconciliation fields')
  cr$landmark <- figure1_integers(cr$landmark_year)
  life$landmark <- figure1_integers(life$landmark)
  unified$landmark <- figure1_integers(unified$landmark)
  for (d in list(cr,life,unified)) figure1_require(nrow(d)==6L &&
    !anyDuplicated(d$landmark) && setequal(d$landmark,0:5),'Six unique L0-L5 summaries are required')
  cr <- cr[order(cr$landmark),,drop=FALSE]
  life <- life[order(life$landmark),,drop=FALSE]
  unified <- unified[order(unified$landmark),,drop=FALSE]
  ncr <- figure1_integers(cr$n_at_risk)
  nlife <- figure1_integers(life$matched_n)
  nu <- figure1_integers(unified$n)
  figure1_require(all(figure1_integers(life$eligible_n)==nlife) &&
    all(as.numeric(life$match_rate)==1),'Life-table matching is incomplete')
  figure1_require(identical(ncr,figure1_integers(unified$original_cr_n)) &&
    identical(nlife,figure1_integers(unified$original_life_n)) && all(nu<=pmin(ncr,nlife)),
    'The three cohort summaries do not share the expected definitions')
  # These are frozen cross-check gates, never fallback plotting data.
  figure1_require(identical(ncr,c(3918L,2496L,1786L,1423L,1192L,1047L)) &&
    identical(nlife,c(3796L,2469L,1775L,1420L,1191L,1048L)) &&
    identical(nu,c(3736L,2427L,1746L,1399L,1173L,1035L)),
    'Frozen landmark counts changed: stop instead of silently replacing the figure')
  list(flow=flow,counts=data.frame(landmark=0:5,competing_risk=ncr,life_table=nlife,intersection=nu))
}

figure1_plot <- function(input) {
  for (p in c('ggplot2','patchwork'))
    figure1_require(requireNamespace(p,quietly=TRUE),paste('Missing plotting package:',p))
  # One schematic argument: eligibility defines distinct survivor populations;
  # all forward windows begin at diagnosis-origin landmarks, not surgery.
  # a = eligibility provenance; b = population denominators plus time design.
  ink <- '#202020'; mid <- '#606060'; edge <- '#939393'
  size <- function(pt) pt*25.4/72.27
  base <- ggplot2::theme_void(base_family='Arial',base_size=7) +
    ggplot2::theme(plot.margin=ggplot2::margin(6,5,4,5),
      plot.background=ggplot2::element_rect(fill='white',colour=NA),
      plot.tag=ggplot2::element_text(size=8,face='bold',family='Arial'),
      plot.tag.position='topleft')
  blank <- function() ggplot2::ggplot()+
    ggplot2::coord_cartesian(xlim=c(0,1),ylim=c(0,1),expand=FALSE,clip='off')+base
  labels <- c('Primary malignant\ngallbladder tumors','Age >=18 years',
    'Adenocarcinoma, NOS\n(ICD-O-3 8140/3)','Histologically confirmed',
    'Primary tumor under\ninternational rules','Recorded resection\n(codes 30/40/60*)',
    'Registry-derived M0','Classifiable cause of death')
  y <- seq(.90,.13,length.out=nrow(input$flow)); h <- .079
  nodes <- data.frame(y=y,label=paste0(labels,'\nn = ',
    format(input$flow$n_after,big.mark=',',trim=TRUE)),stringsAsFactors=FALSE)
  a <- blank()+ggplot2::annotate('text',x=.02,y=.985,label='Cohort derivation',
    hjust=0,vjust=1,size=size(7.5),fontface='bold',family='Arial',colour=ink)+
    ggplot2::geom_rect(data=nodes,ggplot2::aes(ymin=y-h/2,ymax=y+h/2),
      xmin=.025,xmax=.79,fill='white',colour=edge,linewidth=.28)+
    ggplot2::geom_text(data=nodes,ggplot2::aes(y=y,label=label),x=.4075,
      size=size(7.0),lineheight=.98,family='Arial',colour=ink)
  for (i in 2:nrow(nodes)) {
    a <- a+ggplot2::annotate('segment',x=.4075,xend=.4075,
      y=y[i-1]-h/2,yend=y[i]+h/2+.004,linewidth=.27,colour=mid,
      arrow=grid::arrow(length=grid::unit(1.3,'mm'),type='closed'))+
      ggplot2::annotate('text',x=.82,y=mean(y[c(i-1,i)]),
        label=paste0('Excluded\nn = ',format(input$flow$n_excluded[i],big.mark=',',trim=TRUE)),
        hjust=0,size=size(6),lineheight=1.0,family='Arial',colour=mid)
  }
  b <- blank()+ggplot2::annotate('text',x=.02,y=.985,
    label='Analytic populations and landmarks',hjust=0,vjust=1,
    size=size(7.5),fontface='bold',family='Arial',colour=ink)+
    ggplot2::annotate('rect',xmin=.025,xmax=.98,ymin=.88,ymax=.95,
      fill='white',colour=edge,linewidth=.28)+
    ggplot2::annotate('text',x=.5025,y=.915,
      label=paste0('Source cohort: 2004-2023\nCompeting-risk N = ',
        format(tail(input$flow$n_after,1),big.mark=',',trim=TRUE)),
      size=size(7.1),family='Arial',lineheight=1.05,colour=ink)+
    ggplot2::annotate('text',x=.025,y=.846,label='Analytic cohorts: diagnoses 2004-2015',
      hjust=0,size=size(6.7),fontface='bold',family='Arial',colour=ink)
  x <- seq(.37,.945,length.out=6)
  b <- b+ggplot2::annotate('text',x=x,y=.799,label=paste0('L',0:5),
    size=size(6.5),fontface='bold',family='Arial',colour=ink)
  ys <- c(.751,.705,.659)
  for (i in seq_along(ys)) {
    field <- c('competing_risk','life_table','intersection')[i]
    b <- b+ggplot2::annotate('text',x=.025,y=ys[i],
      label=c('Competing risks','Life table','Intersection')[i],hjust=0,
      size=size(6.4),family='Arial',colour=ink)+
      ggplot2::annotate('text',x=x,y=ys[i],label=input$counts[[field]],
        size=size(6.4),family='Arial',colour=ink)
  }
  b <- b+ggplot2::annotate('text',x=.025,y=.603,
    label='Separate, overlapping populations; not pooled denominators.',hjust=0,
    size=size(5.9),family='Arial',colour=mid)+
    ggplot2::annotate('text',x=.025,y=.537,label='Diagnosis-origin landmark design',hjust=0,
      size=size(7.0),fontface='bold',family='Arial',colour=ink)
  to_x <- function(year) .20+.0925*year
  rows <- seq(.466,.171,length.out=6)
  for (s in 0:5) {
    b <- b+ggplot2::annotate('text',x=.025,y=rows[s+1],
      label=if(s==0) 'L0\nDiagnosis' else if(s==5) 'L5\n5 y alive' else paste0('L',s),
      hjust=0,size=size(6.3),lineheight=.98,family='Arial',colour=ink)+
      ggplot2::annotate('point',x=to_x(s),y=rows[s+1],size=1.4,shape=16,colour=ink)+
      ggplot2::annotate('segment',x=to_x(s)+.008,xend=to_x(s+3),
        y=rows[s+1],yend=rows[s+1],linewidth=.36,colour=mid,
        arrow=grid::arrow(length=grid::unit(1.6,'mm'),type='closed'))
  }
  b <- b+ggplot2::annotate('text',x=.59,y=.115,label='Each window: next 36 months',
    size=size(6.3),family='Arial',colour=ink)+
    ggplot2::annotate('segment',x=to_x(0),xend=to_x(8),y=.078,yend=.078,
      colour=edge,linewidth=.28)+
    ggplot2::annotate('segment',x=to_x(0:8),xend=to_x(0:8),y=.078,yend=.069,
      colour=edge,linewidth=.28)+
    ggplot2::annotate('text',x=to_x(0:8),y=.047,label=0:8,
      size=size(6.1),family='Arial',colour=ink)+
    ggplot2::annotate('text',x=.57,y=.014,label='Years since diagnosis',
      size=size(6.1),family='Arial',colour=ink)
  patchwork::wrap_plots(a,b,nrow=1,widths=c(1,1.06))+
    patchwork::plot_annotation(tag_levels='a',caption=paste(
      '*2004-2022 codes 30/40/60; 2023 equivalents A300/A400/A600. Codes do not establish R0 margins.',
      'Resection date unavailable; all landmarks begin at diagnosis. Intersection is a sensitivity cohort, not a replacement.',sep='\n'),
      theme=ggplot2::theme(plot.caption=ggplot2::element_text(size=6.0,family='Arial',
        hjust=0,colour=ink,lineheight=1.1),plot.margin=ggplot2::margin(3,5,5,5)))
}

figure1_alignment <- function(plot,path) {
  # Figure-specific independent gate, not a dependency on private QA tools.
  # Measure real rendered viewports: unresolved gtable null units are not sizes.
  require_patchwork_panel_alignment <- function(plot) {
    probe <- tempfile(fileext='.pdf')
    grDevices::cairo_pdf(probe,width=170/25.4,height=180/25.4,family='Arial')
    on.exit({grDevices::dev.off();unlink(probe)},add=TRUE)
    g <- patchwork::patchworkGrob(plot)
    rows <- g$layout[grepl('^panel-[0-9]+$',g$layout$name),,drop=FALSE]
    rows <- rows[order(rows$l),,drop=FALSE]
    figure1_require(nrow(rows)==2L,'Figure1 requires exactly two measured panels')
    grid::grid.newpage();grid::grid.draw(g);grid::grid.force()
    rectangles <- lapply(seq_len(2),function(i) {
      r <- rows[i,]
      grid::upViewport(0)
      grid::seekViewport(paste0(r$name,'.',r$t,'-',r$l,'-',r$b,'-',r$r))
      lower <- grid::deviceLoc(grid::unit(0,'npc'),grid::unit(0,'npc'),valueOnly=TRUE)
      upper <- grid::deviceLoc(grid::unit(1,'npc'),grid::unit(1,'npc'),valueOnly=TRUE)
      c(lower$x,lower$y,upper$x,upper$y)*72
    })
    grid::upViewport(0)
    m <- do.call(rbind,rectangles)
    error <- max(abs(m[1,c(2,4)]-m[2,c(2,4)]))
    figure1_require(all(is.finite(m)) && all(m[,3]>m[,1]) &&
      all(m[,4]>m[,2]) && m[1,3]<=m[2,1] && error<=1.5,
      'Rendered panel alignment failed; do not export')
    list(status='PASS',backend='R Cairo / actual grid viewports',tolerance_pt=1.5,
      maximum_shared_edge_difference_pt=error,panels=list(a=rectangles[[1]],b=rectangles[[2]]),
      note='Eligibility and population/time panels intentionally have different widths; common top/bottom edges are checked.')
  }
  result <- require_patchwork_panel_alignment(plot)
  jsonlite::write_json(result,path,pretty=TRUE,auto_unbox=TRUE,digits=NA)
  invisible(result)
}

figure1_main <- function() {
  args <- commandArgs(trailingOnly=TRUE)
  if (!length(args) || '--help' %in% args) {
    cat('Reconstructed Figure1; display-only, no estimation. Missing inputs stop.\n',
      '--cohort-qc <frozen QC xlsx> --life-summary <frozen life xlsx>\n',
      '--phase3-summary <frozen Phase3 xlsx> --output-dir <existing private directory>\n',
      '[--master-check <frozen master xlsx>] [--validate-only]\n',
      'Set GBC_CODE_ROOT and GBC_OUTPUT_ROOT; outputs must be new and outside frozen input roots.\n')
    return(invisible(NULL))
  }
  value <- function(key,optional=FALSE) {
    i <- match(key,args)
    if (is.na(i) && optional) return(NULL)
    figure1_require(!is.na(i) && i<length(args) && !startsWith(args[i+1L],'--'),paste('Missing argument:',key))
    args[i+1L]
  }
  input <- figure1_inputs(value('--cohort-qc'),value('--life-summary'),
    value('--phase3-summary'),value('--master-check',TRUE))
  if ('--validate-only' %in% args) {
    print(input$flow); print(input$counts)
    cat('PASS: frozen aggregate counts and sequential eligibility reconcile; no figure exported.\n')
    return(invisible(input))
  }
  code <- Sys.getenv('GBC_CODE_ROOT',getwd())
  source(file.path(code,'scripts/current_kernels/public_config.R'),local=TRUE)
  directory <- normalizePath(value('--output-dir'),winslash='/',mustWork=TRUE)
  paths <- vapply(c('Figure1.pdf','Figure1_preview.png','Figure1_alignment.json'),
    function(n)gbc_new_output_path(file.path(directory,n)),'')
  figure1_require(isTRUE(capabilities('cairo')),'Cairo PDF support is required')
  figure1_require(requireNamespace('ragg',quietly=TRUE),'ragg is required for the R preview')
  figure1_require(requireNamespace('jsonlite',quietly=TRUE),'jsonlite is required for layout QA')
  options(device=function(...)stop('Open an explicit output device; no implicit Rplots.pdf is allowed'))
  plot <- figure1_plot(input)
  figure1_alignment(plot,paths[3])
  grDevices::cairo_pdf(paths[1],width=170/25.4,height=180/25.4,family='Arial',onefile=TRUE,bg='white')
  tryCatch(print(plot),finally=grDevices::dev.off())
  ragg::agg_png(paths[2],width=170,height=180,units='mm',res=300,background='white')
  tryCatch(print(plot),finally=grDevices::dev.off())
  cat('Figure1 vector PDF and R preview exported; only verified frozen aggregate inputs were read.\n')
  invisible(input)
}

if (sys.nframe()==0L) figure1_main()
