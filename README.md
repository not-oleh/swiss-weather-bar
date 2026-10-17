# Swiss Weather Bar

A small macOS menu bar app that shows the local weather forecast for any Swiss postcode.

- Current temperature and conditions in the menu bar
- Wind, gusts, sunrise and sunset
- The next 24 hours in 3-hour steps, with the chance of rain
- A 7-day forecast with min/max temperature and rain range
- Search by place name or postcode, or follow your current location (on by default)
- Recent locations, Open at Login

Free and open source. No account, no tracking, no ads.

## Data source

**Source: MeteoSwiss.** Forecasts come from the
[MeteoSwiss Open Government Data](https://opendatadocs.meteoswiss.ch/e-forecast-data/e4-local-forecast-data)
local forecast dataset (`ogd-local-forecasting`), published on the Swiss federal geodata
infrastructure (data.geo.admin.ch) under the
[Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/) licence and the
[MeteoSwiss Open Data terms of use](https://opendatadocs.meteoswiss.ch/general/terms-of-use).

`SwissWeatherBar/places.tsv` is derived from the same dataset's point metadata
(`ogd-local-forecasting_meta_point.csv`): postcode points with name, altitude and coordinates.

The app downloads only the rows it needs, using small HTTP range requests, and only when a
new forecast run has been published (hourly). It does not fetch the same content repeatedly.

The weather symbols are emoji and the condition texts are written for this app. MeteoSwiss
graphics are not used.

**This is an independent project. It is not affiliated with, endorsed by or supported by
MeteoSwiss or the Swiss Confederation.** Forecasts are provided without any guarantee of
accuracy or availability. For official forecasts and weather warnings, see
[meteoswiss.admin.ch](https://www.meteoswiss.admin.ch).

## Privacy

- Your location is used only on your Mac, to pick the nearest postcode, and is never sent anywhere.
- The only network requests go to `data.geo.admin.ch`.
- Settings (chosen place, recent places) are stored in your user defaults.

## Install

Requires macOS 13 or later and the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/olehhnat/swiss-weather-bar.git
cd swiss-weather-bar
./SwissWeatherBar/build.sh
mv "SwissWeatherBar/Swiss Weather Bar.app" /Applications/
open "/Applications/Swiss Weather Bar.app"
```

On first launch macOS asks for location access, which the app uses to pick your nearest
postcode. If you decline, choose a place with **Change Location…** instead.

## Licence

The code is released under the [MIT Licence](LICENSE). See [NOTICE](NOTICE) for the data terms. Forecast data and `places.tsv`
remain © MeteoSwiss, used under CC BY 4.0.
