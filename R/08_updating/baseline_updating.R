# Publication source copy. See docs/original_script_mapping.md and reproducibility_notes.md.

gbc_recalibration <- local({
  S <- new.env(parent=emptyenv())
  CFG <- list(seed=20260905L, module_stream=3L, B=1000L, tau=3,
              models=c("A","B","C"), causes=c("GBC","Other","All_death"))
  CFG$files <- c(patient="data/analysis_patient_level_v2.parquet", landmark="data/analysis_landmark_long_v2.parquet",
    sap="spec/SAP_TECHNICAL_ADDENDUM_v1.1.md", models="outputs/DEVELOPMENT_MODELS.rds",
    validation="outputs/VALIDATION_RESULTS.xlsx", report="outputs/VALIDATION_REPORT.md", library="R/07_validation/temporal_validation.R")
  CFG$hashes <- setNames(character(7),names(CFG$files))
  CFG$hashes[["patient"]] <- "b8bb4d6d7a5c00924aedd9383c3be4ba22c7b0c1060d72288be64207d88fd870"
  CFG$hashes[["landmark"]] <- "6d7ebcc62aa2da953ccdada3cce61ab366bcd0dfde0b24d7349bdafa5efe5da1"
  CFG$hashes[["sap"]] <- "9a5e363afb395fe86d12ddc94817b4d727af74dae0dc27946acb6d00c79c328d"
  CFG$hashes[["models"]] <- "7a331db957503af153aaf119a3d439b6f8e5edb56f769b1457a65ff9038af74f"
  CFG$hashes[["validation"]] <- "8e4b7ee40885b3c2c9a252af5b0b5e7815bb836270c123c7147acb53df69fc59"
  CFG$hashes[["report"]] <- "bd5672c14e1c78d23ba728c41ea0458fbcc558fa5de83b6aafbb44fcf310c2b9"
  CFG$hashes[["library"]] <- "4702d2f7698b160eeb059ff57c885c44fe58b91a88011e648a475868b2ad50ae"
  files <- unlist(lapply(sys.frames(),function(f)f$ofile))
  files <- c(sub("^--file=","",grep("^--file=",commandArgs(),value=TRUE)),files)
  S$script <- if(length(files))tail(files,1) else NA_character_
  assert <- function(ok,msg) {if(!isTRUE(ok))stop(msg,call.=FALSE);invisible(TRUE)}
  say <- function(...) {cat(format(Sys.time(),"%H:%M:%S"),...,"\n");flush.console()}
  capture <- function(exe,args) {
    z <- suppressWarnings(system2(exe,vapply(args,shQuote,character(1)),stdout=TRUE,stderr=TRUE))
    assert(is.null(attr(z,"status")),paste("Dependency/read failed:",paste(z,collapse="\n"))); z
  }
  py_json <- function(code,args=character(),python=S$python) {
    jsonlite::fromJSON(paste(capture(python,c("-c",code,args)),collapse=""))
  }
  hashes <- function() {
    h <- vapply(CFG$files,function(p)digest::digest(file=file.path(S$root,p),algo="sha256"),character(1))
    assert(identical(unname(h),unname(CFG$hashes)),"Frozen input changed: STOP, do not repair/reclean/retrain."); h
  }
  setup <- function() {
    roots <- c(if(!is.na(S$script))dirname(dirname(normalizePath(S$script,winslash="/",mustWork=TRUE))),getwd(),Sys.getenv("GBC_FINAL_RUN_ROOT", unset = getwd()))
    ok <- vapply(roots,function(p)file.exists(file.path(p,CFG$files[["library"]])) && file.exists(file.path(p,CFG$files[["validation"]])),logical(1))
    assert(any(ok),"Cannot locate gbc_final_run with completed formal validation.")
    S$root <- normalizePath(roots[which(ok)[1]],winslash="/",mustWork=TRUE)
    S$mode <- getOption("gbc.recalibration.mode","final")
    assert(S$mode %in% c("final","smoke"),"Mode must be final or smoke.")
    S$B <- if(S$mode=="final")CFG$B else 3L
    assert(as.character(getRversion())=="4.4.3","Use the locked R 4.4.3 runtime.")
    versions <- c(survival="3.8.3",Hmisc="5.2.3",jsonlite="2.0.0",digest="0.6.37",processx="3.8.6")
    for(p in names(versions))assert(requireNamespace(p,quietly=TRUE) &&
      utils::compareVersion(as.character(utils::packageVersion(p)),versions[[p]])==0,paste("Missing/mismatched locked package:",p))
    suppressPackageStartupMessages(library(survival))
    hashes()
    libenv <- new.env(parent=.GlobalEnv)
    old <- getOption("gbc.validation.autorun"); options(gbc.validation.autorun=FALSE)
    tryCatch(sys.source(file.path(S$root,CFG$files[["library"]]),envir=libenv),finally=options(gbc.validation.autorun=old))
    S$V <- libenv$gbc_validation
    assert(is.environment(S$V) && all(c("predict_frozen","design","weights_ipcw","aj","auc2","calibrate") %in% ls(S$V)),"Required validated functions unavailable.")
    frozen <- readRDS(file.path(S$root,CFG$files[["models"]]))
    assert(isTRUE(frozen$formal_run) && frozen$mode=="final" && frozen$selected_C=="C_FULL" &&
           all(frozen$stability$valid==500L) && all(is.na(frozen$PH_selection)),"Frozen development eligibility mismatch.")
    assert(identical(as.numeric(frozen$knots),c(48,65,76,87)),"Frozen age knots mismatch.")
    S$models <- frozen$models[c("A","B","C_FULL")];names(S$models) <- CFG$models
    S$model_hash <- digest::digest(S$models,algo="sha256")
    for(m in CFG$models)for(k in 1:2)assert(is.null(S$models[[m]][[k]]$tv) && S$models[[m]][[k]]$theta==1 &&
      all(is.finite(S$models[[m]][[k]]$beta)),"Unexpected frozen model structure.")
    runtime <- Sys.getenv("GBC_RUNTIME_ROOT")
    S$python <- Sys.getenv("GBC_PYTHON")
    S$audit_python <- file.path(runtime,"python/python.exe")
    S$node <- file.path(runtime,"node/bin/node.exe");S$modules <- file.path(runtime,"node/node_modules")
    for(p in c(S$python,S$audit_python,S$node,S$modules))assert(file.exists(p),paste("Missing existing dependency:",p))
    capture(S$python,c("-c","import pyarrow,pandas; print(pyarrow.__version__)"))
    capture(S$audit_python,c("-c","import openpyxl; print(openpyxl.__version__)"))
    report <- readLines(file.path(S$root,CFG$files[["report"]]),warn=FALSE,encoding="UTF-8")
    assert(any(grepl("Mode: final",report,fixed=TRUE)) && any(grepl("Patient bootstrap attempts: 1000",report,fixed=TRUE)),
           "The existing main validation must be FINAL, not SMOKE.")
    S$outdir <- if(S$mode=="final")file.path(S$root,"outputs") else tempfile("gbc_recalibration_smoke_")
    dir.create(S$outdir,showWarnings=FALSE,recursive=TRUE)
    S$targets <- file.path(S$outdir,c("RECALIBRATION_RESULTS.xlsx","RECALIBRATION_REPORT.md"))
    assert(!any(file.exists(S$targets)),"Recalibration output already exists; refusing to overwrite.")
    say("Baseline-only",S$mode,"; beta frozen; main validation will be imported, not recomputed.")
  }
  read_existing_validation <- function() {
    code <- r"---(import json,sys
import openpyxl
w=openpyxl.load_workbook(sys.argv[1],read_only=True,data_only=True)
needed=['performance','calibration','calibration_curve_data']
out={}
for name in needed:
    it=w[name].iter_rows(min_row=5,values_only=True); fields=list(next(it)); records=[]
    for vals in it:
        if all(v is None for v in vals): continue
        records.append({k:(vals[j] if j<len(vals) else None) for j,k in enumerate(fields) if k is not None})
    out[name]=records
w.close();print(json.dumps(out,separators=(',',':')))
)---"
    x <- py_json(code,file.path(S$root,CFG$files[["validation"]]),S$audit_python)
    p <- x$performance[x$performance$analysis=="primary",,drop=FALSE]
    c <- x$calibration[x$calibration$analysis=="primary",,drop=FALSE]
    assert(nrow(p)==54 && nrow(c)==27 && all(p$bootstrap_attempts==1000L),"Existing validation schema/replicate count mismatch.")
    assert(setequal(unique(p$model),c("A","B","C_FULL")) && setequal(unique(p$cause),CFG$causes),"Existing validation model/cause mismatch.")
    S$existing <- list(performance=p,calibration=c,curves=x$calibration_curve_data)
    say("Imported formal validation:",nrow(p),"performance rows,",nrow(c),"calibration cells; preserved source CIs.")
    invisible(S$existing)
  }
  count_windows <- function(d,period) {
    do.call(rbind,lapply(1:3,function(s) {
      z <- d[d$time>s,,drop=FALSE];u <- z$time-s
      data.frame(period=period,landmark=s,n=nrow(z),GBC=sum(u<=3 & z$status==1),Other=sum(u<=3 & z$status==2),
                 early_censored=sum(u<3 & z$status==0),source_n=nrow(d),record_type="Landmark_counts")
    }))
  }
  read_data <- function() {
    code <- r"---(import json,sys,hashlib
from pathlib import Path
import pyarrow.parquet as pq
root=Path(sys.argv[1]);mode=sys.argv[2]
source=root/'data/analysis_patient_level_v2.parquet'
flt=[('year_dx','>=',2012),('year_dx','<=',2017)]
c=pq.read_table(source,columns=['patient_id','year_dx','survival_days_analysis','event_competing'],filters=flt).to_pandas()
assert c.patient_id.is_unique
counts=[]; ids=[]
for label,start,end in [('UPDATE_2012_2014',2012,2014),('POST_2015_2017',2015,2017)]:
    q=c[c.year_dx.between(start,end)]; t=q.survival_days_analysis/365.25
    for s in [1,2,3]:
        a=q[t>s];u=a.survival_days_analysis/365.25-s;e=a.event_competing
        counts.append(dict(period=label,landmark=s,n=len(a),GBC=int(((u<=3)&(e==1)).sum()),Other=int(((u<=3)&(e==2)).sum()),early_censored=int(((u<3)&(e==0)).sum()),source_n=len(q),record_type='Full_count_reconciliation'))
    picked=sorted(q.patient_id.tolist(),key=lambda x:hashlib.sha256(('20260905|recal_smoke|'+label+'|'+str(x)).encode()).hexdigest())[:60]
    ids.extend(picked)
if mode!='final':flt=flt+[('patient_id','in',ids)]
cols=['patient_id','record_id','year_dx','age_dx','age_90plus_flag','sex','T_model','N_model','grade_model','survival_days_analysis','event_competing','M_harmonized']
p=pq.read_table(source,columns=cols,filters=flt).to_pandas().sort_values('patient_id',kind='stable')
lc=['patient_id','record_id','year_dx','landmark_year','time_from_landmark','time_to_analysis_end','event_within_window','analysis_role']
l=pq.read_table(root/'data/analysis_landmark_long_v2.parquet',columns=lc,filters=flt+[('analysis_role','==','PREDICTION_PREP')]).to_pandas()
print(json.dumps(dict(patient=json.loads(p.to_json(orient='records')),landmark=json.loads(l.to_json(orient='records')),counts=counts),separators=(',',':')))
)---"
    obj <- py_json(code,c(S$root,S$mode));d <- obj$patient;l <- obj$landmark
    expected <- data.frame(period=rep(c("UPDATE_2012_2014","POST_2015_2017"),each=3),landmark=rep(1:3,2))
    expected$n <- c(775L,575L,463L,758L,570L,471L)
    expected$GBC <- c(287L,157L,83L,277L,146L,85L)
    expected$Other <- c(85L,63L,65L,79L,74L,73L)
    expected$early_censored <- c(9L,8L,2L,11L,11L,11L)
    for(k in names(expected))assert(identical(as.character(obj$counts[[k]]),as.character(expected[[k]])),
      paste("STOP: full-period count mismatch in",k,"; no cohort redefinition allowed."))
    S$full_counts <- obj$counts
    assert(nrow(d)>0 && !anyNA(d) && !anyDuplicated(d$patient_id) && !anyDuplicated(d$record_id),"Invalid frozen patient identifiers/data.")
    d$time <- d$survival_days_analysis/365.25;d$status <- as.integer(d$event_competing)
    d$T_core <- ifelse(d$T_model %in% c("Unknown","Unknown/nonstandard"),"Unknown",d$T_model)
    d$age_group <- as.character(cut(d$age_dx,c(-Inf,65,80,Inf),right=FALSE,labels=c("<65","65-79",">=80")))
    assert(all(d$year_dx %in% 2012:2017) && all(d$M_harmonized=="M0") && all(d$status %in% 0:2) &&
      all(is.finite(d$time)) && all(d$time>0) && all(d$age_dx[d$age_90plus_flag]==90),"Frozen coding/year/time mismatch.")
    for(v in list(c("sex","Female","Male"),c("T_core","T1","T2","T3/4","Unknown"),
      c("N_model","N0","N+","Unknown"),c("grade_model","G1","G2","G3/4","Unknown")))
      assert(all(d[[v[1]]] %in% v[-1]),paste("Invalid frozen category:",v[1]))
    rebuilt <- do.call(rbind,lapply(1:3,function(s) {z<-d[d$time>s,,drop=FALSE];z$lm<-s;z$u<-z$time-s;z}))
    key <- function(id,s)paste(id,s,sep="|")
    j <- match(key(rebuilt$record_id,rebuilt$lm),key(l$record_id,l$landmark_year))
    assert(nrow(rebuilt)==nrow(l) && !anyNA(j) && !anyDuplicated(key(l$record_id,l$landmark_year)) &&
      all(l$analysis_role=="PREDICTION_PREP") && max(abs(l$time_from_landmark[j]/365.25-rebuilt$u))<1e-8 &&
      max(abs(l$time_to_analysis_end[j]/365.25-pmin(rebuilt$u,3)))<1e-8 &&
      all(l$event_within_window[j]==ifelse(rebuilt$u<=3,rebuilt$status,0L)),"Stored/rebuilt landmark mismatch.")
    u <- d[d$year_dx<=2014,,drop=FALSE];e <- d[d$year_dx>=2015,,drop=FALSE]
    u$source_index <- seq_len(nrow(u));e$source_index <- seq_len(nrow(e))
    u$cluster <- u$source_index;e$cluster <- e$source_index
    firewall(u,e)
    if(S$mode=="smoke")assert(nrow(u)<=60L && nrow(e)<=60L,"SMOKE source-patient cap exceeded.")
    S$counts <- rbind(count_windows(u,"UPDATE_2012_2014"),count_windows(e,"POST_2015_2017"))
    say("Count reconciliation PASS; independent sources:",nrow(u),"update /",nrow(e),"evaluation patients.")
    list(update=u,evaluation=e)
  }
  firewall <- function(update,evaluation=NULL) {
    assert(nrow(update)>0 && all(update$year_dx %in% 2012:2014),"FIREWALL: baseline updating permits 2012-2014 only.")
    if(!is.null(evaluation))assert(nrow(evaluation)>0 && all(evaluation$year_dx %in% 2015:2017) &&
      !any(evaluation$patient_id %in% update$patient_id),"FIREWALL: independent evaluation permits disjoint 2015-2017 only.")
    invisible(TRUE)
  }
  signature <- function(models) lapply(models,function(pair)lapply(pair,function(f) {f$baseline<-NULL;f$support<-NULL;f}))
  breslow_offset <- function(time,event,lp) {
    assert(length(time)==length(lp) && all(is.finite(time)) && all(is.finite(lp)),"Invalid baseline offset input.")
    times <- sort(unique(time[event]));weights <- exp(lp)
    assert(all(is.finite(weights)) && all(weights>0),"Nonfinite/zero offset risk weights.")
    if(!length(times))return(data.frame(time=numeric(),hazard=numeric(),events=integer()))
    ord <- order(time);risk <- rev(cumsum(rev(weights[ord])))
    den <- risk[match(times,time[ord])]
    deaths <- tabulate(match(time[event],times),nbins=length(times))
    assert(all(den>0) && all(is.finite(den)),"Unsupported baseline risk set.")
    data.frame(time=times,hazard=deaths/den,events=deaths)
  }
  update_baselines <- function(update,audit=FALSE) {
    firewall(update);out <- S$models;ledger <- list()
    for(m in CFG$models)for(k in 1:2) {
      base <- list();support <- numeric()
      for(s in if(m=="A")1L else 1:3) {
        d <- update[update$time>s,,drop=FALSE]
        if(!nrow(d)) {base[[as.character(s)]]<-data.frame(time=numeric(),hazard=numeric(),events=integer());support[as.character(s)]<-0;next}
        x <- S$V$design(d,s,m,k);beta <- S$models[[m]][[k]]$beta
        assert(identical(colnames(x),names(beta)),"Frozen design/offset coefficient mismatch.")
        lp <- drop(x%*%beta)
        tt <- if(m=="A")d$time else pmin(d$time-s,3)
        event <- d$status==k & (m=="A" | d$time-s<=3)
        b <- breslow_offset(tt,event,lp)
        if(audit && nrow(b)) {
          independent <- vapply(b$time,function(t)sum(tt==t & event)/sum(exp(lp[tt>=t])),numeric(1))
          assert(max(abs(b$hazard-independent))<1e-12,"Independent Breslow offset check failed.")
        }
        base[[as.character(s)]] <- b;support[as.character(s)] <- max(tt)
        if(audit)ledger[[length(ledger)+1L]] <- data.frame(period="UPDATE_2012_2014",model=if(m=="C")"C_FULL" else m,
          cause=CFG$causes[k],landmark=s,n=nrow(d),events=sum(event),baseline_jumps=nrow(b),
          maximum_followup=max(tt),risk_set_at_6y=if(m=="A")sum(tt>=6) else NA_integer_,
          events_after_diagnosis_year4=if(m=="A")sum(event & tt>4) else NA_integer_,record_type="Baseline_update",
          status=if(max(tt)>=if(m=="A")6 else 3)"SUPPORTED" else "HORIZON_UNSUPPORTED")
      }
      out[[m]][[k]]$baseline <- base;out[[m]][[k]]$support <- support
    }
    assert(identical(signature(out),signature(S$models)),"BETA/STRUCTURE CHANGED: STOP.")
    assert(all(vapply(out$A,function(f)identical(names(f$baseline),"1"),logical(1))) &&
      all(vapply(c(out$B,out$C),function(f)identical(names(f$baseline),as.character(1:3)),logical(1))),"A/B/C baseline structure changed.")
    if(audit)S$baseline_ledger <- do.call(rbind,ledger)
    out
  }
  predict_all <- function(models,d) {
    out <- list()
    for(s in 1:3) {
      ii <- which(d$time>s);out[[as.character(s)]] <- list()
      for(m in CFG$models) {
        p <- matrix(NA_real_,nrow(d),3)
        if(length(ii) && !is.null(models))p[ii,] <- S$V$predict_frozen(models[[m]],d[ii,,drop=FALSE],s,m)$p
        out[[as.character(s)]][[m]] <- p
      }
    }
    out
  }
  subset_predictions <- function(cache,draw)lapply(cache,function(z)lapply(z,function(p)p[draw,,drop=FALSE]))
  make_curve_spec <- function(d,original,updated) {
    spec <- list()
    for(s in 1:3) {
      ii <- which(d$time>s);spec[[as.character(s)]] <- list()
      spec[[as.character(s)]]$cap10 <- S$V$weights_ipcw(d[ii,,drop=FALSE],s)$truncate
      for(state in c("ORIGINAL","UPDATED")) {
        pr <- if(state=="ORIGINAL")original else updated
        spec[[as.character(s)]][[state]] <- list()
        for(m in CFG$models) {
          p <- pr[[as.character(s)]][[m]][ii,,drop=FALSE]
          spec[[as.character(s)]][[state]][[m]] <- lapply(1:3,function(k) {
            v <- if(k==3)rowSums(p[,1:2,drop=FALSE]) else p[,k]
            ok <- length(v)>0 && all(is.finite(v))
            list(grid=if(ok)unique(S$V$q7(v,seq(0,1,length.out=61))) else numeric(),
                 central=if(ok)S$V$q7(v,c(.01,.99)) else c(NA_real_,NA_real_))
          })
        }
      }
    }
    spec
  }
  row_key <- function(z)paste(z$era,z$model,z$cause,z$landmark,z$analysis,z$record_type,z$metric,z$index,sep="|")
  evaluate <- function(d,original,updated,spec,detailed=FALSE) {
    assert(all(d$year_dx %in% 2015:2017),"FIREWALL: scoring permits 2015-2017 only.")
    rows <- list()
    add <- function(s,m,k,state,analysis,type,metric,value,n,events,other=NA_integer_,index="",x=NA_real_,
                    note="",support="OK",count=NA_real_,density=NA_real_,bin_lower=NA_real_,bin_upper=NA_real_) {
      rows[[length(rows)+1L]] <<- data.frame(era=paste0("POST_2015_2017_",state),
        model=if(m=="C")"C_FULL" else m,cause=k,landmark=s,status=state,analysis=analysis,
        record_type=type,metric=metric,estimate=as.numeric(value),n=n,events=events,other_events=other,
        index=as.character(index),predicted_risk=x,count=count,density=density,bin_lower=bin_lower,bin_upper=bin_upper,
        support_flag=support,note=note,stringsAsFactors=FALSE)
    }
    for(s in 1:3) {
      ii <- which(d$time>s);dd <- d[ii,,drop=FALSE];n <- nrow(dd);u <- dd$time-s;e <- dd$status
      iw <- S$V$weights_ipcw(dd,s)
      weights <- list(primary=iw,covariate=S$V$weights_ipcw(dd,s,"covariate"))
      if(spec[[as.character(s)]]$cap10) {cw<-iw;cw$w<-pmin(cw$w,10);weights$cap10<-cw}
      obs <- S$V$aj(u,e);ne <- c(sum(u<=3 & e==1),sum(u<=3 & e==2),sum(u<=3 & e>0))
      for(name in names(iw$stats))add(s,"Shared","All","SHARED","primary","IPCW_QC",name,iw$stats[[name]],n,ne[3],
        support=if(iw$reliable)"OK" else "UNRELIABLE",note=iw$note)
      for(state in c("ORIGINAL","UPDATED"))for(m in CFG$models) {
        pp <- (if(state=="ORIGINAL")original else updated)[[as.character(s)]][[m]][ii,,drop=FALSE]
        supported <- n>0 && all(is.finite(pp))
        qc <- c(unsupported_n=if(n)sum(!is.finite(rowSums(pp))) else 0,
          closure_max_error=if(supported)max(abs(rowSums(pp)-1)) else NA_real_,
          minimum_probability=if(supported)min(pp) else NA_real_)
        add(s,m,"Three_state",state,"primary","Probability_QC",names(qc),qc,n,ne[3],
            note="Numerical coherence only, not empirical calibration")
        for(k in 1:3) {
          p <- if(k==3)rowSums(pp[,1:2,drop=FALSE]) else pp[,k]
          y <- as.integer(u<=3 & if(k==3)e>0 else e==k)
          O <- if(k==3)sum(obs[1:2]) else unname(obs[k]);E <- S$V$mean_safe(p)
          oe <- if(is.finite(E) && E>0)O/E else NA_real_
          cs <- spec[[as.character(s)]][[state]][[m]][[k]]
          for(method in names(weights)) {
            w <- weights[[method]];cal <- S$V$calibrate(p,y,w$w,grid=if(method=="primary")cs$grid else numeric())
            good <- supported && all(is.finite(w$w))
            slope <- cal$values[["slope"]]
            values <- c(AUC2=S$V$auc2(p,y,w$w),Brier=if(good)sum(w$w*(y-p)^2)/n else NA_real_,
              observed_AJ=O,mean_predicted=E,O_over_E=oe,O_minus_E_pp=100*(O-E),abs_O_minus_E_pp=100*abs(O-E),
              calibration_intercept=cal$values[["intercept"]],calibration_slope=slope,
              calibration_offset_intercept=cal$values[["offset_intercept"]],abs_slope_minus_1=abs(slope-1),
              abs_log_OE=if(is.finite(oe) && oe>0)abs(log(oe)) else NA_real_,ICI=cal$values[["ICI"]])
            support <- if(!supported)"PREDICTION_UNSUPPORTED" else if(!w$reliable)"IPCW_UNRELIABLE" else "OK"
            add(s,m,CFG$causes[k],state,method,"Metric",names(values),values,n,ne[k],if(k<3)ne[3-k] else 0,
              support=support,note=cal$method)
            if(method=="primary" && length(cs$grid)) {
              notes <- if(detailed)paste(cal$method,"; knots(logit)=",paste(signif(cal$knots,8),collapse="/"),
                ifelse(cs$grid<cs$central[1] | cs$grid>cs$central[2],"; sparse_tail","; central_1_99_percent")) else ""
              add(s,m,CFG$causes[k],state,method,"smooth_curve","observed_smoothed_risk",cal$curve,n,ne[k],
                index=seq_along(cs$grid),x=cs$grid,support=support,note=notes)
            }
          }
          if(detailed && supported) {
            h <- hist(p,breaks=seq(0,1,length.out=21),plot=FALSE)
            add(s,m,CFG$causes[k],state,"primary","risk_histogram","count",h$counts,n,ne[k],index=seq_len(20),
              x=h$mids,count=h$counts,density=h$counts/(n*.05),bin_lower=h$breaks[1:20],bin_upper=h$breaks[2:21],
              note="Original evaluation-sample prediction distribution; width=.05; unweighted count/density")
          }
        }
      }
    }
    tab <- do.call(rbind,rows)
    metrics <- c("AUC2","Brier","abs_O_minus_E_pp","ICI","abs_slope_minus_1","calibration_slope","abs_log_OE")
    z <- tab[tab$record_type=="Metric" & tab$metric %in% metrics,,drop=FALSE]
    original_rows <- z[z$status=="ORIGINAL",,drop=FALSE];new <- z[z$status=="UPDATED",,drop=FALSE]
    k <- function(a)paste(a$model,a$cause,a$landmark,a$analysis,a$metric,sep="|")
    j <- match(k(new),k(original_rows));assert(!anyNA(j),"Paired update keys mismatch.")
    new$original <- original_rows$estimate[j];new$updated <- new$estimate
    new$estimate <- new$updated-new$original;new$status <- "UPDATED_MINUS_ORIGINAL"
    new$era <- "POST_2015_2017_PAIRED";new$record_type <- "Paired_effect"
    new$support_flag <- ifelse(new$support_flag=="OK" & original_rows$support_flag[j]=="OK","OK","UNRELIABLE")
    new$note <- ifelse(new$metric=="AUC2","Positive favors updated; not the recalibration success criterion",
      ifelse(new$metric=="calibration_slope","Signed slope change; judge distance to 1, not a larger slope",
             "Negative favors updated; evaluate effect size and paired CI without a clinical threshold"))
    tab$original <- tab$updated <- NA_real_
    tab <- rbind(tab,new[,names(tab)]);tab$key <- row_key(tab)
    assert(!anyDuplicated(tab$key),"Duplicate metric/curve key.")
    tab
  }
  rng_streams <- function() {
    RNGkind("L'Ecuyer-CMRG");set.seed(CFG$seed)
    module <- get(".Random.seed",envir=.GlobalEnv)
    for(j in seq_len(CFG$module_stream))module <- parallel::nextRNGStream(module)
    list(update=module,evaluation=parallel::nextRNGSubStream(module))
  }
  bootstrap <- function(update,evaluation,original,spec,point) {
    streams <- rng_streams();S$initial_streams <- streams
    ii <- which(!point$record_type %in% c("risk_histogram","Probability_QC"))
    keys <- point$key[ii];values <- matrix(NA_real_,length(ii),S$B)
    errors <- rep("",S$B);update_failures <- 0L
    for(b in seq_len(S$B)) {
      assign(".Random.seed",streams$update,envir=.GlobalEnv)
      iu <- sample.int(nrow(update),nrow(update),replace=TRUE);streams$update <- get(".Random.seed",envir=.GlobalEnv)
      assign(".Random.seed",streams$evaluation,envir=.GlobalEnv)
      ie <- sample.int(nrow(evaluation),nrow(evaluation),replace=TRUE);streams$evaluation <- get(".Random.seed",envir=.GlobalEnv)
      du <- update[iu,,drop=FALSE];de <- evaluation[ie,,drop=FALSE]
      du$cluster <- seq_len(nrow(du));de$cluster <- seq_len(nrow(de));firewall(du,de)
      assert(length(unique(du$cluster))==nrow(update) && length(unique(de$cluster))==nrow(evaluation),"Patient copies collapsed.")
      updated <- tryCatch(update_baselines(du),error=function(e)e)
      if(inherits(updated,"error")) {errors[b]<-conditionMessage(updated);updated<-NULL;update_failures<-update_failures+1L}
      pr <- tryCatch(predict_all(updated,de),error=function(e)e)
      if(inherits(pr,"error")) {errors[b]<-conditionMessage(pr);pr<-predict_all(NULL,de);update_failures<-update_failures+1L}
      ev <- tryCatch(evaluate(de,subset_predictions(original,ie),pr,spec),error=function(e)e)
      if(inherits(ev,"error"))errors[b] <- conditionMessage(ev) else {
        jj <- match(keys,ev$key);assert(!anyNA(jj),"Bootstrap output layout changed.")
        values[,b] <- ev$estimate[jj]
      }
      if(b==1L || b%%10L==0L || b==S$B)say("Two-sample patient bootstrap",b,"/",S$B)
    }
    point$lower95 <- point$upper95 <- NA_real_;point$valid_bootstrap <- NA_integer_;point$bootstrap_attempts <- NA_integer_
    sensitive <- point$record_type=="smooth_curve" | point$metric %in%
      c("calibration_slope","calibration_intercept","calibration_offset_intercept","abs_slope_minus_1","ICI")
    for(j in seq_along(ii)) {
      r <- ii[j];v <- values[j,];valid <- is.finite(v);nv <- sum(valid)
      point$valid_bootstrap[r] <- nv;point$bootstrap_attempts[r] <- S$B
      if(nv/S$B>=.95 && is.finite(point$estimate[r]))point[r,c("lower95","upper95")] <- S$V$q7(v[valid],c(.025,.975)) else {
        point$support_flag[r] <- paste(point$support_flag[r],"CI_UNSUPPORTED_<95%",sep="; ")
        if(sensitive[r])point$estimate[r] <- NA_real_
      }
      if(!is.finite(point$estimate[r]))point$support_flag[r] <- paste(point$support_flag[r],"ESTIMATE_NA",sep="; ")
    }
    list(table=point,errors=errors,update_failures=update_failures,attempts=S$B)
  }
  historical_metrics <- function() {
    p <- S$existing$performance
    p$era <- "VALIDATION_2012_2017_ORIGINAL";p$status <- "ORIGINAL";p$analysis <- "primary"
    p$record_type <- "Metric";p$support_flag <- p$status
    p$support_flag <- S$existing$performance$status
    p$note <- "Imported unchanged from formal VALIDATION_RESULTS.xlsx; existing validation-only percentile CI"
    c <- S$existing$calibration
    mapping <- c(observed_AJ="observed_AJ",mean_predicted="mean_predicted",O_over_E="O_over_E",O_minus_E="O_minus_E_pp",
      abs_O_minus_E="abs_O_minus_E_pp",calibration_intercept="calibration_intercept",calibration_slope="calibration_slope",
      calibration_offset_intercept="calibration_offset_intercept",ICI="ICI")
    rows <- lapply(names(mapping),function(k) {
      data.frame(era="VALIDATION_2012_2017_ORIGINAL",model=c$model,cause=c$cause,landmark=c$landmark,status="ORIGINAL",
        analysis="primary",record_type="Metric",metric=mapping[[k]],estimate=c[[k]],lower95=c[[paste0(k,"_lower95")]],
        upper95=c[[paste0(k,"_upper95")]],n=c$n,events=c$events,other_events=c$other_events,
        valid_bootstrap=c[[paste0(k,"_valid_bootstrap")]],bootstrap_attempts=1000L,
        support_flag=c[[paste0(k,"_status")]],note="Imported unchanged; O-E uses percentage points")
    })
    for(k in c("abs_slope_minus_1","abs_log_OE")) {
      value <- if(k=="abs_slope_minus_1")abs(c$calibration_slope-1) else ifelse(c$O_over_E>0,abs(log(c$O_over_E)),NA_real_)
      rows[[length(rows)+1L]] <- data.frame(era="VALIDATION_2012_2017_ORIGINAL",model=c$model,cause=c$cause,landmark=c$landmark,
        status="ORIGINAL",analysis="primary",record_type="Metric",metric=k,estimate=value,lower95=NA_real_,upper95=NA_real_,
        n=c$n,events=c$events,other_events=c$other_events,valid_bootstrap=NA_integer_,bootstrap_attempts=1000L,
        support_flag="SOURCE_DERIVED_POINT_ONLY",note="Simple transformation of saved estimate; raw validation draws unavailable, so transformed percentile CI NOT fabricated")
    }
    S$V$bind_fill(c(list(p),rows))
  }
  shape_sheets <- function(tab) {
    hist <- historical_metrics()
    all_metrics <- S$V$bind_fill(list(hist,tab[tab$record_type=="Metric",,drop=FALSE]))
    perf_cols <- c("era","model","cause","landmark","status","analysis","metric","estimate","lower95","upper95",
                   "n","events","other_events","valid_bootstrap","bootstrap_attempts","support_flag","note")
    performance <- all_metrics[all_metrics$metric %in% c("AUC2","Brier"),perf_cols,drop=FALSE]
    cal_long <- all_metrics[!all_metrics$metric %in% c("AUC2","Brier"),,drop=FALSE]
    cal_long$version <- cal_long$status;cal_long$status <- cal_long$support_flag
    ids <- c("era","model","cause","landmark","version","analysis")
    calmap <- setNames(c("observed_AJ","mean_predicted","O_over_E","O_minus_E_pp","abs_O_minus_E_pp",
      "calibration_intercept","calibration_slope","calibration_offset_intercept","abs_slope_minus_1","abs_log_OE","ICI"),
      c("observed_AJ","mean_predicted","O_over_E","O_minus_E_pp","abs_O_minus_E_pp","calibration_intercept",
        "calibration_slope","calibration_offset_intercept","abs_slope_minus_1","abs_log_OE","ICI"))
    calibration <- S$V$wide_metrics(cal_long,ids,calmap)
    names(calibration)[names(calibration)=="version"] <- "status"
    pa <- tab[tab$record_type=="Paired_effect",,drop=FALSE]
    pa$difference <- pa$estimate
    paired <- pa[,c("model","cause","landmark","analysis","metric","original","updated","difference","lower95","upper95",
                     "n","events","valid_bootstrap","bootstrap_attempts","support_flag","note"),drop=FALSE]
    old_curves <- S$existing$curves
    old_curves$era <- "VALIDATION_2012_2017_ORIGINAL";old_curves$status <- "ORIGINAL";old_curves$analysis <- "primary"
    old_curves$note <- paste("Imported unchanged from formal main validation.",old_curves$note)
    curves <- tab[tab$record_type %in% c("smooth_curve","risk_histogram"),,drop=FALSE]
    curves$observed_smoothed_risk <- ifelse(curves$record_type=="smooth_curve",curves$estimate,NA_real_)
    curves$interpretation_range <- ifelse(grepl("sparse_tail",curves$note,fixed=TRUE),"sparse_tail",
      ifelse(curves$record_type=="smooth_curve","central_1_99_percent","full_prediction_range"))
    curves$risk_bin <- ifelse(curves$record_type=="risk_histogram",as.integer(curves$index),NA_integer_)
    curves <- S$V$bind_fill(list(old_curves,curves))
    curve_cols <- c("era","model","cause","landmark","status","analysis","predicted_risk","observed_smoothed_risk",
      "lower95","upper95","record_type","observed_AJ","risk_bin","bin_lower","bin_upper","count","density",
      "n","events","interpretation_range","valid_bootstrap","bootstrap_attempts","support_flag","note")
    curves <- curves[,curve_cols,drop=FALSE]
    qc <- tab[tab$record_type %in% c("IPCW_QC","Probability_QC"),
      c("era","model","cause","landmark","status","record_type","metric","estimate","n","events","support_flag","note"),drop=FALSE]
    counts <- S$counts;counts$record_type <- if(S$mode=="smoke")"SMOKE_evaluated_counts" else "Evaluated_counts"
    cohort_counts <- S$V$bind_fill(list(counts,S$full_counts,S$baseline_ledger,qc))
    assert(sum(performance$era=="VALIDATION_2012_2017_ORIGINAL")==54L &&
      sum(performance$analysis=="primary")==162L,"Three-era primary performance rows missing.")
    assert(sum(paired$analysis=="primary")==189L,"Paired update metrics missing.")
    assert(sum(calibration$analysis=="primary")==81L,"Three-era calibration cells missing.")
    for(era in c("POST_2015_2017_ORIGINAL","POST_2015_2017_UPDATED")) {
      h <- curves[curves$era==era & curves$record_type=="risk_histogram",,drop=FALSE]
      for(z in split(h,paste(h$model,h$cause,h$landmark)))
        assert(sum(z$count)==z$n[1] && abs(sum(z$density*(z$bin_upper-z$bin_lower))-1)<1e-10,"Plot-ready histogram normalization failed.")
    }
    list(cohort_counts=cohort_counts,performance=performance,calibration=calibration,
         paired_update_effect=paired,calibration_curve_data=curves)
  }
  fmt <- function(z,digits=3) {
    if(!nrow(z) || !is.finite(z$estimate[1]))return("NA")
    est <- formatC(z$estimate[1],format="f",digits=digits)
    if(is.finite(z$lower95[1]) && is.finite(z$upper95[1]))paste0(est," [",formatC(z$lower95[1],format="f",digits=digits),", ",
      formatC(z$upper95[1],format="f",digits=digits),"]") else paste0(est," [CI unavailable]")
  }
  report_lines <- function(tab,boot) {
    metrics <- tab[tab$record_type=="Metric" & tab$analysis=="primary",,drop=FALSE]
    pa <- tab[tab$record_type=="Paired_effect" & tab$analysis=="primary",,drop=FALSE]
    old <- historical_metrics()
    get <- function(m,k,s,state,metric)metrics[metrics$model==m & metrics$cause==k & metrics$landmark==s & metrics$status==state & metrics$metric==metric,,drop=FALSE]
    range_text <- function(x)if(any(is.finite(x)))paste(formatC(range(x[is.finite(x)]),digits=4,format="f"),collapse=" to ") else "not estimable"
    lines <- c(paste0("# ",if(S$mode=="smoke")"SMOKE ONLY - " else "","Baseline-only recalibration"),"",
      "2012-2014 update; independent 2015-2017 post-update evaluation. Future horizon: 3 years at L1/L2/L3.",
      "NO COEFFICIENT REFITTING. NO MODEL TUNING ON POST-UPDATE EVALUATION DATA.","",
      "## Execution and populations", "",
      "Only the two cause-specific baseline hazards were updated. All beta coefficients, age knots, coding, Unknown penalties and C FULL interactions were verified unchanged. A retains one diagnosis-time baseline per cause, estimated from all available follow-up of update-period L1 survivors, then properly conditions at each landmark. B/C retain separate L1/L2/L3 baselines and frozen shared/s-specific predictors.","",
      "| Period | Landmark | n | GBC deaths by 3y | Other deaths by 3y | Early censored |", "|---|---|---:|---:|---:|---:|")
    for(j in seq_len(nrow(S$counts))) {
      r <- S$counts[j,];lines <- c(lines,sprintf("| %s | L%d | %d | %d | %d | %d |",r$period,r$landmark,r$n,r$GBC,r$Other,r$early_censored))
    }
    lines <- c(lines,"","The full frozen-cohort counts matched the requested six landmark screens exactly. Low historical event-count screening for update L2/L3 does not trigger coefficient fitting, cohort expansion or a new stopping rule. Repeated landmarks are not independent patients.",
      paste("Update-period A follow-up extends to",formatC(max(S$baseline_ledger$maximum_followup[S$baseline_ledger$model=="A"]),digits=2,format="f"),
        "years after diagnosis; its post-year-4 events are retained. See cohort_counts for baseline support."),"",
      "## Preserve the original temporal validation", "",
      "The 2012-2017 original-model estimates and confidence intervals are copied from the completed VALIDATION_RESULTS.xlsx. They were not recomputed or overwritten. Comparisons with UPDATED use ORIGINAL on the SAME 2015-2017 evaluation patients, not a different era's overall estimate.","",
      "| Model / cause, L1 | Main 2012-2017 O/E | Main 2012-2017 O-E (pp) | Post ORIGINAL O/E | Post UPDATED O/E |", "|---|---|---|---|---|")
    for(m in c("A","B","C_FULL"))for(k in CFG$causes) {
      h <- old[old$model==m & old$cause==k & old$landmark==1,,drop=FALSE]
      lines <- c(lines,paste0("| ",m," / ",k," | ",fmt(h[h$metric=="O_over_E",])," | ",fmt(h[h$metric=="O_minus_E_pp",]),
        " | ",fmt(get(m,k,1,"ORIGINAL","O_over_E"))," | ",fmt(get(m,k,1,"UPDATED","O_over_E"))," |"))
    }
    lines <- c(lines,"","## Independent post-update effects", "",
      "Entries are UPDATED minus ORIGINAL with paired 95% percentile CI. Negative Brier, absolute O-E, ICI, absolute(slope-1) or absolute log(O/E) favors updating. Positive AUC favors updated discrimination; a larger slope is not automatically better. O-E and its absolute value are percentage points.","",
      "| Model / cause / LM | Delta abs(O-E), pp | Delta ICI | Delta abs(slope-1) | Delta Brier | Delta AUC2 |", "|---|---|---|---|---|---|")
    for(m in c("A","B","C_FULL"))for(k in CFG$causes)for(s in 1:3) {
      vals <- vapply(c("abs_O_minus_E_pp","ICI","abs_slope_minus_1","Brier","AUC2"),function(metric)
        fmt(pa[pa$model==m & pa$cause==k & pa$landmark==s & pa$metric==metric,,drop=FALSE],4),character(1))
      lines <- c(lines,paste0("| ",m," / ",k," / L",s," | ",paste(vals,collapse=" | ")," |"))
    }
    lines <- c(lines,"","The performance/calibration sheets give all ORIGINAL and UPDATED point estimates and intervals, including observed AJ, mean prediction, free and offset intercepts, slope and absolute log(O/E). No model is selected from its highest AUC.","",
      "## Scientific interpretation","")
    improvement <- function(m,metric) {
      z <- pa[pa$model==m & pa$metric==metric,,drop=FALSE]
      c(point_better=sum(z$estimate<0,na.rm=TRUE),supported_better=sum(z$upper95<0 & z$support_flag=="OK",na.rm=TRUE),
        supported_worse=sum(z$lower95>0 & z$support_flag=="OK",na.rm=TRUE))
    }
    counts <- list()
    for(m in c("A","B","C_FULL")) {
      changes <- lapply(c("abs_O_minus_E_pp","ICI","abs_slope_minus_1","Brier","abs_log_OE"),function(metric)improvement(m,metric))
      names(changes) <- c("abs_O_minus_E_pp","ICI","abs_slope_minus_1","Brier","abs_log_OE");counts[[m]]<-changes
      sentences <- vapply(names(changes),function(metric)paste0(metric,": ",changes[[metric]][1],"/9 point improvements; ",
        changes[[metric]][2]," favorable and ",changes[[metric]][3]," unfavorable paired intervals"),character(1))
      lines <- c(lines,paste0(m,": ",paste(sentences,collapse="; "),"."),"")
      a <- pa[pa$model==m & pa$metric=="AUC2",,drop=FALSE]
      slopes <- metrics[metrics$model==m & metrics$status=="UPDATED" & metrics$metric=="calibration_slope",,drop=FALSE]
      remain <- sum((slopes$upper95<1 | slopes$lower95>1) & slopes$support_flag=="OK",na.rm=TRUE)
      lines <- c(lines,paste0(m," delta-AUC2 spans ",range_text(a$estimate),"; ",sum(a$lower95>0,na.rm=TRUE),
        "/9 intervals support a discrimination increase. Updated slopes exclude 1 in ",remain,"/9 cells. ",
        if(remain>0)"Residual slope departures caution that baseline-only updating is insufficient in those cells." else
          "No demonstrated slope departure does not prove correct predictor effects, particularly with wide intervals."),"")
    }
    all_concordant <- all(vapply(counts,function(z)all(vapply(z[c("abs_O_minus_E_pp","ICI","Brier")],
      function(v)v[["supported_better"]]==9,logical(1))),logical(1)))
    lines <- c(lines,if(all_concordant)"Calibration and prediction error improved consistently across all planned cells and models; clinical importance still requires judging the displayed effect sizes." else
      "Baseline-only updating provided heterogeneous or limited benefit: a uniformly supported improvement across all models, causes and landmarks is not established. Favorable individual cells must not be presented as universal success.","",
      "### Did L1 overprediction improve?","")
    for(m in c("A","B","C_FULL"))for(k in CFG$causes) {
      o <- get(m,k,1,"ORIGINAL","O_minus_E_pp");u <- get(m,k,1,"UPDATED","O_minus_E_pp")
      d <- pa[pa$model==m & pa$cause==k & pa$landmark==1 & pa$metric=="abs_O_minus_E_pp",]
      before <- if(is.finite(o$upper95) && o$upper95<0)"original post-period overprediction supported" else "original post-period overprediction not conclusively established"
      change <- if(is.finite(d$upper95) && d$upper95<0)"absolute error reduction supported" else if(is.finite(d$lower95) && d$lower95>0)"absolute error increased" else "absolute error change uncertain"
      after <- if(is.finite(u$upper95) && u$upper95<0)"residual overprediction remains" else if(is.finite(u$lower95) && u$lower95>0)"updated underprediction supported" else "remaining signed deviation uncertain"
      lines <- c(lines,paste0(m," / ",k,": ",before,"; ",change,"; ",after,". O-E: ",fmt(o)," to ",fmt(u)," pp."))
    }
    lines <- c(lines,"",
      "A reduction in O/E distance, absolute O-E or ICI with little AUC change is consistent with correction of baseline absolute-risk drift. It does not prove that predictor effects are unchanged or that baseline drift is the sole cause. Recalibrating both competing hazards can change CIF ranking even when beta is fixed, so AUC invariance is not assumed.",
      "If calibration improves without a demonstrated discrimination gain, report that distinction. No clinical/material delta-AUC threshold was prespecified: crossing zero is not equivalence, and small decimals are not a superiority rule. If residual slope/ICI problems remain, baseline-only recalibration is insufficient; no further beta or slope updating is performed.",
      "These findings concern the independent 2015-2017 evaluation, not retroactive repair of every 2012-2017 prediction. Case mix, coding, cause-of-death error and dependent censoring may contribute. Registry prognosis is not causal treatment benefit or a deployment recommendation. Full update-period follow-up makes this a retrospective transport experiment, not a simulation of information already available at the start of 2015.","",
      "## Methods and uncertainty", "",
      paste("Seed",CFG$seed,"; L'Ecuyer-CMRG module stream",CFG$module_stream,"; independent update/evaluation substreams. Attempts:",
        boot$attempts,"; baseline/prediction failures:",boot$update_failures,"; evaluator errors:",sum(nzchar(boot$errors)),"."),
      "Each draw independently resamples patients within each period, rebuilds all landmarks, re-estimates update baselines and evaluation G/calibration nuisances, and compares ORIGINAL/UPDATED on the same evaluation draw. The updated and paired intervals include update-sample plus evaluation-sample uncertainty, conditional on fixed developed beta. ORIGINAL-only performance naturally depends on the evaluation draw, not the update draw. Failed draws are not replaced.",
      "The validated 02_validation.R functions provide strict-left IPCW, competing-death AUC2 controls, all-patient-denominator Brier, AJ risk and IPCW quasi-binomial low-df calibration. Its support/fallback/link-only clipping and >=95% valid-bootstrap requirements are retained. Calibration slopes are diagnostic estimates, never applied as new predictor coefficients. Covariate/cap10 sensitivities are labeled separately.",
      "Calibration curve grids are fixed from each original point-analysis prediction distribution; nuisance spline knots and updated predictions are recomputed in each draw. Unsupported curve tails are NA; bands are pointwise, not simultaneous. Risk-bin counts/densities in calibration_curve_data allow later plotting without refitting or another bootstrap. Negative/positive ideal distances are never obtained by ad hoc clipping; abs log(O/E) is unavailable when O/E is nonpositive.",
      "Original full-validation percentile intervals are imported, not pooled with post-update intervals. Newly requested absolute transformations whose historical bootstrap draws were not saved have historical point estimates only; their intervals are explicitly unavailable. All post-period transformed-distance intervals use the corresponding two-sample draws.",
      if(S$mode=="smoke")"SMOKE ONLY: <=60 patients per source and 3 draws test execution, firewalls, unchanged beta and the five-sheet export. Neither its intervals nor its narrative are article results." else "")
    lines
  }
  write_workbook <- function(sheets,path) {
    js <- r"---(import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const req=createRequire(path.join(process.argv[1],'recalibration_loader.cjs'));
const {Workbook,SpreadsheetFile}=await import(pathToFileURL(req.resolve('@oai/artifact-tool')).href);
const chunks=[];for await(const chunk of process.stdin)chunks.push(chunk);
const p=JSON.parse(Buffer.concat(chunks).toString('utf8'));
const wb=Workbook.create();
for(const [name,rows] of Object.entries(p.sheets)) {
 const fields=Object.keys(rows[0]);const sh=wb.worksheets.add(name);sh.showGridLines=false;
 sh.getRange('A2').values=[[name.replaceAll('_',' ').toUpperCase()]];
 sh.getRange('A2').format.font={name:'Arial',size:14,bold:true,color:'#23415B'};
 sh.getRange('A3').values=[[p.banner]];
 sh.getRange('A3').format.font={name:'Arial',size:10,bold:true,color:p.mode==='smoke'?'#A13726':'#23415B'};
 sh.getRange('A4').values=[['3-year horizon; O-E in percentage points; paired deltas = UPDATED minus ORIGINAL; blanks = unavailable, never zero.']];
 sh.getRange('A4').format.font={name:'Arial',size:9,color:'#555555'};
 sh.getRangeByIndexes(4,0,1,fields.length).values=[fields];
 sh.getRangeByIndexes(5,0,rows.length,fields.length).values=rows.map(r=>fields.map(k=>r[k]??null));
 const all=sh.getRangeByIndexes(4,0,rows.length+1,fields.length);
 all.format.font={name:'Arial',size:10,color:'#243347'};all.format.rowHeight=20;all.format.verticalAlignment='center';
 const head=sh.getRangeByIndexes(4,0,1,fields.length);
 head.format.fill='#304F70';head.format.font={name:'Arial',size:10,bold:true,color:'#FFFFFF'};
 head.format.wrapText=true;head.format.rowHeight=44;head.format.horizontalAlignment='center';
 for(let j=0;j<fields.length;j++) {
  const key=fields[j];const vals=rows.map(r=>r[key]).filter(v=>v!==null&&v!==undefined);
  const numeric=vals.length>0&&vals.every(v=>typeof v==='number');let width=18;
  if(['model','cause','landmark','n','events','other_events'].includes(key))width=12;
  if(['era','period','status','support_flag','record_type'].includes(key))width=36;
  if(key==='metric')width=27;if(key==='note')width=85;
  if(key.length>24&&width===18)width=25;
  sh.getRangeByIndexes(4,j,rows.length+1,1).format.columnWidth=width;
  const col=sh.getRangeByIndexes(5,j,rows.length,1);col.format.horizontalAlignment=numeric?'right':'left';
  if(numeric)col.setNumberFormat(/(^n$|events|censored|source_n|landmark|count|risk_bin|valid_bootstrap|bootstrap_attempts|baseline_jumps)/.test(key)?'0':'0.0000');
 }
 sh.freezePanes.freezeRows(5);
}
wb.recalculate();
const out=await SpreadsheetFile.exportXlsx(wb);
await fs.writeFile(process.argv[2],out.data,{flag:'wx'});
console.log('RECALIBRATION WORKBOOK EXPORT PASS: '+Object.keys(p.sheets).join(', '));
)---"
    payload <- jsonlite::toJSON(list(mode=S$mode,
      banner=if(S$mode=="smoke")"SMOKE ONLY - NOT FOR ARTICLE - 60 PATIENTS PER PERIOD / 3 DRAWS" else
        "BASELINE-ONLY UPDATE: 2012-2014 / INDEPENDENT EVALUATION: 2015-2017 / BETA FROZEN",
      sheets=sheets),auto_unbox=TRUE,dataframe="rows",na="null",digits=16)
    child <- processx::process$new(S$node,c("--input-type=module","-e",js,S$modules,path),
      stdin="|",stdout="|",stderr="2>&1",windows_hide_window=TRUE,encoding="UTF-8",cleanup=TRUE)
    on.exit({if(child$is_alive())child$kill()},add=TRUE)
    output <- character();started <- Sys.time()
    drain <- function() {
      output <<- c(output,child$read_output())
      assert(as.numeric(difftime(Sys.time(),started,units="secs"))<600,"Workbook export exceeded 10 minutes.")
    }
    bytes <- charToRaw(enc2utf8(as.character(payload)))
    for(first in seq.int(1L,length(bytes),by=65536L)) {
      pending <- bytes[first:min(first+65535L,length(bytes))]
      while(length(pending)) {
        assert(child$is_alive(),paste("Workbook child exited while reading input:",paste(output,collapse="")))
        pending <- child$write_input(pending);drain()
        if(length(pending))child$poll_io(10L)
      }
    }
    close(child$get_input_connection())
    while(child$is_alive()) {child$poll_io(500L);drain()}
    drain();code <- child$get_exit_status()
    assert(identical(code,0L) && file.exists(path) && file.info(path)$size>1000,
      paste("Workbook streaming/export failed; status:",code,";",paste(output,collapse="")))
    say(trimws(paste(output,collapse="")))
    read_code <- r"---(import json,sys,zipfile
