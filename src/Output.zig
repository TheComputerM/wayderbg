const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

/// Wrapper over a wl_output
pub const Output = struct {
    wl_output: *wl.Output,
    wl_name: u32,

    scale: u31 = 0,
    width: u31 = 0,
    height: u31 = 0,

    wl_surface: ?*wl.Surface = null,
    layer_surface: ?*zwlr.LayerSurfaceV1 = null,

    configured: bool = false,

    pub fn destroy(output: *Output) void {
        output.destroyPrimitives();
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

    pub fn setListener(output: *Output) void {
        output.wl_output.setListener(*Output, outputListener, output);
    }
};

fn outputListener(_: *wl.Output, event: wl.Output.Event, output: *Output) void {
    switch (event) {
        .geometry => |geometry| {
            output.width = @intCast(geometry.width);
            output.height = @intCast(geometry.height);
        },
        .scale => |scale| {
            output.scale = @intCast(scale.factor);
        },
        .done => {
            output.configured = true;
        },
        else => {},
    }
}
