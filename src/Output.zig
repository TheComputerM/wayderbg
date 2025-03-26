const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const Context = @import("./Context.zig").Context;

/// Wrapper over a wl_output
pub const Output = struct {
    wl_output: *wl.Output,
    wl_name: u32,

    // TODO: try with u32
    scale: u31 = 0,
    width: u31 = 0,
    height: u31 = 0,

    render_width: u31 = 0,
    render_height: u31 = 0,

    context: *Context,
    wl_surface: ?*wl.Surface = null,
    layer_surface: ?*zwlr.LayerSurfaceV1 = null,

    configured: bool = false,

    pub fn destroy(output: *Output) void {
        output.destroyPrimitives();
        output.wl_output.release();
        std.log.debug("destroyed output wl_name:{}", .{output.wl_name});
    }

    fn destroyPrimitives(output: *Output) void {
        if (output.layer_surface) |layer_surface| {
            layer_surface.destroy();
        }
        if (output.wl_surface) |wl_surface| {
            wl_surface.destroy();
        }

        output.layer_surface = null;
        output.wl_surface = null;
        output.configured = false;
    }

    pub fn init(output: *Output) !void {
        output.wl_output.setListener(*Output, outputListener, output);
        if (output.context.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    }

    fn addSurfaceToOutput(output: *Output) !void {
        if (output.wl_surface) |_| return;

        const wl_surface = try output.context.compositor.?.createSurface();

        // We don't want our surface to have any input region (default is infinite)
        const empty_region = try output.context.compositor.?.createRegion();
        defer empty_region.destroy();
        wl_surface.setInputRegion(empty_region);

        // Full surface should be opaque
        const opaque_region = try output.context.compositor.?.createRegion();
        defer opaque_region.destroy();
        wl_surface.setOpaqueRegion(opaque_region);

        const layer_surface = try output.context.layer_shell.?.getLayerSurface(wl_surface, output.wl_output, .background, "wayderbg");
        layer_surface.setExclusiveZone(-1);
        layer_surface.setAnchor(.{ .top = true, .right = true, .bottom = true, .left = true });

        output.wl_surface = wl_surface;
        output.layer_surface = layer_surface;

        layer_surface.setListener(*Output, layerSurfaceListener, output);
        wl_surface.commit();
        if (output.context.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    }

    pub fn render(output: *Output) !void {
        const buffer = blk: {
            const width = output.render_width;
            const height = output.render_height;
            const stride = width * 4;
            const size = stride * height;

            const Pixel = [4]u8;

            const fd = try std.posix.memfd_create("wayderbg", 0);
            try std.posix.ftruncate(fd, size);
            const data = try std.posix.mmap(
                null,
                size,
                std.posix.PROT.READ | std.posix.PROT.WRITE,
                .{ .TYPE = .SHARED },
                fd,
                0,
            );
            const pixels: []Pixel = mem.bytesAsSlice(Pixel, data);
            @memset(pixels, Pixel{ 0, 0, 0xFF, 0xFF });

            const pool = try output.context.shm.?.createPool(fd, size);
            defer pool.destroy();

            break :blk try pool.createBuffer(0, width, height, stride, wl.Shm.Format.argb8888);
        };

        const wl_surface = output.wl_surface.?;
        wl_surface.attach(buffer, 0, 0);
        wl_surface.commit();
        if (output.context.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    }
};

fn outputListener(_: *wl.Output, event: wl.Output.Event, output: *Output) void {
    switch (event) {
        .mode => |mode| {
            output.width = @intCast(mode.width);
            output.height = @intCast(mode.height);
        },
        .scale => |scale| {
            output.scale = @intCast(scale.factor);
        },
        .done => {
            output.addSurfaceToOutput() catch |err| {
                std.log.err("error adding surface to output: {}", .{err});
            };
            std.log.info("wl_output:{} configured", .{output.wl_name});
        },
        else => {},
    }
}

fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, output: *Output) void {
    switch (event) {
        .configure => |configure| {
            layer_surface.ackConfigure(configure.serial);

            const w: u31 = @truncate(configure.width);
            const h: u31 = @truncate(configure.height);

            if (output.configured and output.render_width == w and output.render_height == h) {
                output.wl_surface.?.commit();
                return;
            }

            output.render_width = w;
            output.render_height = h;
            output.configured = true;
            std.log.debug("configuring output for wl_output:{} as {}x{}", .{ output.wl_name, w, h });
        },
        .closed => {
            output.destroyPrimitives();
        },
    }
}
