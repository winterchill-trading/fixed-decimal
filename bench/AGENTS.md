# AGENTS.md: fixed-decimal/bench

`bench.ml` measures parse, print and arithmetic cost with `core_bench`, reporting ns per
call and words per call. Its numbers are quoted in `../README.md` (Performance).

The executable `bench` is declared in `bench/dune`; it is built by `@fixed-decimal/all`.

Rules:
- Report words per call, not just time. A regression in words is a bug even when time holds.
- Name the platform when a number goes into the README; macOS arm64 and Linux amd64 differ.
