# Metric conventions

- Use lowercase snake_case names.
- Counters represent cumulative events and should end in `_total`.
- Gauges represent values that can move in both directions, such as active sessions or queue depth.
- Include units in names where useful: `_seconds`, `_bytes`, `_total`.
- Use stable, bounded dimensions only when label support is implemented.
- Never use user ID, phone number, email, session ID, raw intent, prompt, URL, exception text, or arbitrary user input as a label.
- Prefer a small set of outcome categories over raw error messages.
- Do not put secrets, payloads, or personal data in metric help text.
- Treat every new metric as a public operational contract: document its meaning, type, unit, and cardinality.
