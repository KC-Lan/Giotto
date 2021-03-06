% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/spatial_structures.R
\name{createSpatialDelaunayNetwork}
\alias{createSpatialDelaunayNetwork}
\title{createSpatialDelaunayNetwork}
\usage{
createSpatialDelaunayNetwork(
  gobject,
  method = c("deldir", "delaunayn_geometry", "RTriangle"),
  dimensions = "all",
  name = "delaunay_network",
  maximum_distance = "auto",
  minimum_k = 0,
  options = "Pp",
  Y = TRUE,
  j = TRUE,
  S = 0,
  verbose = T,
  return_gobject = TRUE,
  ...
)
}
\arguments{
\item{gobject}{giotto object}

\item{dimensions}{which spatial dimensions to use (default = all)}

\item{name}{name for spatial network (default = 'delaunay_network')}

\item{maximum_distance}{distance cuttof for Delaunay neighbors to consider. If "auto", "upper wisker" value of the distance vector between neighbors is used; see the boxplot{graphics} documentation for more details.(default = "auto")}

\item{minimum_k}{minimum number of neigbhours if maximum_distance != NULL}

\item{options}{(geometry) String containing extra control options for the underlying Qhull command; see the Qhull documentation (../doc/qhull/html/qdelaun.html) for the available options. (default = 'Pp', do not report precision problems)}

\item{Y}{(RTriangle) If TRUE prohibits the insertion of Steiner points on the mesh boundary.}

\item{j}{(RTriangle) If TRUE jettisons vertices that are not part of the final triangulation from the output.}

\item{S}{(RTriangle) Specifies the maximum number of added Steiner points.}

\item{verbose}{verbose}

\item{return_gobject}{boolean: return giotto object (default = TRUE)}

\item{...}{Other parameters of the \code{\link[RTriangle]{triangulate}} function}
}
\value{
giotto object with updated spatial network slot
}
\description{
Create a spatial Delaunay network based on cell centroid physical distances.
}
\details{
Creates a spatial Delaunay network as explained in \code{\link[geometry]{delaunayn}} (default), \code{\link[deldir]{deldir}}, or \code{\link[RTriangle]{triangulate}}.
}
\examples{
    createSpatialDelaunayNetwork(gobject)
}
