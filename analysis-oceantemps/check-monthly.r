# Quick precuror script to check whether the monhtly observations have been updated (around the 15th of the month)

library(tidyverse)
library(rvest)
library(here)

#' Scrape the update time for the monthly obs from nasa psl and compare against
#' the time saved to disk.
#' 
#' @param last_update_path The path to a text file saving the previous update
#'   time. Assumed to exist.
#' @return A boolean indicating that newer observations are available.
current_obs_newer <- function(last_update_path) {

  # get the previous update time from disk
  last_update_dt <- readLines(last_update_path) |> ymd_hm()

  # scrape the current update time from nasa psl
  "https://downloads.psl.noaa.gov/Datasets/noaa.oisst.v2.highres/" |>
    read_html() |>
    html_element("#indexlist") |>
    html_table() |>
    select(Name, `Last modified`) |>
    filter(Name == "sst.mon.mean.nc") |>
    pull(`Last modified`) |>
    ymd_hm() ->
  current_update_dt

  return(current_update_dt > last_update_dt)
}

#' Determine whether new monthly observations are available
#' 
#' @return A boolean. True if new obs are available for download, or if obs have
#' never been downloaded
check_remote_obs_stale <- function() {

  last_update_path <- here("data", "monthly", "last-monthly-update.txt")

  (!file.exists(last_update_path)) || current_obs_newer(last_update_path)
  
}

# we need a way to return this to the github action (eg. set-output)
check_remote_obs_stale()
