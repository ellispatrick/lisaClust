#' Generate local indicators of spatial association
#'
#' @param cells A SegmentedCells or data frame that contains at least the 
#' variables x and y, giving the  coordinates of each cell, and cellType.
#' @param Rs A vector of the radii that the measures of association should be calculated.
#' @param BPPARAM A BiocParallelParam object.
#' @param window Should the window around the regions be 'square', 'convex' or 'concave'.
#' @param window.length A tuning parameter for controlling the level of concavity 
#' when estimating concave windows.
#' @param whichParallel Should the function use parallization on the imageID or 
#' the cellType.
#' @param sigma A numeric variable used for scaling when filting inhomogeneous L-curves.
#' @param lisaFunc Either "K" or "L" curve.
#' @param minLambda  Minimum value for density for scaling when fitting inhomogeneous L-curves.
#' @param fast A logical describing whether to use a fast approximation of the 
#' inhomogeneous local L-curves.
#'
#' @return A matrix of LISA curves
#'
#' @examples
#' library(spicyR)
#' # Read in data as a SegmentedCells objects
#' isletFile <- system.file("extdata","isletCells.txt.gz", package = "spicyR")
#' cells <- read.table(isletFile, header=TRUE)
#' cellExp <- SegmentedCells(cells, cellProfiler = TRUE)
#'
#' # Cluster cell types
#' markers <- cellMarks(cellExp)
#' kM <- kmeans(markers,8)
#' cellType(cellExp) <- paste('cluster',kM$cluster, sep = '')
#'
#' # Generate LISA
#' lisaCurves <- lisa(cellExp)
#'
#' # Cluster the LISA curves
#' kM <- kmeans(lisaCurves,2)
#' region(cellExp) <- paste('region',kM$cluster,sep = '_')
#'
#' @export
#' @rdname lisa
#' @importFrom methods is
#' @importFrom BiocParallel SerialParam bplapply
#' @importFrom S4Vectors DataFrame
#' @importFrom BiocGenerics do.call rbind
#' @importFrom dplyr bind_rows
#' @importFrom spicyR cellSummary
lisa <-
  function(cells,
           Rs = NULL,
           BPPARAM = BiocParallel::SerialParam(),
           window = "convex",
           window.length = NULL,
           whichParallel = 'imageID',
           sigma = NULL,
           lisaFunc = "K",
           minLambda = 0.05,
           fast = TRUE) {
    if (is.data.frame(cells)) {
      if (is.null(cells$cellID)) {
        message("Creating cellID as it doesn't exist")
        cells$cellID <-
          paste("cell", seq_len(nrow(cells)), sep = "_")
      }
      
      if (is.null(cells$cellType)) {
        stop("I need celltype")
      }
      
      if (is.null(cells$x) | is.null(cells$y)) {
        stop("I need x and y coordinates")
      }
      
      if (is.null(cells$imageCellID)) {
        cells$imageCellID <- paste("cell", seq_len(nrow(cells)), sep = "_")
      }
      if (length(unique(cells$imageCellID)) != nrow(cells))
        stop("The number of rows in cells does not equal the number of uniqueCellIDs")
      
      if (is.null(cells$imageID)) {
        message(
          "There is no imageID. I'll assume this is only one image and create an arbitrary imageID"
        )
        cells$imageID <- "image1"
      }
      
      cellSummary <-
        split(S4Vectors::DataFrame(cells[, c("imageID",
                                             "imageCellID",
                                             "cellID",
                                             "x",
                                             "y",
                                             "cellType")]), cells$imageID)
    }
    
    if (is(cells, "SegmentedCells")) {
      cellSummary <- spicyR::cellSummary(cells, bind = FALSE)
    }
    
    if (is.null(Rs)) {
      # loc = do.call('rbind', cellSummary)
      # range <- max(loc$x) - min(loc$x)
      # maxR <- range / 5
      # Rs = seq(from = maxR / 20, maxR, length.out = 20)
      Rs = c(20, 50, 100)
    }
    
    BPimage = BPcellType = BiocParallel::SerialParam()
    if (whichParallel == 'imageID')
      BPimage <- BPPARAM
    if (whichParallel == 'cellType')
      BPcellType <- BPPARAM
    
    if(!fast){
      message("Generating local L-curves. ")
      if(identical(BPimage, BPcellType)) 
        message("You might like to consider setting BPPARAM to run the calculations in parallel.")
    curveList <-
      BiocParallel::bplapply(
        cellSummary,
        generateCurves,
        Rs = Rs,
        window = window,
        window.length = window.length,
        BPcellType = BPcellType,
        BPPARAM = BPimage,
        sigma = sigma
      )
    }
    
    if(fast){
      
      message("Generating local L-curves. If you run out of memory, try 'fast = FALSE'.")
      
      curveList <-
        BiocParallel::bplapply(
          cellSummary,
          inhomLocalK,
          Rs = Rs,
          sigma = sigma,
          window = window,
          window.length = window.length,
          minLambda = minLambda,
          lisaFunc = lisaFunc,
          BPPARAM = BPimage
        )
    }
    
    curvelist <- lapply(curveList, as.data.frame)
    curves <- as.matrix(dplyr::bind_rows(curvelist))
    rownames(curves) <- as.character(spicyR::cellSummary(cells)$cellID)
    curves <- curves[as.character(spicyR::cellSummary(cells)$cellID), ]
    
    return(curves)
  }




