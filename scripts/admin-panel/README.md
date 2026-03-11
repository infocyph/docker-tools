# Admin Panel (Scaffold)

Bootstrap-based admin shell aligned to:

- Priority 1: TailAdmin Analytics-style dashboard composition
- Priority 2: TailAdmin SaaS-style secondary widgets

## Structure

- `index.php` entry file
- `app/index.php` simple page router
- `app/pages/*` layout and dashboard view
- `public/css/panel.css` theme and component styles
- `public/js/panel.js` UI interactions (theme, sidebar, meters)

## Run locally

```bash
cd scripts/admin-panel
php -S 0.0.0.0:9920
```

Open:

`http://localhost:9920`

## Notes

- Current data in dashboard cards/tables/charts is placeholder seed data.
- Next step is wiring real LDS sources such as `status --json`, `profile-chooser`, and `env-store`.
