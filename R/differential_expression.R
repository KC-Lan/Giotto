

#' @title findScranMarkers
#' @name findScranMarkers
#' @description Identify marker genes for all or selected clusters based on scran's implementation of findMarkers.
#' @param gobject giotto object
#' @param expression_values gene expression values to use
#' @param cluster_column clusters to use
#' @param subset_clusters selection of clusters to compare
#' @param group_1 group 1 cluster IDs from cluster_column for pairwise comparison
#' @param group_2 group 2 cluster IDs from cluster_column for pairwise comparison
#' @param ... additional parameters for the findMarkers function in scran
#' @return data.table with marker genes
#' @details This is a minimal convenience wrapper around
#' the \code{\link[scran]{findMarkers}} function from the scran package.
#'
#' To perform differential expression between cluster groups you need to specificy cluster IDs
#' to the parameters \emph{group_1} and \emph{group_2}.
#'
#' @export
#' @examples
#'     findScranMarkers(gobject)
findScranMarkers <- function(gobject,
                             expression_values = c('normalized', 'scaled', 'custom'),
                             cluster_column,
                             subset_clusters = NULL,
                             group_1 = NULL,
                             group_2 = NULL,
                             ...) {


  if("scran" %in% rownames(installed.packages()) == FALSE) {
    stop("\n package 'scran' is not yet installed \n",
         "To install: \n",
         "if (!requireNamespace('BiocManager', quietly = TRUE)) install.packages('BiocManager');
         BiocManager::install('scran')"
    )
  }

  # expression data
  values = match.arg(expression_values, choices = c('normalized', 'scaled', 'custom'))
  expr_data = Giotto:::select_expression_values(gobject = gobject, values = values)

  # cluster column
  cell_metadata = pDataDT(gobject)
  if(!cluster_column %in% colnames(cell_metadata)) {
    stop('\n cluster column not found \n')
  }

  # subset expression data
  if(!is.null(subset_clusters)) {

    cell_metadata = cell_metadata[get(cluster_column) %in% subset_clusters]
    subset_cell_IDs = cell_metadata[['cell_ID']]
    expr_data = expr_data[, colnames(expr_data) %in% subset_cell_IDs]


  } else if(!is.null(group_1) & !is.null(group_2)) {

    cell_metadata = cell_metadata[get(cluster_column) %in% c(group_1, group_2)]

    # create new pairwise group
    group_1_name = paste0(group_1, collapse = '_')
    group_2_name = paste0(group_2, collapse = '_')
    cell_metadata[, pairwise_select_comp := ifelse(get(cluster_column) %in% group_1, group_1_name, group_2_name)]

    cluster_column = 'pairwise_select_comp'

    # expression data
    subset_cell_IDs = cell_metadata[['cell_ID']]
    expr_data = expr_data[, colnames(expr_data) %in% subset_cell_IDs]


  }


  ## SCRAN ##
  marker_results = scran::findMarkers(x = expr_data, groups = cell_metadata[[cluster_column]], ...)

  savelist = lapply(names(marker_results), FUN = function(x) {
    dfr = marker_results[[x]]
    DT = data.table::as.data.table(dfr)
    DT[, genes := rownames(dfr)]
    DT[, cluster := x]

  })

  return(savelist)

}



