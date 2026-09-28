const vex = @import("vex");

const obj = @embedFile("teapot.obj");

const MAX_V: usize = 530;
const MAX_F: usize = 1024;
/// Depth buckets for the painter's-algorithm sort. O(n) instead of O(n^2).
const BUCKETS: usize = 1024;
/// Faces closer than this to the eye are dropped (the camera clamp keeps the
/// camera outside the teapot, so this is just insurance).
const NEAR: f32 = 20;
/// The camera may not get closer than this to the model center. Keeps every
/// vertex in front of the near plane, so no geometry ever needs clipping.
const CAM_MIN_DIST: f32 = 90;
/// Overflow guard for the int conversion only. Far wider than any reachable
/// projection, so it never clips real geometry.
const COORD_LIMIT: f32 = 100000;

var verts: [MAX_V]Vec3 = undefined;
var norms: [MAX_V]Vec3 = undefined;
var tris: [MAX_F][3]u16 = undefined;
var vert_cnt: u32 = 0;
var norm_cnt: u32 = 0;
var face_cnt: u32 = 0;
var center: Vec3 = .{ .x = 0, .y = 0, .z = 0 };

/// Per-face centroid in model space (center subtracted), precomputed at load
/// so lighting never has to average the transformed corners again.
var fcent: [MAX_F]Vec3 = undefined;
/// Rotated vertex positions, reused every frame.
var xf: [MAX_V]Vec3 = undefined;

const TriCmd = struct {
    z: f32,
    shade: i32,
    sx0: i32,
    sy0: i32,
    sx1: i32,
    sy1: i32,
    sx2: i32,
    sy2: i32,
};

var cmds: [MAX_F]TriCmd = undefined;
var sorted: [MAX_F]TriCmd = undefined;
var bucket_of: [MAX_F]u16 = undefined;
var bucket_start: [BUCKETS]u32 = undefined;

fn skipSpc(line: []const u8, idx: *u32) void {
    while (idx.* < line.len and (line[idx.*] == ' ' or line[idx.*] == '\t')) idx.* += 1;
}

fn parseF32(line: []const u8, idx: *u32) f32 {
    skipSpc(line, idx);
    var neg: f32 = 1;
    if (idx.* < line.len and line[idx.*] == '-') {
        neg = -1;
        idx.* += 1;
    } else if (idx.* < line.len and line[idx.*] == '+') idx.* += 1;
    var val: f32 = 0;
    var frac: f32 = 0;
    var div: f32 = 1;
    var is_frac = false;
    while (idx.* < line.len) {
        const c = line[idx.*];
        if (c >= '0' and c <= '9') {
            if (!is_frac) {
                val = val * 10 + @as(f32, @floatFromInt(c - '0'));
            } else {
                div *= 10;
                frac += @as(f32, @floatFromInt(c - '0')) / div;
            }
        } else if (c == '.') {
            is_frac = true;
        } else if (c == 'e' or c == 'E') {
            idx.* += 1;
            var exp_neg: f32 = 1;
            if (idx.* < line.len and line[idx.*] == '-') {
                exp_neg = -1;
                idx.* += 1;
            } else if (idx.* < line.len and line[idx.*] == '+') idx.* += 1;
            var exp_val: u32 = 0;
            while (idx.* < line.len) {
                const ec = line[idx.*];
                if (ec >= '0' and ec <= '9') {
                    exp_val = exp_val * 10 + (ec - '0');
                    idx.* += 1;
                } else break;
            }
            var exp_mul: f32 = 1;
            var ei: u32 = 0;
            while (ei < exp_val) {
                exp_mul *= 10;
                ei += 1;
            }
            if (exp_neg < 0) {
                val = (val + frac) / exp_mul;
                frac = 0;
            } else {
                val = (val + frac) * exp_mul;
                frac = 0;
            }
            break;
        } else break;
        idx.* += 1;
    }
    return neg * (val + frac);
}

fn parseU32(line: []const u8, idx: *u32) u32 {
    skipSpc(line, idx);
    var val: u32 = 0;
    while (idx.* < line.len) {
        const c = line[idx.*];
        if (c >= '0' and c <= '9') {
            val = val * 10 + (c - '0');
            idx.* += 1;
        } else break;
    }
    return val;
}

