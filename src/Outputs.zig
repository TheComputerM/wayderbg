const std = @import("std");

const Output = @import("Output.zig").Output;

/// Linked list of outputs/displays available
pub const Outputs = struct {
    data: std.SinglyLinkedList(Output) = .{},
    allocator: std.mem.Allocator = std.heap.page_allocator,

    pub fn addOutput(outputs: *Outputs, output: Output) !void {
        const node = try outputs.allocator.create(std.SinglyLinkedList(Output).Node);
        errdefer outputs.allocator.destroy(node);
        node.data = output;
        outputs.data.prepend(node);
        node.data.init();
        std.log.debug("added output wl_output:{} to list of outputs", .{output.wl_name});
    }

    pub fn destroy(outputs: *Outputs) void {
        while (outputs.data.popFirst()) |node| {
            node.data.destroy();
            outputs.allocator.destroy(node);
        }
    }

    /// Destroys the output with the given wl_name
    pub fn destroyOutput(outputs: *Outputs, wl_name: u32) void {
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
