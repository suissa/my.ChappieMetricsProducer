# zmetrics

Lib de métricas para **Zig 0.16.0**: counter, gauge e histograma com hot path sem alocação,
sem lock e sem lookup, mais exposição em texto Prometheus.

```sh
zig build test                         # 13 testes (inclui concorrência)
zig build example                      # imprime um /metrics de exemplo
zig build bench -Doptimize=ReleaseFast # benchmark (rode em máquina multi-core!)
zig build -Dmetrics_enabled=false      # hot path vira no-op em comptime
```

## Uso

```zig
var reg = zm.Registry.init(gpa, io, .{});
defer reg.deinit();

// registra UMA vez (cold path), guarda o ponteiro
const ok  = try reg.counter("http_requests_total", "Total.", .{ .method = "GET", .code = "200" });
const lat = try reg.histogram("http_request_duration_seconds", "Latência.", .{ .route = "/users" }, .{ .divisor = 1e9 });

// hot path
ok.inc();
var t = lat.startTimer(io);
defer t.observe();

// GET /metrics
try reg.write(&writer);
```

## Decisões de design

| Peça | Decisão |
|---|---|
| Counter | `ShardedCounter(n)`: slots de 1 cache line, slot por thread (`threadlocal`), `fetchAdd(.monotonic)` |
| Gauge | `f64` guardado como bits num `u64` atômico; `add` por CAS |
| Histograma | log-linear (HDR-like): índice por `@clz` + shifts, O(1), erro relativo ≤ 1/2^P (padrão P=3 → 12,5%). Só 2 RMW por `observe` (bucket + sum); `count` = soma dos buckets |
| Labels | nomes validados em comptime; valores escapados uma vez no registro; registro idempotente |
| Cardinalidade | `max_series` → `error.CardinalityLimit` |
| Memória | tudo numa arena do registry; ponteiros estáveis; hot path não aloca |
| Exposição | só buckets não vazios + `+Inf`; `+Inf == _count` garantido; scrape não bloqueia escritores |
| 0.16 | `std.Thread.Mutex` e `std.time.Timer` não existem mais: lock via `std.Io.Mutex` e tempo via `std.Io.Timestamp`, ambos com o `io` guardado no registry |

## Próximos passos sugeridos

1. Shards no histograma (hoje só o Counter é sharded).
2. Gauge/histograma com `precision_bits` configurável por série.
3. Exporters OpenMetrics (com `# EOF` e exemplars), StatsD e OTLP como módulos separados.
4. Summary/quantis (t-digest ou DDSketch) se precisar de quantis no cliente.
 