#' @title findScranMarkers_one_vs_all
#' @name findScranMarkers_one_vs_all
#' @description Identify marker genes for all clusters in a one vs all manner based on scran's implementation of findMarkers.
#' @param gobject giotto object
#' @param expression_values gene expression values to use
#' @param cluster_column clusters to use
#' @param subset_clusters subset of clusters to use
#' @param pval filter on minimal p-value
#' @param logFC filter on logFC
#' @param min_genes minimum genes to keep per cluster, overrides pval and logFC
#' @param verbose be verbose
#' @param ...  additional parameters for the findMarkers function in scran
#' @return data.table with marker genes
#' @seealso \code{\link{findScranMarkers}}
#' @export
#' @examples
#'     findScranMarkers_one_vs_all(gobject)
findScranMarkers_one_vs_all <- function(gobject,
                                        expression_values = c('normalized', 'scaled', 'custom'),
                                        cluster_column,
                                        subset_clusters = NULL,
                                        pval = 0.01,
                                        logFC = 0.5,
                                        min_genes = 10,
                                        verbose = TRUE,
                                        ...) {


  if("scran" %in% rownames(installed.packages()) == FALSE) {
    stop("\n package 'scran' is not yet installed \n",
         "To install: \n",
         "if (!requireNamespace('BiocManager', quietly = TRUE)) install.packages('BiocManager');
         BiocManager::install('scran')"
    )
  }

  # expression data
  values = match.arg(expression_values, choices = c('normalized', 'scaled', 'custom'))

  # cluster column
  cell_metadata = pDataDT(gobject)
  if(!cluster_column %in% colnames(cell_metadata)) {
    stop('\n cluster column not found \n')
  }

  # restrict to a subset of clusters
  if(!is.null(subset_clusters)) {

    cell_metadata = cell_metadata[get(cluster_column) %in% subset_clusters]
    subset_cell_IDs = cell_metadata[['cell_ID']]
    gobject = subsetGiotto(gobject = gobject, cell_ids = subset_cell_IDs)
    cell_metadata = pDataDT(gobject)
  }



  # sort uniq clusters
  uniq_clusters = sort(unique(cell_metadata[[cluster_column]]))


  # save list
  result_list = list()


  for(clus_i in 1:length(uniq_clusters)) {

    selected_clus = uniq_clusters[clus_i]
    other_clus = uniq_clusters[uniq_clusters != selected_clus]

    if(verbose == TRUE) {
      cat('\n start with cluster ', selected_clus, '\n')
    }

    # one vs all markers
    markers = findScranMarkers(gobject = gobject,
                               expression_values = values,
                               cluster_column = cluster_column,
                               group_1 = selected_clus,
                               group_2 = other_clus )

    # identify list to continue with
    select_bool = unlist(lapply(markers, FUN = function(x) {
      unique(x$cluster) == selected_clus
    }))
    selected_table = data.table::as.data.table(markers[select_bool])
    data.table::setnames(selected_table, colnames(selected_table)[4], 'logFC')

    # filter selected table
    filtered_table = selected_table[logFC > 0]
    filtered_table[, 'ranking' := rank(-logFC)]
    filtered_table = filtered_table[(p.value <= pval & logFC >= logFC) | (ranking <= min_genes)]

    result_list[[clus_i]] = filtered_table
  }


  return(do.call('rbind', result_list))

}


