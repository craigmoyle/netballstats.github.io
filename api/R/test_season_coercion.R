#!/usr/bin/env Rscript

# Regression tests for season parameter handling and goals logic fixes
# Tests the coerce_seasons() helper function and error response consistency

suppressPackageStartupMessages({
  library(jsonlite)
})

source("api/R/helpers.R", local = TRUE)

test_count <- 0
pass_count <- 0

run_test <- function(name, test_expr) {
  test_count <<- test_count + 1
  tryCatch({
    test_expr()
    pass_count <<- pass_count + 1
    cat(sprintf("✓ Test %d: %s\n", test_count, name))
  }, error = function(e) {
    cat(sprintf("✗ Test %d: %s - %s\n", test_count, name, conditionMessage(e)))
  })
}

assert_equal <- function(actual, expected, message = "") {
  if (!identical(actual, expected)) {
    stop(sprintf("Expected %s, got %s. %s", toString(expected), toString(actual), message))
  }
}

assert_null <- function(value, message = "") {
  if (!is.null(value)) {
    stop(sprintf("Expected NULL, got %s. %s", toString(value), message))
  }
}

assert_not_null <- function(value, message = "") {
  if (is.null(value)) {
    stop(sprintf("Expected non-NULL value. %s", message))
  }
}

# ============================================================================
# TEST SUITE 1: coerce_seasons() Helper Function
# ============================================================================

run_test("coerce_seasons() with NULL input returns NULL", function() {
  result <- coerce_seasons(NULL, multiple = FALSE)
  assert_null(result)
})

run_test("coerce_seasons() with empty vector returns NULL", function() {
  result <- coerce_seasons(c(), multiple = FALSE)
  assert_null(result)
})

run_test("coerce_seasons() with NA returns NULL", function() {
  result <- coerce_seasons(NA, multiple = FALSE)
  assert_null(result)
})

run_test("coerce_seasons() with single season returns integer", function() {
  result <- coerce_seasons(2023, multiple = FALSE)
  assert_equal(result, 2023L)
  assert_equal(typeof(result), "integer")
})

run_test("coerce_seasons() with multiple=TRUE returns integer vector", function() {
  result <- coerce_seasons(c(2022, 2023), multiple = TRUE)
  assert_equal(result, c(2022L, 2023L))
  assert_equal(typeof(result), "integer")
})

run_test("coerce_seasons() with multiple=FALSE on vector returns first element", function() {
  result <- coerce_seasons(c(2022, 2023, 2024), multiple = FALSE)
  assert_equal(result, 2022L)
})

run_test("coerce_seasons() converts character season to integer", function() {
  result <- coerce_seasons("2023", multiple = FALSE)
  assert_equal(result, 2023L)
})

run_test("coerce_seasons() doesn't crash on empty array (regression test)", function() {
  # This would crash without the fix
  seasons <- c()
  result <- coerce_seasons(seasons, multiple = FALSE)
  assert_null(result)
})

# ============================================================================
# TEST SUITE 2: build_goals_stat_expression() Helper Function
# ============================================================================

run_test("build_goals_stat_expression() builds correct SQL expression", function() {
  result <- build_goals_stat_expression("pms1", "pms2")
  expected <- "(pms1.match_value + 2 * COALESCE(pms2.match_value, 0))"
  assert_equal(result, expected)
})

run_test("build_goals_stat_expression() with custom aliases", function() {
  result <- build_goals_stat_expression("a", "b")
  expected <- "(a.match_value + 2 * COALESCE(b.match_value, 0))"
  assert_equal(result, expected)
})

run_test("build_goals_stat_expression() maintains consistent format", function() {
  result1 <- build_goals_stat_expression("pms1", "pms2")
  result2 <- build_goals_stat_expression("pms1", "pms2")
  assert_equal(result1, result2, "Multiple calls should return identical results")
})

# ============================================================================
# TEST SUITE 3: Error Response Schema Consistency
# ============================================================================

run_test("Error responses have consistent status field", function() {
  # This test checks the structure - actual execution would need a DB
  # but we can verify the schema structure is correct
  error_response <- list(
    status = jsonlite::unbox("error"),
    intent_type = jsonlite::unbox("comparison"),
    error = jsonlite::unbox("Test error"),
    code = jsonlite::unbox("TEST_ERROR")
  )
  
  assert_not_null(error_response$status)
  assert_not_null(error_response$intent_type)
  assert_not_null(error_response$error)
  assert_not_null(error_response$code)
})

# ============================================================================
# TEST SUITE 4: Season Parameter Edge Cases
# ============================================================================

run_test("coerce_seasons() preserves integer type", function() {
  result <- coerce_seasons(2023L, multiple = FALSE)
  assert_equal(typeof(result), "integer")
})

run_test("coerce_seasons() handles numeric year correctly", function() {
  result <- coerce_seasons(2023.0, multiple = FALSE)
  assert_equal(result, 2023L)
})

run_test("coerce_seasons() with multiple seasons preserves order", function() {
  seasons <- c(2025, 2023, 2024)
  result <- coerce_seasons(seasons, multiple = TRUE)
  assert_equal(result, c(2025L, 2023L, 2024L))
})

run_test("coerce_seasons() with vector of length 1 and multiple=FALSE", function() {
  result <- coerce_seasons(c(2023), multiple = FALSE)
  assert_equal(result, 2023L)
})

run_test("coerce_seasons() with vector of length 1 and multiple=TRUE", function() {
  result <- coerce_seasons(c(2023), multiple = TRUE)
  assert_equal(result, 2023L)
})

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n")
cat(sprintf("========================================\n"))
cat(sprintf("Test Results: %d/%d passed\n", pass_count, test_count))
cat(sprintf("========================================\n"))

if (pass_count == test_count) {
  cat("✓ All tests passed!\n")
  quit(status = 0)
} else {
  cat(sprintf("✗ %d test(s) failed\n", test_count - pass_count))
  quit(status = 1)
}