import openpyxl
names=['cohort_counts','performance','calibration','paired_update_effect','calibration_curve_data']
with zipfile.ZipFile(sys.argv[1]) as z:
 assert not any(n.startswith(('xl/media/','xl/drawings/','xl/charts/')) for n in z.namelist())
w=openpyxl.load_workbook(sys.argv[1],read_only=True,data_only=True)
assert w.sheetnames==names
out={}
for name in names:
 it=w[name].iter_rows(min_row=5,values_only=True);keys=list(next(it));records=[]
 for vals in it:
  if all(v is None for v in vals):continue
  records.append({k:(vals[j] if j<len(vals) else None) for j,k in enumerate(keys) if k is not None})
 out[name]=records
w.close();print(json.dumps(out,separators=(',',':')))
)---"
    read <- py_json(read_code,path,S$audit_python)
    assert(identical(names(read),names(sheets)),"Readback worksheet order mismatch.")
    cells <- 0L
    for(name in names(sheets)) {
      a <- sheets[[name]];b <- read[[name]]
      assert(nrow(a)==nrow(b) && identical(names(a),names(b)),paste("Readback dimensions/columns mismatch:",name))
      for(k in names(a)) {
        x<-a[[k]];y<-b[[k]]
        if(is.character(x))x[x==""]<-NA_character_
        if(is.character(y))y[y==""]<-NA_character_
        assert(identical(is.na(x),is.na(y)),paste("Readback missing-value mismatch:",name,k))
        valid<-!is.na(x)
        if(is.numeric(x))assert(all(abs(x[valid]-as.numeric(y[valid]))<=1e-10*pmax(1,abs(x[valid]))),paste("Readback numeric mismatch:",name,k)) else
          assert(identical(as.character(x[valid]),as.character(y[valid])),paste("Readback text mismatch:",name,k))
        cells <- cells+length(x)
      }
    }
    say("Readback PASS:",length(sheets),"sheets;",cells,"aggregate cells; plot-ready data present; no drawings.")
  }
  run <- function() {
    rngkind <- RNGkind();hadseed <- exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE)
    oldseed <- if(hadseed)get(".Random.seed",envir=.GlobalEnv) else NULL
    on.exit({do.call(RNGkind,as.list(rngkind));if(hadseed)assign(".Random.seed",oldseed,envir=.GlobalEnv)
      else if(exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE))rm(".Random.seed",envir=.GlobalEnv)},add=TRUE)
    setup();read_existing_validation();data <- read_data()
    updated <- update_baselines(data$update,audit=TRUE)
    assert(identical(signature(updated),signature(S$models)),"BETA FROZEN check failed.")
    probe <- data$update[1,,drop=FALSE];probe$year_dx <- 2015L
    denied <- tryCatch({update_baselines(probe);FALSE},error=function(e)grepl("FIREWALL",conditionMessage(e),fixed=TRUE))
    assert(denied,"Future-period row was not rejected from baseline updating.")
    original_predictions <- predict_all(S$models,data$evaluation)
    updated_predictions <- predict_all(updated,data$evaluation)
    specs <- make_curve_spec(data$evaluation,original_predictions,updated_predictions)
    point <- evaluate(data$evaluation,original_predictions,updated_predictions,specs,detailed=TRUE)
    say("Baseline-only update/independent offset arithmetic PASS; beta and firewall PASS. Starting",S$B,"two-sample draws.")
    boot <- bootstrap(data$update,data$evaluation,original_predictions,specs,point)
    assert(identical(digest::digest(S$models,algo="sha256"),S$model_hash),"Frozen development models mutated.")
    hashes();sheets <- shape_sheets(boot$table);report <- report_lines(boot$table,boot)
    assert(!any(file.exists(S$targets)),"Output appeared during analysis; refusing overwrite.")
    write_workbook(sheets,S$targets[1])
    assert(!file.exists(S$targets[2]),"Report appeared during export; refusing overwrite.")
    writeLines(enc2utf8(report),S$targets[2],useBytes=TRUE)
    hashes()
    assert(all(file.exists(S$targets)) && all(file.info(S$targets)$size>1000),"Missing final deliverable.")
    say(if(S$mode=="smoke")"RECALIBRATION SMOKE COMPLETE - NOT FORMAL ANALYSIS" else "BASELINE-ONLY RECALIBRATION COMPLETE")
    say("BETA FROZEN = YES; BASELINE-ONLY UPDATE = PASS; UPDATE/EVALUATION FIREWALL = PASS")
    say("Output directory:",S$outdir)
    invisible(list(mode=S$mode,files=S$targets,bootstrap_attempts=S$B,update_failures=boot$update_failures))
  }
  environment()
})
if(isTRUE(getOption("gbc.recalibration.autorun", FALSE)))gbc_recalibration$run()