#' @title findGiniMarkers
#' @name findGiniMarkers
#' @description Identify marker genes for selected clusters based on gini detection and expression scores.
#' @param gobject giotto object
#' @param expression_values gene expression values to use
#' @param cluster_column clusters to use
#' @param subset_clusters selection of clusters to compare
#' @param group_1 group 1 cluster IDs from cluster_column for pairwise comparison
#' @param group_2 group 2 cluster IDs from cluster_column for pairwise comparison
#' @param min_expr_gini_score filter on minimum gini coefficient for expression
#' @param min_det_gini_score filter on minimum gini coefficient for detection
#' @param detection_threshold detection threshold for gene expression
#' @param rank_score rank scores for both detection and expression to include
#' @param min_genes minimum number of top genes to return
#' @return data.table with marker genes
#' @details
#' Detection of marker genes using the \url{https://en.wikipedia.org/wiki/Gini_coefficient}{gini}
#' coefficient is based on the following steps/principles per gene:
#' \itemize{
#'   \item{1. calculate average expression per cluster}
#'   \item{2. calculate detection fraction per cluster}
#'   \item{3. calculate gini-coefficient for av. expression values over all clusters}
#'   \item{4. calculate gini-coefficient for detection fractions over all clusters}
#'   \item{5. convert gini-scores to rank scores}
#'   \item{6. for each gene create combined score = detection rank x expression rank x expr gini-coefficient x detection gini-coefficient}
#'   \item{7. for each gene sort on expression and detection rank and combined score}
#' }
#'
#' As a results "top gini" genes are genes that are very selectivily expressed in a specific cluster,
#' however not always expressed in all cells of that cluster. In other words highly specific, but
#' not necessarily sensitive at the single-cell level.
#'
#' To perform differential expression between cluster groups you need to specificy cluster IDs
#' to the parameters \emph{group_1} and \emph{group_2}.
#'
#' @export
#' @examples
#'     findGiniMarkers(gobject)
findGiniMarkers <- function(gobject,
                            expression_values = c('normalized', 'scaled', 'custom'),
                            cluster_column,
                            subset_clusters = NULL,
                            group_1 = NULL,
                            group_2 = NULL,
                            min_expr_gini_score = 0.2,
                            min_det_gini_score = 0.2,
                            detection_threshold = 0,
                            rank_score = 1,
                            min_genes = 5) {

  ## select expression values
  values = match.arg(expression_values, c('normalized', 'scaled', 'custom'))


  # cluster column
  cell_metadata = pDataDT(gobject)
  if(!cluster_column %in% colnames(cell_metadata)) {
    stop('\n cluster column not found \n')
  }


  # subset clusters
  if(!is.null(subset_clusters)) {

    cell_metadata = cell_metadata[get(cluster_column) %in% subset_clusters]
    subset_cell_IDs = cell_metadata[['cell_ID']]
    gobject = subsetGiotto(gobject = gobject, cell_ids = subset_cell_IDs)

  } else if(!is.null(group_1) & !is.null(group_2)) {

    cell_metadata = cell_metadata[get(cluster_column) %in% c(group_1, group_2)]

    # create new pairwise group
    group_1_name = paste0(group_1, collapse = '_')
    group_2_name = paste0(group_2, collapse = '_')
    cell_metadata[, pairwise_select_comp := ifelse(get(cluster_column) %in% group_1, group_1_name, group_2_name)]

    cluster_column = 'pairwise_select_comp'

    # expression data
    subset_cell_IDs = cell_metadata[['cell_ID']]
    gobject = subsetGiotto(gobject = gobject, cell_ids = subset_cell_IDs)
    gobject@cell_metadata = cell_metadata
  }


  # average expression per cluster
  aggr_sc_clusters <- Giotto:::create_average_DT(gobject = gobject,
                                                 meta_data_name = cluster_column,
                                                 expression_values = values)
  aggr_sc_clusters_DT <- data.table::as.data.table(aggr_sc_clusters)
  aggr_sc_clusters_DT[, genes := rownames(aggr_sc_clusters)]
  aggr_sc_clusters_DT_melt <- data.table::melt.data.table(aggr_sc_clusters_DT,
                                                          variable.name = 'cluster',
                                                          id.vars = 'genes',
                                                          value.name = 'expression')


  ## detection per cluster
  aggr_detection_sc_clusters <- Giotto:::create_average_detection_DT(gobject = gobject,
                                                                     meta_data_name = cluster_column,
                                                                     expression_values = values,
                                                                     detection_threshold = detection_threshold)
  aggr_detection_sc_clusters_DT <- as.data.table(aggr_detection_sc_clusters)
  aggr_detection_sc_clusters_DT[, genes := rownames(aggr_detection_sc_clusters)]
  aggr_detection_sc_clusters_DT_melt <- data.table::melt.data.table(aggr_detection_sc_clusters_DT,
                                                                    variable.name = 'cluster',
                                                                    id.vars = 'genes',
                                                                    value.name = 'detection')

  ## gini
  aggr_sc_clusters_DT_melt[, expression_gini := Giotto:::mygini_fun(expression), by = genes]
  aggr_detection_sc_clusters_DT_melt[, detection_gini := Giotto:::mygini_fun(detection), by = genes]


  ## combine
  aggr_sc = cbind(aggr_sc_clusters_DT_melt, aggr_detection_sc_clusters_DT_melt[,.(detection, detection_gini)])

  ## create combined rank

  # expression rank for each gene in all samples
  # rescale expression rank range between 1 and 0.1
  aggr_sc[, expression_rank := rank(-expression), by = genes]
  aggr_sc[, expression_rank := scales::rescale(expression_rank, to = c(1, 0.1)), by = cluster]

  # detection rank for each gene in all samples
  # rescale detection rank range between 1 and 0.1
  aggr_sc[, detection_rank := rank(-detection), by = genes]
  aggr_sc[, detection_rank := scales::rescale(detection_rank, to = c(1, 0.1)), by = cluster]

  # create combine score based on rescaled ranks and gini scores
  aggr_sc[, comb_score := (expression_gini*expression_rank)*(detection_gini*detection_rank)]
  setorder(aggr_sc, cluster, -comb_score)
  aggr_sc[, comb_rank := 1:.N, by = cluster]

  top_genes_scores = aggr_sc[comb_rank <= min_genes | (expression_rank <= rank_score & detection_rank <= rank_score)]
  top_genes_scores_filtered = top_genes_scores[comb_rank <= min_genes | (expression > min_expr_gini_score & detection > min_det_gini_score)]
  setorder(top_genes_scores_filtered, cluster, comb_rank)


  # remove 'cluster_' part if this is not part of the original cluster names
  original_uniq_cluster_names = unique(cell_metadata[[cluster_column]])
  if(sum(grepl('cluster_', original_uniq_cluster_names)) == 0) {
    top_genes_scores_filtered[, cluster := gsub(x = cluster, 'cluster_', '')]
  }

  return(top_genes_scores_filtered)

}




