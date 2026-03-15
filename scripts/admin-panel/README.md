# Admin Panel (Scaffold)

Bootstrap-based admin shell aligned to:

https://vue-demo.tailadmin.com/

## Structure

- `index.php` entry file
- `router.php` PHP built-in server router
- `app/bootstrap.php` namespace autoloader
- `app/index.php` app kernel entry
- `app/pages/*` layout and dashboard view
- `src/*` namespaced routing/http/kernel classes
- `public/css/core.css` minified compiled core stylesheet (TailAdmin baseline)
- `public/css/panel.css` theme and component styles
- `public/js/core.js` minified compiled core script bundle (TailAdmin baseline)
- `public/js/panel.js` UI interactions (theme, sidebar, meters)

## Run locally

```bash
cd scripts/admin-panel
php -S 0.0.0.0:9920 -t . router.php
```

Open:

`http://localhost:9920`

Additional routes:

- `http://localhost:9920/logs`
- `http://localhost:9920/docker-logs`
- `http://localhost:9920/db-health`
- `http://localhost:9920/queue-health`
- `http://localhost:9920/slo-view`
- `http://localhost:9920/log-heatmap`
- `http://localhost:9920/drift-monitor`
- `http://localhost:9920/synthetic-flows`
- `http://localhost:9920/tls-monitor`
- `http://localhost:9920/runtime-watch`
- `http://localhost:9920/volume-monitor`
- `http://localhost:9920/alerts`
- `http://localhost:9920/live-stats`

AJAX data endpoint:

- `http://localhost:9920/api/live-stats` (powered by full `status --json` payload)
  - Includes `core`, `sections`, `checks`, and derived summary fields.
- `http://localhost:9920/api/docker-logs` (service-grouped container logs; supports `service`, `since`, `grep`, `tail`)
- `http://localhost:9920/api/db-health` (DB/Redis runtime checks; supports `engine`)
- `http://localhost:9920/api/queue-health` (queue/cron checks; supports `since`, `pending_threshold`, `heartbeat_stale_sec`)
- `http://localhost:9920/api/slo-view` (error budget/SLO metrics; supports `timeout`, `paths`)
- `http://localhost:9920/api/log-heatmap` (error signatures by service/time bucket; supports `since`, `bucket_min`, `top`, `line_limit`)
- `http://localhost:9920/api/drift-monitor` (generated vs active config drift)
- `http://localhost:9920/api/synthetic-flows` (synthetic route probes; supports `domain`, `paths`, `timeout`)
- `http://localhost:9920/api/tls-monitor` (TLS/mTLS checks with policy/posture/trend; supports `domain` partial/wildcard, `timeout`, `retries`)
- `http://localhost:9920/api/runtime-watch` (restart/OOM/event monitor; supports `since`, `restart_threshold`, `event_limit`)
- `http://localhost:9920/api/volume-monitor` (volume growth/inode monitor; returns all project volumes, with backend safety cap)
- `http://localhost:9920/api/alerts` (alert rules + quiet hours + dedupe + acknowledgement; supports `run`, `ack_rule`, `ack_fingerprint`)

## Notes

- Current data in dashboard cards/tables/charts is placeholder seed data.
- Live Stats page is wired to `status --json` via `/api/live-stats`.
- Live Stats includes both structured widgets and a full raw JSON viewer.
- Next step is wiring additional LDS sources such as `profile-chooser` and `env-store`.
- TLS monitor policy sources:
  - Nginx host config (`ssl_verify_client`) with optional markers: `ap_tls_expected_mtls`, `ap_tls_min_days`, `ap_tls_san_strict`.
  - Optional policy file: `/etc/share/state/tls-monitor-policy.tsv` using `pattern|expected_mtls|min_days|san_strict`.
