const std = @import("std");

pub const MetricKind = enum {
    counter,
    gauge,
};

pub const Counter = struct {
    name: []const u8,
    help: []const u8,
    value: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    pub fn inc(self: *Counter) void {
        _ = self.value.fetchAdd(1, .monotonic);
    }

    pub fn add(self: *Counter, amount: u64) void {
        _ = self.value.fetchAdd(amount, .monotonic);
    }

    pub fn get(self: *const Counter) u64 {
        return self.value.load(.monotonic);
    }
};

pub const Gauge = struct {
    name: []const u8,
    help: []const u8,
    value: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    pub fn set(self: *Gauge, value: i64) void {
        self.value.store(value, .monotonic);
    }

    pub fn inc(self: *Gauge) void {
        _ = self.value.fetchAdd(1, .monotonic);
    }

    pub fn dec(self: *Gauge) void {
        _ = self.value.fetchSub(1, .monotonic);
    }

    pub fn add(self: *Gauge, amount: i64) void {
        _ = self.value.fetchAdd(amount, .monotonic);
    }

    pub fn get(self: *const Gauge) i64 {
        return self.value.load(.monotonic);
    }
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    counters: std.ArrayList(*Counter) = .empty,
    gauges: std.ArrayList(*Gauge) = .empty,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        for (self.counters.items) |metric| self.allocator.destroy(metric);
        for (self.gauges.items) |metric| self.allocator.destroy(metric);
        self.counters.deinit(self.allocator);
        self.gauges.deinit(self.allocator);
    }

    pub fn counter(self: *Registry, name: []const u8, help: []const u8) !*Counter {
        try validateName(name);
        if (self.findCounter(name)) |existing| return error.DuplicateMetric;
        const metric = try self.allocator.create(Counter);
        metric.* = .{ .name = try self.allocator.dupe(u8, name), .help = try self.allocator.dupe(u8, help) };
        errdefer {
            self.allocator.free(metric.name);
            self.allocator.free(metric.help);
            self.allocator.destroy(metric);
        }
        try self.counters.append(self.allocator, metric);
        return metric;
    }

    pub fn gauge(self: *Registry, name: []const u8, help: []const u8) !*Gauge {
        try validateName(name);
        if (self.findGauge(name) != null or self.findCounter(name) != null) return error.DuplicateMetric;
        const metric = try self.allocator.create(Gauge);
        metric.* = .{ .name = try self.allocator.dupe(u8, name), .help = try self.allocator.dupe(u8, help) };
        errdefer {
            self.allocator.free(metric.name);
            self.allocator.free(metric.help);
            self.allocator.destroy(metric);
        }
        try self.gauges.append(self.allocator, metric);
        return metric;
    }

    pub fn render(self: *const Registry) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(self.allocator);
        for (self.counters.items) |metric| {
            try appendHelpAndType(self.allocator, &output, metric.name, metric.help, "counter");
            try appendFmt(self.allocator, &output, "{s} {d}\n", .{ metric.name, metric.get() });
        }
        for (self.gauges.items) |metric| {
            try appendHelpAndType(self.allocator, &output, metric.name, metric.help, "gauge");
            try appendFmt(self.allocator, &output, "{s} {d}\n", .{ metric.name, metric.get() });
        }
        return output.toOwnedSlice(self.allocator);
    }

    fn findCounter(self: *const Registry, name: []const u8) ?*Counter {
        for (self.counters.items) |metric| {
            if (std.mem.eql(u8, metric.name, name)) return metric;
        }
        return null;
    }

    fn findGauge(self: *const Registry, name: []const u8) ?*Gauge {
        for (self.gauges.items) |metric| {
            if (std.mem.eql(u8, metric.name, name)) return metric;
        }
        return null;
    }
};

fn validateName(name: []const u8) !void {
    if (name.len == 0) return error.InvalidMetricName;
    for (name, 0..) |ch, index| {
        const valid = std.ascii.isAlphanumeric(ch) or ch == '_' or ch == ':';
        if (!valid or (index == 0 and std.ascii.isDigit(ch))) return error.InvalidMetricName;
    }
}

fn appendHelpAndType(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    name: []const u8,
    help: []const u8,
    kind: []const u8,
) !void {
    try appendFmt(allocator, output, "# HELP {s} {s}\n# TYPE {s} {s}\n", .{ name, help, name, kind });
}

fn appendFmt(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    comptime format: []const u8,
    args: anytype,
) !void {
    const chunk = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(chunk);
    try output.appendSlice(allocator, chunk);
}

test "counter renders Prometheus exposition" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    const requests = try registry.counter("chappie_requests_total", "Total handled requests");
    requests.inc();
    requests.add(2);

    const rendered = try registry.render();
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        "# HELP chappie_requests_total Total handled requests\n# TYPE chappie_requests_total counter\nchappie_requests_total 3\n",
        rendered,
    );
}

test "gauge supports setting and decrementing" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    const active = try registry.gauge("chappie_active_sessions", "Current active sessions");
    active.set(4);
    active.dec();

    try std.testing.expectEqual(@as(i64, 3), active.get());
}

test "rejects invalid names and duplicate metric names" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectError(error.InvalidMetricName, registry.counter("1bad", "invalid"));
    _ = try registry.counter("requests_total", "Requests");
    try std.testing.expectError(error.DuplicateMetric, registry.counter("requests_total", "Duplicate"));
    try std.testing.expectError(error.DuplicateMetric, registry.gauge("requests_total", "Duplicate"));
}
