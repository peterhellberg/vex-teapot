const std = @import("std");

pub fn build(b: *std.Build) void {
    // Carts compile to wasm32-freestanding.
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // The vex SDK provides the `vex` module (the host API bindings). The
    // SDK has no external dependencies, so a cart build never fetches
    // anything heavy (raylib/wasm3 live in a separate cmd/vex package).
    const vex = b.dependency("vex", .{});

    const cart = b.addExecutable(.{
        .name = "vex-teapot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cart.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{
                    .name = "vex",
                    .module = vex.module("vex"),
                },
                // The `spr` module (comptime PNG/sprite decoder) is also
                // exposed by the SDK. Uncomment to import it from
                // src/cart.zig (and add `const spr = @import("spr");`).
                // .{
                //     .name = "spr",
                //     .module = vex.module("spr"),
                // },
            },
        }),
    });
    cart.entry = .disabled; // no _start; the console calls update()
    cart.rdynamic = true; // export boot()/update()
    b.installArtifact(cart);

    // run/web point vex-run and vex-web at the *installed* wasm
    // (zig-out/bin/<name>.wasm) -- a stable path, unlike the build cache. Run
    // `zig build --watch` in another terminal to rebuild on every edit; vex-run
    // (started with --watch) and vex-web both reload it automatically. Both
    // tools must be on your PATH (e.g. via `make install` in the vex repo).
    const wasm = b.getInstallPath(.bin, cart.out_filename);

    // `zig build run` builds + installs the cart and runs it in vex-run, the
    // pure-Go native host (no raylib/wasm3, no X11 dev headers required).
    // --watch makes a concurrent `zig build --watch` reload it automatically.
    const run = b.addSystemCommand(&.{ "vex-run", "--watch" });
    run.addArg(wasm);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Build the cart and run it in vex-run").dependOn(&run.step);

    // `zig build web` builds + installs the cart and serves it via vex-web.
    const web = b.addSystemCommand(&.{"vex-web"});
    web.addArg(wasm);
    web.step.dependOn(b.getInstallStep());
    if (b.args) |args| web.addArgs(args);
    b.step("web", "Build the cart and serve it with vex-web").dependOn(&web.step);

    // `zig build bundle` builds + installs the cart and writes a static
    // bundle (bundle/<name>/ and bundle/<name>.zip) ready to host anywhere.
    const bundle = b.addSystemCommand(&.{ "vex-web", "-bundle" });
    bundle.addArg(wasm);
    bundle.step.dependOn(b.getInstallStep());
    b.step("bundle", "Build the cart and write a static bundle with vex-web").dependOn(&bundle.step);

    // `zig build deploy` bundles, copies src/ into the bundle, then scp's
    // it to play.c7.se. Edit scp_target / public_url below to point at
    // your own hosting setup.
    const scp_target = "c7.se:/var/www/play.c7.se/vex/";
    const public_url = "https://play.c7.se/vex/" ++ "vex-teapot" ++ "/";

    const rm_src = b.addSystemCommand(&.{ "rm", "-rf", "bundle/" ++ "vex-teapot" ++ "/src" });
    rm_src.step.dependOn(&bundle.step);

    const copy_src = b.addSystemCommand(&.{ "cp", "-r", "src", "bundle/" ++ "vex-teapot" ++ "/." });
    copy_src.step.dependOn(&rm_src.step);

    const deploy_cmd = "scp -r bundle/* " ++ scp_target ++
        " && echo '→ Uploaded to " ++ public_url ++ "'";
    const deploy = b.addSystemCommand(&.{ "bash", "-c", deploy_cmd });
    deploy.step.dependOn(&copy_src.step);
    b.step("deploy", "Bundle the cart and scp it to play.c7.se").dependOn(&deploy.step);
}
