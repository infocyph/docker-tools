# 🛠️ Docker Tools Container

[![Docker Publish](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/tools)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/tools)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Base: Alpine](https://img.shields.io/badge/Base-Alpine-brightgreen.svg)](https://alpinelinux.org)

A lightweight, multi-tool Docker image for **SSL automation**, **vhost generation**, **Docker diagnostics**, and **host notifications** — built for local development & debugging workflows.

---

## 📦 Available on Registries

| Registry         | Image Name                 |
|------------------|----------------------------|
| Docker Hub       | `docker.io/infocyph/tools` |
| GitHub Container | `ghcr.io/infocyph/tools`   |

---

## 🚀 Features

- Alpine-based toolbox image (multi-stage build fetches `mkcert` + `lazydocker`)
- Auto-generates trusted local certificates via [`mkcert`](https://github.com/FiloSottile/mkcert)
- Server + client cert generation (includes `.p12` for Nginx client)
- Wildcard domains auto-added by scanning `/etc/share/vhosts/**.conf`
- Includes: `curl`, `wget`, `git`, `openssl`, `nmap`, `jq`, `tree`, `ncdu`, `sqlite`, `socat`, etc.
- Docker TUI via [`lazydocker`](https://github.com/jesseduffield/lazydocker) (mount Docker socket)
- Interactive vhost generator: `mkhost` (Nginx/Apache templates)
- Notifications: `notifierd` (TCP listener) + `notify` (sender)

---

## 🧰 Preinstalled utilities

| Tool         | Purpose |
|-------------|---------|
| `mkcert`     | Local CA + trusted TLS certificates |
| `certify`    | Scan vhosts and generate server/client certs |
| `mkhost`     | Generate Nginx/Apache vhost configs from templates |
| `lazydocker` | Docker TUI (requires docker socket) |
| `notify`     | Send notification to `notifierd` |
| `notifierd`  | TCP → stdout bridge (for host watchers) |
| `gitx`       | Git helper CLI |
| `chromacat`  | Colorized output |
| `sqlitex`    | SQLite helper CLI |

---

## 🔧 Certificate automation (certify)

On container startup, the entrypoint runs `certify` (best-effort). It:

1. Scans all `*.conf` under `/etc/share/vhosts/**`
2. Extracts domains from filenames (basename without `.conf`)
3. Adds wildcard variants automatically (`*.domain`)
4. Always includes: `localhost`, `127.0.0.1`, `::1`
5. Generates server and client certificates using `mkcert`

### 📁 Domain detection by filename

| File name                | Domains generated                          |
|--------------------------|--------------------------------------------|
| `test.local.conf`        | `test.local`, `*.test.local`               |
| `example.com.conf`       | `example.com`, `*.example.com`             |
| `internal.dev.site.conf` | `internal.dev.site`, `*.internal.dev.site` |

---

## 🔐 Generated cert files

All certs are written to `/etc/mkcert`.

| Certificate Type | Files Generated |
|------------------|-----------------|
| Apache (Server)  | `apache-server.pem`, `apache-server-key.pem` |
| Apache (Client)  | `apache-client.pem`, `apache-client-key.pem` |
| Nginx (Server)   | `nginx-server.pem`, `nginx-server-key.pem` |
| Nginx (Proxy)    | `nginx-proxy.pem`, `nginx-proxy-key.pem` |
| Nginx (Client)   | `nginx-client.pem`, `nginx-client-key.pem`, `nginx-client.p12` |

---

## 📦 Docker Compose example

```yaml
services:
  tools:
    image: infocyph/tools:latest
    container_name: docker-tools
    volumes:
      - ../../configuration/apache:/etc/share/vhosts/apache:ro
      - ../../configuration/nginx:/etc/share/vhosts/nginx:ro
      - ../../configuration/ssl:/etc/mkcert
      - ../../configuration/rootCA:/etc/share/rootCA
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ=Asia/Dhaka
      # - NOTIFY_TCP_PORT=9901
      # - NOTIFY_PREFIX=__HOST_NOTIFY__
      # - NOTIFY_TOKEN=
````

Use as:

* one-shot cert generator: `docker run --rm ... infocyph/tools certify`
* long-lived utility box: default CMD runs `notifierd`

---

## ▶️ Manual run

```bash
docker run --rm -it \
  -v $(pwd)/configuration/apache:/etc/share/vhosts/apache:ro \
  -v $(pwd)/configuration/nginx:/etc/share/vhosts/nginx:ro \
  -v $(pwd)/configuration/ssl:/etc/mkcert \
  -v $(pwd)/configuration/rootCA:/etc/share/rootCA \
  -v /var/run/docker.sock:/var/run/docker.sock \
  infocyph/tools:latest
```

---

## 🧩 `mkhost` (interactive vhost generator)

```bash
docker exec -it docker-tools mkhost
```

Writes configs into:

* `/etc/share/vhosts/nginx/<domain>.conf`
* `/etc/share/vhosts/apache/<domain>.conf`

Helpers:

```bash
docker exec docker-tools mkhost --ACTIVE_PHP_PROFILE
docker exec docker-tools mkhost --APACHE_ACTIVE
docker exec docker-tools mkhost --RESET
```

---

## 🔔 Notifications

### Server: `notifierd`

`notifierd` listens on TCP (default `9901`) and emits a single-line event to stdout with a fixed prefix (default `__HOST_NOTIFY__`).

### Client: `notify` (inside the tools container)

```bash
notify "Build done" "All services are healthy ✅"
```

With options:

```bash
notify -H 127.0.0.1 -p 9901 -t 2500 -u normal -s api "Deploy" "Finished"
```

---

## 🖥️ Host sender: `docknotify.sh`

A host-side companion that sends notifications to the tools `notifierd` service using a stable one-line TCP protocol:

**Protocol (tab-separated):** `token  timeout  urgency  source  title  body` ([GitHub][1])

### Install on host

```bash
sudo curl -fsSL \
  "https://raw.githubusercontent.com/infocyph/Scriptomatic/refs/heads/main/bash/docknotify.sh" \
  -o /usr/local/bin/docknotify \
  && sudo chmod +x /usr/local/bin/docknotify
```

### Usage

```bash
docknotify "Build done" "All services are healthy ✅"
```

Options:

```bash
docknotify -H SERVER_TOOLS -p 9901 -t 2500 -u normal -s host "Deploy" "Finished"
```

> Requirement: `nc` must exist on the machine running `docknotify`. ([GitHub][1])

---

## 📟 Tail docker logs (formatted watcher)

If your container name is `docker-tools` and prefix is `__HOST_NOTIFY__`, this prints formatted events:

```bash
docker logs -f docker-tools 2>/dev/null | awk -v p="__HOST_NOTIFY__" '
  index($0, p) == 1 {
    line = $0
    sub("^" p "[ \t]*", "", line)

    n = split(line, a, "\t")
    if (n >= 6) {
      token = a[1]
      timeout = a[2]
      urgency = a[3]
      source = a[4]
      title = a[5]

      body = a[6]
      for (i = 7; i <= n; i++) body = body "\t" a[i]

      printf("[%-8s][%s] %s — %s\n", urgency, source, title, body)
    } else {
      print line
    }
    fflush()
  }
'
```

### Linux desktop popup (optional)

If your host has `notify-send`:

```bash
docker logs -f docker-tools 2>/dev/null | awk -v p="__HOST_NOTIFY__" '
  function shescape(s) { gsub(/["\\]/, "\\\\&", s); return s }
  index($0, p) == 1 {
    line = $0
    sub("^" p "[ \t]*", "", line)

    n = split(line, a, "\t")
    if (n >= 6) {
      urgency = a[3]
      source  = a[4]
      title   = a[5]

      body = a[6]
      for (i = 7; i <= n; i++) body = body "\t" a[i]

      cmd = "command -v notify-send >/dev/null 2>&1 && notify-send \"" shescape(title) "\" \"" shescape(body) "\""
      system(cmd)
      printf("[%-8s][%s] %s — %s\n", urgency, source, title, body)
      fflush()
    }
  }
'
```

> If you changed `NOTIFY_PREFIX`, replace `__HOST_NOTIFY__` in the commands.

---

## 🌍 Environment variables (tools container)

| Variable           | Default             | Description              |
| ------------------ | ------------------- | ------------------------ |
| `TZ`               | (empty)             | Timezone                 |
| `CAROOT`           | `/etc/share/rootCA` | mkcert CA root directory |
| `NOTIFY_TCP_PORT`  | `9901`              | notifier TCP port        |
| `NOTIFY_FIFO`      | `/run/notify.fifo`  | internal FIFO path       |
| `NOTIFY_PREFIX`    | `__HOST_NOTIFY__`   | stdout prefix            |
| `NOTIFY_TOKEN`     | (empty)             | optional token auth      |
| `NOTIFY_TITLE_MAX` | `100`               | title clamp              |
| `NOTIFY_BODY_MAX`  | `300`               | body clamp               |

---

## 🐳 Lazydocker

```bash
docker exec -it docker-tools lazydocker
```

Make sure `/var/run/docker.sock` is mounted.

---

## 📝 License

Licensed under the [MIT License](LICENSE)
© [infocyph, abmmhasan](https://github.com/infocyph)

---

## 💬 Feedback / Issues

Found a bug or want a feature?
Open an issue or start a discussion in the GitHub repo.
