# 🛠️ Docker Tools Container

[![Docker Publish](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml)
![Docker Pulls](https://img.shields.io/docker/pulls/infocyph/tools)
![Docker Image Size](https://img.shields.io/docker/image-size/infocyph/tools)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Base: Alpine](https://img.shields.io/badge/Base-Alpine-brightgreen.svg)](https://alpinelinux.org)

LocalDevStack control-plane and developer toolbox image for:

- ✅ SSL automation (`mkcert` + `certify`)
- ✅ Interactive vhost generation (`mkhost`) + templates
- ✅ Cleanup vhosts (`rmhost`)
- ✅ SOPS/Age encrypted env workflow (`senv`)
- ✅ Host notifications pipeline (`notifierd` + `notify` + host `docknotify`)
- ✅ Docker ops + TUI (`docker-cli` + compose + `lazydocker`)
- ✅ Network diagnostics (`netx`, `dig`, `mtr`, `traceroute`, `nmap`, etc.)
- ✅ Daily dev/ops utilities (`git`, `jq`, `yq`, `rg`, `fd`, `sqlite`, `shellcheck`, `nano`, etc.)
- ✅ Privileged LocalDevStack admin panel routed through `https://admin.localhost`
- ✅ Optional local AI consumer commands (`askai`, `aiops`) backed by the selected local `llm` service (`llm-ollama` or `llm-fastflow`)

---

## 📦 Available on Registries

| Registry         | Image Name                 |
|------------------|----------------------------|
| Docker Hub       | `docker.io/infocyph/tools` |
| GitHub Container | `ghcr.io/infocyph/tools`   |

---

## 🚢 Release publication

Published GitHub releases are the immutable source for versioned images.

- A GitHub **release published** event builds from that exact release tag, publishes the same immutable tag plus `latest`, and refuses to overwrite an existing version tag.
- Scheduled/manual refreshes rebuild from the **latest published release source** and update `latest` only, allowing rolling inputs such as `alpine:latest`, mkcert, lazydocker, Toolset, and runtime metadata to refresh without mutating historical version tags.
- amd64 and arm64 release candidates are built and gated first; the final multi-architecture publish reuses those candidate caches rather than forcing another rolling-base pull.
- The exact published digest is then re-gated against the LocalDevStack compatibility contract before the workflow is considered successful.
- Docker Hub and GHCR receive the same multi-architecture image, BuildKit SBOM/provenance, and GitHub/Sigstore attestations.

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
- Stores runtime state in `env-store` (JSON), including helper query/reset flags (`APACHE_ACTIVE`)

### 3) SOPS/Age encrypted env workflow (Model B)
- `age` + `sops` installed
- `senv` provides a clean workflow around `.env` ↔ `.env.enc`
- Supports:
  - repo-local config `./.sops.yaml` (highest priority)
  - global fallback config/key under `/etc/share/sops/global` (mountable)
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
- `pandoc` for document conversion/structure workflows
- `magick` (ImageMagick) for JPEG/PNG/GIF/WebP and other image conversions exposed by installed delegates
- `ffmpeg` / `ffprobe` for audio/video transcoding, remuxing and stream inspection
- `sox` / `soxi` for audio processing, effects and audio inspection
- `mkvmerge`, `mkvinfo`, `mkvextract`, `mkvpropedit` for Matroska workflows
- `mediainfo` for container/stream metadata inspection
- `xvidcore` as explicit MPEG-4 Part 2/Xvid codec runtime support for FFmpeg
- Default editor UX:
  - `nano` is default `EDITOR` and `VISUAL`
  - `/etc/nanorc` is configured to load syntax rules when available
- `chromacat`, `figlet`, `show-banner` shell hook

### 8) LocalDevStack control plane + admin panel
- Admin panel remains deterministic first and is intended to be reached through the LocalDevStack Nginx route: `https://admin.localhost`
- Mutating/sensitive API actions use the stack-scoped admin authorization and same-origin boundary
- External commands are executed through the bounded PHP `ProcessRunner`
- Tools health checks only Tools-owned processes; Docker/database/AI availability does not make the container unhealthy
- Docker-socket operations are expected to stay scoped to the current Compose project rather than unrelated host containers

### 9) Optional local AI consumer
- `docker-tools` never embeds, starts, pulls, or stores Ollama models
- The active provider/runtime is either `docker-llm-ollama` or `docker-llm-fastflow`
- Container-to-container endpoint is resolved from `LDS_AI_RUNTIME`:
  - `npu` -> `http://llm-fastflow:11434/v1`
  - `cpu|nvidia|amd` -> `http://llm-ollama:11434/v1`
- User-facing endpoint remains Nginx-owned at `https://llm.localhost`
- `askai` provides direct prompt/file/stdin access with per-request `--think`, `--no-think`, and `--think-auto`
- `aiops` exposes the same per-request thinking switches for diagnostic/review analysis
- `LDS_AI_THINK` is the stack/container default; request-level switches override it, while `--think-auto` bypasses it and uses the provider/model default
- strict `askai --json` generation always disables thinking so reasoning cannot displace the required JSON payload
- the Admin AI Assistant exposes the same request-level thinking choice
- `gitx ai-commit` remains implemented by Toolset; docker-tools only forces its local Ollama mode and disables Gemini/cloud fallback
- when the active `llm` backend is FastFlow, current Toolset `gitx ai-commit` is not backend-compatible until Toolset gains a generic OpenAI provider
- AI output is advisory only and is never auto-executed

### 10) Deterministic document structure
- `docstruct` extracts Markdown/RST plus supported config/dependency-manifest structure without requiring an LLM
- RST gets a narrow deterministic Sphinx supplement for explicit targets, directives, `include`, `toctree`, and typed roles
- YAML/JSON/TOML/INI extraction records key hierarchy only; scalar values are not copied into the sidecar by default
- recognized Python pip manifests (`requirements*.txt`, `constraints*.txt`, and `requirements/*.txt`) are parsed deterministically; package names and include/constraint links are retained while credential-bearing option/direct-URL values are not copied
- local document links/includes/toctree targets are resolved mechanically when possible
- typed code-symbol references remain explicit and unresolved; Graphify already owns code AST extraction and any later reconciliation
- parser work is bounded by file/corpus/file-count/node-count/time limits

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
| `status` | Docker compose project status and diagnostics (`--json` supported) |
| `env-store` | JSON-backed key/value store for runtime state (`jq` managed) |
| `profile-chooser` | Interactive profile+env collector for host-side compose flush |
| `domain-which` | Resolve app/container/profile/docroot for a domain (supports `--json`) |
| `es-policy` | Bootstrap/update Elasticsearch ILM + templates + Kibana data views |
| `gitx` | Git helper CLI; AI commit mode is pinned to local Ollama when enabled |
| `docstruct` | Deterministic Markdown/RST/config/Python-requirements structural extractor |
| `askai` | Direct optional local-LLM client with file/stdin/JSON/stream support |
| `aiops` | Bounded AI explanations for stack diagnostics, troubleshooting, review, and Graphify output |
| `chromacat` | Colorized output |
| `sqlitex` | SQLite helper CLI |
| `netx` | Networking helper wrapper |
| `composer` | PHP dependency manager |

---

## 📚 Deterministic document structure

`docstruct` creates a versioned `docker-tools.docstruct/v1` JSON sidecar without contacting an LLM.

```bash
docstruct README.md
docstruct docs/
docstruct docs/ --include '*.md' --include '*.rst'
docstruct docs/ --exclude 'generated/*' --output /tmp/docstruct.json
docstruct docs/ --no-gitignore --compact
```

Optional semantic review remains separate and additive:

```bash
docstruct docs/ --output /tmp/docstruct.json
aiops document-review --file /tmp/docstruct.json > /tmp/docstruct-review.json
docstruct graphify /tmp/docstruct.json \
  --review /tmp/docstruct-review.json \
  --source-root /home/user/project \
  --output /tmp/docstruct.graphify.json
```

The last command exports a Graphify-compatible semantic fragment containing only
mechanically safe non-code facts plus validated additive review nodes/edges. When
docstruct ran inside `SERVER_TOOLS` against `/app`, `--source-root` can remap
provenance to the host project root used by host Graphify without requiring that host
path to exist inside the container. Same-file located semantic nodes are canonicalized
to Graphify's `(source_file, label)` identity rule before export, with affected edges
rewired and deduplicated. It does not modify `graphify-out/graph.json`, Graphify caches,
or manifests. CI validates the emitted fragment with the real minimum supported Graphify
(`graphifyy==0.9.65`) through both `graphify merge-chunks` and an LLM-free
`graphify cluster-only --no-label --no-viz` round trip; the node count must remain
stable.

Current Graphify does not yet expose a supported `extract --semantic-fragment` (or
equivalent) ingestion flag that owns incremental manifest/cache replacement semantics.
Until such an interface exists, docker-tools stops at the validated fragment boundary.

Current deterministic coverage:

- Markdown headings, links, anchors, and code blocks through Pandoc;
- RST headings/code blocks through Pandoc plus explicit Sphinx/RST targets, directives, `include`, `toctree`, and `:doc:`/`:ref:`/`:class:`/`:func:`/`:meth:`/`:mod:` references;
- YAML/JSON/TOML/INI key hierarchy without scalar-value export;
- Python requirements/constraints manifests with deterministic package and include/constraint relationships;
- resolution of provable local document links/includes/toctree references;
- source evidence and explicit unresolved references;
- bounded review context is split into small file/byte-limited chunks before any LLM call;
- document-review retries one malformed structured response once before returning failure to the caller;
- Graphify export uses a reserved `docstruct_` namespace and a safe replacement merge that preserves code nodes;
- same-file located document identities are canonicalized before Graphify consumes the fragment.

Resource controls:

```text
DOCSTRUCT_MAX_FILE_BYTES=2097152
DOCSTRUCT_MAX_CORPUS_BYTES=33554432
DOCSTRUCT_MAX_FILES=1000
DOCSTRUCT_MAX_NODES=20000
DOCSTRUCT_MAX_REFERENCES=50000
DOCSTRUCT_PARSE_TIMEOUT=15
DOCSTRUCT_REVIEW_FILE_BYTES=32768
DOCSTRUCT_REVIEW_TOTAL_BYTES=1048576
DOCSTRUCT_REVIEW_CHUNK_BYTES=49152
DOCSTRUCT_REVIEW_CHUNK_FILES=4
# optional explicit review-workspace boundary:
DOCSTRUCT_REVIEW_ROOT=/workspace
```

The sidecar limit is separate from `LDS_AI_MAX_CONTEXT_BYTES`: the full deterministic artifact is used only to select bounded review chunks. Every model-bound chunk is still redacted and checked against the normal AI context limit.

Directory scans respect `.gitignore` by default when Git metadata is available; `--no-gitignore` disables that behavior. Repeatable `--include` and `--exclude` globs provide explicit corpus shaping. Symlinked corpus entries are not followed, and references that would escape the supplied root remain unresolved.

## 🤖 Optional local AI

AI is an optional consumer feature. All ordinary Tools/admin/monitor/document-structure behavior works without an LLM provider.

Default provider contract:

```text
LDS_AI_ENABLED=auto
LDS_AI_RUNTIME=cpu
LDS_AI_MODEL=
```

Useful commands:

```bash
askai "Explain this error"

# direct safe-file input; secret-looking/private-key/binary files are refused
askai --file ./nginx.conf "Review this configuration"

# provider status only; no generation
aiops provider

# deterministic collector -> redacted context -> local model
aiops explain status
aiops explain alerts --json
aiops explain logs --context-only
aiops troubleshoot --stream

# explicitly supplied review inputs
aiops review --file ./nginx.conf

# deterministic document structure -> validated additive semantic patch
docstruct docs/ --output /tmp/docstruct.json
aiops document-review --file /tmp/docstruct.json

aiops graphify --file ./graphify-output.json

# repository metadata only; it does not implicitly send file/diff contents
aiops repo-review
```

AI safety contract:

- provider preflight and generation use separate timeouts;
- positive/negative availability is cached briefly;
- context, request, and response bytes are independently bounded;
- generation is not retried after partial streamed output;
- multiple installed models require explicit `LDS_AI_MODEL` instead of silently choosing one;
- known secrets/tokens/credential values are deterministically redacted;
- `.env`, `.ssh`, private keys, credential/secret files, P12/PFX, and binary inputs are refused for automatic file ingestion;
- monitor/log/config/repository data is treated as untrusted data inside a fixed prompt boundary;
- raw prompts/responses are not persisted by default;
- model output is never executed as shell, SQL, code, or Docker commands;
- `aiops document-review` never rewrites the deterministic sidecar; it returns a separately versioned additive patch and rejects unknown source files or node IDs.

The Admin Panel exposes an explicit **AI Assistant** page. It performs only a provider availability check on load; analysis starts only after the user presses **Run Analysis**. The response shows the redacted context that was supplied to the provider and can be cancelled/bounded by the UI/server timeout.

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
│  ├─ node/                 # Node vhost/profile metadata (*.yaml)
│  ├─ fpm/                  # FPM pool config dirs/files (phpXX/*)
│  ├─ ssl/                  # Generated certificates (.pem, .p12, keys)
│  ├─ certs/                # Exported cert copies from `certify`
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
├─ logs/                    # Optional host logs for status/logviewer (/global/log)
│
└─ docker-compose.yml

````

> Migration: move legacy top-level files into `configuration/sops/global/`:
> - `configuration/sops/age.keys` -> `configuration/sops/global/age.keys`
> - `configuration/sops/.sops.yaml` -> `configuration/sops/global/.sops.yaml`

### 🔗 Container mount mapping

| Host path | Container path |Used by |
|---|---|---|
| `./configuration/apache` | `/etc/share/vhosts/apache` | `mkhost`, `certify` |
| `./configuration/nginx` | `/etc/share/vhosts/nginx` |`mkhost`, `certify` |
| `./configuration/docker-compose` | `/etc/share/vhosts/docker-compose` | `mkhost`, `rmhost`, `status` checks |
| `./configuration/fpm` | `/etc/share/vhosts/fpm` | `mkhost`, `init-php-dirs`, `status` checks |
| `./configuration/ssl` | `/etc/mkcert` |  `certify`, `mkcert` |
| `./configuration/certs` | `/etc/share/certs` | `certify` export dir, `status` checks |
| `./configuration/rootCA` | `/etc/share/rootCA` |  `mkcert` (CA store) |
| `./configuration/sops/config` | `/etc/share/sops/config` | optional per-project SOPS configs |
| `./configuration/sops/global` | `/etc/share/sops/global` | global fallback key/config for `senv` |
| `./configuration/sops/keys` | `/etc/share/sops/keys` | per-project Age keys |
| `./secrets-repo` | `/etc/share/vhosts/sops` |  `senv dec --in=...` (alias input source) |
| `./logs` | `/global/log` | `status` checks, LogViewer |
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
      - ./configuration/docker-compose:/etc/share/vhosts/docker-compose
      - ./configuration/fpm:/etc/share/vhosts/fpm

      - ./configuration/ssl:/etc/mkcert
      - ./configuration/certs:/etc/share/certs
      - ./configuration/rootCA:/etc/share/rootCA

      - ./configuration/sops/config:/etc/share/sops/config
      - ./configuration/sops/global:/etc/share/sops/global
      - ./configuration/sops/keys:/etc/share/sops/keys
      - ./secrets-repo:/etc/share/vhosts/sops:ro
      - ./logs:/global/log:ro

      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ=Asia/Dhaka
      # - NOTIFY_TCP_PORT=9901
      # - NOTIFY_PREFIX=__HOST_NOTIFY__
      # - NOTIFY_TOKEN=
````

Use as:

* one-shot cert generator: `docker run --rm ... infocyph/tools certify`
* long-lived utility/control-plane box: default CMD runs `notifierd`

> Security: mounting `/var/run/docker.sock` gives Tools privileged access to the Docker daemon. LocalDevStack operations should remain scoped to the current Compose project. Do not publish the raw admin port by default; use `https://admin.localhost` through the hardened Nginx route.

---

## ▶️ Manual run

```bash
docker run --rm -it \
  -v "$(pwd)/configuration/apache:/etc/share/vhosts/apache" \
  -v "$(pwd)/configuration/nginx:/etc/share/vhosts/nginx" \
  -v "$(pwd)/configuration/docker-compose:/etc/share/vhosts/docker-compose" \
  -v "$(pwd)/configuration/fpm:/etc/share/vhosts/fpm" \
  -v "$(pwd)/configuration/ssl:/etc/mkcert" \
  -v "$(pwd)/configuration/certs:/etc/share/certs" \
  -v "$(pwd)/configuration/rootCA:/etc/share/rootCA" \
  -v "$(pwd)/configuration/sops/config:/etc/share/sops/config" \
  -v "$(pwd)/configuration/sops/global:/etc/share/sops/global" \
  -v "$(pwd)/configuration/sops/keys:/etc/share/sops/keys" \
  -v "$(pwd)/logs:/global/log:ro" \
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
| LDS (Server)     | `lds-server.pem`, `lds-server-key.pem`                         |
| LDS (Client Internal) | `lds-client-internal.pem`, `lds-client-internal-key.pem` |
| LDS (Client User) | `lds-client-user.pem`, `lds-client-user-key.pem`, `lds-client-user.p12` |

### 🎯 Certificate role mapping

Use certs by TLS role, not by service name:

| Traffic / Role | Certificate to use |
| --- | --- |
| Client -> Nginx (TLS termination, including localhost router) | `lds-server.pem`, `lds-server-key.pem` |
| Nginx -> Apache (mTLS upstream client auth) | `lds-client-internal.pem`, `lds-client-internal-key.pem` |
| Apache as TLS server for Nginx | `lds-server.pem`, `lds-server-key.pem` |
| Human/browser/API client cert bundle | `lds-client-user.p12` (from `lds-client-user.pem`, `lds-client-user-key.pem`) |

For `locals.conf`-style Nginx HTTPS routers, use:

```nginx
ssl_certificate /etc/mkcert/lds-server.pem;
ssl_certificate_key /etc/mkcert/lds-server-key.pem;
```

---

## 🧩 mkhost (interactive vhost generator)

`mkhost` is your “domain setup wizard”. It generates:

* Nginx vhost: `/etc/share/vhosts/nginx/<domain>.conf`
* Apache vhost (only if you choose Apache): `/etc/share/vhosts/apache/<domain>.conf`
* Node service yaml (only if you choose Node): `/etc/share/vhosts/docker-compose/<token>.yaml`
* PHP service yaml (only if you choose PHP): `/etc/share/vhosts/docker-compose/phpXX.yaml`

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

    * PHP: choose PHP version
    * Node: choose Node version + optional run command
* If HTTPS: optional client certificate verification (mutual TLS)

### HTTPS + certificates

If you enable HTTPS, `mkhost` triggers `certify` automatically so the required certs exist.

### Helpful flags

`mkhost` stores state in `env-store`.
You can query/reset these values:

```bash
mkhost --RESET
mkhost --APACHE_ACTIVE
mkhost --JSON
```

* `--RESET` clears mkhost state.
* `--APACHE_ACTIVE` prints `apache` when Apache mode was selected.
* `--JSON` prints structured state from key `MKHOST_STATE`.

---

## 🧹 rmhost (remove vhost configs)

`rmhost` deletes the generated files for a domain:

* `/etc/share/vhosts/nginx/<domain>.conf`
* `/etc/share/vhosts/apache/<domain>.conf`
* `/etc/share/vhosts/docker-compose/<token>.yaml` (Node token is a safe slug of the domain)

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

State/query flags:

```bash
rmhost --RESET
rmhost --APACHE_DELETE
rmhost --JSON
```

---

## 📊 status (project diagnostics)

`status` reports compose-project health and runtime diagnostics in both human and machine-readable forms.

Usage:

```bash
status [--json] [--quiet] [service]
```

Examples:

```bash
status
status php84
status --json | jq .
```

Human output sections:

* Core: `Project`, `Profiles`, `Containers`, `Ports`, `URLs`
* Diagnostics: `Problems`, `Container runtime` (`Top consumers` + `Stats`), `Disk`, `Volumes`, `Networks`, `Probes`, `Recent errors`, `Drift`
* `Checks`:
  * `System test`: internet reachability, egress IP, memory, docker runtime
  * `Project containers`: container health summary
  * `Project artifacts`: artifact and log counts
  * `Project mounts`: mount readiness and emptiness checks

`--json` shape:

* Top-level: `generated_at`, `full`, `core`, `sections`
* `core`: project metadata, running summary, port summaries, URLs
* `sections`: `problems`, `containers` (merged `core` + `top_consumers` + `stats`), `disk`, `volumes`, `networks`, `probes`, `recent_errors`, `drift`, `checks`

Helpful env overrides:

* `STATUS_PROJECT` (force project name)
* `STATUS_PROBE=0|1` (disable/enable URL probing)
* `STATUS_FORCE_COLOR=1` (force ANSI colors)
* `STATUS_MOUNT_DEEP_COUNT=1` (opt-in deep recursive mount file counts; default is fast shallow mode)
* `STATUS_LOG_SCAN_MAX_DEPTH=3` (depth limit for `/global/log` checks; use `all` or `-1` for full recursion)
* `WORKING_DIR` / `LDS_WORKDIR` (workdir hint)
* `ENV_DOCKER` (custom docker env file path)
* `VHOST_NGINX_DIR` (domain source dir)

---

## 🔎 domain-which (domain metadata resolver)

`domain-which` resolves runtime metadata for a domain by reading LDS headers from Nginx vhost files.

```bash
domain-which --list-domains
domain-which example.com
domain-which --json example.com
domain-which --app example.com
```

---

## 🧩 profile-chooser (host-flush helper)

`profile-chooser` lets you interactively select service profiles and their required env values, then stores state in `env-store` (JSON by default; SQLite optional).
Host-side tooling can fetch newline-separated outputs and decide how/when to flush into compose env/profiles.

```bash
profile-chooser                # interactive selection
profile-chooser --json         # full saved state
profile-chooser --profiles     # newline list
profile-chooser --services     # newline list
profile-chooser --envs         # newline KEY=VALUE pairs
profile-chooser --reset
```

Stored state key in `env-store`:

* `PROFILE_CHOOSER_STATE` (structured JSON object)

---

## 🗃️ env-store (JSON state store)

`env-store` is a small JSON-backed key/value store for container runtime state.
It is used by profile/mkhost/rmhost flows as the single state backend.

Default file:

* `/etc/share/state/env-store.json` (override with `ENV_STORE_JSON`)
* Optional SQLite backend: set `ENV_STORE_BACKEND=sqlite` (DB path: `ENV_STORE_DB`)

Common structured keys used by bundled scripts:

* `PROFILE_CHOOSER_STATE`
* `MKHOST_STATE`
* `RMHOST_STATE`

Examples:

```bash
env-store set-json STACK_META '{"name":"LocalDevStack","ports":[80,443],"flags":{"probe":true}}'
env-store get-json STACK_META
env-store list
env-store json | jq .
```

---

## 🧱 es-policy (Elasticsearch/Kibana bootstrap)

`es-policy` ensures ILM policies/templates for log data streams and can provision Kibana data views.

```bash
es-policy
es-policy --force
```

Common env overrides:

* `ES_URL` (default `http://elasticsearch:9200`)
* `KIBANA_URL` (default `http://kibana:5601`)
* `REPLICAS` (default `0`)

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

### Config selection order

`senv` chooses the SOPS config in this order:

1. Repo-local → `./.sops.yaml`
2. Project config (optional) → `/etc/share/sops/config/<id>.sops.yaml`
3. Global fallback (preferred) → `/etc/share/sops/global/.sops.yaml`
4. Override: `SOPS_CONFIG_FILE=/path/to/.sops.yaml`

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

### Validation checklist

Run the smoke test inside the tools container:

```bash
bash /etc/share/scripts/tests/senv-smoke.sh
```

Expected coverage:

- `init` global bootstrap
- `keygen` no-overwrite guard
- `.env` encrypt/decrypt roundtrip
- `push`/`pull` alias flow (`SOPS_REPO_DIR`)
- safe-path guard and `--unsafe` override

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
| `ADMIN_PANEL_AUTOSTART` | `1`                              | start the built-in admin panel |
| `ADMIN_PANEL_BIND`      | `0.0.0.0`                         | internal admin listener bind; do not publish raw host port by default |
| `ADMIN_PANEL_PORT`      | `9911`                            | internal admin listener used by `admin.localhost` |
| `ADMIN_PANEL_TOKEN`     | (empty)                            | stack-scoped control token for mutations/sensitive downloads |
| `ADMIN_PANEL_LOG_ROOTS` | `/global/log`                     | colon-separated admin log roots; legacy `LOGVIEW_ROOTS` is accepted as a compatibility fallback |
| `LDS_AI_ENABLED`        | `auto`                            | `auto`, `0`, or `1`; AI remains optional |
| `LDS_AI_RUNTIME`        | `cpu`                             | selects `llm-fastflow` for `npu`, otherwise `llm-ollama` |
| `LDS_AI_URL`            | derived                           | optional override; normally resolved from `LDS_AI_RUNTIME` |
| `LDS_AI_MODEL`          | (empty)                            | explicit model override; required when installed-model choice is ambiguous |
| `LDS_AI_THINK`          | (empty)                            | default thinking override: empty/provider default, `true`, or `false`; request-level controls can override it |
| `LDS_AI_CONNECT_TIMEOUT` | `2`                              | provider connect timeout seconds |
| `LDS_AI_PREFLIGHT_TIMEOUT` | `5`                            | provider availability/model preflight timeout seconds |
| `LDS_AI_TIMEOUT`        | `1800`                            | generation timeout seconds shared by CLI and Admin AI analysis |
| `LDS_AI_AVAILABILITY_TTL` | `5`                            | positive/negative availability cache TTL |
| `LDS_AI_MAX_CONTEXT_BYTES` | `524288`                       | maximum context bytes |
| `LDS_AI_MAX_REQUEST_BYTES` | `1048576`                      | maximum serialized request bytes |
| `LDS_AI_MAX_RESPONSE_BYTES` | `2097152`                     | maximum response/stream bytes |
| `LDS_AIOPS_COLLECT_TIMEOUT` | `15`                          | per deterministic collector timeout used by `aiops` |
| `SOPS_BASE_DIR`       | `/etc/share/sops`                  | global SOPS base directory           |
| `SOPS_KEYS_DIR`       | `/etc/share/sops/keys`             | per-project keys directory           |
| `SOPS_CFG_DIR`        | `/etc/share/sops/config`           | per-project config directory         |
| `SOPS_GLOBAL_DIR`     | `/etc/share/sops/global`           | global fallback key/config directory |
| `SOPS_CONFIG_FILE`    | (empty)                            | override global fallback .sops.yaml  |
| `SOPS_AGE_KEY_FILE`   | (empty)                            | override age key file path           |
| `SENV_PROJECT`        | (auto)                             | project id (auto-detected from git)  |
| `SOPS_REPO_DIR`       | `/etc/share/vhosts/sops`           | shared encrypted env repo mount      |
| `STATUS_PROJECT`      | (auto)                             | force project name for `status` |
| `STATUS_PROBE`        | `1`                                | enable URL probes in `status` |
| `STATUS_FORCE_COLOR`  | `0`                                | force color output in `status` |
| `STATUS_MOUNT_DEEP_COUNT` | `0`                           | deep recursive mount file counts in `status` checks (slow on bind mounts) |
| `STATUS_LOG_SCAN_MAX_DEPTH` | `3`                         | max depth for `/global/log` file counts in `status` checks (`all`/`-1` = full recursion) |
| `WORKING_DIR` / `LDS_WORKDIR` | current dir                | stack root hint for `status` |
| `ENV_DOCKER`          | `$WORKING_DIR/docker/.env`         | compose env file path used by `status` |
| `VHOST_NGINX_DIR`     | auto                               | vhost dir used by `status` URL discovery |
| `ENV_STORE_BACKEND`   | `json`                             | backend for `env-store` (`json` or `sqlite`) |
| `ENV_STORE_JSON`      | `/etc/share/state/env-store.json` | JSON state file used by `env-store` and stateful shell tools |
| `ENV_STORE_DB`        | `/etc/share/state/env-store.db`   | SQLite state DB used when `ENV_STORE_BACKEND=sqlite` |
| `ENV_STORE_SQLITE_BIN`| `sqlite3`                          | sqlite client binary used by `env-store` |

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
