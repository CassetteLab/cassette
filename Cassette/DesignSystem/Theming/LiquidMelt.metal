// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// SwiftUI `.distortionEffect` shader: a liquid ripple concentrated near the BOTTOM edge of a view, used to
/// melt an album cover into the body in soft, organic, animated waves.
///
/// - `position` : the destination pixel (view-local coordinates), supplied by SwiftUI.
/// - `bounds`   : the view's bounding rect (.boundingRect) — `bounds.w` is the height.
/// - `time`     : animation phase (seconds, wrapped) driving the wave motion.
/// - `amplitude`: maximum pixel displacement at the very bottom.
/// - `band`     : height (in points, measured up from the bottom) over which the ripple ramps in.
[[ stitchable ]] float2 liquidBottom(float2 position, float4 bounds, float time, float amplitude, float band) {
    float height = bounds.w;
    float fromBottom = height - position.y;
    // Ramp the effect from 0 (above the band) to 1 (at the very bottom); squared for a soft ease-in.
    float ramp = clamp(1.0 - fromBottom / band, 0.0, 1.0);
    float falloff = ramp * ramp;
    // Sum of sines at different frequencies/phases → organic, non-repeating motion.
    float wave = sin(position.x / 48.0 + time) * 0.55
               + sin(position.x / 29.0 - time * 1.3) * 0.30
               + sin(position.x / 17.0 + time * 0.8) * 0.15;
    float dy = wave * amplitude * falloff;
    float dx = sin(position.y / 26.0 + time * 0.7) * amplitude * 0.35 * falloff;
    return float2(position.x + dx, position.y + dy);
}
