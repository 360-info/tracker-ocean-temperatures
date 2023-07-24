
library(stringr)
library(rvest)
library(dplyr)
library(lubridate)
library(here)

#' Extract and validate arg values using a regex pattern
extract_arg <- function(args, pattern) {
  str_extract(pattern, group = 1) |>
  na.omit()
}

#' Returns a string recording the time of the last monthly update
get_last_monthly_update_dt <- function() {
  here("data", "monthly", "last-monthly-update.txt") |>
    readLines(last_update_path) |>
    ymd_hm()
}

#' Writes the supplied date-time string out to record the last monthly update
set_last_monthly_update_dt <- function(dt) {
  dt |> writeLines(here("data", "monthly", "last-monthly-update.txt"))
}

# scrape the current monthly update date-time from nasa psl
get_current_monthly_dt <- function() {
  "https://downloads.psl.noaa.gov/Datasets/noaa.oisst.v2.highres/" |>
    read_html() |>
    html_element("#indexlist") |>
    html_table() |>
    select(Name, `Last modified`) |>
    filter(Name == "sst.mon.mean.nc") |>
    pull(`Last modified`) |>
    ymd_hm()
}
