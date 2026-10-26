#version 440
// The cover in 3D (DepthCover.qml): the whole cover, each point moved by how
// near it is (`paattu depth`'s depth map, paattu/depth.py) as the cover
// leans, swells on the beat and, for a cover of layers rather than a
// subject, drifts. Built into DepthCover.frag.qsb with Qt's shader baker:
//
//     /usr/lib/qt6/bin/qsb --qt6 -o plugin/DepthCover.frag.qsb plugin/shaders/DepthCover.frag
//
// From "shared from here" to "shared to here" it is the same as the Flutter
// app's (app/shaders/depth_cover.frag); tests/test_depth.py checks.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 tilt;
  vec2 centre;
  float strength;
  float punch;
  float level;
  float clock;
  float flow;
  float corner;
  float side;
};

layout(binding = 1) uniform sampler2D picture;
layout(binding = 2) uniform sampler2D depthMap;

// shared from here
// What stays put as the cover leans: nearer moves with it, further against it.
const float PIVOT = 0.35;

float nearAt(vec2 p) {
  return texture(depthMap, clamp(p, 0.0, 1.0)).r;
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
    float d = nearAt(p);
    float near = d - PIVOT;
    vec2 drift = vec2(sin(clock * 0.61 + d * 5.0 + p.y * 3.1), cos(clock * 0.47 + d * 4.3 + p.x * 2.7)) * (0.35 + d);
    p = base - lean * near - (base - centre) * (near * swell) - drift * wave;
  }
  p = clamp(p, 0.0, 1.0);
  vec3 colour = texture(picture, p).rgb;
  vec3 here = texture(depthMap, p).rgb;

  // The subject's shadow on what is behind it, falling away from the light.
  float shadow = texture(depthMap, clamp(p + lean * 0.8 - vec2(0.0, 0.015 * s), 0.0, 1.0)).g;
  colour *= 1.0 - 0.8 * shadow * (1.0 - here.b) * s;

  // Light from above on the left, swinging as the cover leans: the slopes
  // of what stands out that face it catch it.
  float e = 1.5 / 64.0;
  vec2 slope = vec2(nearAt(p + vec2(e, 0.0)) - nearAt(p - vec2(e, 0.0)),
                    nearAt(p + vec2(0.0, e)) - nearAt(p - vec2(0.0, e)));
  vec2 light = vec2(-0.6, -0.8) - tilt * 0.6;
  light /= max(0.001, length(light));
  colour += -dot(slope, light) * 0.45 * (1.0 + punch) * s;

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
  fragColor = depthCover(qt_TexCoord0) * qt_Opacity;
}
