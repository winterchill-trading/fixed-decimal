# AGENTS.md: fixed-decimal/.github

- `workflows/ci.yml`: checkout, the shared `ox-setup` action, `dune build`, `dune test`,
  `dune exec examples/notional.exe`, odoc install, `@doc` with odoc warnings failing the
  step, then the reusable obj-magic workflow from `winterchill-trading/infra`.
- This repository pins no siblings; it is the root of the workspace dependency order.
- Concurrency is `cancel-in-progress: true`; push once per finished change.
- To check a run: one `gh run list --limit 1`, then at most one `gh run watch <id>
  --exit-status`. Never poll.
