const std = @import("std");

/// Compile-time bounded labels. Label names are part of the type, so the
/// number of dimensions is fixed and there is no per-observation allocation.
pub fn Counter(comptime names: anytype) type {
    comptime {
        if (@typeInfo(@TypeOf(names)) != .array) @compileError("label names must be a comptime array");
        if (names.len == 0) @compileError("at least one label is required");
        for (names) |name| {
            if (@TypeOf(name) != []const u8 and @TypeOf(name) != *const [name.len:0]u8) {
                @compileError("label names must be string literals");
            }
        }
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

        /// Renders only the label set. Intended to be appended by an exporter.
        pub fn renderLabels(self: *const Self, writer: anytype) !void {
            try writer.writeByte('{');
            inline for (names, 0..) |name, index| {
                if (index != 0) try writer.writeByte(',');
                try writer.print("{s}=\"", .{name});
                try escapeLabelValue(writer, self.label_values[index]);
                try writer.writeByte('"');
            }
            try writer.writeByte('}');
        }
    };
}

fn escapeLabelValue(writer: anytype, value: []const u8) !void {
    for (value) |ch| {
        switch (ch) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            else => try writer.writeByte(ch),
        }
    }
}

test "compile-time labels are fixed and render without allocation" {
    const RequestCounter = Counter(.{"method", "status"});
    var metric = RequestCounter.init(.{"POST", "200"});
    metric.inc();

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try metric.renderLabels(output.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("{method=\"POST\",status=\"200\"}", output.items);
}

test "label values escape prometheus special characters" {
    const RequestCounter = Counter(.{"route"});
    var metric = RequestCounter.init(.{"/x\\y\"z\n"});

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try metric.renderLabels(output.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("{route=\"/x\\\\y\\\"z\\n\"}", output.items);
}