#' @importFrom spatstat.geom ppp
pppGenerate <- function(cells, window, window.length) {
  ow <- makeWindow(cells, window, window.length)
  pppCell <- spatstat.geom::ppp(
    cells$x,
    cells$y,
    window = ow,
    marks = cells$cellType
  )
  
  pppCell
}

#' @importFrom spatstat.geom owin convexhull ppp
#' @importFrom concaveman concaveman
makeWindow <-
  function(data,
           window = "square",
           window.length = NULL) {
    data = data.frame(data)
    ow <-
      spatstat.geom::owin(xrange = range(data$x), yrange = range(data$y))
    
    if (window == "convex") {
      p <- spatstat.geom::ppp(data$x, data$y, ow)
      ow <- spatstat.geom::convexhull(p)
      
    }
    if (window == "concave") {
      message("Concave windows are temperamental. Try choosing values of window.length > and < 1 if you have problems.")
      if(is.null(window.length)){
        window.length <- (max(data$x) - min(data$x))/20
      }else{
        window.length <- (max(data$x) - min(data$x))/20 * window.length
      }
      dist <- (max(data$x) - min(data$x)) / (length(data$x))
      bigDat <-
        do.call("rbind", lapply(as.list(as.data.frame(t(data[, c("x", "y")]))), function(x)
          cbind(
            x[1] + c(0, 1, 0,-1,-1, 0, 1,-1, 1) * dist,
            x[2] + c(0, 1, 1, 1,-1,-1,-1, 0, 0) * dist
          )))
      ch <-
        concaveman::concaveman(bigDat,
                               length_threshold = window.length,
                               concavity = 1)
      poly <- as.data.frame(ch[nrow(ch):1, ])
      colnames(poly) <- c("x", "y")
      ow <-
        spatstat.geom::owin(
          xrange = range(poly$x),
          yrange = range(poly$y),
          poly = poly
        )
      
    }
    ow
  }


#' @importFrom spatstat.geom union.owin border inside.owin solapply intersect.owin area
borderEdge <- function(X, maxD){
  W <-X$window
  bW <- spatstat.geom::union.owin(spatstat.geom::border(W,maxD, outside = FALSE),
                             spatstat.geom::border(W,2, outside = TRUE))
  inB <- spatstat.geom::inside.owin(X$x, X$y, bW)
  e <- rep(1, X$n)
  if(any(inB)){
    circs <-spatstat.geom:: discs(X[inB], maxD, separate = TRUE)
    circs <- spatstat.geom::solapply(circs, spatstat.geom::intersect.owin, X$window)
    areas <- unlist(lapply(circs, spatstat.geom::area))/(pi*maxD^2)
    e[inB] <- areas
  }
  
  e
}