#' @title findGiniMarkers_one_vs_all
#' @name findGiniMarkers_one_vs_all
#' @description Identify marker genes for all clusters in a one vs all manner based on gini detection and expression scores.
#' @param gobject giotto object
#' @param expression_values gene expression values to use
#' @param cluster_column clusters to use
#' @param subset_clusters selection of clusters to compare
#' @param min_expr_gini_score filter on minimum gini coefficient on expression
#' @param min_det_gini_score filter on minimum gini coefficient on detection
#' @param detection_threshold detection threshold for gene expression
#' @param rank_score rank scores for both detection and expression to include
#' @param min_genes minimum number of top genes to return
#' @param verbose be verbose
#' @return data.table with marker genes
#' @seealso \code{\link{findGiniMarkers}}
#' @export
#' @examples
#'     findGiniMarkers_one_vs_all(gobject)
findGiniMarkers_one_vs_all <- function(gobject,
                                       expression_values = c('normalized', 'scaled', 'custom'),
                                       cluster_column,
                                       subset_clusters = NULL,
                                       min_expr_gini_score = 0.5,
                                       min_det_gini_score = 0.5,
                                       detection_threshold = 0,
                                       rank_score = 1,
                                       min_genes = 4,
                                       verbose = TRUE) {


  # expression data
  values = match.arg(expression_values, choices = c('normalized', 'scaled', 'custom'))

  # cluster column
  cell_metadata = pDataDT(gobject)
  if(!cluster_column %in% colnames(cell_metadata)) {
    stop('\n cluster column not found \n')
  }

  if(!is.null(subset_clusters)) {

    cell_metadata = cell_metadata[get(cluster_column) %in% subset_clusters]
    subset_cell_IDs = cell_metadata[['cell_ID']]
    gobject = subsetGiotto(gobject = gobject, cell_ids = subset_cell_IDs)
    cell_metadata = pDataDT(gobject)
  }


  # sort uniq clusters
  uniq_clusters = sort(unique(cell_metadata[[cluster_column]]))


  # save list
  result_list = list()

  ## GINI
  for(clus_i in 1:length(uniq_clusters)) {

    selected_clus = uniq_clusters[clus_i]
    other_clus = uniq_clusters[uniq_clusters != selected_clus]

    if(verbose == TRUE) {
      cat('\n start with cluster ', selected_clus, '\n')
    }

    markers = findGiniMarkers(gobject = gobject,
                              expression_values = values,
                              cluster_column = cluster_column,
                              group_1 = selected_clus,
                              group_2 = other_clus,
                              min_expr_gini_score = min_expr_gini_score,
                              min_det_gini_score = min_det_gini_score,
                              detection_threshold = detection_threshold,
                              rank_score = rank_score,
                              min_genes = min_genes)

    # filter steps
    #clus_name = paste0('cluster_', selected_clus)
    filtered_table = markers[cluster == selected_clus]

    result_list[[clus_i]] = filtered_table
  }

  return(do.call('rbind', result_list))

}




