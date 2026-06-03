#version 100

precision mediump float;

// Input vertex attributes (from vertex shader)
varying vec2 fragTexCoord;
varying vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

uniform vec2 resolution;
uniform vec2 center;
uniform float time;

void main() {
  // Normalize coordinates
  //   vec2 uv = (fragTexCoord * 2.0 - 1.0);
  vec2 uv = fragTexCoord;

  // Distance from center
  float dist = length(uv);

  // Create glow: more transparent further out
  //   float alpha = smoothstep(0.8, 0.1, dist);

  // Add pulsating effect
  float pulse = 0.8 + 0.2 * sin((time + dist) * 5.0);
  float alpha = 0.8 + 0.2 * sin((time + dist) * 3.0);

  // Final color (blue-ish energy ball)
  vec3 color = fragColor.rgb * pulse;

  gl_FragColor = vec4(color, alpha);
}
