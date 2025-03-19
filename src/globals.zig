const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const Outputs = @import("outputs.zig").Outputs;
const Output = @import("outputs.zig").Output;

pub const Globals = struct {
    display: *wl.Display,

    shm: ?*wl.Shm = null,
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,
    layer_shell: ?*zwlr.LayerShellV1 = null,

    outputs: Outputs = Outputs{},

    pub fn init(globals: *Globals) !void {
        const registry = try globals.display.getRegistry();
        registry.setListener(*Globals, registryListener, globals);
        if (globals.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    }

    pub fn destroy(globals: *Globals) void {
        if (globals.compositor) |compositor| compositor.destroy();
        if (globals.layer_shell) |layer_shell| layer_shell.destroy();
        if (globals.shm) |shm| shm.destroy();
        if (globals.wm_base) |wm_base| wm_base.destroy();
        globals.outputs.destroy();
    }
};

fn _registryListener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) !void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                globals.compositor = try registry.bind(global.name, wl.Compositor, 1);
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                globals.shm = try registry.bind(global.name, wl.Shm, 1);
            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                globals.wm_base = try registry.bind(global.name, xdg.WmBase, 1);
            } else if (mem.orderZ(u8, global.interface, zwlr.LayerShellV1.interface.name) == .eq) {
                globals.layer_shell = try registry.bind(global.name, zwlr.LayerShellV1, 3);
            } else if (mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                const wl_output = try registry.bind(global.name, wl.Output, 4);
                errdefer wl_output.release();
                const output = Output{
                    .wl_output = wl_output,
                    .wl_name = global.name,
                };
                try globals.outputs.prepend(output);
            } else {
                return;
            }
            std.log.info("detected {s}:{}", .{ global.interface, global.name });
        },
        .global_remove => |global| {
            globals.outputs.destroyOutput(global.name);
        },
    }
}

/// Wrapper function to catch errors in _registryListener.
fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Globals) void {
    _registryListener(registry, event, context) catch |err| switch (err) {
        else => return,
    };
}
