# 🛠️ Docker Tools Container

[![Docker Publish](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/tools)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/tools)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Base: Alpine](https://img.shields.io/badge/Base-Alpine-brightgreen.svg)](https://alpinelinux.org)

A lightweight, multi-tool Docker image for:

- ✅ SSL automation (`mkcert` + `certify`)
- ✅ Interactive vhost generation (`mkhost`) + templates
- ✅ SOPS/Age encrypted env workflow (`senv`)
- ✅ Host notifications pipeline (`notifierd` + `notify` + host `docknotify`)
- ✅ Docker ops + TUI (`docker-cli` + compose + `lazydocker`)
- ✅ Network diagnostics (`netx`, `dig`, `mtr`, `traceroute`, `nmap`, etc.)
- ✅ Daily dev/ops utilities (`git`, `jq`, `yq`, `rg`, `fd`, `sqlite`, `shellcheck`, `nano`, etc.)

---

## 📦 Available on Registries

| Registry         | Image Name                 |
|------------------|----------------------------|
| Docker Hub       | `docker.io/infocyph/tools` |
| GitHub Container | `ghcr.io/infocyph/tools`   |

---

## 🚀 Features (what’s included)

### 1) SSL + local CA automation
- `mkcert` bundled (downloaded during build)
- `certify` scans vhosts under `/etc/share/vhosts/**` and generates:
  - Apache server/client certs
  - Nginx server/proxy/client certs (includes `.p12` for Nginx client)
- Wildcards are auto-added from filenames (`example.com.conf` → `example.com` + `*.example.com`)
- Always includes: `localhost`, `127.0.0.1`, `::1`
- Stable CA root via `CAROOT=/etc/share/rootCA`

### 2) Interactive vhost generator + templates
- `mkhost` (interactive) generates Nginx/Apache vhost configs using shipped templates under `/etc/http-templates/`
- Uses runtime-versions DB baked during build:
  - `/etc/share/runtime-versions.json` (override via `RUNTIME_VERSIONS_DB`)
- Supports helper flags to query/reset internal “active” selections (`ACTIVE_PHP_PROFILE`, `APACHE_ACTIVE`, `RESET`)

### 3) SOPS/Age encrypted env workflow (Model B)
- `age` + `sops` installed
- `senv` provides a clean workflow around `.env` ↔ `.env.enc`
- Designed to support:
  - repo-local config `./.sops.yaml` (highest priority)
  - global fallback config/key under `/etc/share/sops` (mountable)
  - multi-project keys (per-repo)

### 4) Host notifications pipeline
- `notifierd` listens on TCP (default `9901`) and emits a stable single-line event to stdout using a prefix (default `__HOST_NOTIFY__`)
- `notify` sends events into `notifierd` (inside container)
- Host can watch formatted events and show popups
- Optional host-side sender `docknotify` can push events to the container from the host

### 5) Docker debugging + TUI
- `docker-cli` + `docker-cli-compose`
- `lazydocker` bundled (mount the docker socket)

### 6) Network & diagnostics toolbox
- `netx` (Toolset wrapper)
- `curl`, `wget`, `ping`, `nc` (netcat)
- `dig` / `nslookup` (bind-tools)
- `iproute2`, `traceroute`, `mtr`
- `nmap`

### 7) Daily dev/ops utilities
- `git` + `gitx` (Toolset)
- `jq`, `yq`
- `ripgrep (rg)`, `fd`
- `sqlite` + `sqlitex` (Toolset)
- `shellcheck`
- `zip`, `unzip`, `tree`, `ncdu`
- Default editor UX:
  - `nano` is default `EDITOR` and `VISUAL`
  - `/etc/nanorc` is configured to load syntax rules when available
- `chromacat`, `figlet`, `show-banner` shell hook

---

## 🧰 Included commands

| Command | Purpose |
|---|---|
| `mkcert` | Local CA + trusted TLS certificates |
| `certify` | Scan vhosts and generate server/client certs |
| `mkhost` | Generate Nginx/Apache vhost configs from templates |
| `delhost` | Remove generated vhost configs (cleanup helper) |
| `senv` | SOPS/Age workflow for `.env` + `.env.enc` |
| `lazydocker` | Docker TUI (requires docker socket) |
| `notify` | Send notification to `notifierd` |
| `notifierd` | TCP → stdout bridge (for host watchers) |
| `gitx` | Git helper CLI |
| `chromacat` | Colorized output |
| `sqlitex` | SQLite helper CLI |
| `netx` | Networking helper wrapper |

---

## 📂 Directory layout (recommended)

This repo is designed so you can keep **all generated + persistent artifacts** in a single `configuration/` folder, and mount them into the container.

> Rule of thumb:
> - Mount **RW** if the container should generate/update files there (`certify`, `mkhost`, `senv init/keygen`).
> - Mount **RO** if you want “consume only” behavior (good for shared secrets repo).

### ✅ Suggested structure

```

.
├─ configuration/
│  ├─ apache/               # Generated/managed Apache vhosts (*.conf)
│  ├─ nginx/                # Generated/managed Nginx vhosts (*.conf)
│  ├─ ssl/                  # Generated certificates (.pem, .p12, keys)
│  ├─ rootCA/               # mkcert CA store (persist across rebuilds)
│  └─ sops/                 # Global SOPS Model B (persisted)
│     ├─ age.keys           # Global Age key (fallback)
│     ├─ .sops.yaml         # Global fallback config (created by senv init if writable)
│     ├─ keys/              # Per-project keys
│     │  ├─ projectA.age.keys
│     │  └─ projectB.age.keys
│     └─ config/            # Optional per-project configs
│        ├─ projectA.sops.yaml
│        └─ projectB.sops.yaml
│
├─ secrets-repo/            # Optional shared encrypted env store (usually RO mount)
│  ├─ projectA/
│  │  └─ .env.enc
│  └─ projectB/
│     └─ prod/.env.enc
│
└─ docker-compose.yml

````

### 🔗 Container mount mapping

| Host path | Container path | RW/RO | Used by |
|---|---|---:|---|
| `./configuration/apache` | `/etc/share/vhosts/apache` | RW | `mkhost`, `certify` |
| `./configuration/nginx` | `/etc/share/vhosts/nginx` | RW | `mkhost`, `certify` |
| `./configuration/ssl` | `/etc/mkcert` | RW | `certify`, `mkcert` |
| `./configuration/rootCA` | `/etc/share/rootCA` | RW | `mkcert` (CA store) |
| `./configuration/sops` | `/etc/share/sops` | RW | `senv init`, `senv keygen`, `senv enc/dec/edit` |
| `./secrets-repo` | `/etc/share/vhosts/sops` | RO | `senv dec --in=...` (alias input source) |
| `/var/run/docker.sock` | `/var/run/docker.sock` | RW | `docker`, `lazydocker` |

### 🧠 How `senv` uses this layout

- **Config priority**
  1. `./.sops.yaml` (repo-local)
  2. `/etc/share/sops/config/<project>.sops.yaml` (optional)
  3. `/etc/share/sops/.sops.yaml` (global fallback)

- **Key selection (Model B)**
  - `--key <path>` / `SOPS_AGE_KEY_FILE=<path>` (explicit)
  - `/etc/share/sops/keys/<project>.age.keys` (project)
  - `/etc/share/sops/age.keys` (global fallback)

- **Shared encrypted env repo**
  - If you pass `--in=demo.env.enc` (no `/`, no `./`), it resolves to:
    `/etc/share/vhosts/sops/demo.env.enc`
  - If `--out` is omitted, output defaults to **current directory**.

---

## 📁 Important mount points (stable paths)

### Vhosts
- `/etc/share/vhosts/nginx`   → generated Nginx vhosts
- `/etc/share/vhosts/apache`  → generated Apache vhosts
- `/etc/http-templates`       → shipped templates used by `mkhost`

### Certificates & CA
- `/etc/mkcert`          → certificate output (mount RW)
- `/etc/share/rootCA`    → CA root store (mount RW)
- `CAROOT=/etc/share/rootCA`

### SOPS/Age (recommended)
Mount a single directory from host for persistence:
- `/etc/share/sops`      → global keys + fallback config (mount RW)

Optional “shared encrypted env repo” input mount:
- `/etc/share/vhosts/sops` → read-only store of encrypted env files shared across repos (mount RO)

---

## 📦 Docker Compose example

```yaml
services:
  tools:
    image: infocyph/tools:latest
    container_name: docker-tools
    volumes:
      # vhosts (read-only ok, mkhost needs RW if you generate inside container)
      - ./configuration/apache:/etc/share/vhosts/apache
      - ./configuration/nginx:/etc/share/vhosts/nginx

      # certificates + CA (RW)
      - ./configuration/ssl:/etc/mkcert
      - ./configuration/rootCA:/etc/share/rootCA

      # sops global (RW, persists keys/configs)
      - ./configuration/sops:/etc/share/sops

      # optional: shared encrypted env repo (RO)
      - ./secrets-repo:/etc/share/vhosts/sops:ro

      # docker tooling
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
  -v "$(pwd)/configuration/apache:/etc/share/vhosts/apache" \
  -v "$(pwd)/configuration/nginx:/etc/share/vhosts/nginx" \
  -v "$(pwd)/configuration/ssl:/etc/mkcert" \
  -v "$(pwd)/configuration/rootCA:/etc/share/rootCA" \
  -v "$(pwd)/configuration/sops:/etc/share/sops" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  infocyph/tools:latest
```

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
| ------------------------ | ------------------------------------------ |
| `test.local.conf`        | `test.local`, `*.test.local`               |
| `example.com.conf`       | `example.com`, `*.example.com`             |
| `internal.dev.site.conf` | `internal.dev.site`, `*.internal.dev.site` |

---

## 🔐 Generated cert files

All certs are written to `/etc/mkcert`.

| Certificate Type | Files Generated                                                |
| ---------------- | -------------------------------------------------------------- |
| Apache (Server)  | `apache-server.pem`, `apache-server-key.pem`                   |
| Apache (Client)  | `apache-client.pem`, `apache-client-key.pem`                   |
| Nginx (Server)   | `nginx-server.pem`, `nginx-server-key.pem`                     |
| Nginx (Proxy)    | `nginx-proxy.pem`, `nginx-proxy-key.pem`                       |
| Nginx (Client)   | `nginx-client.pem`, `nginx-client-key.pem`, `nginx-client.p12` |

---

## 🧩 mkhost (interactive vhost generator)

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

## 🔐 senv (SOPS/Age env workflow)

### Design goals

* Works from `docker exec` in any mounted project directory.
* Prefer repo-local config: `./.sops.yaml` (highest priority).
* Otherwise use global fallback config under `/etc/share/sops` (mountable).
* Supports “shared encrypted env repo” mounted at `/etc/share/vhosts/sops`:

    * `--in=demo.env.enc` resolves to `/etc/share/vhosts/sops/demo.env.enc`
    * if `--out` is not specified, output defaults to the current working directory

### Typical usage

Initialize (creates missing defaults only when writable/mounted):

```bash
senv init
```

Initialize repo-local config in current directory:

```bash
senv init --local
```

Local-only init (does not touch `/etc/share/sops`):

```bash
senv init --local-only
```

Status / info:

```bash
senv info
```

Generate key explicitly:

```bash
senv keygen --project projectA
```

Open the selected config in nano:

```bash
senv config --project projectA
```

Encrypt / decrypt (defaults):

```bash
senv enc          # .env -> .env.enc
senv dec          # .env.enc -> .env
senv edit         # edit .env.enc using sops editor mode
```

Explicit input/output:

```bash
senv enc --in=./.env --out=./.env.enc
senv dec --in=./.env.enc --out=./.env
```

Use “shared encrypted env repo” as input source:

```bash
# reads from /etc/share/vhosts/sops/demo.env.enc
# writes to ./demo.env (unless --out is set)
senv dec --in=demo.env.enc

# nested path inside the shared repo
senv dec --in=projectA/prod/.env.enc --out=./.env
```

Push/Pull sugar (shared encrypted repo):

```bash
# pull /etc/share/vhosts/sops/<project>/.env.enc -> ./.env
senv pull --project projectA

# push ./.env -> /etc/share/vhosts/sops/<project>/.env.enc
senv push --project projectA
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

## 🖥️ Host sender: `docknotify`

A host-side companion that sends notifications to the tools `notifierd` service using a stable one-line TCP protocol.

**Protocol (tab-separated):** `token  timeout  urgency  source  title  body`

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
docknotify -H docker-tools -p 9901 -t 2500 -u normal -s host "Deploy" "Finished"
```

> Requirement: `nc` must exist on the machine running `docknotify`.

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
      title = a[5]
      body = a[6]
      for (i = 7; i <= n; i++) body = body "\t" a[i]

      cmd = "command -v notify-send >/dev/null 2>&1 && notify-send \"" shescape(title) "\" \"" shescape(body) "\""
      system(cmd)
      fflush()
    }
  }
'
```

> If you changed `NOTIFY_PREFIX`, replace `__HOST_NOTIFY__` in the commands.

---

## 🌍 Environment variables (tools container)

| Variable              | Default                            | Description                          |
| --------------------- | ---------------------------------- | ------------------------------------ |
| `TZ`                  | (empty)                            | Timezone                             |
| `CAROOT`              | `/etc/share/rootCA`                | mkcert CA root directory             |
| `RUNTIME_VERSIONS_DB` | `/etc/share/runtime-versions.json` | runtime versions DB used by `mkhost` |
| `EDITOR` / `VISUAL`   | `nano`                             | default editor                       |
| `NOTIFY_TCP_PORT`     | `9901`                             | notifier TCP port                    |
| `NOTIFY_FIFO`         | `/run/notify.fifo`                 | internal FIFO path                   |
| `NOTIFY_PREFIX`       | `__HOST_NOTIFY__`                  | stdout prefix                        |
| `NOTIFY_TOKEN`        | (empty)                            | optional token auth                  |
| `SOPS_BASE_DIR`       | `/etc/share/sops`                  | global SOPS base directory           |
| `SOPS_KEYS_DIR`       | `/etc/share/sops/keys`             | per-project keys directory           |
| `SOPS_CFG_DIR`        | `/etc/share/sops/config`           | per-project config directory         |
| `SOPS_REPO_DIR`       | `/etc/share/vhosts/sops`           | shared encrypted env repo mount      |

---

## 🐳 Lazydocker

```bash
docker exec -it docker-tools lazydocker
```

Make sure `/var/run/docker.sock` is mounted.

---

## 📝 License

Licensed under the [MIT License](LICENSE)
© infocyph
