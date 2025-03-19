const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const Outputs = @import("Outputs.zig").Outputs;
const Output = @import("Output.zig").Output;

pub const Context = struct {
    display: *wl.Display,

    shm: ?*wl.Shm = null,
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,
    layer_shell: ?*zwlr.LayerShellV1 = null,

    outputs: Outputs = Outputs{},

    pub fn init(globals: *Context) !void {
        const registry = try globals.display.getRegistry();
        registry.setListener(*Context, registryListener, globals);
        if (globals.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    }

    pub fn destroy(context: *Context) void {
        if (context.compositor) |compositor| compositor.destroy();
        if (context.layer_shell) |layer_shell| layer_shell.destroy();
        if (context.shm) |shm| shm.destroy();
        if (context.wm_base) |wm_base| wm_base.destroy();
        context.outputs.destroy();
    }
};

fn _registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) !void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = try registry.bind(global.name, wl.Compositor, 1);
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shm = try registry.bind(global.name, wl.Shm, 1);
            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                context.wm_base = try registry.bind(global.name, xdg.WmBase, 1);
            } else if (mem.orderZ(u8, global.interface, zwlr.LayerShellV1.interface.name) == .eq) {
                context.layer_shell = try registry.bind(global.name, zwlr.LayerShellV1, 3);
            } else if (mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                const wl_output = try registry.bind(global.name, wl.Output, 4);
                errdefer wl_output.release();
                const output = Output{
                    .wl_output = wl_output,
                    .wl_name = global.name,
                };
                try context.outputs.prepend(output);
            } else {
                return;
            }
            std.log.info("detected {s}:{}", .{ global.interface, global.name });
        },
        .global_remove => |global| {
            context.outputs.destroyOutput(global.name);
        },
    }
}

/// Wrapper function to catch errors in _registryListener.
fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    _registryListener(registry, event, context) catch |err| switch (err) {
        else => return,
    };
}
