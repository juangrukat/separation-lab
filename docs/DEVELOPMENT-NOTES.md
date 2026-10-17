# Separation Lab — on-device feasibility prototype

Approved workflow: select boundaries, calibrate against tape markings, receive capture guidance, capture multiple frames, and review separation plus variation. This prototype measures visible in-plane separation only. Surface offset remains outside this experiment.

## Use
1. Place the tape alongside the opening, in the same plane. Use diffuse lighting and support the phone. Both edges and reference markings must be visible.
2. Capture a three-photo sequence. Start with standard detail. High detail requests the largest supported main-camera photo dimensions; it is slower and uses more memory.
3. On the first photo, pinch to zoom and tap two tape markings. Enter their actual separation in millimetres (for example 10, not the number of ticks).
4. Tap each material boundary along the direction you want to measure. Use at least a few image pixels of separation initially. Keep the tape and feature near the image centre.
5. Analyze. The app initializes the selected edges using gradient-profile peaks, then jointly fits two blurred boundaries against native pixel samples. It measures nine nearby cross-sections and attempts to track reference and edge locations in subsequent photos.
6. Save the evidence bundle to Files using the share sheet.

### Build 2: boundary correction
The assisted fitter now allows different brightness on the two material surfaces and searches up to 32 source-image pixels around approximate taps, depending on the selected width. Detected positions are shown on the photograph. Tap an R1/R2/E1/E2 chip to replace only that point; tap the chip again to cancel editing. Edge chips show enlarged local crops. Reference calibration is preserved when adjusting edges.

If refinement cannot resolve the feature, explicitly select **Point-to-point** for a manual pixel-distance estimate. This does not verify edges or estimate subpixel boundary positions, and it is labelled separately in the UI and exports. The app never silently converts a failed assisted measurement into a manual one.

Three-photo assisted captures now use Vision whole-image translation registration before local feature tracking. Focus, exposure, and white balance are held fixed during the sequence. Scale/rotation/local-correlation checks remain in place, so some sequences may still produce a single accepted photo. The latest capture and selection are retained locally in Documents/LatestCapture for diagnosis; a new capture replaces them. Saving is available even when edge fitting fails.

Nineteen numerical checks pass, including new regressions for unequal surface brightness, approximate tap placement, explicit manual measurement, and globally registered motion beyond the previous local search window. The result layout and Metal → Vision → assisted-fit path were exercised on the physical phone with an explicitly synthetic three-image fixture. This verifies implementation behavior, not physical measurement accuracy.

### Build 3: reference keyboard and photo layout
Reference distance now uses a native decimal text field with a persistent Done accessory above the keypad. Finishing editing dismisses the keyboard and resets the photo to fit. A separate Fit photo button is always available. The image's fit geometry is now updated during the scroll view's actual layout rather than only during SwiftUI updates, including when the keyboard changes the available height. Selected points remain in original image coordinates. Reference input is remembered between launches. Developer UI fixtures no longer replace the latest real capture.

Verified on the physical iPhone with a timed synthetic UI exercise: the decimal keypad and Done accessory appear, the Done action dismisses the keypad, the photo expands back to its available fit size, and all four markers remain selected. The most recent real capture can be reopened using the developer launch argument `--restore-latest` without substituting fixture images.

### Build 4: full cutout width
For an opening partly occupied by a tab, enable **Full cutout · ignore interior tab** under Assisted edges. This independently refines each selected outer contour using locally smoothed intensity profiles, avoiding the opening fitter's uniform-interior assumption. Verify that the orange markers indicate the intended rim, rather than a bevel, highlight, or internal tab. Nearby-section range is displayed separately from between-photo range; neither is a validated uncertainty interval.

The supplied failed export was replayed through the actual iPhone's Metal pipeline. Original assisted opening fit reproduced 0/9 accepted sections. Full-cutout mode produced approximately 11.88 mm from the first photo, with a 0.64 mm range across nearby sections; the remaining two photos still failed local tracking. This is a provisional contour estimate, not an accuracy claim. The retained 20 mm reference corresponds visually to the metric 5-to-7 cm markings. Twenty-two numerical checks pass, including obstructed cutouts and blank-image rejection. Developer-only `--replay-inspection` reads copied originals and selection from Documents/ReplayInspection without replacing the latest real capture.

## Interpretation
The estimate assumes both boundaries and tape are coplanar and the camera is approximately perpendicular. Two reference points provide a local scalar scale, not full perspective or lens-distortion correction. Results are experimental and are not tolerance decisions. Variation across sections includes real edge roughness. Agreement across photos is not absolute accuracy. Unresolved edges and failed frame tracking are rejected.

## Processing
AVFoundation uses the physical main camera, with automatic camera switching avoided. Metal computes luminance from original-resolution photos when available; CPU fallback is explicit. CPU processing handles local template tracking, subpixel fitting, calibration, and robust statistics. Neural inference is deliberately absent until a trained boundary model is available. LiDAR is not used as a dimensional reference. A lightweight preview provides brightness, focus, and stability guidance. Capture orientation is fixed to portrait.

## Validation plan
Build and install on the connected iPhone 14 Pro Max. Exercise algorithmic fixtures for fractional-pixel edges, scale, rejection of ambiguous boundaries, and tracking. Smoke-test app launch and permission handling. Physical validation requires reference-measured openings, multiple capture distances, repeated placements, and representative materials. No minimum width or accuracy specification is claimed.

## Build
Run `xcodegen generate` in this folder. Open SeparationLab.xcodeproj, select a development team and physical iPhone, and run. Camera evidence remains local unless explicitly exported. Export includes original photographs and measurement metadata.

## Initial verification, 17 October 2026
Release build signed and installed on the connected iPhone 14 Pro Max running iOS 26.6. Launch and live camera preview verified by device screenshots after the user granted camera access. The main lens reports a minimum focus distance of 200 mm. Fourteen synthetic checks passed: fractional-pixel blurred openings of both polarities, calibration scaling, blank/unresolved/invalid-reference rejection, median statistics, translated-frame tracking, and full-resolution tracking refinement. Physical dimensional accuracy has not yet been verified. Synthetic tests are implementation checks, not metrological evidence.

To repeat the numerical checks on macOS, compile `SeparationLab/Measurement.swift`, `SeparationLab/Registration.swift`, and `Tests/MeasurementChecks.swift` together using `swiftc -O`, then run the resulting executable. A developer-only `--ui-fixture` launch argument displays and analyzes an explicitly synthetic image for layout/processing checks; it is not a physical camera measurement.