#' @importFrom spatstat.geom ppp
#' @importFrom spatstat.core localLcross localLcross.inhom density.ppp
#' @importFrom BiocParallel bplapply
generateCurves <-
  function(data,
           Rs,
           window,
           window.length,
           BPcellType = BPcellType,
           sigma = sigma,
           ...) {
    ow <- makeWindow(data, window, window.length)
    p1 <-
      spatstat.geom::ppp(
        x = data$x,
        y = data$y,
        window = ow,
        marks = data$cellType
      )
    
    if (!is.null(sigma)) {
      d <- spatstat.core::density.ppp(p1, sigma = sigma)
      d <- d / mean(d)
    }
    
    
    locIJ <-
      BiocParallel::bplapply(as.list(levels(p1$marks)), function(j) {
        locI <- lapply(as.list(levels(p1$marks)), function(i) {
          iID <- data$cellID[p1$marks == i]
          jID <- data$cellID[p1$marks == j]
          locR <- matrix(NA, length(iID), length(Rs))
          rownames(locR) <- iID
          
          if (length(jID) > 1 & length(iID) > 1) {
            if (!is.null(sigma)) {
              dFrom <- d * (sum(p1$marks == i) - 1) / spatstat.geom::area(ow)
              dTo <-
                d * (sum(p1$marks == j) - 1) / spatstat.geom::area(ow)
              localL <-
                spatstat.core::localLcross.inhom(
                  p1,
                  from = i,
                  to = j,
                  verbose = FALSE,
                  lambdaFrom = dFrom,
                  lambdaTo = dTo
                )
            } else{
              localL <-
                spatstat.core::localLcross(
                  p1,
                  from = i,
                  to = j,
                  verbose = FALSE
                )
            }
            ur <-
              vapply(Rs, function(x)
                which.min(abs(localL$r - x))[1], numeric(1))
            locR <-
              t(apply(as.matrix(localL)[, grep("iso", colnames(localL))],
                      2, function(x)
                        ((x - localL$theo)/localL$theo)[ur]))
            rownames(locR) <- iID
          }
          colnames(locR) <-
            paste(j, round(Rs, 2), sep = "_")
          
          locR
        })
        do.call("rbind", locI)
      }, BPPARAM = BPcellType)
    do.call("cbind", locIJ)
  }

#' @importFrom stats loess rpois var
sqrtVar <- function(x){
  len = 1000
  lambda <- (seq(1,300,length.out = len)/100)^x
  mL <- max(lambda)
  
  
  V <- NULL
  for(i in 1:len){
    V[i] <- var(sqrt(rpois(10000,lambda[i]))  ) 
  }
  
  lambda <- lambda^(1/x)
  V <- V
  
  f <- loess(V~lambda,span = 0.1)
}



#' @importFrom spatstat.geom nearest.valid.pixel area marks
weightCounts <- function(dt, X, maxD, lam) {
  maxD <- as.numeric(as.character(maxD))
  
  # edge correction
  e <- borderEdge(X, maxD)
  
  # lambda <- as.vector(e%*%t(maxD^2*lam*pi))
  # pred <- predict(fit,lambda^(1/4))
  # pred[lambda < 0.001] = (lambda - 4*lambda^2)[lambda < 0.001]
  # pred[lambda > mL^(1/4)] = 0.25
  # V <- e%*%t(maxD^2*lam*pi)
  # V[] <- pred
  
  
  lambda <- as.vector(maxD^2*lam*pi)
  names(lambda) <- names(lam)
  LE <- (e)%*%t(lambda)
  mat <- apply(dt,2,function(x)x)
  mat <- ((mat) - (LE))
  mat <- mat/sqrt(LE)
  
#   # plot(apply(mat,2,sd))
#   # plot(apply(mat,2,mean))  
  colnames(mat) <- paste(maxD, colnames(mat), sep = "_")
  mat
}

