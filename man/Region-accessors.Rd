% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/AllGenerics.R
\name{Region accessors}
\alias{Region accessors}
\alias{region,SegmentedCells-method}
\alias{region<-,SegmentedCells-method}
\alias{region}
\alias{region<-}
\title{Region accessors for SegmentedCells}
\usage{
region(x, imageID = NULL, annot = FALSE)

region(x, imageID = NULL) <- value
}
\arguments{
\item{x}{A `SegmentedCells` object.}

\item{imageID}{A vector of imageIDs to specifically extract.}

\item{annot}{Add cell annotation when selecting region information.}

\item{value}{The relevant information used to replace.}
}
\value{
DataFrame or a list of DataFrames
}
\description{
Methods to access various components of the `SegmentedCells` object.
}
\examples{
library(spicyR)
set.seed(51773)

x <- round(c(runif(200),runif(200)+1,runif(200)+2,runif(200)+3,
             runif(200)+3,runif(200)+2,runif(200)+1,runif(200)),4)*100
y <- round(c(runif(200),runif(200)+1,runif(200)+2,runif(200)+3,
             runif(200),runif(200)+1,runif(200)+2,runif(200)+3),4)*100
cellType <- factor(paste('c',rep(rep(c(1:2),rep(200,2)),4),sep = ''))
imageID <- rep(c('s1', 's2'),c(800,800))

cells <- data.frame(x, y, cellType, imageID)

cellExp <- SegmentedCells(cells, cellProfiler = TRUE)


# Generate LISA
lisaCurves <- lisa(cellExp)

# Cluster the LISA curves
kM <- kmeans(lisaCurves,2)
region(cellExp) <- paste('region',kM$cluster,sep = '_')

}
