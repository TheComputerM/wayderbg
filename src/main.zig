const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const Context = @import("Context.zig").Context;

pub fn main() anyerror!void {
    var context = Context{
        .display = try wl.Display.connect(null),
    };
    try context.init();
    errdefer context.destroy();

    while (true) {
        if (context.outputs.ready()) {
            try context.outputs.data.first.?.data.render();
            break;
        }
    }

    while (true) {
        if (context.display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }
}
