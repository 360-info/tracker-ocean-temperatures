
library(stringr)
library(readr)
library(rvest)
library(dplyr)
library(lubridate)
library(glue)
library(ClimateOperators)
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


#' Return the path of a mask for a single region defined by a lon-lat box.
#' 
#' Regions used here are largely based on ENSO and IOD monitoring regions:
#' http://www.bom.gov.au/climate/enso/indices.shtml
#' 
#' @param id The id for the region to be used as the netcdf variable name
#' @param lon_min Longitude to start box from
#' @param lon_max Longitude to end box at
#' @param lat_min Latitude to start box from
#' @param lat_max Latitude to end box at
#' @param mask_path The path to the mask file
#' @return Path to the created NetCDF
make_lonlat_box_mask <- function(id, lon_min, lon_max, lat_min, lat_max,
  mask_path) {
  focusregion_path <- tempfile(pattern = "focusregion-", fileext = ".nc")
  cdo(
    "-L",
    csl("chname", "seamask", id),
    csl(glue("-sellonlatbox,{lon_min},{lon_max},{lat_min},{lat_max}")),
    csl("-select", "name=seamask"),
    mask_path,
    focusregion_path)
  return(focusregion_path)
}

#' Return the path of a mask file remapped to the grid of iven observations
#' 
#' Our masks are on a 1° grid, but our obs are 0.25°x0.25°. This function
#' regrids the mask file and returns the (temporary) path to the new file.
#'
#' @param sst_path The path to an nc file with observed sea surface temps
get_regridded_mask_path <- function(sst_path) {
  mask_path <- here("data", "RECCAP2_region_masks_all_v20221025.nc")
  regridded_mask_path <- tempfile(pattern = "regrid-masks-", fileext = ".nc")
  
  # add other regions 
  # regions <- read_csv(here("data", "regions.csv"))
  # regions %>%
  #   dplyr::select(-name) %>%
  #   mutate(mask_path =
  #     pmap_chr(., make_lonlat_box_mask, mask_path = mask_path)) ->
  # region_paths

  # merged_masks_path <- tempfile(pattern = "allmasks-", fileext = ".nc")

  # in theory i should be able to merge all of them in one step, but
  # cdo is throwing an error unless i do them a few at a time
  # i'll just generate a new temp file for each pair
  # (WIP - this isn't working either!)

  # cdo("merge", region_paths$mask_path[1], mask_path, merged_masks_path)

  # for (i in seq_along(region_paths$mask_path) |> tail(-1)) {
  #   masks_cumulative <- tempfile(pattern = "allmasks-cum-", fileext = ".nc")

  #   cdo(
  #     "cat",
  #     region_paths$mask_path[i],
  #     merged_masks_path,
  #     masks_cumulative)
    
  #   unlink(merged_masks_path)
  #   merged_masks_path <- masks_cumulative
  # }

  # regrid to the 0.25°x0.25° grid
  cdo(csl("remapnn", sst_path), mask_path, regridded_mask_path)

  return(regridded_mask_path)
}

#' Returns a time series of field-averaged SSTs for the specified ocean region
#' 
#' Masking procedure based on https://code.mpimet.mpg.de/boards/53/topics/10933
#' 
#' @param ocean One of the oceans in the masks file. Includes arctic, atlantic,
#'   indian, pacific, southern.
#' @param regions A string specifying one or more regions within the ocean
#'   mask, separated by commas. Eg. "1,2,3"
#' @param sst_path The path to the downloaded sea surface temperatures (.nc)
#' @param mask_path The path to the mask file (.nc)
extract_basin_timeseries <- function(ocean, regions, sst_path, mask_path) {

  region <- str_split(regions, ",\\s?") |> unlist()
  region_expression <- glue("({ocean}=={region})") |> paste(collapse = " || ")

  # join the mask regions we want into a single, binary mask (1 or NaN)
  region_mask_path <- tempfile(pattern = "regionmask-", fileext = ".nc")
  cdo(
    csl("-expr", glue("'sst = ({region_expression}) ? 1.0 : {ocean}/0'")),
    mask_path,
    region_mask_path)

  # apply the mask to the sst obs
  region_monthly_path <- tempfile(pattern = "maskedssts-", fileext = ".nc")
  cdo("-mul", region_mask_path, sst_path, region_monthly_path)

  # finally, calculate and output the time series
  region_ts_path <- tempfile(pattern = "timeseries-", fileext = ".nc")
  cdo("fldmean", region_monthly_path, region_ts_path)
  series <- cdo(csl("outputtab", "date", "value"), region_ts_path)

  # cleanup temp files (we're doing this a few times, so best to save on space)
  unlink(region_mask_path)
  unlink(region_monthly_path)
  unlink(region_ts_path)

  # tidy the time series up and return
  series |>
    str_trim() |>
    tibble(data = _) |>
    slice(-1) |>
    tidyr::separate(data, into = c("date", "value"), sep = "\\s+",
      convert = TRUE)
}