# Quick precuror script to check whether the monhtly observations have been updated (around the 15th of the month)

library(dplyr)
library(lubridate)
library(here)
source(here("analysis-oceantemps", "util.r"))

#' Scrape the update time for the monthly obs from nasa psl and compare against
#' the time saved to disk.
#' 
#' @return A boolean indicating that newer observations are available.
newer_obs_available <- function() {
  return(get_current_monthly_dt() > get_last_monthly_update_dt())
}

#' Determine whether new monthly observations are available
#' 
#' @return A boolean. True if new obs are available for download, or if obs have
#' never been downloaded
check_remote_obs_stale <- function() {
  (!file.exists(last_update_path)) || newer_obs_available()
}

is_stale <- check_remote_obs_stale()

stopifnot(
  "Error: check_remote_obs_stale() returned a missing value." =
    !is.na(is_stale))

# save whether obs are stale to env var $MONTHLY_IS_STALE for later steps
message("Are monthly obs stale? ", is_stale)
system2("echo", c(
  paste0("MONTHLY_IS_STALE=", is_stale),
  ">>",
  "$GITHUB_ENV"))