#' @title findMastMarkers
#' @name findMastMarkers
#' @description Identify marker genes for selected clusters based on the MAST package.
#' @param gobject giotto object
#' @param expression_values gene expression values to use
#' @param cluster_column clusters to use
#' @param group_1 group 1 cluster IDs from cluster_column for pairwise comparison
#' @param group_1_name custom name for group_1 clusters
#' @param group_2 group 2 cluster IDs from cluster_column for pairwise comparison
#' @param group_2_name custom name for group_2 clusters
#' @param adjust_columns column in pDataDT to adjust for (e.g. detection rate)
#' @param ... additional parameters for the zlm function in MAST
#' @return data.table with marker genes
#' @details This is a minimal convenience wrapper around the \code{\link[MAST]{zlm}}
#' from the MAST package to detect differentially expressed genes.
#' @export
#' @examples
#'     findMastMarkers(gobject)
findMastMarkers <- function(gobject,
                            expression_values = c('normalized', 'scaled', 'custom'),
                            cluster_column,
                            group_1 = NULL,
                            group_1_name = NULL,
                            group_2 = NULL,
                            group_2_name = NULL,
                            adjust_columns = NULL,
                            ...) {

  if("MAST" %in% rownames(installed.packages()) == FALSE) {
    stop("\n package 'MAST' is not yet installed \n",
         "To install: \n",
         "if (!requireNamespace('BiocManager', quietly = TRUE)) install.packages('BiocManager');
         BiocManager::install('MAST')"
    )
  }

  ## select expression values to use
  values = match.arg(expression_values, c('normalized', 'scaled', 'custom'))

  ## cluster column
  cell_metadata = pDataDT(gobject)
  if(!cluster_column %in% colnames(cell_metadata)) {
    stop('\n cluster column not found \n')
  }

  ## select group ids
  if(is.null(group_1) | is.null(group_2)) {
    stop('\n specificy group ids for both group_1 and group_2 \n')
  }

  ## subset data based on group_1 and group_2
  cell_metadata = cell_metadata[get(cluster_column) %in% c(group_1, group_2)]
  if(nrow(cell_metadata) == 0) {
    stop('\n there are no cells for group_1 or group_2, check cluster column \n')
  }

  ## create new pairwise group
  if(is.null(group_1_name)) group_1_name = paste0(group_1, collapse = '_')
  if(is.null(group_2_name)) group_2_name = paste0(group_2, collapse = '_')
  cell_metadata[, pairwise_select_comp := ifelse(get(cluster_column) %in% group_1, group_1_name, group_2_name)]

  if(nrow(cell_metadata[pairwise_select_comp == group_1_name]) == 0) {
    stop('\n there are no cells for group_1, check cluster column \n')
  }

  if(nrow(cell_metadata[pairwise_select_comp == group_2_name]) == 0) {
    stop('\n there are no cells for group_2, check cluster column \n')
  }

  cluster_column = 'pairwise_select_comp'

  # expression data
  subset_cell_IDs = cell_metadata[['cell_ID']]
  gobject = subsetGiotto(gobject = gobject, cell_ids = subset_cell_IDs)
  gobject@cell_metadata = cell_metadata



  ## START MAST ##
  ## create mast object ##
  # expression data
  values = match.arg(expression_values, choices = c('normalized', 'scaled', 'custom'))
  expr_data = Giotto:::select_expression_values(gobject = gobject, values = values)
  # column & row data
  column_data = pDataDT(gobject)
  setnames(column_data, 'cell_ID', 'wellKey')
  row_data = fDataDT(gobject)
  setnames(row_data, 'gene_ID', 'primerid')
  # mast object
  mast_data = MAST::FromMatrix(exprsArray = expr_data,
                               cData = column_data,
                               fData = row_data)

  ## set conditions and relevel
  cond <- factor(SingleCellExperiment::colData(mast_data)[[cluster_column]])
  cond <- stats::relevel(cond, group_2_name)
  mast_data@colData[[cluster_column]] <- cond

  ## create formula and run MAST gene regressions
  if(!is.null(adjust_columns)) {
    myformula = as.formula(paste0("~ 1 + ",cluster_column, " + ", paste(adjust_columns, collapse = " + ")))
  } else {
    myformula = as.formula(paste0("~ 1 + ",cluster_column))
  }
  zlmCond <- MAST::zlm(formula = myformula, sca = mast_data, ...)

  ## run LRT and return data.table with results
  sample = paste0(cluster_column, group_1_name)
  summaryCond <- MAST::summary(zlmCond, doLRT=sample)
  summaryDt <- summaryCond$datatable
  fcHurdle <- merge(summaryDt[contrast==sample & component=='H',.(primerid, `Pr(>Chisq)`)], #hurdle P values
                    summaryDt[contrast==sample & component=='logFC', .(primerid, coef, ci.hi, ci.lo)], by='primerid') #logFC coefficients
  fcHurdle[,fdr := p.adjust(`Pr(>Chisq)`, 'fdr')]
  data.table::setorder(fcHurdle, fdr)
  fcHurdle[, cluster := paste0(group_1_name,'_vs_', group_2_name)]
  data.table::setnames(fcHurdle, old = 'primerid', new = 'genes')

  return(fcHurdle)

}




