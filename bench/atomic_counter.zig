const std = @import("std");
const labels = @import("labels");

const BenchCounter = labels.Counter(.{"worker"});
const iterations_per_thread: u64 = 1_000_000;

fn incrementMany(counter: *BenchCounter, iterations: u64) void {
    var i: u64 = 0;
    while (i < iterations) : (i += 1) counter.inc();
}

fn runCase(thread_count: usize) !void {
    var counter = BenchCounter.init(.{"benchmark"});
    var threads: [16]std.Thread = undefined;
    var timer = try std.time.Timer.start();

    for (threads[0..thread_count]) |*thread| {
        thread.* = try std.Thread.spawn(.{}, incrementMany, .{ &counter, iterations_per_thread });
    }
    for (threads[0..thread_count]) |*thread| thread.join();

    const elapsed_ns = timer.read();
    const operations = iterations_per_thread * @as(u64, @intCast(thread_count));
    const ops_per_second = if (elapsed_ns == 0) 0 else @as(u64, @intCast((@as(u128, operations) * std.time.ns_per_s) / elapsed_ns));

    std.debug.print("threads={d} operations={d} elapsed_ms={d} ops_per_second={d} final={d}\n", .{
        thread_count,
        operations,
        elapsed_ns / std.time.ns_per_ms,
        ops_per_second,
        counter.get(),
    });
}

pub fn main() !void {
    try runCase(1);
    try runCase(4);
    try runCase(16);
}
