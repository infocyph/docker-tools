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
- `http://localhost:9920/live-stats`

AJAX data endpoint:

- `http://localhost:9920/api/live-stats` (powered by full `status --json` payload)
  - Includes `core`, `sections`, `checks`, and derived summary fields.
- `http://localhost:9920/api/docker-logs` (service-grouped container logs; supports `service`, `since`, `grep`, `tail`)

## Notes

- Current data in dashboard cards/tables/charts is placeholder seed data.
- Live Stats page is wired to `status --json` via `/api/live-stats`.
- Live Stats includes both structured widgets and a full raw JSON viewer.
- Next step is wiring additional LDS sources such as `profile-chooser` and `env-store`.
