`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) {
    return(y)
  }

  if (is.character(x) && !nzchar(x[1])) {
    return(y)
  }

  x
}

database_url <- function() {
  trimws(Sys.getenv("NETBALL_STATS_DATABASE_URL", Sys.getenv("DATABASE_URL", "")))
}

parse_positive_env_int <- function(name, default) {
  parsed <- suppressWarnings(as.integer(Sys.getenv(name, as.character(default))))
  if (is.na(parsed) || parsed < 1L) {
    return(default)
  }

  parsed
}

parse_nonnegative_env_int <- function(name, default) {
  parsed <- suppressWarnings(as.integer(Sys.getenv(name, as.character(default))))
  if (is.na(parsed) || parsed < 0L) {
    return(default)
  }

  parsed
}

postgres_connect_timeout_seconds <- function() {
  parse_positive_env_int("NETBALL_STATS_DB_CONNECT_TIMEOUT_SECONDS", 5L)
}

postgres_statement_timeout_ms <- function() {
  parse_nonnegative_env_int("NETBALL_STATS_DB_STATEMENT_TIMEOUT_MS", 5000L)
}

database_backend <- function() {
  "postgres"
}

parse_database_url <- function(url) {
  parsed <- httr::parse_url(url)
  scheme <- tolower(parsed$scheme %||% "")
  if (!scheme %in% c("postgres", "postgresql")) {
    stop("Unsupported database URL scheme: ", scheme, ".", call. = FALSE)
  }

  db_name <- sub("^/", "", parsed$path %||% "")
  if (!nzchar(db_name)) {
    stop("Database URL must include a database name.", call. = FALSE)
  }

  list(
    host = parsed$hostname %||% parsed$host,
    port = as.integer(parsed$port %||% 5432L),
    dbname = db_name,
    user = utils::URLdecode(parsed$username %||% ""),
    password = utils::URLdecode(parsed$password %||% ""),
    sslmode = (parsed$query %||% list())$sslmode %||% Sys.getenv("NETBALL_STATS_DB_SSLMODE", "verify-full")
  )
}

postgres_connection_args <- function() {
  if (nzchar(database_url())) {
    connection_args <- parse_database_url(database_url())
  } else {
    connection_args <- list(
      host = trimws(Sys.getenv("NETBALL_STATS_DB_HOST", "")),
      port = as.integer(Sys.getenv("NETBALL_STATS_DB_PORT", "5432")),
      dbname = trimws(Sys.getenv("NETBALL_STATS_DB_NAME", "")),
      user = trimws(Sys.getenv("NETBALL_STATS_DB_USER", "")),
      password = Sys.getenv("NETBALL_STATS_DB_PASSWORD", ""),
      sslmode = Sys.getenv("NETBALL_STATS_DB_SSLMODE", "verify-full")
    )
  }

  sslrootcert <- trimws(Sys.getenv("NETBALL_STATS_DB_SSLROOTCERT", ""))
  if (nzchar(sslrootcert)) {
    connection_args$sslrootcert <- sslrootcert
  }

  connection_args$connect_timeout <- postgres_connect_timeout_seconds()
  connection_args$options <- sprintf(
    "-c statement_timeout=%d",
    postgres_statement_timeout_ms()
  )

  required_fields <- c("host", "dbname", "user", "password")
  missing_fields <- required_fields[!vapply(connection_args[required_fields], nzchar, logical(1))]
  if (length(missing_fields)) {
    stop(
      "Missing PostgreSQL connection settings: ",
      paste(missing_fields, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  connection_args
}

database_target_description <- function() {
  args <- postgres_connection_args()
  sprintf("postgresql://%s:%s/%s", args$host, args$port, args$dbname)
}

open_database_connection <- function() {
  args <- postgres_connection_args()
  do.call(DBI::dbConnect, c(list(drv = RPostgres::Postgres()), args))
}
