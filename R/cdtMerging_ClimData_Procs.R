
mergingClimData <- function(){
    message <- .cdtData$GalParams[['message']]
    Insert.Messages.Out(message[['10']], TRUE, "i")

    varClim <- gsub("merge\\.", "", .cdtData$GalParams$action)
    if(varClim == 'pres'){
        if(.cdtData$GalParams$prmsl) varClim <- "prmsl"
    }

    daty <- seq.format.date.time(.cdtData$GalParams$period,
                                 .cdtData$GalParams$date.range,
                                 .cdtData$GalParams$minhour)
    dtrg <- merged_date_range_filename(daty, .cdtData$GalParams$period)

    dirMRGClim <- paste('MERGED', toupper(varClim), 'Data', dtrg$start, dtrg$end, sep = '_')
    outdir <- file.path(.cdtData$GalParams$output$dir, dirMRGClim)
    dir.create(file.path(outdir, 'DATA'), showWarnings = FALSE, recursive = TRUE)

    mrgOpts <- merging.options()

    if(.cdtData$GalParams$action != "merge.rain")
        .cdtData$GalParams$RnoR <- list(use = FALSE, wet = 1.0, smooth = FALSE)

    if(mrgOpts$saveGridBuffer)
        dir.create(file.path(outdir, "GRID_BUFFER"), showWarnings = FALSE, recursive = TRUE)

    if(.cdtData$GalParams$RnoR$use && mrgOpts$saveRnoR)
        dir.create(file.path(outdir, 'RAIN-NO-RAIN'), showWarnings = FALSE, recursive = TRUE)

    if(.cdtData$GalParams$interp$method == "okr"){
        .cdtData$GalParams$interp$vgm_dir <- "VARIOGRAM"
        .cdtData$GalParams$interp$vgm_save <- TRUE
        dir.create(file.path(outdir, "VARIOGRAM"), showWarnings = FALSE, recursive = TRUE)
    }

    ##################

    out_params <- .cdtData$GalParams
    out_params <- out_params[!names(out_params) %in% c("settingSNC", "message")]
    out_params$merging_options <- mrgOpts
    out_params$blanking_options <- blanking.options()
    saveRDS(out_params, file.path(outdir, 'merging_parameters.rds'))

    ##################

    Insert.Messages.Out(message[['11']], TRUE, "i")

    ## station data
    stnData <- getStnOpenData(.cdtData$GalParams$STN.file)
    stnData <- getCDTdataAndDisplayMsg(stnData, .cdtData$GalParams$period,
                                       .cdtData$GalParams$STN.file)
    if(is.null(stnData)) return(NULL)

    ##################
    ## NetCDF sample file
    ncDataInfo <- getNCDFSampleData(.cdtData$GalParams$INPUT$sample)
    if(is.null(ncDataInfo)){
        Insert.Messages.Out(message[['12']], TRUE, 'e')
        return(NULL)
    }

    ##################
    ## DEM data
    demData <- NULL
    if(.cdtData$GalParams$MRG$method == "RK" &
       (.cdtData$GalParams$auxvar$dem |
        .cdtData$GalParams$auxvar$slope |
        .cdtData$GalParams$auxvar$aspect)
      )
    {
        demInfo <- getNCDFSampleData(.cdtData$GalParams$auxvar$demfile)
        if(is.null(demInfo)){
            Insert.Messages.Out(message[['13']], TRUE, "e")
            return(NULL)
        }
        jfile <- getIndex.AllOpenFiles(.cdtData$GalParams$auxvar$demfile)
        demData <- .cdtData$OpenFiles$Data[[jfile]][[2]]
    }

    ##################
    ##Create grid for interpolation

    if(.cdtData$GalParams$grid$from == "data"){
        grd.lon <- ncDataInfo$lon
        grd.lat <- ncDataInfo$lat
    }

    if(.cdtData$GalParams$grid$from == "new"){
        grdInfo <- .cdtData$GalParams$grid$bbox
        grd.lon <- seq(grdInfo$minlon, grdInfo$maxlon, grdInfo$reslon)
        grd.lat <- seq(grdInfo$minlat, grdInfo$maxlat, grdInfo$reslat)
    }

    if(.cdtData$GalParams$grid$from == "ncdf"){
        grdInfo <- getNCDFSampleData(.cdtData$GalParams$grid$ncfile)
        if(is.null(grdInfo)){
            Insert.Messages.Out(message[['14']], TRUE, "e")
            return(NULL)
        }
        grd.lon <- grdInfo$lon
        grd.lat <- grdInfo$lat
    }

    xy.grid <- list(lon = grd.lon, lat = grd.lat)

    ##################
    ## regrid DEM data

    if(!is.null(demData)){
        demData$lon <- demData$x
        demData$lat <- demData$y
        is.regridDEM <- is.diffSpatialPixelsObj(defSpatialPixels(xy.grid),
                                                defSpatialPixels(demData),
                                                tol = 1e-07)
        if(is.regridDEM){
            demData <- cdt.interp.surface.grid(demData, xy.grid)
        }else demData <- demData[c('x', 'y', 'z')]
        demData$z[demData$z < 0] <- 0
    }

    ##################
    ## Get NetCDF data info

    ncInfo <- ncInfo.with.date.range(.cdtData$GalParams$INPUT,
                                     .cdtData$GalParams$date.range,
                                     .cdtData$GalParams$period,
                                     .cdtData$GalParams$minhour)
    if(is.null(ncInfo)){
        Insert.Messages.Out(message[['15']], TRUE, "e")
        return(NULL)
    }
    ncInfo$ncinfo <- ncDataInfo

    ##################
    ## blanking
    outMask <- NULL

    if(.cdtData$GalParams$blank$data){
        shpd <- getShpOpenData(.cdtData$GalParams$blank$shpf)[[2]]
        outMask <- create.mask.grid(shpd, xy.grid)
    }

    Insert.Messages.Out(message[['16']], TRUE, "s")

    ##################

    Insert.Messages.Out(message[['17']], TRUE, "i")

    ret <- cdtMerging(stnData = stnData, ncInfo = ncInfo, xy.grid = xy.grid, params = .cdtData$GalParams,
                      variable = varClim, demData = demData, outdir = outdir, mask = outMask)

    if(!is.null(ret)){
        if(ret != 0){
          file_log <- file.path(outdir, "log_file.txt")
          Insert.Messages.Out(paste(message[['18']], file_log), TRUE, "w")
        }
    }else return(NULL)

    Insert.Messages.Out(message[['19']], TRUE, "s")
    return(0)
}

merged_date_range_filename <- function(dates, tstep){
    daty <- range(dates)
    if(tstep == 'monthly'){
        xdeb <- format(daty[1], "%b%Y")
        xfin <- format(daty[2], "%b%Y")
    }else if(tstep == 'hourly'){
        xdeb <- format(daty[1], '%Y%m%d%H')
        xfin <- format(daty[2], '%Y%m%d%H')
    }else if(tstep == 'minute'){
        xdeb <- format(daty[1], '%Y%m%d%H%M')
        xfin <- format(daty[2], '%Y%m%d%H%M')
    }else{
        xdeb <- paste0(as.numeric(format(daty[1], "%d")), format(daty[1], "%b%Y"))
        xfin <- paste0(as.numeric(format(daty[2], "%d")), format(daty[2], "%b%Y"))
    }

    list(start = xdeb, end = xfin)
}
