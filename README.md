# 🛠️ Docker Tools Container

[![Docker Publish](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/tools)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/tools)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Base: Alpine](https://img.shields.io/badge/Base-Alpine-brightgreen.svg)](https://alpinelinux.org)

A lightweight, multi-tool Docker image for:

- ✅ SSL automation (`mkcert` + `certify`)
- ✅ Interactive vhost generation (`mkhost`) + templates
- ✅ Cleanup vhosts (`rmhost`)
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
- `mkcert` bundled
- `certify` scans vhosts under `/etc/share/vhosts/**` and generates:
  - Apache server/client certs
  - Nginx server/proxy/client certs (includes `.p12` for Nginx client)
- Wildcards are auto-added from filenames (`example.com.conf` → `example.com` + `*.example.com`)
- Always includes: `localhost`, `127.0.0.1`, `::1`
- Stable CA root via `CAROOT=/etc/share/rootCA`

### 2) Interactive vhost generator + templates
- `mkhost` generates Nginx/Apache vhost configs using predefined templates
- Uses runtime-versions DB baked during build:
  - `/etc/share/runtime-versions.json` (override via `RUNTIME_VERSIONS_DB`)
- Supports helper flags to query/reset internal “active” selections (`ACTIVE_PHP_PROFILE`, `ACTIVE_NODE_PROFILE`, `APACHE_ACTIVE`)

### 3) SOPS/Age encrypted env workflow (Model B)
- `age` + `sops` installed
- `senv` provides a clean workflow around `.env` ↔ `.env.enc`
- Supports:
  - repo-local config `./.sops.yaml` (highest priority)
  - global fallback config/key under `/etc/share/sops/global` (mountable; back-compat: `/etc/share/sops/*`)
  - multi-project keys (per-repo) + “shared encrypted env repo” input mount

### 4) Host notifications pipeline
- `notifierd` listens on TCP (default `9901`) and emits a stable single-line event to stdout using a prefix (default `__HOST_NOTIFY__`)
- `notify` sends events into `notifierd` (inside container)
- Host can watch formatted events and show popups
- Optional host-side sender `docknotify` can push events to the container from the host

### 5) Docker debugging + TUI
- `docker-cli` + compose
- `lazydocker` bundled (mount the docker socket)

### 6) Network & diagnostics toolbox
- `netx` (Toolset wrapper)
- `curl`, `wget`, `ping`, `nc`
- `dig`/`nslookup` (bind-tools)
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
| `mkhost` | Generate vhost configs (Nginx/Apache) + optional Node compose |
| `rmhost` | Remove vhost configs for domain(s) (Nginx/Apache/Node yaml) |
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
│  └─ sops/                 # Global SOPS (Model B; persisted)
│     ├─ global/            # Global fallback key + config (preferred)
│     │  ├─ age.keys
│     │  └─ .sops.yaml
│     ├─ keys/              # Per-project keys (recommended)
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

> Back-compat: if your `configuration/sops` already contains `age.keys` and/or `.sops.yaml` at the top level, `senv` will still detect/use them. New defaults are created under `configuration/sops/global/`.

### 🔗 Container mount mapping

| Host path | Container path |Used by |
|---|---|---|
| `./configuration/apache` | `/etc/share/vhosts/apache` | `mkhost`, `certify` |
| `./configuration/nginx` | `/etc/share/vhosts/nginx` |`mkhost`, `certify` |
| `./configuration/ssl` | `/etc/mkcert` |  `certify`, `mkcert` |
| `./configuration/rootCA` | `/etc/share/rootCA` |  `mkcert` (CA store) |
| `./configuration/sops` | `/etc/share/sops` | `senv init`, `senv keygen`, `senv enc/dec/edit` |
| `./secrets-repo` | `/etc/share/vhosts/sops` |  `senv dec --in=...` (alias input source) |
| `/var/run/docker.sock` | `/var/run/docker.sock` |  `docker`, `lazydocker` |

---

## 📦 Docker Compose example

```yaml
services:
  tools:
    image: infocyph/tools:latest
    container_name: docker-tools
    volumes:
      - ./configuration/apache:/etc/share/vhosts/apache
      - ./configuration/nginx:/etc/share/vhosts/nginx

      - ./configuration/ssl:/etc/mkcert
      - ./configuration/rootCA:/etc/share/rootCA

      - ./configuration/sops:/etc/share/sops
      - ./secrets-repo:/etc/share/vhosts/sops:ro

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

`mkhost` is your “domain setup wizard”. It generates:

* Nginx vhost: `/etc/share/vhosts/nginx/<domain>.conf`
* Apache vhost (only if you choose Apache): `/etc/share/vhosts/apache/<domain>.conf`
* Node service yaml (only if you choose Node): `/etc/share/vhosts/node/<token>.yaml`

Run it:

```bash
docker exec -it docker-tools mkhost
```

### What it asks (flow)

It runs a guided 9-step flow (slightly different for PHP vs Node):

* Domain name (validated)
* App type: **PHP** or **Node**
* Server type (PHP only): **Nginx** or **Apache**

    * Node always uses **Nginx proxy mode**
* HTTP / HTTPS mode (keep HTTP, redirect, or HTTPS)
* Document root (`/app/<path>`)
* Client body size
* Runtime version selection:

    * PHP: choose PHP version/profile
    * Node: choose Node version + optional run command
* If HTTPS: optional client certificate verification (mutual TLS)

### HTTPS + certificates

If you enable HTTPS, `mkhost` triggers `certify` automatically so the required certs exist.

### Helpful flags

`mkhost` stores the “active selections” into env (used by your `server` wrapper to enable compose profiles).
You can query/reset these values:

```bash
mkhost --RESET
mkhost --ACTIVE_PHP_PROFILE
mkhost --ACTIVE_NODE_PROFILE
mkhost --APACHE_ACTIVE
```

* `--RESET` clears all active selections.
* `--ACTIVE_PHP_PROFILE` prints the chosen PHP profile (if PHP was selected).
* `--ACTIVE_NODE_PROFILE` prints the chosen Node profile (if Node was selected).
* `--APACHE_ACTIVE` prints `apache` when Apache mode was selected.

---

## 🧹 rmhost (remove vhost configs)

`rmhost` deletes the generated files for a domain:

* `/etc/share/vhosts/nginx/<domain>.conf`
* `/etc/share/vhosts/apache/<domain>.conf`
* `/etc/share/vhosts/node/<token>.yaml` (token is a safe slug of the domain)

Run it:

```bash
docker exec -it docker-tools rmhost example.com
```

Multiple domains (batch plan + single confirmation):

```bash
docker exec -it docker-tools rmhost a.localhost b.localhost api.example.com
```

Interactive mode (no args):

```bash
docker exec -it docker-tools rmhost
```

Behavior:

* Validates the domain format before deleting
* Shows exactly what files it will remove
* Requires confirmation (`y/N`) — in multi-domain mode it asks **once** for the full plan
* If nothing exists for that domain, it exits with code `2` (useful for scripts)

---

## 🔐 senv (SOPS/Age env workflow)

`senv` wraps **SOPS + Age** for a predictable `.env` ⇄ `.env.enc` workflow, with:

- **Repo-local config**: `./.sops.yaml` (highest priority)
- **Global defaults**: `/etc/share/sops/global/{age.keys,.sops.yaml}` (preferred)
- **Model B multi-project keys**: per-project keys under `/etc/share/sops/keys/`
- **Shared encrypted env repo mount**: `/etc/share/vhosts/sops` for sourcing/storing encrypted envs

### Key selection order

`senv` chooses the Age key in this order:

1. `--key <path>` or `SOPS_AGE_KEY_FILE=<path>`
2. `--project <id>` → `/etc/share/sops/keys/<id>.age.keys`
3. Global fallback (preferred) → `/etc/share/sops/global/age.keys`
4. Back-compat fallback (if present) → `/etc/share/sops/age.keys`

### Config selection order

`senv` chooses the SOPS config in this order:

1. Repo-local → `./.sops.yaml`
2. Project config (optional) → `/etc/share/sops/config/<id>.sops.yaml`
3. Global fallback (preferred) → `/etc/share/sops/global/.sops.yaml`
4. Back-compat fallback (if present) → `/etc/share/sops/.sops.yaml`
5. Override: `SOPS_CONFIG_FILE=/path/to/.sops.yaml`

### Writes & permissions

`senv init` / `senv keygen` will only create files under `/etc/share/sops/**` when:

- the container user is **root**, and
- the target path is **writable** (not a read-only mount).

If you mount `/etc/share/sops` read-only, `senv` will operate in **consume-only** mode.

### Typical usage

Initialize (ensures missing global defaults + optional project config + key when writable):

```bash
senv init
```

Initialize and also create repo-local config in the current directory:

```bash
senv init --local
```

Local-only init (creates `./.sops.yaml` only; never touches `/etc/share/sops`):

```bash
senv init --local-only
```

Status / info:

```bash
senv info
```

Generate a per-project key (refuses to overwrite a real key):

```bash
senv keygen --project projectA
```

Open the effective config in nano:

```bash
senv config
```

Encrypt / decrypt (defaults):

```bash
senv enc          # .env -> .env.enc
senv dec          # .env.enc -> .env
senv edit         # edit .env.enc using sops editor mode
```

Explicit key / project selection:

```bash
senv enc --project projectA
senv dec --project projectA

senv enc --key ./keys/projectA.age.keys
```

### Shared encrypted env repo (alias input/output)

If `--in` / `--out` is **not** absolute (`/…`) and not `./…` / `../…`, it is treated as an alias under:

- `SOPS_REPO_DIR` (default `/etc/share/vhosts/sops`)

Examples:

```bash
# reads:  /etc/share/vhosts/sops/projectA/prod/.env.enc
# writes: ./.env
senv dec --in projectA/prod/.env.enc --out ./.env

# if --out is omitted, it writes to current directory by default
senv dec --in projectA/.env.enc
```

Push/Pull sugar (shared encrypted repo):

```bash
# pull /etc/share/vhosts/sops/<project>/.env.enc -> ./.env
senv pull --project projectA

# push ./.env -> /etc/share/vhosts/sops/<project>/.env.enc
senv push --project projectA
```

### Safe-path guard

By default `senv` restricts input/output paths to stay inside:

- current working directory
- `/etc/share/vhosts/sops`
- `/etc/share/sops`

To bypass (not recommended unless you know what you’re doing):

```bash
senv dec --unsafe --in /somewhere/file.env.enc --out /somewhere/file.env
```

---

## 🔔 Notifications


### Server: `notifierd`

`notifierd` listens on TCP (default `9901`) and emits a single-line event to stdout with a fixed prefix (default `__HOST_NOTIFY__`).

### Client: `notify` (inside the tools container)

```bash
notify "Build done" "All services are healthy ✅"
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

---

## 📟 Tail docker logs (formatted watcher)

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
| `SOPS_GLOBAL_DIR`    | `/etc/share/sops/global`           | global fallback key/config directory |
| `SOPS_CONFIG_FILE`   | (empty)                            | override global fallback .sops.yaml  |
| `SOPS_AGE_KEY_FILE`  | (empty)                            | override age key file path           |
| `SENV_PROJECT`       | (auto)                             | project id (auto-detected from git)  |
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
