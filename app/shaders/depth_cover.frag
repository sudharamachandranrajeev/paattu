#version 460 core
// The cover in 3D (lib/src/ui/depth_cover.dart): the whole cover, each point
// moved by how near it is (the depth map, lib/src/depth.dart) as the cover
// leans, swells on the beat and, for a cover of layers rather than a
// subject, drifts.
//
// From "shared from here" to "shared to here" it is the same as the Omarchy
// app's (plugin/shaders/DepthCover.frag); tests/test_depth.py checks.

#include <flutter/runtime_effect.glsl>

uniform vec2 size;
uniform vec2 tilt;
uniform vec2 centre;
uniform float strength;
uniform float punch;
uniform float level;
uniform float clock;
uniform float flow;
uniform float corner;
uniform float side;
uniform sampler2D picture;
uniform sampler2D depthMap;

out vec4 fragColor;

// shared from here
// What stays put as the cover leans: nearer moves with it, further against it.
const float PIVOT = 0.35;

float nearAt(vec2 p) {
  return texture(depthMap, clamp(p, 0.0, 1.0)).r;
}

// How near, softened a little more: the picture flows round the subject's
// edge instead of stretching across it.
float softNear(vec2 p) {
  float e = 1.5 / 64.0;
  return 0.4 * nearAt(p) + 0.15 * (nearAt(p + vec2(e, 0.0)) + nearAt(p - vec2(e, 0.0)) +
                                   nearAt(p + vec2(0.0, e)) + nearAt(p - vec2(0.0, e)));
}

// The cover at uv (0 to 1 across and down), premultiplied. At strength 0 it
// is the plain cover; the effect comes in as strength goes to 1.
vec4 depthCover(vec2 uv) {
  float s = strength;
  // Seen a little nearer, so what moves always has picture to show.
  vec2 base = 0.5 + (uv - 0.5) / (1.0 + 0.06 * s);
  vec2 lean = tilt * 0.022 * s;
  float swell = (0.03 * punch + 0.01 * level) * s;
  float wave = 0.006 * flow * s;
  // The point shown here is the one that, moved, lands here: found by
  // stepping towards it (the depth map is soft, so a few steps do).
  vec2 p = base;
  for (int i = 0; i < 4; i++) {
    float d = softNear(p);
    float near = d - PIVOT;
    vec2 drift = vec2(sin(clock * 0.61 + d * 5.0 + p.y * 3.1), cos(clock * 0.47 + d * 4.3 + p.x * 2.7)) * (0.35 + d);
    p = base - lean * near - (base - centre) * (near * swell) - drift * wave;
  }
  p = clamp(p, 0.0, 1.0);
  vec3 colour = texture(picture, p).rgb;
  vec3 here = texture(depthMap, p).rgb;

  // The subject's shadow on what is behind it, falling away from the
  // light: a soft dimming, never a dark band.
  float shadow = texture(depthMap, clamp(p + lean * 0.8 - vec2(0.0, 0.01 * s), 0.0, 1.0)).g;
  colour *= 1.0 - 0.3 * shadow * (1.0 - here.b) * s;

  // Light from above on the left, swinging as the cover leans: the broad
  // slopes of what stands out that face it are a little brighter, those
  // turned away a little darker. It scales the picture's own colour, so no
  // pale rim is drawn round the subject.
  float e = 3.0 / 64.0;
  vec2 slope = vec2(softNear(p + vec2(e, 0.0)) - softNear(p - vec2(e, 0.0)),
                    softNear(p + vec2(0.0, e)) - softNear(p - vec2(0.0, e)));
  vec2 light = vec2(-0.6, -0.8) - tilt * 0.6;
  light /= max(0.001, length(light));
  colour *= 1.0 + clamp(-dot(slope, light) * 0.25, -0.1, 0.1) * (1.0 + 0.5 * punch) * s;

  // A slow sheen gliding over the nearer layers of a cover without a subject.
  float band = p.x * 0.6 + p.y * 0.8 - (mod(clock * 0.04, 1.8) - 0.4);
  colour += exp(-band * band * 30.0) * here.r * flow * 0.06 * s;

  // The rounded corners, smooth at the edge.
  vec2 q = abs(uv - 0.5) - 0.5 + corner;
  float outside = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
  float inside = clamp(0.5 - outside * side, 0.0, 1.0);
  return vec4(clamp(colour, 0.0, 1.0), 1.0) * inside;
}
// shared to here

void main() {
  fragColor = depthCover(FlutterFragCoord().xy / size);
}
