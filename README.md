# vex-teapot

A 3D Utah teapot viewer for the [VEX fantasy console](https://github.com/peterhellberg/vex),
written in Zig. Parses an OBJ file at boot time and renders it with flat shading
and palette-based lighting.

## Controls

| Input | Action |
|-------|--------|
| **Mouse drag** | Rotate the teapot |
| **Arrow keys** | Move the camera (forward/backward, strafe left/right) |
| **Z** | Cycle the main light through three fixed positions |
| **X** | Toggle between blue and green palettes |

## Lighting

Two point lights illuminate the teapot. The main light position is controlled
with **Z**; the fill light remains fixed on the opposite side.

- **Ambient**: 0.15 base brightness
- **Main light** (yellow indicator): up to 60% contribution
- **Fill light**: up to 40% contribution

Only surfaces facing a light receive its contribution.

## Play online

<https://play.c7.se/vex/vex-teapot/>

## Build

```sh
zig build       # build the cart (zig-out/bin/vex-teapot.wasm)
zig build run   # build + run in vex
zig build web   # build + serve via vex-web
zig build bundle  # build + export static bundle (bundle/vex-teapot/)
```

Requires [Zig 0.17](https://ziglang.org/download/) and the `vex` and `vex-web` CLI tools.
