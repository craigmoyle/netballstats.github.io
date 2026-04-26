#!/usr/bin/env Rscript

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
Sys.setenv(
  NETBALL_STATS_REPO_ROOT = repo_root,
  NETBALL_STATS_BROWSER_APPINSIGHTS_CONNECTION_STRING = paste(
    "InstrumentationKey=00000000-0000-0000-0000-000000000000",
    "IngestionEndpoint=https://example.com",
    sep = ";"
  )
)

source(file.path(repo_root, "api", "plumber.R"), local = TRUE)

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) {
    stop(message, call. = FALSE)
  }
}

public_context <- telemetry_sanitise_context(list(traffic_class = "public"))
assert_true(identical(public_context$traffic_class, "public"), "Expected public traffic_class to survive context sanitisation.")

invalid_context <- telemetry_sanitise_context(list(traffic_class = "something_else"))
assert_true(is.null(invalid_context$traffic_class), "Expected invalid traffic_class values to be dropped.")

event_envelope <- build_telemetry_envelope(
  "event",
  list(
    name = "compare_completed",
    uri = "https://example.com/compare/",
    context = list(
      session_id = "s-123",
      user_id = "u-123",
      operation_id = "op-123",
      traffic_class = "testing"
    ),
    properties = list(page_type = "compare")
  ),
  list(
    HTTP_X_FORWARDED_FOR = "202.128.120.22",
    REMOTE_ADDR = "202.128.120.22",
    HTTP_USER_AGENT = "test-agent",
    HTTP_ACCEPT_LANGUAGE = "en-AU"
  )
)

assert_true(
  identical(event_envelope$data$baseData$properties$traffic_class, "testing"),
  "Expected telemetry envelope properties to include the normalized traffic_class."
)

cat("Telemetry proxy checks passed.\n")