#' @title findMastMarkers_one_vs_all
#' @name findMastMarkers_one_vs_all
#' @description Identify marker genes for all clusters in a one vs all manner based on the MAST package.
#' @param gobject giotto object
#' @param expression_values gene expression values to use
#' @param cluster_column clusters to use
#' @param subset_clusters selection of clusters to compare
#' @param adjust_columns column in pDataDT to adjust for (e.g. detection rate)
#' @param pval filter on minimal p-value
#' @param logFC filter on logFC
#' @param min_genes minimum genes to keep per cluster, overrides pval and logFC
#' @param verbose be verbose
#' @param ... additional parameters for the zlm function in MAST
#' @return data.table with marker genes
#' @seealso \code{\link{findMastMarkers}}
#' @export
#' @examples
#'     findMastMarkers_one_vs_all(gobject)
findMastMarkers_one_vs_all = function(gobject,
                                      expression_values = c('normalized', 'scaled', 'custom'),
                                      cluster_column,
                                      subset_clusters = NULL,
                                      adjust_columns = NULL,
                                      pval = 0.001,
                                      logFC = 1,
                                      min_genes = 10,
                                      verbose = TRUE,
                                      ...) {


  if("MAST" %in% rownames(installed.packages()) == FALSE) {
    stop("\n package 'MAST' is not yet installed \n",
         "To install: \n",
         "if (!requireNamespace('BiocManager', quietly = TRUE)) install.packages('BiocManager');
         BiocManager::install('MAST')"
    )
  }


  ## cluster column
  cell_metadata = pDataDT(gobject)
  if(!cluster_column %in% colnames(cell_metadata)) {
    stop('\n cluster column not found \n')
  }

  # restrict to a subset of clusters
  if(!is.null(subset_clusters)) {

    cell_metadata = cell_metadata[get(cluster_column) %in% subset_clusters]
    subset_cell_IDs = cell_metadata[['cell_ID']]
    gobject = subsetGiotto(gobject = gobject, cell_ids = subset_cell_IDs)
    cell_metadata = pDataDT(gobject)
  }

  ## sort uniq clusters
  uniq_clusters = sort(unique(cell_metadata[[cluster_column]]))

  # save list
  result_list = list()

  for(clus_i in 1:length(uniq_clusters)) {

    selected_clus = uniq_clusters[clus_i]
    other_clus = uniq_clusters[uniq_clusters != selected_clus]

    if(verbose == TRUE) {
      cat('\n start with cluster ', selected_clus, '\n')
    }

    temp_mast_markers = findMastMarkers(gobject = gobject,
                                        expression_values = expression_values,
                                        cluster_column = cluster_column,
                                        adjust_columns = adjust_columns,
                                        group_1 = selected_clus,
                                        group_1_name = selected_clus,
                                        group_2 = other_clus,
                                        group_2_name = 'others')

    result_list[[clus_i]] = temp_mast_markers

  }

  # filter or retain only selected marker genes
  result_dt = do.call('rbind', result_list)
  result_dt[, ranking := 1:.N, by = 'cluster']
  filtered_result_dt = result_dt[ranking <= min_genes | (fdr < pval & coef > logFC)]

  return(filtered_result_dt)

}







