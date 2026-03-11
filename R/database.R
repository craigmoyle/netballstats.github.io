`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) {
    return(y)
  }

  if (is.character(x) && !nzchar(x[1])) {
    return(y)
  }

  x
}

default_sqlite_db_path <- function(base_path) {
  normalizePath(file.path(base_path, "storage", "netball_stats.sqlite"), mustWork = FALSE)
}

database_url <- function() {
  trimws(Sys.getenv("NETBALL_STATS_DATABASE_URL", Sys.getenv("DATABASE_URL", "")))
}

database_backend <- function() {
  configured <- tolower(trimws(Sys.getenv("NETBALL_STATS_DB_BACKEND", "")))
  if (configured %in% c("postgres", "postgresql")) {
    return("postgres")
  }
  if (configured == "sqlite") {
    return("sqlite")
  }

  if (nzchar(database_url()) || nzchar(Sys.getenv("NETBALL_STATS_DB_HOST", ""))) {
    return("postgres")
  }

  "sqlite"
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
    sslmode = (parsed$query %||% list())$sslmode %||% Sys.getenv("NETBALL_STATS_DB_SSLMODE", "require")
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
      sslmode = Sys.getenv("NETBALL_STATS_DB_SSLMODE", "require")
    )
  }

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

database_target_description <- function(default_sqlite_path) {
  if (database_backend() == "postgres") {
    args <- postgres_connection_args()
    sprintf("postgresql://%s:%s/%s", args$host, args$port, args$dbname)
  } else {
    default_sqlite_path
  }
}

open_database_connection <- function(default_sqlite_path, require_existing_sqlite = TRUE) {
  if (database_backend() == "postgres") {
    args <- postgres_connection_args()
    return(do.call(DBI::dbConnect, c(list(drv = RPostgres::Postgres()), args)))
  }

  if (require_existing_sqlite && !file.exists(default_sqlite_path)) {
    stop(
      "Database file not found at ",
      default_sqlite_path,
      ". Run scripts/build_database.R first.",
      call. = FALSE
    )
  }

  DBI::dbConnect(RSQLite::SQLite(), default_sqlite_path)
}
