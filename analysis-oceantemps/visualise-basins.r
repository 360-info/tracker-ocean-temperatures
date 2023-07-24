library(tidyverse)

masks <- read_csv(here("data", "basinmask_04_surface.msk.gz"))

read_csv(here("data", "basins.csv")) |>
  filter(std_depth_level == 1) |>
  select(code, name) ->
mask_index

basin_colours <-
  c("#000000","#004949","#009292","#ff6db6","#ffb6db",
  "#490092","#006ddb","#b66dff","#6db6ff","#b6dbff",
  "#920000","#924900","#db6d00","#24ff24","#ffff6d")
 
masks |>
  left_join(mask_index, c("Basin_0m" = "code"), keep = TRUE) |>
  mutate(code_and_name = paste0(name, " (", code, ")")) |>
  ggplot() +
    aes(x = Longitude, y = Latitude, fill = code_and_name) +
    geom_raster(alpha = 0.8) +
    scale_fill_manual(values = basin_colours) +
    scale_x_continuous(
      expand = expansion(),
      labels = scales::label_number(suffix = "°")) +
    scale_y_continuous(
      expand = expansion(),
      labels = scales::label_number(suffix = "°")) +
  theme_minimal() +
  labs(x = NULL, y = NULL,
    fill = "Basin",
    title = "Surface basins") ->
basin_plot

ggsave(here("data", "basins.png"), basin_plot, bg = "white")
