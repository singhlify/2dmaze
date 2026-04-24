#version 460 core

// Custom Flutter FragmentProgram shader.
//
// Purpose: evidence that Flutter supports the programmable pipeline
// (Aakash's goal.md Q5). This shader is authored in GLSL, compiled to
// SPIR-V by the Flutter build tool, and translated at runtime to the
// platform's shading language (HLSL on Windows via ANGLE/Impeller,
// Metal on macOS/iOS, GLSL ES on Android/Web).
//
// It paints an animated "plasma" — the kind of purely GPU-computed
// effect a simulator UI might use for heatmaps, overlays, or data
// visualization. Inputs:
//
//   uTime       (seconds)  — animation phase
//   uResolution (pixels)   — output size in physical pixels
//
// Outputs a single RGBA fragment.

#include <flutter/runtime_effect.glsl>

layout(location = 0) uniform float uTime;
layout(location = 1) uniform vec2  uResolution;

out vec4 fragColor;

void main() {
    vec2 pos = FlutterFragCoord() / uResolution;       // 0..1
    vec2 c   = pos * 2.0 - 1.0;                        // -1..1 centered
    c.x *= uResolution.x / uResolution.y;              // aspect correct

    // Classic plasma: sum of a few sines.
    float t = uTime;
    float v = 0.0;
    v += sin(c.x * 8.0 + t);
    v += sin(c.y * 8.0 + t * 1.3);
    v += sin((c.x + c.y) * 6.0 + t * 0.7);
    v += sin(length(c) * 10.0 - t * 1.7);
    v *= 0.25;                                         // keep in -1..1

    // Map to a palette — simple RGB gradient.
    vec3 col;
    col.r = 0.5 + 0.5 * sin(v * 3.14159 + 0.0);
    col.g = 0.5 + 0.5 * sin(v * 3.14159 + 2.094);
    col.b = 0.5 + 0.5 * sin(v * 3.14159 + 4.188);

    fragColor = vec4(col, 1.0);
}