#' @title findMarkers
#' @name findMarkers
#' @description Identify marker genes for selected clusters.
#' @param gobject giotto object
#' @param expression_values gene expression values to use
#' @param cluster_column clusters to use
#' @param method method to use to detect differentially expressed genes
#' @param subset_clusters selection of clusters to compare
#' @param group_1 group 1 cluster IDs from cluster_column for pairwise comparison
#' @param group_2 group 2 cluster IDs from cluster_column for pairwise comparison
#' @param min_expr_gini_score gini: filter on minimum gini coefficient for expression
#' @param min_det_gini_score gini: filter minimum gini coefficient for detection
#' @param detection_threshold gini: detection threshold for gene expression
#' @param rank_score gini: rank scores to include
#' @param min_genes minimum number of top genes to return (for gini)
#' @param group_1_name mast: custom name for group_1 clusters
#' @param group_2_name mast: custom name for group_2 clusters
#' @param adjust_columns mast: column in pDataDT to adjust for (e.g. detection rate)
#' @param ... additional parameters for the findMarkers function in scran or zlm function in MAST
#' @return data.table with marker genes
#' @details Wrapper for all individual functions to detect marker genes for clusters.
#' @seealso \code{\link{findScranMarkers}}, \code{\link{findGiniMarkers}} and \code{\link{findMastMarkers}}
#' @export
#' @examples
#'     findMarkers(gobject)
findMarkers <- function(gobject,
                        expression_values = c('normalized', 'scaled', 'custom'),
                        cluster_column,
                        method = c('scran','gini','mast'),
                        subset_clusters = NULL,
                        group_1 = NULL,
                        group_2 = NULL,
                        min_expr_gini_score = 0.5,
                        min_det_gini_score = 0.5,
                        detection_threshold = 0,
                        rank_score = 1,
                        min_genes = 4,
                        group_1_name = NULL,
                        group_2_name = NULL,
                        adjust_columns = NULL,
                        ...) {


  # select method
  method = match.arg(method, choices = c('scran','gini','mast'))

  if(method == 'scran') {

    markers_result =  findScranMarkers(gobject = gobject,
                                       expression_values = expression_values,
                                       cluster_colum = cluster_column,
                                       subset_clusters = subset_clusters,
                                       group_1 = group_1,
                                       group_2 = group_2, ...)
  } else if(method == 'gini') {

    markers_result <-  findGiniMarkers(gobject = gobject,
                                       expression_values = expression_values,
                                       cluster_column = cluster_column,
                                       subset_clusters = subset_clusters,
                                       group_1 = group_1,
                                       group_2 = group_2,
                                       min_expr_gini_score = min_expr_gini_score,
                                       min_det_gini_score = min_det_gini_score,
                                       detection_threshold = detection_threshold,
                                       rank_score = rank_score,
                                       min_genes = min_genes)

  } else if(method == 'mast') {

    markers_result <- findMastMarkers(gobject = gobject,
                                      expression_values = expression_values,
                                      cluster_column = cluster_column,
                                      group_1 = group_1,
                                      group_1_name = group_1_name,
                                      group_2 = group_2,
                                      group_2_name = group_2_name,
                                      adjust_columns = adjust_columns,
                                      ...)

  }

  return(markers_result)

}


