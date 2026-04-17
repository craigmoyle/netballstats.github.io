`%||%` <- get0("%||%", ifnotfound = function(x, y) if (is.null(x) || length(x) == 0) y else x)

required_player_reference_columns <- function() {
  c("player_id", "date_of_birth", "nationality", "import_status", "source_label", "source_url", "verified_at", "notes")
}

normalize_import_status <- function(value) {
  normalized <- tolower(trimws(as.character(value %||% "")))
  if (!nzchar(normalized)) {
    return(NA_character_)
  }
  if (!normalized %in% c("local", "import")) {
    stop("import_status must be either 'local' or 'import'.", call. = FALSE)
  }
  normalized
}

debut_age_band <- function(age_years) {
  age_years <- suppressWarnings(as.numeric(age_years))
  if (is.na(age_years)) return(NA_character_)
  if (age_years < 20) return("19 and under")
  if (age_years < 23) return("20 to 22")
  if (age_years < 26) return("23 to 25")
  "26 and over"
}

read_player_reference_csv <- function(path) {
  rows <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  missing_columns <- setdiff(required_player_reference_columns(), names(rows))
  if (length(missing_columns)) {
    stop("Missing player reference columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  }

  rows <- rows[required_player_reference_columns()]
  rows$player_id <- as.integer(rows$player_id)
  if (anyNA(rows$player_id)) {
    stop("player_id must be an integer in every maintained row.", call. = FALSE)
  }

  rows$date_of_birth <- as.Date(rows$date_of_birth)
  if (any(is.na(rows$date_of_birth))) {
    stop("date_of_birth must be ISO-8601 (YYYY-MM-DD) in every maintained row.", call. = FALSE)
  }

  rows$import_status <- vapply(rows$import_status, normalize_import_status, character(1))
  rows$nationality <- trimws(as.character(rows$nationality))
  rows$source_label <- trimws(as.character(rows$source_label))
  rows$source_url <- trimws(as.character(rows$source_url))
  rows$verified_at <- as.Date(rows$verified_at)

  if (any(!nzchar(rows$nationality))) stop("nationality is required for every maintained row.", call. = FALSE)
  if (any(!nzchar(rows$source_label))) stop("source_label is required for every maintained row.", call. = FALSE)
  if (any(!nzchar(rows$source_url))) stop("source_url is required for every maintained row.", call. = FALSE)
  if (any(is.na(rows$verified_at))) stop("verified_at must be ISO-8601 (YYYY-MM-DD) in every maintained row.", call. = FALSE)

  rows$notes <- as.character(rows$notes %||% "")
  rows
}
