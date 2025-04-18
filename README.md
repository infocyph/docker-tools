# 🛠️ Docker Tools Container

[![Docker Publish](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml/badge.svg)](https://github.com/infocyph/docker-tools/actions/workflows/docker.publish.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Base: Alpine](https://img.shields.io/badge/Base-Alpine-brightgreen.svg)](https://alpinelinux.org)

> A lightweight, multi-tool Docker image with SSL automation, Docker diagnostics and CLI utilities — designed for
> development and debugging workflows.

---

## 📦 Available on Registries

| Registry         | Image Name                 |
|------------------|----------------------------|
| Docker Hub       | `docker.io/infocyph/tools` |
| GitHub Container | `ghcr.io/infocyph/tools`   |

---

## 🚀 Features

- Lightweight Alpine-based container  
- Auto-generates trusted development certificates using [`mkcert`](https://github.com/FiloSottile/mkcert)  
- Supports server and client certificate generation  
- Wildcard domain certs via virtual host file scanning  
- Includes tools like `curl`, `git`, `openssl`, `nmap`, `jq`, `tree`, and `ncdu`  
- Interactive Docker TUI via [`lazydocker`](https://github.com/jesseduffield/lazydocker)  
- Host volumes supported for cert persistence and dynamic vhost domain input
- Bundles `.p12` client certificates
- Set timezone via environment variable `TZ`

---

## 🛠️ Preinstalled Utilities

| Tool                | Purpose                                   |
|---------------------|-------------------------------------------|
| `mkcert`            | Generate local CA-signed SSL certs        |
| `mkhost`            | Generate nginx, apache host configuration |
| `openssl`           | Certificate inspection, bundling          |
| `lazydocker`        | TUI-based Docker management               |
| `curl`/`wget`       | Web endpoint testing                      |
| `jq`                | JSON manipulation                         |
| `nmap`              | Network scanner                           |
| `net-tools`         | IP, ARP, routing, and ifconfig commands   |
| `ncdu`              | Disk usage visualizer                     |
| `tree`              | Directory structure visualizer            |
| `bash`, `coreutils` | POSIX compatibility and scripting         |

---

## 🔧 How It Works

On container startup, the included `certify.sh` script:

1. Scans all `*.conf` files under `/etc/share/vhosts/**`
2. Extracts domain names from filenames
3. Adds wildcard versions automatically
4. Generates server and client certificates using `mkcert`

---

## 📁 Domain Detection by Filename

The script looks for `.conf` files in **any subdirectory** under `/etc/share/vhosts`.

**Filename → Domains:**

| File Name                | Domains Generated                          |
|--------------------------|--------------------------------------------|
| `test.local.conf`        | `test.local`, `*.test.local`               |
| `example.com.conf`       | `example.com`, `*.example.com`             |
| `internal.dev.site.conf` | `internal.dev.site`, `*.internal.dev.site` |

Additionally added automatically:

- `localhost`
- `127.0.0.1`
- `::1`

---

## 📦 Example: Docker Compose Integration

```yaml
services:
  certgen:
    image: infocyph/docker-tools
    container_name: docker-tools
    volumes:
      - ../../configuration/apache:/etc/share/vhosts/apache:ro
      - ../../configuration/nginx:/etc/share/vhosts/nginx:ro
      - ../../configuration/ssl:/etc/mkcert
      - ../../configuration/rootCA:/etc/share/rootCA
      - /var/run/docker.sock:/var/run/docker.sock
```

📝 This container can run as a one-shot cert generator or as a long-lived utility box.

---

## 🔐 Generated Files

| Certificate Type | Files Generated                                                |
|------------------|----------------------------------------------------------------|
| Apache (Server)  | `apache-server.pem`, `apache-server-key.pem`                   |
| Apache (Client)  | `apache-client.pem`, `apache-client-key.pem`                   |
| Nginx (Server)   | `nginx-server.pem`, `nginx-server-key.pem`                     |
| Nginx (Proxy)    | `nginx-proxy.pem`, `nginx-proxy-key.pem`                       |
| Nginx (Client)   | `nginx-client.pem`, `nginx-client-key.pem`, `nginx-client.p12` |

🛡️ All generated certs are placed in `/etc/mkcert`.

---

## 📜 Example Manual Run

```bash
docker run --rm -it \
  -v $(pwd)/configuration/apache:/etc/share/vhosts/apache:ro \
  -v $(pwd)/configuration/nginx:/etc/share/vhosts/nginx:ro \
  -v $(pwd)/configuration/ssl:/etc/mkcert \
  infocyph/tools
```

---

## 🔎 Lazydocker Usage

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

Encountered a problem or want to suggest a feature?  
[Open an issue](https://github.com/infocyph/docker-tools/issues) or start a discussion!