#' @title findMarkers_one_vs_all
#' @name findMarkers_one_vs_all
#' @description Identify marker genes for all clusters in a one vs all manner.
#' @param gobject giotto object
#' @param expression_values gene expression values to use
#' @param cluster_column clusters to use
#' @param method method to use to detect differentially expressed genes
#' @param subset_clusters selection of clusters to compare
#' @param pval scran & mast: filter on minimal p-value
#' @param logFC scan & mast: filter on logFC
#' @param min_genes minimum genes to keep per cluster, overrides pval and logFC
#' @param min_expr_gini_score gini: filter on minimum gini coefficient for expression
#' @param min_det_gini_score gini: filter minimum gini coefficient for detection
#' @param detection_threshold gini: detection threshold for gene expression
#' @param rank_score gini: rank scores to include
#' @param adjust_columns mast: column in pDataDT to adjust for (e.g. detection rate)
#' @param verbose be verbose
#' @param ... additional parameters for the findMarkers function in scran or zlm function in MAST
#' @return data.table with marker genes
#' @details Wrapper for all one vs all functions to detect marker genes for clusters.
#' @seealso \code{\link{findScranMarkers_one_vs_all}}, \code{\link{findGiniMarkers_one_vs_all}} and \code{\link{findMastMarkers_one_vs_all}}
#' @export
#' @examples
#'     findMarkers_one_vs_all(gobject)
findMarkers_one_vs_all <- function(gobject,
                                   expression_values = c('normalized', 'scaled', 'custom'),
                                   cluster_column,
                                   subset_clusters = NULL,
                                   method = c('scran','gini','mast'),
                                   # scran & mast
                                   pval = 0.01,
                                   logFC = 0.5,
                                   min_genes = 10,
                                   # gini
                                   min_expr_gini_score = 0.5,
                                   min_det_gini_score = 0.5,
                                   detection_threshold = 0,
                                   rank_score = 1,
                                   # mast specific
                                   adjust_columns = NULL,
                                   verbose = TRUE,
                                   ...) {


  # select method
  method = match.arg(method, choices = c('scran','gini','mast'))

  if(method == 'scran') {

    markers_result = findScranMarkers_one_vs_all(gobject = gobject,
                                                 expression_values = expression_values,
                                                 cluster_column = cluster_column,
                                                 subset_clusters = subset_clusters,
                                                 pval = pval,
                                                 logFC = logFC,
                                                 min_genes = min_genes,
                                                 verbose = verbose,
                                                 ...)
  } else if(method == 'gini') {

    markers_result = findGiniMarkers_one_vs_all(gobject = gobject,
                                                expression_values = expression_values,
                                                cluster_column = cluster_column,
                                                subset_clusters = subset_clusters,
                                                min_expr_gini_score = min_expr_gini_score,
                                                min_det_gini_score = min_det_gini_score,
                                                detection_threshold = detection_threshold,
                                                min_genes = min_genes,
                                                verbose = verbose)

  } else if(method == 'mast') {

    markers_result = findMastMarkers_one_vs_all(gobject = gobject,
                                                expression_values = expression_values,
                                                cluster_column = cluster_column,
                                                subset_clusters = subset_clusters,
                                                adjust_columns = adjust_columns,
                                                pval = pval,
                                                logFC = logFC,
                                                min_genes = min_genes,
                                                verbose = verbose,
                                                ...)

  }

  return(markers_result)


}









