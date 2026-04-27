#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(jsonlite)
})

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    return(y)
  }
  x
}

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) {
    stop(message, call. = FALSE)
  }
}

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
lockfile <- file.path(repo_root, "renv.lock")
dockerfile <- file.path(repo_root, "Dockerfile.azure")

lock_data <- jsonlite::fromJSON(lockfile, simplifyVector = FALSE)
packages <- lock_data$Packages %||% list()
super_netball <- packages$superNetballR

assert_true(!is.null(super_netball), "Expected renv.lock to include superNetballR.")
assert_true(identical(super_netball$Source, "GitHub"), "Expected superNetballR to be sourced from GitHub in renv.lock.")

docker_text <- paste(readLines(dockerfile, warn = FALSE), collapse = "\n")
uses_lockfile_restore <- grepl("renv::restore\\(", docker_text)
uses_github_install <- grepl("install_github\\(", docker_text)

assert_true(
  uses_lockfile_restore || uses_github_install,
  "Expected Dockerfile.azure to install GitHub packages via renv::restore() or remotes::install_github()."
)

if (uses_github_install) {
  github_ref <- sprintf(
    "%s/%s@%s",
    super_netball$RemoteUsername,
    super_netball$RemoteRepo,
    super_netball$RemoteRef
  )
  assert_true(
    grepl(github_ref, docker_text, fixed = TRUE),
    sprintf("Expected Dockerfile.azure to install superNetballR from %s.", github_ref)
  )
}

assert_true(
  grepl("requireNamespace", docker_text, fixed = TRUE) ||
    grepl("installed.packages(", docker_text, fixed = TRUE),
  "Expected Dockerfile.azure to verify required R packages are installed before the image build succeeds."
)

cat("Dockerfile.azure handles GitHub R packages and verifies required package availability.\n")
