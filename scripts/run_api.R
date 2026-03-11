#!/usr/bin/env Rscript

script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(), value = TRUE)
  if (!length(file_arg)) {
    return(normalizePath(".", mustWork = FALSE))
  }

  normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = FALSE)
}

repo_root <- normalizePath(file.path(dirname(script_path()), ".."), mustWork = FALSE)
options(netballstats.repo_root = repo_root)

host <- Sys.getenv("NETBALL_STATS_HOST", "127.0.0.1")
port <- as.integer(Sys.getenv("NETBALL_STATS_PORT", "8000"))

pr <- plumber::plumb(file.path(repo_root, "api", "plumber.R"))
pr$run(host = host, port = port)