#' @importFrom spatstat.geom ppp closepairs marks area
#' @importFrom spatstat.core density.ppp
#' @importFrom tidyr pivot_longer
#' @importFrom dplyr left_join
inhomLocalK <-
  function (data,
            Rs = c(20, 50, 100, 200),
            sigma = 10000,
            window = "convex",
            window.length = NULL,
            minLambda = 0.05,
            lisaFunc = "K") {

    ow <- makeWindow(data, window, window.length)
    X <-
      spatstat.geom::ppp(
        x = data$x,
        y = data$y,
        window = ow,
        marks = data$cellType
      )
    
    if (is.null(Rs))
      Rs = c(20, 50, 100, 200)
    if (is.null(sigma))
      sigma = 100000
    
    maxR <- min(ow$xrange[2]- ow$xrange[1], ow$yrange[2]- ow$yrange[1])/2.01
    Rs <- unique(pmin(c(0, sort(Rs)),maxR))
    
    den <- spatstat.core::density.ppp(X, sigma = sigma)
    den <- den / mean(den)
    den$v <- pmax(den$v, minLambda)

    p <- spatstat.geom::closepairs(X, max(Rs), what = "ijd")
    n <- X$n
    p$j <- data$cellID[p$j]
    p$i <- data$cellID[p$i]
    
    cT <- data$cellType
    names(cT) <- data$cellID
    
    p$d <- cut(p$d, Rs, labels = Rs[-1], include.lowest = TRUE)
    
    # inhom density
    np <- spatstat.geom::nearest.valid.pixel(X$x, X$y, den)
    w <- den$v[cbind(np$row, np$col)]
    names(w) <- data$cellID
    p$wt <- 1/w[p$j]*mean(w)
    rm(np)
    
    lam <- table(data$cellType)/spatstat.geom::area(X)
    
 

    p$cellTypeJ <- cT[p$j]
    p$cellTypeI <- cT[p$i]
    p$i <- factor(p$i, levels = data$cellID)
    
    edge <- sapply(Rs[-1],function(x)borderEdge(X,x))
    edge <- as.data.frame(edge)
    colnames(edge) <- Rs[-1]
    edge$i <- data$cellID
    edge <- tidyr::pivot_longer(edge,-i,"d")
    
    p <- dplyr::left_join(as.data.frame(p), edge, c("i", "d"))
    p$d <- factor(p$d, levels = Rs[-1])
  
    

    p <- as.data.frame(p)

    if(lisaFunc == "K"){
      r <- getK(p, lam)
    }
    if(lisaFunc == "L"){
      r <- getL(p, lam)
    }
    
    as.matrix(r[data$cellID,])
    
  }


#' @importFrom data.table as.data.table setkey CJ dcast .SD ":="
getK <-
  function (p, lam) {

    r <- data.table::as.data.table(p)
    r$wt <- r$wt
    r <- r[,j:=NULL]
    r <- r[,cellTypeI:=NULL]
    data.table::setkey(r, i, d, cellTypeJ,value)
    r <- r[data.table::CJ(i, d, cellTypeJ, unique = TRUE)
    ][, lapply(.SD, sum), by = .(i, d, cellTypeJ,value)
    ][is.na(wt), wt := 0]
    r <- r[, wt := cumsum(wt), by = list(i, cellTypeJ)]
    r$value[is.na(r$value)] <- 1
    E <- as.numeric(as.character(r$d))^2*pi*r$value*as.numeric(lam[r$cellTypeJ])
    r$wt <- (r$wt-E)/sqrt(E)
    r <- r[,value:=NULL]
    r <- data.table::dcast(r, i ~ d + cellTypeJ, value.var = 'wt')

    r <- as.data.frame(r)
    rownames(r) <- r$i
    r <- r[,-1]
    
    r
    
  }


#' @importFrom data.table as.data.table setkey CJ dcast .SD ":="
getL <-
  function (p, lam) {
    
    r <- data.table::as.data.table(p)
    r$wt <- r$wt
    r <- r[,j:=NULL]
    r <- r[,cellTypeI:=NULL]
    data.table::setkey(r, i, d, cellTypeJ,value)
    r <- r[data.table::CJ(i, d, cellTypeJ, unique = TRUE)
    ][, lapply(.SD, sum), by = .(i, d, cellTypeJ,value)
    ][is.na(wt), wt := 0]
    r <- r[, wt := cumsum(wt), by = list(i, cellTypeJ)]
    r$value[is.na(r$value)] <- 1
    E <- as.numeric(as.character(r$d))^2*pi*r$value*as.numeric(lam[r$cellTypeJ])
    r$wt <- sqrt(r$wt)-sqrt(E)
    r <- r[,value:=NULL]
    r <- data.table::dcast(r, i ~ d + cellTypeJ, value.var = 'wt')
    
    r <- as.data.frame(r)
    rownames(r) <- r$i
    r <- r[,-1]
    
    r
    
  }

