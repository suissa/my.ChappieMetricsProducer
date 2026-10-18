const std = @import("std");

pub const MetricKind = enum {
    counter,
    gauge,
    histogram,
};

pub const Counter = struct {
    name: []const u8,
    help: []const u8,
    value: std.atomic.Value(u64) align(64) = std.atomic.Value(u64).init(0),

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
    value: std.atomic.Value(i64) align(64) = std.atomic.Value(i64).init(0),

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


/// Fixed-memory histogram with logarithmic upper bounds (1, 2, 4, ... 2^63, +Inf).
/// Observation is O(1), allocation-free, and lock-free after registration.
pub const Histogram = struct {
    name: []const u8,
    help: []const u8,
    buckets: [65]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** 65,
    count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    sum: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    pub fn observe(self: *Histogram, value: u64) void {
        const index: usize = if (value <= 1) 0 else @intCast(64 - @clz(value - 1));
        _ = self.buckets[index].fetchAdd(1, .monotonic);
        _ = self.count.fetchAdd(1, .monotonic);
        _ = self.sum.fetchAdd(value, .monotonic);
    }

    pub fn getCount(self: *const Histogram) u64 {
        return self.count.load(.monotonic);
    }

    pub fn getSum(self: *const Histogram) u64 {
        return self.sum.load(.monotonic);
    }
};
\npub const Registry = struct {
    allocator: std.mem.Allocator,
    counters: std.ArrayList(*Counter) = .empty,
    gauges: std.ArrayList(*Gauge) = .empty,\n    histograms: std.ArrayList(*Histogram) = .empty,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        for (self.counters.items) |metric| {
            self.allocator.free(metric.name);
            self.allocator.free(metric.help);
            self.allocator.destroy(metric);
        }
        for (self.gauges.items) |metric| {
            self.allocator.free(metric.name);
            self.allocator.free(metric.help);
            self.allocator.destroy(metric);
        }
        self.counters.deinit(self.allocator);
        self.gauges.deinit(self.allocator);\n        for (self.histograms.items) |metric| {\n            self.allocator.free(metric.name);\n            self.allocator.free(metric.help);\n            self.allocator.destroy(metric);\n        }\n        self.histograms.deinit(self.allocator);
    }

    pub fn counter(self: *Registry, name: []const u8, help: []const u8) !*Counter {
        try validateName(name);
        if (self.findCounter(name) != null or self.findGauge(name) != null or self.findHistogram(name) != null) return error.DuplicateMetric;
        const metric = try self.allocator.create(Counter);
        errdefer self.allocator.destroy(metric);
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_help = try self.allocator.dupe(u8, help);
        errdefer self.allocator.free(owned_help);
        metric.* = .{ .name = owned_name, .help = owned_help };
        try self.counters.append(self.allocator, metric);
        return metric;
    }

    pub fn gauge(self: *Registry, name: []const u8, help: []const u8) !*Gauge {
        try validateName(name);
        if (self.findGauge(name) != null or self.findCounter(name) != null or self.findHistogram(name) != null) return error.DuplicateMetric;
        const metric = try self.allocator.create(Gauge);
        errdefer self.allocator.destroy(metric);
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_help = try self.allocator.dupe(u8, help);
        errdefer self.allocator.free(owned_help);
        metric.* = .{ .name = owned_name, .help = owned_help };
        try self.gauges.append(self.allocator, metric);
        return metric;
    }


    pub fn histogram(self: *Registry, name: []const u8, help: []const u8) !*Histogram {
        try validateName(name);
        if (self.findCounter(name) != null or self.findGauge(name) != null or self.findHistogram(name) != null) return error.DuplicateMetric;
        const metric = try self.allocator.create(Histogram);
        errdefer self.allocator.destroy(metric);
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_help = try self.allocator.dupe(u8, help);
        errdefer self.allocator.free(owned_help);
        metric.* = .{ .name = owned_name, .help = owned_help };
        try self.histograms.append(self.allocator, metric);
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

        for (self.histograms.items) |metric| {
            try appendHelpAndType(self.allocator, &output, metric.name, metric.help, "histogram");
            var cumulative: u64 = 0;
            for (0..64) |index| {
                cumulative += metric.buckets[index].load(.monotonic);
                const upper_bound = @as(u64, 1) << @intCast(index);
                try appendFmt(self.allocator, &output, "{s}_bucket{{le=\"{d}\"}} {d}\\n", .{ metric.name, upper_bound, cumulative });
            }
            cumulative += metric.buckets[64].load(.monotonic);
            try appendFmt(self.allocator, &output, "{s}_bucket{{le=\"+Inf\"}} {d}\\n", .{ metric.name, cumulative });
            try appendFmt(self.allocator, &output, "{s}_sum {d}\\n{s}_count {d}\\n", .{ metric.name, metric.getSum(), metric.name, metric.getCount() });
        }
        return output.toOwnedSlice(self.allocator);
    }

    fn findCounter(self: *const Registry, name: []const u8) ?*Counter {
        for (self.counters.items) |metric| {
            if (std.mem.eql(u8, metric.name, name)) return metric;
        }
        return null;
    }

    fn findHistogram(self: *const Registry, name: []const u8) ?*Histogram {\n        for (self.histograms.items) |metric| {\n            if (std.mem.eql(u8, metric.name, name)) return metric;\n        }\n        return null;\n    }\n\n    fn findGauge(self: *const Registry, name: []const u8) ?*Gauge {
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

test "histogram records observations and exports cumulative buckets" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    const latency = try registry.histogram("chappie_latency_ms", "Request latency in milliseconds");
    latency.observe(1);
    latency.observe(2);
    latency.observe(5);

    try std.testing.expectEqual(@as(u64, 3), latency.getCount());
    try std.testing.expectEqual(@as(u64, 8), latency.getSum());

    const rendered = try registry.render();
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "chappie_latency_ms_bucket{le=\"1\"} 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "chappie_latency_ms_bucket{le=\"2\"} 2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "chappie_latency_ms_bucket{le=\"+Inf\"} 3\n") != null);
}

test "histogram name cannot collide with another metric kind" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();
    _ = try registry.counter("requests_total", "Requests");
    try std.testing.expectError(error.DuplicateMetric, registry.histogram("requests_total", "Collision"));
}
