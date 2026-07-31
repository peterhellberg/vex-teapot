const vex = @import("vex");

const obj = @embedFile("teapot.obj");
var verts: [530]Vec3 = undefined;
var norms: [530]Vec3 = undefined;
var tris: [1024][3]u16 = undefined;
var vert_cnt: u32 = 0;
var norm_cnt: u32 = 0;
var face_cnt: u32 = 0;
var center: Vec3 = .{ .x = 0, .y = 0, .z = 0 };

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

    const focal: f32 = 100;
    const fscale: f32 = 4;
    const cx: f32 = 160;
    const cy: f32 = 90;

    var xf: [530]Vec3 = undefined;
    var xn: [530]Vec3 = undefined;
    for (verts[0..vert_cnt], 0..) |vp, i| {
        var v = sub(vp, center);
        v = rotateY(v, rot_y);
        v = rotateX(v, rot_x);
        xf[i] = v;

        var n = norms[i];
        n = rotateY(n, rot_y);
        n = rotateX(n, rot_x);
        xn[i] = n;
    }

    const lv = sub(light_pos, cam_pos);

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

    var cmds: [1024]TriCmd = undefined;
    var cmd_cnt: u32 = 0;

    for (tris[0..face_cnt]) |f| {
        const v0 = xf[f[0]];
        const v1 = xf[f[1]];
        const v2 = xf[f[2]];

        const cv0 = sub(v0, cam_pos);
        const cv1 = sub(v1, cam_pos);
        const cv2 = sub(v2, cam_pos);
        const px0 = cv0.x / cv0.z;
        const py0 = cv0.y / cv0.z;
        const px1 = cv1.x / cv1.z;
        const py1 = cv1.y / cv1.z;
        const px2 = cv2.x / cv2.z;
        const py2 = cv2.y / cv2.z;

        const pc = avg3(v0, v1, v2);
        const ld = normalize(sub(light_pos, pc));
        const ld2 = normalize(sub(light2, pc));

        const n0 = xn[f[0]];
        const n1 = xn[f[1]];
        const n2 = xn[f[2]];
        const s0 = 0.15 + @max(0, dot(n0, ld)) * 0.6 + @max(0, dot(n0, ld2)) * 0.4;
        const s1 = 0.15 + @max(0, dot(n1, ld)) * 0.6 + @max(0, dot(n1, ld2)) * 0.4;
        const s2 = 0.15 + @max(0, dot(n2, ld)) * 0.6 + @max(0, dot(n2, ld2)) * 0.4;
        const intensity = clamp((s0 + s1 + s2) * (1.0 / 3.0), 0, 1);
        const shade: i32 = 2 + @as(i32, @intFromFloat(intensity * 13.999));

        const s0x = px0 * focal * fscale + cx;
        const s0y = -py0 * focal * fscale + cy;
        const s1x = px1 * focal * fscale + cx;
        const s1y = -py1 * focal * fscale + cy;
        const s2x = px2 * focal * fscale + cx;
        const s2y = -py2 * focal * fscale + cy;

        cmds[cmd_cnt] = .{
            .z = (cv0.z + cv1.z + cv2.z) * (1.0 / 3.0),
            .shade = shade,
            .sx0 = @intFromFloat(s0x),
            .sy0 = @intFromFloat(s0y),
            .sx1 = @intFromFloat(s1x),
            .sy1 = @intFromFloat(s1y),
            .sx2 = @intFromFloat(s2x),
            .sy2 = @intFromFloat(s2y),
        };
        cmd_cnt += 1;
    }

    var i: u32 = 1;
    while (i < cmd_cnt) {
        var j = i;
        while (j > 0 and cmds[j].z > cmds[j - 1].z) {
            const tmp = cmds[j];
            cmds[j] = cmds[j - 1];
            cmds[j - 1] = tmp;
            j -= 1;
        }
        i += 1;
    }

    const lx: i32 = @intFromFloat(lv.x / lv.z * focal * fscale + cx);
    const ly: i32 = @intFromFloat(-lv.y / lv.z * focal * fscale + cy);

    vex.circ(lx, ly, 3, 1);
    vex.circb(lx, ly, 3, 1);

    for (cmds[0..cmd_cnt]) |c| vex.tri(
        c.sx0,
        c.sy0,
        c.sx1,
        c.sy1,
        c.sx2,
        c.sy2,
        c.shade,
    );
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

fn dot(a: Vec3, b: Vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn len(a: Vec3) f32 {
    return @sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

fn normalize(a: Vec3) Vec3 {
    const l = len(a);

    return if (l > 0) .{
        .x = a.x / l,
        .y = a.y / l,
        .z = a.z / l,
    } else a;
}

fn avg3(a: Vec3, b: Vec3, c: Vec3) Vec3 {
    return .{
        .x = (a.x + b.x + c.x) / 3.0,
        .y = (a.y + b.y + c.y) / 3.0,
        .z = (a.z + b.z + c.z) / 3.0,
    };
}

fn rotateX(v: Vec3, a: f32) Vec3 {
    const c = @cos(a);
    const s = @sin(a);

    return .{
        .x = v.x,
        .y = v.y * c - v.z * s,
        .z = v.y * s + v.z * c,
    };
}

fn rotateY(v: Vec3, a: f32) Vec3 {
    const c = @cos(a);
    const s = @sin(a);

    return .{
        .x = v.x * c + v.z * s,
        .y = v.y,
        .z = -v.x * s + v.z * c,
    };
}

fn clamp(v: f32, lo: f32, hi: f32) f32 {
    return @min(hi, @max(lo, v));
}