fn setPal(idx: u32) void {
    if (idx == 0) {
        vex.pal(0x0, 0x060810);
        vex.pal(0x1, 0xf0c050);
        vex.pal(0x2, 0x0c0e1a);
        vex.pal(0x3, 0x121c2e);
        vex.pal(0x4, 0x182c44);
        vex.pal(0x5, 0x203e5c);
        vex.pal(0x6, 0x285076);
        vex.pal(0x7, 0x326492);
        vex.pal(0x8, 0x3c7aae);
        vex.pal(0x9, 0x4890c8);
        vex.pal(0xA, 0x52a4e0);
        vex.pal(0xB, 0x5cb6f0);
        vex.pal(0xC, 0x66c6fc);
        vex.pal(0xD, 0x70d4ff);
        vex.pal(0xE, 0x78e0ff);
        vex.pal(0xF, 0x80eaff);
    } else {
        vex.pal(0x0, 0x060810);
        vex.pal(0x1, 0xf0c050);
        vex.pal(0x2, 0x0a180c);
        vex.pal(0x3, 0x0f2414);
        vex.pal(0x4, 0x14321e);
        vex.pal(0x5, 0x1a422a);
        vex.pal(0x6, 0x225438);
        vex.pal(0x7, 0x2a6848);
        vex.pal(0x8, 0x347e5a);
        vex.pal(0x9, 0x3e966e);
        vex.pal(0xA, 0x4aae82);
        vex.pal(0xB, 0x56c496);
        vex.pal(0xC, 0x62d8aa);
        vex.pal(0xD, 0x6ceabc);
        vex.pal(0xE, 0x76f8cc);
        vex.pal(0xF, 0x80ffda);
    }
}

fn loadTeapot() void {
    var vi: u32 = 0;
    var ni: u32 = 0;
    var fi: u32 = 0;
    var i: u32 = 0;
    while (i < obj.len) {
        const ls = i;
        while (i < obj.len and obj[i] != '\n') i += 1;
        const line = obj[ls..i];
        if (i < obj.len) i += 1;
        if (line.len == 0 or line[0] == '#') continue;
        if (line.len >= 2 and line[0] == 'v' and line[1] == ' ') {
            var idx: u32 = 2;
            const x = parseF32(line, &idx);
            const y = parseF32(line, &idx);
            const z = parseF32(line, &idx);
            verts[vi] = .{ .x = x, .y = y, .z = z };
            vi += 1;
        } else if (line.len >= 3 and line[0] == 'v' and line[1] == 'n') {
            var idx: u32 = 3;
            const x = parseF32(line, &idx);
            const y = parseF32(line, &idx);
            const z = parseF32(line, &idx);
            norms[ni] = .{ .x = x, .y = y, .z = z };
            ni += 1;
        } else if (line.len >= 2 and line[0] == 'f' and line[1] == ' ') {
            var idx: u32 = 2;
            const a = parseU32(line, &idx);
            const b = parseU32(line, &idx);
            const c = parseU32(line, &idx);
            tris[fi] = .{ @intCast(a - 1), @intCast(b - 1), @intCast(c - 1) };
            fi += 1;
        }
    }
    vert_cnt = vi;
    norm_cnt = ni;
    face_cnt = fi;

    var mn: Vec3 = .{ .x = 1e9, .y = 1e9, .z = 1e9 };
    var mx: Vec3 = .{ .x = -1e9, .y = -1e9, .z = -1e9 };
    for (verts[0..vi]) |vv| {
        if (vv.x < mn.x) mn.x = vv.x;
        if (vv.y < mn.y) mn.y = vv.y;
        if (vv.z < mn.z) mn.z = vv.z;
        if (vv.x > mx.x) mx.x = vv.x;
        if (vv.y > mx.y) mx.y = vv.y;
        if (vv.z > mx.z) mx.z = vv.z;
    }
    center = Vec3{
        .x = (mn.x + mx.x) / 2,
        .y = (mn.y + mx.y) / 2,
        .z = (mn.z + mx.z) / 2,
    };

    // Face centroids in model space, so lighting never has to average the
    // transformed corners again.
    for (tris[0..fi], 0..) |f, k| {
        fcent[k] = sub(avg3(verts[f[0]], verts[f[1]], verts[f[2]]), center);
    }
}

