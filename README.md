# my.ChappieMetricsProducer

**Canonical metrics producer for AllasCode and MyChappie, implemented in Zig.**

The library owns metric definitions and Prometheus exposition. VictoriaMetrics is the time-series backend/scraper; it is not embedded into the Zig process. The default integration is pull-based: expose the rendered text at `/metrics`, then configure VictoriaMetrics to scrape it.

## Status

Initial canonical foundation. This repository establishes the contract, a small dependency-free metric registry, Prometheus text exposition, tests, and a scrape example. The HTTP server adapter and broader metric types are follow-up work.

## Requirements

- Zig 0.15.2 (pinned in CI).
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

## Design contract

- Metric names use Prometheus conventions; counters end in `_total`.
- Use bounded, low-cardinality labels when label support is added. Never label by user ID, phone, session ID, prompt, raw intent, or other PII/high-cardinality values.
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
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/METRIC-CONVENTIONS.md](docs/METRIC-CONVENTIONS.md).

## Canonical ownership

This repository is the source of truth for the Zig metrics producer contract. Applications should depend on this library rather than implementing their own metric names or exposition format.
