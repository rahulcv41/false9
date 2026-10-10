# Solar Designer (iOS)

SwiftUI app for designing rooftop solar plants end-to-end on an iPhone/iPad.

| Step | What it does |
|---|---|
| 1. Site & roof image | Satellite map (MapKit). Search an address, **paste `lat, lon` copied from Google Maps**, use GPS, pinch-zoom, confirm and capture a screenshot — pixel scale is calibrated automatically. You can also import a Google-Maps screenshot from Photos and calibrate by tapping two points of known length. |
| 2. Roof outline & obstacles | Draw the roof boundary, place water tanks / stair rooms / vents with heights. |
| 3. 360° / skyline survey | Import a 360° (equirectangular) video recorded on site or earlier and tap obstacle tops; or stand on the roof and mark them live with camera + compass + motion sensors. Builds a skyline (horizon) profile. |
| 4. Equipment | Panel, inverter, tilt/azimuth, set-backs, tariff, cost. |
| 5. 2D layout | Auto-places panels (set-back, obstacle clearance, row spacing for the winter solstice), strings them for the chosen inverter. |
| 6. Shade analysis | Sun-path simulation (12 representative days, 15-min steps) against skyline + rooftop obstacle shadows; per-panel shade loss, monthly kWh, shade heat-map, sun-path/skyline chart. |
| 7. Outputs | Project report (PDF), single-line diagram (PDF), 2D layout drawing (PDF), 3D rendered image, 3D fly-around video (MP4). |

## Build

Requires macOS + Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open SolarDesigner.xcodeproj
```

Set your signing team in Xcode, run on a device (camera, compass and motion sensors need real hardware). CI (`.github/workflows/ios.yml`) builds and runs unit tests on every push.

## Notes & limits

* Uses Apple MapKit satellite imagery (no API key). Google Maps tiles can't be embedded without a Google SDK/key and licence — paste Google coordinates or import a screenshot instead.
* iPhones can't record 360° video natively; use a 360 camera and import the equirectangular export.
* Yield = clear-sky model × clearness factor × performance ratio. Replace with PVGIS/Meteonorm data for bankable figures.
* Electrical sizing and the SLD are **indicative**; a licensed engineer must verify them.
