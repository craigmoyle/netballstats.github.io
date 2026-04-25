#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})

source("R/database.R")
source("api/R/helpers.R")

test_conn <- NULL

setup_test_db <- function() {
  tryCatch(
    {
      test_conn <<- open_database_connection()
      cat("✓ Connected to test database\n")
      TRUE
    },
    error = function(e) {
      cat("Note: Database connection not available (",
          conditionMessage(e),
          "). Continuing with function existence check.\n", sep = "")
      FALSE
    }
  )
}

test_comparison_query_exists <- function() {
  if (!exists("build_comparison_query", mode = "function")) {
    cat("✗ build_comparison_query function not found\n")
    return(FALSE)
  }
  cat("✓ build_comparison_query function exists\n")
  TRUE
}

test_trend_query_exists <- function() {
  if (!exists("build_trend_query", mode = "function")) {
    cat("✗ build_trend_query function not found\n")
    return(FALSE)
  }
  cat("✓ build_trend_query function exists\n")
  TRUE
}

test_combination_query_exists <- function() {
  if (!exists("build_combination_query", mode = "function")) {
    cat("✗ build_combination_query function not found\n")
    return(FALSE)
  }
  cat("✓ build_combination_query function exists\n")
  TRUE
}

test_comparison_query <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping comparison query database test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_comparison_query(
        subjects = c("Vixens", "Swifts"),
        stat = "goalAssists",
        season = 2025,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "supported",
        result$intent_type == "comparison",
        length(result$results) == 2,
        result$results[[1]]$subject == "Vixens" || result$results[[1]]$subject == "Swifts",
        !is.null(result$comparison),
        !is.null(result$comparison$leader)
      )
      cat("✓ Comparison query test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Comparison query test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_trend_query <- function() {
  if (is.null(test_conn)) {
    cat("✗ No database connection for trend query test\n")
    return(FALSE)
  }

  tryCatch(
    {
      result <- build_trend_query(
        subject = "Grace Nweke",
        stat = "goalAssists",
        seasons = c(2023, 2024, 2025),
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "supported",
        result$intent_type == "trend",
        result$subject == "Grace Nweke",
        result$subject_type == "player",
        result$stat == "goalAssists",
        !is.null(result$stat_label),
        length(result$seasons) == 3,
        length(result$results) > 0
      )

      for (i in seq_along(result$results)) {
        r <- result$results[[i]]
        stopifnot(
          !is.null(r$season),
          !is.null(r$total),
          !is.null(r$games),
          !is.null(r$average),
          is.numeric(r$average),
          is.numeric(r$total),
          is.numeric(r$games)
        )
        if (i > 1) {
          stopifnot(
            !is.null(r$yoy_change),
            !is.null(r$yoy_change_label),
            is.numeric(r$yoy_change)
          )
        }
      }
      cat("✓ Trend query test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Trend query test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_record_query <- function() {
  if (is.null(test_conn)) {
    cat("✗ No database connection for record query test\n")
    return(FALSE)
  }

  tryCatch(
    {
      result <- build_record_query(
        stat = "intercepts",
        subject_type = "player",
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "supported",
        result$intent_type == "record",
        result$stat == "intercepts",
        result$scope == "all_time",
        !is.null(result$record),
        !is.null(result$record$value),
        !is.null(result$record$all_time_rank),
        !is.null(result$context),
        length(result$context) > 0
      )
      cat("✓ Record query test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Record query test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query <- function() {
  if (is.null(test_conn)) {
    cat("✗ No database connection for combination query test\n")
    return(FALSE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = ">=", threshold = 40),
          list(stat = "gain", operator = ">=", threshold = 5)
        ),
        logical_operator = "AND",
        season = 2024,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "supported",
        result$intent_type == "combination",
        length(result$filters) == 2,
        result$logical_operator == "AND",
        result$season == 2024,
        result$total_matches >= 0,
        !is.null(result$filters[[1]]$stat_label),
        !is.null(result$filters[[2]]$stat_label)
      )

      if (length(result$results) > 0) {
        stopifnot(
          !is.null(result$results[[1]]$player),
          !is.null(result$results[[1]]$goals),
          !is.null(result$results[[1]]$gain)
        )
      }

      cat("✓ Combination query test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Combination query test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_empty_filters <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping empty filters test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("At least one filter", result$error)
      )
      cat("✓ Empty filters test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Empty filters test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_invalid_operator <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping invalid operator test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = "~~", threshold = 40)
        ),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("invalid operator", result$error, ignore.case = TRUE)
      )
      cat("✓ Invalid operator test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Invalid operator test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_non_numeric_threshold <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping non-numeric threshold test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = ">=", threshold = "not-a-number")
        ),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("numeric", result$error, ignore.case = TRUE)
      )
      cat("✓ Non-numeric threshold test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Non-numeric threshold test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_missing_field <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping missing field test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = ">=")
        ),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("stat.*operator.*threshold", result$error, ignore.case = TRUE)
      )
      cat("✓ Missing field test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Missing field test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_invalid_logical_operator <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping invalid logical operator test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = ">=", threshold = 40)
        ),
        logical_operator = "XOR",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("Logical operator", result$error, ignore.case = TRUE)
      )
      cat("✓ Invalid logical operator test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Invalid logical operator test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_invalid_season <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping invalid season test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = ">=", threshold = 40)
        ),
        logical_operator = "AND",
        season = 2000,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("2008 and 2100", result$error, ignore.case = TRUE)
      )
      cat("✓ Invalid season test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Invalid season test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_non_goal_stat <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping non-goal stat test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "gain", operator = ">=", threshold = 5),
          list(stat = "intercepts", operator = ">=", threshold = 2)
        ),
        logical_operator = "AND",
        season = 2024,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "supported",
        result$intent_type == "combination",
        length(result$filters) == 2,
        !is.null(result$filters[[1]]$stat_label),
        !is.null(result$filters[[2]]$stat_label)
      )
      cat("✓ Non-goal stat test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Non-goal stat test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_invalid_stat_key <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping invalid stat key test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "nonexistent_stat", operator = ">=", threshold = 5)
        ),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("not recognized", result$error, ignore.case = TRUE)
      )
      cat("✓ Invalid stat key test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Invalid stat key test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_empty_filters <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping empty filters test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("At least one filter", result$error)
      )
      cat("✓ Empty filters test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Empty filters test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_invalid_operator <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping invalid operator test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = "~~", threshold = 40)
        ),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("invalid operator", result$error, ignore.case = TRUE)
      )
      cat("✓ Invalid operator test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Invalid operator test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_non_numeric_threshold <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping non-numeric threshold test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = ">=", threshold = "not-a-number")
        ),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("numeric", result$error, ignore.case = TRUE)
      )
      cat("✓ Non-numeric threshold test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Non-numeric threshold test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_missing_field <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping missing field test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = ">=")  # Missing threshold
        ),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("stat.*operator.*threshold", result$error, ignore.case = TRUE)
      )
      cat("✓ Missing field test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Missing field test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_invalid_logical_operator <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping invalid logical operator test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = ">=", threshold = 40)
        ),
        logical_operator = "XOR",  # Invalid operator
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("Logical operator", result$error, ignore.case = TRUE)
      )
      cat("✓ Invalid logical operator test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Invalid logical operator test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_invalid_season <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping invalid season test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "goals", operator = ">=", threshold = 40)
        ),
        logical_operator = "AND",
        season = 2000,  # Before 2008
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("2008 and 2100", result$error, ignore.case = TRUE)
      )
      cat("✓ Invalid season test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Invalid season test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_non_goal_stat <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping non-goal stat test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "gain", operator = ">=", threshold = 5),
          list(stat = "intercepts", operator = ">=", threshold = 2)
        ),
        logical_operator = "AND",
        season = 2024,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "supported",
        result$intent_type == "combination",
        length(result$filters) == 2,
        !is.null(result$filters[[1]]$stat_label),
        !is.null(result$filters[[2]]$stat_label)
      )
      cat("✓ Non-goal stat test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Non-goal stat test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_combination_query_invalid_stat_key <- function() {
  if (is.null(test_conn)) {
    cat("⊘ Skipping invalid stat key test (no connection)\n")
    return(TRUE)
  }

  tryCatch(
    {
      result <- build_combination_query(
        filters = list(
          list(stat = "nonexistent_stat", operator = ">=", threshold = 5)
        ),
        logical_operator = "AND",
        season = NULL,
        conn = test_conn
      )

      stopifnot(
        !is.null(result),
        result$status == "error",
        grepl("not recognized", result$error, ignore.case = TRUE)
      )
      cat("✓ Invalid stat key test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Invalid stat key test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_comparison_simple <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("Vixens vs Swifts goal assists")
      stopifnot(
        result$status %in% c("success", "parse_help_needed"),
        result$shape == "comparison",
        result$confidence > 0.65,
        !is.null(result$parsed$subjects),
        length(result$parsed$subjects) >= 2,
        !is.null(result$parsed$stat)
      )
      cat("✓ Parser: comparison (simple) test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: comparison (simple) test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_comparison_with_season <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("Vixens vs Swifts goal assists in 2025")
      stopifnot(
        result$status == "success",
        result$shape == "comparison",
        result$confidence > 0.8,
        !is.null(result$parsed$seasons),
        length(result$parsed$seasons) > 0,
        2025 %in% result$parsed$seasons
      )
      cat("✓ Parser: comparison (with season) test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: comparison (with season) test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_trend_basic <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("Grace Nweke goal assists across 2023, 2024, 2025")
      stopifnot(
        result$status == "success",
        result$shape == "trend",
        result$confidence > 0.8,
        !is.null(result$parsed$subject),
        !is.null(result$parsed$stat),
        !is.null(result$parsed$seasons),
        length(result$parsed$seasons) >= 2
      )
      cat("✓ Parser: trend (basic) test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: trend (basic) test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_record_alltime <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("Highest single-game intercepts all time")
      stopifnot(
        result$status == "success",
        result$shape == "record",
        result$confidence > 0.8,
        !is.null(result$parsed$stat),
        !is.null(result$parsed$scope),
        result$parsed$scope == "all_time"
      )
      cat("✓ Parser: record (all-time) test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: record (all-time) test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_combination_and <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("players with 40+ goals AND 5+ gains in 2024")
      stopifnot(
        result$status %in% c("success", "parse_help_needed", "error"),
        result$shape == "combination" || (result$status == "error" && result$confidence < 0.65),
        result$confidence > 0.4,
        if (result$status %in% c("success", "parse_help_needed")) {
          !is.null(result$parsed$filters) && 
          length(result$parsed$filters) >= 1 &&
          !is.null(result$parsed$logical_operator) &&
          result$parsed$logical_operator == "AND"
        } else {
          TRUE
        }
      )
      cat("✓ Parser: combination (AND) test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: combination (AND) test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_empty_input <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("")
      stopifnot(
        result$status == "error",
        result$confidence == 0,
        is.na(result$shape),
        !is.null(result$error_message)
      )
      cat("✓ Parser: empty input test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: empty input test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_null_input <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse(NULL)
      stopifnot(
        result$status == "error",
        result$confidence == 0,
        is.na(result$shape)
      )
      cat("✓ Parser: null input test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: null input test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_confidence_scaling <- function() {
  tryCatch(
    {
      # Full confidence query
      result_full <- attempt_complex_parse("Vixens vs Swifts goal assists in 2025")
      # Partial confidence query
      result_partial <- attempt_complex_parse("Vixens vs Swifts")
      
      stopifnot(
        result_full$confidence > 0.8,
        result_partial$confidence >= 0.5,
        result_full$confidence >= result_partial$confidence
      )
      cat("✓ Parser: confidence scaling test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: confidence scaling test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_stat_resolution <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("Fever's goals across 2023-2025")
      stopifnot(
        result$status == "success",
        !is.null(result$parsed$stat),
        result$parsed$stat == "goals"
      )
      cat("✓ Parser: stat resolution test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: stat resolution test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_season_range <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("intercepts across 2023-2025")
      stopifnot(
        result$status == "success",
        !is.null(result$parsed$seasons),
        length(result$parsed$seasons) >= 3,
        2023 %in% result$parsed$seasons,
        2024 %in% result$parsed$seasons,
        2025 %in% result$parsed$seasons
      )
      cat("✓ Parser: season range test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: season range test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_medium_confidence_comparison <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("vixens vs swifts goals")
      stopifnot(
        result$status == "parse_help_needed",
        result$confidence >= 0.65,
        result$confidence < 0.85,
        !is.null(result$builder_prefill),
        !is.null(result$builder_prefill$subjects),
        length(result$builder_prefill$subjects) >= 2
      )
      cat("✓ Parser: medium confidence comparison test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: medium confidence comparison test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_medium_confidence_trend <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("vixens across seasons")
      stopifnot(
        result$status == "parse_help_needed",
        result$confidence >= 0.65,
        result$confidence < 0.85,
        !is.null(result$builder_prefill),
        !is.null(result$builder_prefill$subject)
      )
      cat("✓ Parser: medium confidence trend test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: medium confidence trend test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_prefill_comparison <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("vixens vs swifts goals")
      stopifnot(
        result$status == "parse_help_needed",
        !is.null(result$builder_prefill),
        !is.null(result$builder_prefill$subjects),
        !is.null(result$builder_prefill$stat),
        "vixens" %in% tolower(as.character(result$builder_prefill$subjects)),
        "swifts" %in% tolower(as.character(result$builder_prefill$subjects))
      )
      cat("✓ Parser: prefill comparison test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: prefill comparison test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_prefill_trend <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("vixens goals across 2023 2024")
      stopifnot(
        result$status %in% c("success", "parse_help_needed"),
        if (result$status %in% c("success", "parse_help_needed")) {
          !is.null(result$builder_prefill) || !is.null(result$parsed)
        } else {
          TRUE
        },
        !is.null(result$parsed$subject),
        !is.null(result$parsed$stat),
        !is.null(result$parsed$seasons),
        length(result$parsed$seasons) >= 2
      )
      cat("✓ Parser: prefill trend test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: prefill trend test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

test_parser_prefill_combination <- function() {
  tryCatch(
    {
      result <- attempt_complex_parse("goals and assists in 2024")
      stopifnot(
        result$status %in% c("parse_help_needed", "error"),
        if (result$status == "parse_help_needed") {
          !is.null(result$builder_prefill) && 
          !is.null(result$builder_prefill$filters) &&
          !is.null(result$builder_prefill$logical_operator) &&
          length(result$builder_prefill$filters) > 0
        } else {
          TRUE
        }
      )
      cat("✓ Parser: prefill combination test passed\n")
      TRUE
    },
    error = function(e) {
      cat("✗ Parser: prefill combination test failed:", conditionMessage(e), "\n")
      FALSE
    }
  )
}

run_tests <- function() {
  cat("Running query expansion tests...\n\n")

  success <- TRUE
  success <- test_comparison_query_exists() && success
  success <- test_trend_query_exists() && success
  success <- test_combination_query_exists() && success

  if (!setup_test_db()) {
    cat("\nDatabase connection unavailable; skipping database-dependent tests.\n")
  } else {
    success <- test_comparison_query() && success
    success <- test_trend_query() && success
    success <- test_record_query() && success
    success <- test_combination_query() && success
    
    # Edge case tests for combination query
    success <- test_combination_query_empty_filters() && success
    success <- test_combination_query_invalid_operator() && success
    success <- test_combination_query_non_numeric_threshold() && success
    success <- test_combination_query_missing_field() && success
    success <- test_combination_query_invalid_logical_operator() && success
    success <- test_combination_query_invalid_season() && success
    success <- test_combination_query_non_goal_stat() && success
    success <- test_combination_query_invalid_stat_key() && success
  }

  cat("\n--- Parser Enhancement Tests ---\n")
  success <- test_parser_comparison_simple() && success
  success <- test_parser_comparison_with_season() && success
  success <- test_parser_trend_basic() && success
  success <- test_parser_record_alltime() && success
  success <- test_parser_combination_and() && success
  success <- test_parser_empty_input() && success
  success <- test_parser_null_input() && success
  success <- test_parser_confidence_scaling() && success
  success <- test_parser_stat_resolution() && success
  success <- test_parser_season_range() && success

  cat("\n--- Parser Medium Confidence & Prefill Tests ---\n")
  success <- test_parser_medium_confidence_comparison() && success
  success <- test_parser_medium_confidence_trend() && success
  success <- test_parser_prefill_comparison() && success
  success <- test_parser_prefill_trend() && success
  success <- test_parser_prefill_combination() && success

  if (success) {
    cat("\n✓ All tests passed\n")
  } else {
    cat("\n✗ Some tests failed\n")
  }

  if (!is.null(test_conn)) {
    tryCatch(DBI::dbDisconnect(test_conn), error = function(e) NULL)
  }

  invisible(success)
}

if (!interactive()) {
  success <- run_tests()
  quit(status = if (success) 0 else 1)
}
