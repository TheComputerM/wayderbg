const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

/// Linked list of outputs/displays available
pub const Outputs = struct {
    data: std.SinglyLinkedList(Output) = .{},
    allocator: mem.Allocator = std.heap.page_allocator,

    pub fn prepend(outputs: *Outputs, output: Output) !void {
        const node = try outputs.allocator.create(std.SinglyLinkedList(Output).Node);
        errdefer outputs.allocator.destroy(node);
        node.data = output;
        outputs.data.prepend(node);
    }

    pub fn destroy(outputs: *Outputs) void {
        while (outputs.data.popFirst()) |node| {
            node.data.destroy();
            outputs.allocator.destroy(node);
        }
    }

    /// Destroys the output with the given wl_name
    pub fn destoryOutput(outputs: *Outputs, wl_name: u32) void {
        var it = outputs.data.first;
        while (it) |node| {
            if (node.data.wl_name == wl_name) {
                node.data.destroy();
                outputs.data.remove(node);
                outputs.allocator.destroy(node);
                return;
            }
            it = node.next;
        }
    }
};

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
