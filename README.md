# my.ChappieMetricsProducer

**Canonical metrics producer for AllasCode and MyChappie, implemented in Zig.**

The library owns metric definitions and Prometheus exposition. VictoriaMetrics is the time-series backend/scraper; it is not embedded into the Zig process. The default integration is pull-based: expose the rendered text at `/metrics`, then configure VictoriaMetrics to scrape it.

## Status

Core foundation with atomic counters, gauges, fixed-memory histograms, and compile-time bounded labels; Prometheus text exposition; tests; and a VictoriaMetrics scrape example. An HTTP server adapter remains the responsibility of the embedding application.

## Requirements

- Zig 0.16.0 (pinned in CI).
- VictoriaMetrics single-node or cluster; see the official [VictoriaMetrics repository](https://github.com/VictoriaMetrics/VictoriaMetrics).

## Quick start

```zig
const std = @import("std");
const metrics = @import("chappie_metrics");

pub fn main() !void {
    var registry = metrics.Registry.init(std.heap.page_allocator);
    defer registry.deinit();

    const requests = try registry.counter("chappie_requests_total", "Total handled requests");
    requests.inc();

    const body = try registry.render();
    defer std.heap.page_allocator.free(body);
    // Serve body as GET /metrics with Content-Type:
    // text/plain; version=0.0.4; charset=utf-8
    std.debug.print("{s}", .{body});
}
```

## Histogram

```zig
const latency = try registry.histogram("chappie_latency_ms", "Request latency in milliseconds");
latency.observe(12);
```

Histograms use 65 fixed atomic buckets with logarithmic upper bounds (1, 2, 4, …, 2^63, +Inf). Observation is O(1), performs no allocation, and does not search the registry. Bucket counts are cumulative only during export. This representation is intended for non-negative integer measurements; use milliseconds or microseconds as integer units.

## Compile-time bounded labels

Labels are deliberately separate from the registry lookup path. The label names are encoded in the generated type, the number of dimensions is fixed at compile time, and `inc`, `add`, and `get` perform no allocation or name lookup.

```zig
const RequestCounter = metrics.labels.Counter(.{"method", "status"});
var requests = RequestCounter.init(.{"POST", "200"});
requests.inc();
```

`renderLabels` exists only for export. Do not create label values from unbounded user input. Never use user ID, phone, email, session ID, prompt, raw intent, URL, or exception text as a label.

## Design contract

- Metric names use Prometheus conventions; counters end in `_total`.
- Labels have bounded cardinality and fixed dimensionality.
- Do not put secrets, message bodies, or user payloads into metrics.
- Metric collection must not perform network I/O. Export is an adapter concern.
- VictoriaMetrics scrapes the producer; the producer does not write directly to VictoriaMetrics.
- Keep instrumentation optional and cheap; never let telemetry failures change domain outcomes.

## VictoriaMetrics integration

1. Run VictoriaMetrics using its [official documentation](https://docs.victoriametrics.com/).
2. Expose the registry output from your application's HTTP server at `/metrics`.
3. Add the target from `examples/victoriametrics/scrape.yml` to your scrape configuration.
4. Query metrics in MetricsQL / PromQL-compatible expressions.

For a standalone single-node instance, configure scraping with `-promscrape.config=/path/to/promscrape.yml`. Check the official docs for deployment-specific configuration.

## Development

```sh
zig build
zig build test
zig build bench # ReleaseFast: 1, 4, and 16 threads
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/METRIC-CONVENTIONS.md](docs/METRIC-CONVENTIONS.md).

## Canonical ownership

This repository is the source of truth for the Zig metrics producer contract. Applications should depend on this library rather than implementing their own metric names or exposition format.