export fn boot() void {
    vex.title("vex-teapot");
    setPal(0);
    loadTeapot();
}

const light_presets = [3]Vec3{
    .{ .x = 100, .y = 120, .z = 80 },
    .{ .x = -120, .y = 50, .z = -80 },
    .{ .x = 0, .y = 150, .z = 0 },
};
var light_pos = light_presets[2];
var light_pos_idx: u32 = 2;
const light2 = Vec3{
    .x = -120,
    .y = 50,
    .z = -80,
};
var pal_idx: u32 = 0;
var cam_pos: Vec3 = .{
    .x = 0,
    .y = 0,
    .z = -300,
};
var rot_x: f32 = -0.35;
var rot_y: f32 = 0.5;
var target_x: f32 = -0.35;
var target_y: f32 = 0.5;
var pmx: i32 = 160;
var pmy: i32 = 90;
var first_frame = true;

export fn update() void {
    vex.cls(0);

    const mx = vex.mx();
    const my = vex.my();
    if (first_frame) {
        pmx = mx;
        pmy = my;
        first_frame = false;
    }
    if (mx != pmx or my != pmy) {
        target_y = (@as(f32, @floatFromInt(mx)) / 320.0 - 0.5) * 6.2832;
        target_x = (@as(f32, @floatFromInt(my)) / 180.0 - 0.5) * 3.1416;
        pmx = mx;
        pmy = my;
    }
    rot_x += (target_x - rot_x) * 0.12;
    rot_y += (target_y - rot_y) * 0.12;
    if (mx == pmx and my == pmy) target_y += 0.003;

    const spd: f32 = 2;
    if (vex.down(vex.LEFT)) cam_pos.x -= spd;
    if (vex.down(vex.RIGHT)) cam_pos.x += spd;
    if (vex.down(vex.UP)) cam_pos.z += spd;
    if (vex.down(vex.DOWN)) cam_pos.z -= spd;

    if (vex.pressed(vex.X)) {
        pal_idx ^= 1;
        setPal(pal_idx);
    }
    if (vex.pressed(vex.Z)) {
        light_pos_idx = (light_pos_idx + 1) % 3;
        light_pos = light_presets[light_pos_idx];
    }

    // Keep the camera outside the model so no vertex ever crosses the near
    // plane -- a straddling face would project to a full-screen triangle.
    const cv = sub(cam_pos, center);
    const cvd = len(cv);
    if (cvd < CAM_MIN_DIST) {
        const k = if (cvd > 0.001) CAM_MIN_DIST / cvd else 0;
        cam_pos = .{
            .x = center.x + cv.x * k,
            .y = center.y + cv.y * k,
            .z = center.z + cv.z * k,
        };
    }

    const focal: f32 = 100;
    const fscale: f32 = 4;
    const cx: f32 = 160;
    const cy: f32 = 90;
    const proj = focal * fscale;

    // One sin/cos pair per frame instead of four per vertex. Only positions
    // get rotated: lighting happens in model space (see below), so the
    // normals can be used straight out of the OBJ.
    const cy1 = @cos(rot_y);
    const sy1 = @sin(rot_y);
    const cx1 = @cos(rot_x);
    const sx1 = @sin(rot_x);

    for (verts[0..vert_cnt], 0..) |vp, i| {
        var v = sub(vp, center);
        v = rotateY(v, cy1, sy1);
        v = rotateX(v, cx1, sx1);
        xf[i] = v;
    }

    // Lighting runs in model space: the un-rotated vertex normals, the
    // precomputed face centroids and the lights pulled back through the
    // inverse of the position transform (positions are rotated rotY-then-
    // rotX, so the inverse is rotXinv-then-rotYinv). Nothing here depends on
    // the light being a point per frame, so it all collapses to two vectors.
    const l1m = rotateYinv(rotateXinv(light_pos, cx1, sx1), cy1, sy1);
    const l2m = rotateYinv(rotateXinv(light2, cx1, sx1), cy1, sy1);

    const lv = sub(light_pos, cam_pos);
    const wire = vex.mdown(vex.MOUSE_LEFT);

    var cmd_cnt: u32 = 0;
    var zmin: f32 = 0;
    var zmax: f32 = 0;
    const last_n: u32 = norm_cnt - 1;

    for (tris[0..face_cnt], 0..) |f, fi| {
        const v0 = xf[f[0]];
        const v1 = xf[f[1]];
        const v2 = xf[f[2]];

        const p0 = sub(v0, cam_pos);
        const p1 = sub(v1, cam_pos);
        const p2 = sub(v2, cam_pos);
        if (p0.z < NEAR or p1.z < NEAR or p2.z < NEAR) continue;

        // Model-space normals: lighting is done entirely in model space, so
        // these never need rotating.
        const n0 = norms[@min(f[0], last_n)];
        const n1 = norms[@min(f[1], last_n)];
        const n2 = norms[@min(f[2], last_n)];

        const r0 = proj / p0.z;
        const r1 = proj / p1.z;
        const r2 = proj / p2.z;
        const fx0 = p0.x * r0 + cx;
        const fy0 = cy - p0.y * r0;
        const fx1 = p1.x * r1 + cx;
        const fy1 = cy - p1.y * r1;
        const fx2 = p2.x * r2 + cx;
        const fy2 = cy - p2.y * r2;

        // Reject only on the unclamped projection, and only when all three
        // corners sit outside the same edge -- so a face that straddles the
        // border is kept and clipped by the rasterizer. Note there is
        // deliberately no sub-pixel/sliver test here: a triangle too small to
        // pass a float area test can still cover a pixel under the
        // rasterizer's integer edge test, so culling them drops visible
        // single pixels along every silhouette for only a few percent of
        // draw calls.
        if (fx0 >= vex.WIDTH and fx1 >= vex.WIDTH and fx2 >= vex.WIDTH) continue;
        if (fx0 < 0 and fx1 < 0 and fx2 < 0) continue;
        if (fy0 >= vex.HEIGHT and fy1 >= vex.HEIGHT and fy2 >= vex.HEIGHT) continue;
        if (fy0 < 0 and fy1 < 0 and fy2 < 0) continue;

        // Clamp only on the way to the rasterizer, purely so a projection
        // blowup can never reach @intFromFloat out of range. The camera clamp
        // and NEAR keep the real projection within a couple of thousand
        // pixels, so this never actually bites.
        const x0: i32 = @intFromFloat(clamp(fx0, -COORD_LIMIT, vex.WIDTH + COORD_LIMIT));
        const y0: i32 = @intFromFloat(clamp(fy0, -COORD_LIMIT, vex.HEIGHT + COORD_LIMIT));
        const x1: i32 = @intFromFloat(clamp(fx1, -COORD_LIMIT, vex.WIDTH + COORD_LIMIT));
        const y1: i32 = @intFromFloat(clamp(fy1, -COORD_LIMIT, vex.HEIGHT + COORD_LIMIT));
        const x2: i32 = @intFromFloat(clamp(fx2, -COORD_LIMIT, vex.WIDTH + COORD_LIMIT));
        const y2: i32 = @intFromFloat(clamp(fy2, -COORD_LIMIT, vex.HEIGHT + COORD_LIMIT));

        const pc = avg3(p0, p1, p2); // centroid relative to the eye

        // dot(n, d/|d|) == dot(n, d) * k, so one reciprocal replaces three
        // divisions per light.
        const d1 = sub(l1m, fcent[fi]);
        const d2 = sub(l2m, fcent[fi]);
        const k1 = 0.6 / len(d1);
        const k2 = 0.4 / len(d2);
        const s0 = @max(0, dot(n0, d1)) * k1 + @max(0, dot(n0, d2)) * k2;
        const s1 = @max(0, dot(n1, d1)) * k1 + @max(0, dot(n1, d2)) * k2;
        const s2 = @max(0, dot(n2, d1)) * k1 + @max(0, dot(n2, d2)) * k2;
        const intensity = clamp(0.15 + (s0 + s1 + s2) * (1.0 / 3.0), 0, 1);
        const shade: i32 = 2 + @as(i32, @intFromFloat(intensity * 13.999));

        const z = pc.z;
        cmds[cmd_cnt] = .{
            .z = z,
            .shade = shade,
            .sx0 = x0,
            .sy0 = y0,
            .sx1 = x1,
            .sy1 = y1,
            .sx2 = x2,
            .sy2 = y2,
        };
        cmd_cnt += 1;
        if (cmd_cnt == 1) {
            zmin = z;
            zmax = z;
        } else {
            zmin = @min(zmin, z);
            zmax = @max(zmax, z);
        }
    }

    // Counting sort into depth buckets: O(n) instead of the O(n^2) insertion
    // sort, and it only permutes small indices rather than 32-byte commands.
    const span = zmax - zmin;
    const zscale = if (span > 0) @as(f32, @floatFromInt(BUCKETS - 1)) / span else 0;
    for (&bucket_start) |*b| b.* = 0;
    for (cmds[0..cmd_cnt], 0..) |c, i| {
        // bucket 0 is the farthest, so a straight ascending walk draws the
        // scene back to front
        const b: usize = @intFromFloat(clamp((zmax - c.z) * zscale, 0, BUCKETS - 1));
        bucket_of[i] = @intCast(b);
        bucket_start[b] += 1;
    }
    var acc: u32 = 0;
    for (&bucket_start) |*b| {
        const n = b.*;
        b.* = acc;
        acc += n;
    }
    for (cmds[0..cmd_cnt], 0..) |c, i| {
        const b = bucket_of[i];
        sorted[bucket_start[b]] = c;
        bucket_start[b] += 1;
    }

    // The light marker sits at the light's projected position, so it only
    // makes sense while the light is in front of the eye.
    if (@abs(lv.z) >= NEAR) {
        const lx: i32 = @intFromFloat(clamp(lv.x / lv.z * proj + cx, -COORD_LIMIT, vex.WIDTH + COORD_LIMIT));
        const ly: i32 = @intFromFloat(clamp(-lv.y / lv.z * proj + cy, -COORD_LIMIT, vex.HEIGHT + COORD_LIMIT));
        vex.circ(lx, ly, 3, 1);
        vex.circb(lx, ly, 3, 1);
    }

    for (sorted[0..cmd_cnt]) |c| {
        if (wire) {
            vex.trib(
                c.sx0,
                c.sy0,
                c.sx1,
                c.sy1,
                c.sx2,
                c.sy2,
                c.shade,
            );
        } else vex.tri(
            c.sx0,
            c.sy0,
            c.sx1,
            c.sy1,
            c.sx2,
            c.sy2,
            c.shade,
        );
    }
}

