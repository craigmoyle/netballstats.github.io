source("api/R/helpers.R")

question <- "Which teams had the lowest general play turnovers in 2025?"
preview <- preview_ask_the_stats_parse(question)

if (!isTRUE(preview$success)) {
  stop("Expected preview_ask_the_stats_parse() to support the question.")
}

if (!identical(preview$status, "supported")) {
  stop(sprintf(
    "Expected preview_ask_the_stats_parse() status supported, got %s",
    preview$status %||% "NULL"
  ))
}

if (!identical(preview$shape, "list")) {
  stop(sprintf(
    "Expected preview_ask_the_stats_parse() shape list, got %s",
    preview$shape %||% "NULL"
  ))
}

fake_conn <- structure(list(), class = "test-conn")

resolve_query_subject <- function(conn, phrase) {
  stop("resolve_query_subject should not be called for plural team preview execution")
}

resolve_query_team <- function(conn, phrase) {
  if (is.null(phrase)) {
    return(NULL)
  }
  stop("resolve_query_team should not be called for a question without an opponent filter")
}

resolve_query_stat <- function(text) {
  stop("resolve_query_stat should not be called when executing a supported preview parse")
}

intent <- build_simple_query_intent_from_preview(
  fake_conn,
  question,
  preview$parsed,
  limit = 12L
)

if (!identical(intent$status, "supported")) {
  stop(sprintf(
    "Expected build_simple_query_intent_from_preview() to support the question, got %s",
    intent$status %||% "NULL"
  ))
}

if (!identical(intent$intent_type, "lowest")) {
  stop(sprintf(
    "Expected preview execution intent_type lowest, got %s",
    intent$intent_type %||% "NULL"
  ))
}

if (!identical(intent$stat, "generalPlayTurnovers")) {
  stop(sprintf(
    "Expected preview execution stat generalPlayTurnovers, got %s",
    intent$stat %||% "NULL"
  ))
}

if (!identical(intent$subject_type, "teams")) {
  stop(sprintf(
    "Expected preview execution subject_type teams, got %s",
    intent$subject_type %||% "NULL"
  ))
}

if (!identical(intent$season, 2025L)) {
  stop(sprintf(
    "Expected preview execution season 2025, got %s",
    intent$season %||% "NULL"
  ))
}

cat("Preview execution checks passed.\n")
