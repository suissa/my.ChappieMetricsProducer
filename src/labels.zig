const std = @import("std");

/// Compile-time bounded labels. Label names are part of the type, so the
/// number of dimensions is fixed and there is no per-observation allocation.
pub fn Counter(comptime names: anytype) type {
    comptime {
        if (@typeInfo(@TypeOf(names)) != .array) @compileError("label names must be a comptime array");
        if (names.len == 0) @compileError("at least one label is required");
    }

    return struct {
        const Self = @This();
        pub const label_names = names;

        value: std.atomic.Value(u64) align(64) = std.atomic.Value(u64).init(0),
        label_values: [names.len][]const u8,

        pub fn init(values: [names.len][]const u8) Self {
            return .{ .label_values = values };
        }

        pub inline fn inc(self: *Self) void {
            _ = self.value.fetchAdd(1, .monotonic);
        }

        pub inline fn add(self: *Self, amount: u64) void {
            _ = self.value.fetchAdd(amount, .monotonic);
        }

        pub inline fn get(self: *const Self) u64 {
            return self.value.load(.monotonic);
        }

        /// Export-only operation. Observation never calls this function.
        pub fn renderLabels(self: *const Self, allocator: std.mem.Allocator, output: *std.ArrayList(u8)) !void {
            try output.append(allocator, '{');
            inline for (names, 0..) |name, index| {
                if (index != 0) try output.append(allocator, ',');
                try output.appendSlice(allocator, name);
                try output.appendSlice(allocator, "=\"");
                try escapeLabelValue(allocator, output, self.label_values[index]);
                try output.append(allocator, '"');
            }
            try output.append(allocator, '}');
        }
    };
}

fn escapeLabelValue(allocator: std.mem.Allocator, output: *std.ArrayList(u8), value: []const u8) !void {
    for (value) |ch| {
        switch (ch) {
            '\\' => try output.appendSlice(allocator, "\\\\"),
            '"' => try output.appendSlice(allocator, "\\\""),
            '\n' => try output.appendSlice(allocator, "\\n"),
            else => try output.append(allocator, ch),
        }
    }
}

test "compile-time labels are fixed and render without allocation on observation" {
    const RequestCounter = Counter(.{"method", "status"});
    var metric = RequestCounter.init(.{"POST", "200"});
    metric.inc();
    try std.testing.expectEqual(@as(u64, 1), metric.get());

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try metric.renderLabels(std.testing.allocator, &output);
    try std.testing.expectEqualStrings("{method=\"POST\",status=\"200\"}", output.items);
}

test "label values escape prometheus special characters" {
    const RequestCounter = Counter(.{"route"});
    var metric = RequestCounter.init(.{"/x\\y\"z\n"});

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try metric.renderLabels(std.testing.allocator, &output);
    try std.testing.expectEqualStrings("{route=\"/x\\\\y\\\"z\\n\"}", output.items);
}
