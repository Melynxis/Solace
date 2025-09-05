# Solace (single-host)

- **Single host:** All Solace services run on the **Solace** machine.
- **Tmux scope:** Tmux is used **only** for Spirit **Creation** and **Modification** flows. Runtime spirits run as normal services.
- **Observability:** Prometheus/Grafana live on a separate Observability host. Solace exposes metrics; Observability scrapes/pulls.
- **Dirs**
  - `apps/ghostpaw-dashboard` — UI
  - `services/registry` — API for spirit records (+ /metrics)
  - `services/orchestrator` — tmux-based create/modify flows
  - `services/hooks` — stubs (Vigil/Mica/etc.)
  - `infra` — compose files (core + exporters)
  - `spirits` — per-spirit working dirs/specs
  - `docs` — current specs
  - `legacy` — archived refs (code/specs here supersede)
  - `logs`, `tmp` — runtime convenience

> Next steps will populate compose files, API skeletons, and scripts incrementally.
