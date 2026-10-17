# Validation status and restart plan

**Experimental; needs more work. Development is on hold because suitable reference-measurement equipment is unavailable.**

## Checked so far

- Release builds installed and launched on a physical iPhone 14 Pro Max running iOS 26.6.
- Three-photo capture, point selection, scale calibration, keyboard dismissal, image fitting, and result layouts exercised on-device.
- Metal processing and Vision registration exercised with synthetic and real captures.
- 22 numerical checks covering fractional-pixel openings, intensity polarity, unequal brightness, approximate taps, tracking, manual estimates, obstructed cutouts, and invalid-input rejection.

These checks establish implementation behavior, not dimensional accuracy, field repeatability, a minimum opening width, or validated uncertainty.

## Recorded real experiment

A three-photo capture showed a reflective metal cutout with an internal tab. The original opening model rejected all nine sections. Full-cutout mode produced a first-photo estimate of approximately **11.88 mm**, with a **0.64 mm range across nearby sections**. Two photos failed local tracking. No independent reference measurement of this cutout is available.

The entered reference was 20 mm; selected tape positions appeared consistent with metric 5-to-7 cm marks. A tape cannot verify submillimetre accuracy. Rims, bevels, and reflections introduce boundary ambiguity. The 0.64 mm range is not an error bound or confidence interval. The screenshot documents an experiment, not a certified result. Original camera bundles and the source paper PDF are not distributed here.

## Before making accuracy claims

1. Define the measurand: opening width at a prescribed section, full contour width, or another quantity. Height/flush needs a separate method.
2. Obtain reference-measured features with documented uncertainty substantially below the app's proposed error limit. Display resolution alone does not establish instrument accuracy.
3. Control support, lighting, viewing angle, and reference placement. Characterize perspective and lens distortion.
4. Test multiple widths and materials, including reflective, bevelled, textured, and obstructed features.
5. Reposition the phone and reselect points between trials. Include multiple operators and sessions, with held-out physical samples.
6. Report signed bias, absolute errors, 95th-percentile absolute error, repeatability, and failure rate. Include rejected captures in the results.
7. Validate uncertainty reporting and tolerance decisions independently, retaining original evidence and calibration metadata.

## Resume decision

Continue if useful accuracy is possible with a practical employee workflow. Otherwise evaluate a positioning fixture, calibrated reference target, lighting accessory, or optical attachment before expanding the product. The current implementation is a feasibility prototype, not a completed reproduction of the paper's calibrated multi-view regression system.
