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

    pub fn init(output: *Output) void {
        output.wl_output.setListener(*Output, outputListener, output);
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
            std.log.info("wl_output:{} configured", .{output.wl_name});
            output.addSurfaceToOutput() catch |err| {
                std.log.err("error adding surface to output: {}", .{err});
            };
        },
        else => {},
    }
}

fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, output: *Output) void {
    switch (event) {
        .configure => |ev| {
            layer_surface.ackConfigure(ev.serial);

            const w: u31 = @truncate(ev.width);
            const h: u31 = @truncate(ev.height);

            if (output.configured and output.render_width == w and output.render_height == h) {
                output.wl_surface.?.commit();
                return;
            }

            std.log.debug("configuring output for wl_output:{} as {}x{}", .{ output.wl_name, w, h });
            output.render_width = w;
            output.render_height = h;
            output.configured = true;

            // TODO: render on surface
        },
        .closed => {
            output.destroyPrimitives();
        },
    }
}