const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,
};

fn sub(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x = a.x - b.x,
        .y = a.y - b.y,
        .z = a.z - b.z,
    };
}

fn add(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x = a.x + b.x,
        .y = a.y + b.y,
        .z = a.z + b.z,
    };
}

fn dot(a: Vec3, b: Vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn len(a: Vec3) f32 {
    return @sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

fn avg3(a: Vec3, b: Vec3, c: Vec3) Vec3 {
    return .{
        .x = (a.x + b.x + c.x) / 3.0,
        .y = (a.y + b.y + c.y) / 3.0,
        .z = (a.z + b.z + c.z) / 3.0,
    };
}

fn rotateX(v: Vec3, c: f32, s: f32) Vec3 {
    return .{
        .x = v.x,
        .y = v.y * c - v.z * s,
        .z = v.y * s + v.z * c,
    };
}

fn rotateY(v: Vec3, c: f32, s: f32) Vec3 {
    return .{
        .x = v.x * c + v.z * s,
        .y = v.y,
        .z = -v.x * s + v.z * c,
    };
}

/// rotateY by -a, i.e. rotate a world-space vector into model space.
fn rotateYinv(v: Vec3, c: f32, s: f32) Vec3 {
    return .{
        .x = v.x * c - v.z * s,
        .y = v.y,
        .z = v.x * s + v.z * c,
    };
}

/// rotateX by -a, the other half of the inverse vertex transform.
fn rotateXinv(v: Vec3, c: f32, s: f32) Vec3 {
    return .{
        .x = v.x,
        .y = v.y * c + v.z * s,
        .z = -v.y * s + v.z * c,
    };
}

fn clamp(v: f32, lo: f32, hi: f32) f32 {
    return @min(hi, @max(lo, v));
}

fn clampi(v: i32, lo: i32, hi: i32) i32 {
    return @min(hi, @max(lo, v));
}
