# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: fetch mkcert + lazydocker + runtime versions json
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:latest AS fetch
SHELL ["/bin/sh", "-euo", "pipefail", "-c"]

RUN apk add --no-cache curl bash ca-certificates jq \
  && update-ca-certificates \
  && mkdir -p /out \
  && curl -fsSJL --retry 3 --retry-delay 1 --retry-all-errors \
      -o /out/mkcert "https://dl.filippo.io/mkcert/latest?for=linux/amd64" \
  && chmod +x /out/mkcert \
  && curl -fsSL --retry 3 --retry-delay 1 --retry-all-errors \
      "https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh" | bash \
  && cp /usr/local/bin/lazydocker /out/lazydocker \
  && chmod +x /out/lazydocker \
  && tmp="$(mktemp -d)" \
  && curl -fsSL --retry 3 --retry-delay 1 --retry-all-errors \
      "https://endoflife.date/api/v1/products/php/" \
      -o "$tmp/php.json" \
  && curl -fsSL --retry 3 --retry-delay 1 --retry-all-errors \
      "https://endoflife.date/api/v1/products/nodejs/" \
      -o "$tmp/node.json" \
  && jq -n --slurpfile php "$tmp/php.json" --slurpfile node "$tmp/node.json" '
      def nowiso: (now | todateiso8601);
      def sort_node: sort_by(.version|tonumber) | reverse;
      def sort_php:  sort_by(.version) | reverse;

      def php_releases:  ($php[0].result.releases // []);
      def node_releases: ($node[0].result.releases // []);

      def node_current_major:
        (node_releases
          | map(select(.isEol == false and .isLts == false))
          | max_by(.name|tonumber)
          | .name);

      def node_lts_major:
        (node_releases
          | map(select(.isEol == false and .isLts == true))
          | max_by(.name|tonumber)
          | .name);

      {
        generated_at: nowiso,
        sources: {
          php:  "https://endoflife.date/api/v1/products/php/",
          node: "https://endoflife.date/api/v1/products/nodejs/"
        },

        php: {
          active: (
            php_releases
            | map(select(.isMaintained == true))
            | map({ version: .name, debut: .releaseDate, eol: .eolFrom })
            | sort_php
          ),
          deprecated: (
            php_releases
            | map(select(.isMaintained == false))
            | map({ version: .name, eol: .eolFrom })
            | sort_php
          ),
          all: (
            php_releases
            | map({ version: .name, debut: .releaseDate, eol: .eolFrom, maintained: .isMaintained })
            | sort_php
          )
        },

        node: {
          tags: { current: node_current_major, lts: node_lts_major },

          active: (
            node_releases
            | map(select(.isEol == false))
            | map({ version: .name, label: .label, debut: .releaseDate, eol: .eolFrom, lts: .isLts })
            | sort_node
          ),
          deprecated: (
            node_releases
            | map(select(.isEol == true))
            | map({ version: .name, label: .label, eol: .eolFrom })
            | sort_node
          ),
          all: (
            node_releases
            | map({ version: .name, label: .label, debut: .releaseDate, eol: .eolFrom, eolFlag: .isEol, lts: .isLts })
            | sort_node
          )
        }
      }
    ' > /out/runtime-versions.json \
  && chmod 644 /out/runtime-versions.json \
  && rm -rf "$tmp"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: runtime/tools image
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:latest

LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-tools"
LABEL org.opencontainers.image.description="Tools"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="infocyph,abmmhasan"

ENV PATH="/usr/local/bin:/usr/bin:/bin:/usr/games:$PATH" \
    CAROOT=/etc/share/rootCA \
    NOTIFY_FIFO=/run/notify.fifo \
    NOTIFY_TCP_PORT=9901 \
    NOTIFY_PREFIX=__HOST_NOTIFY__ \
    NOTIFY_TOKEN="" \
    RUNTIME_VERSIONS_DB=/etc/share/runtime-versions.json \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN apk add --no-cache \
      curl git wget ca-certificates bash coreutils net-tools nss iputils-ping ncdu jq tree \
      nmap openssl ncurses tzdata figlet musl-locales gawk sqlite socat \
  && update-ca-certificates \
  && mkdir -p /etc/mkcert /etc/share/rootCA /etc/share/vhosts/apache /etc/share/vhosts/nginx \
  && rm -rf /tmp/* /var/tmp/*

SHELL ["/bin/bash", "-c"]

# bring binaries + runtime versions db from stage 1
COPY --from=fetch /out/mkcert /usr/local/bin/mkcert
COPY --from=fetch /out/lazydocker /usr/local/bin/lazydocker
COPY --from=fetch /out/runtime-versions.json /etc/share/runtime-versions.json

COPY scripts/certify.sh /usr/local/bin/certify
COPY scripts/mkhost.sh /usr/local/bin/mkhost
COPY scripts/delhost.sh /usr/local/bin/delhost
COPY scripts/notifierd.sh /usr/local/bin/notifierd
COPY scripts/notify.sh /usr/local/bin/notify
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint
COPY scripts/http-templates/ /etc/http-templates/

ADD https://raw.githubusercontent.com/infocyph/Toolset/main/Git/gitx /usr/local/bin/gitx
ADD https://raw.githubusercontent.com/infocyph/Scriptomatic/master/bash/banner.sh /usr/local/bin/show-banner
ADD https://raw.githubusercontent.com/infocyph/Toolset/main/ChromaCat/chromacat /usr/local/bin/chromacat
ADD https://raw.githubusercontent.com/infocyph/Toolset/main/Sqlite/sqlitex /usr/local/bin/sqlitex
ADD https://raw.githubusercontent.com/infocyph/Toolset/main/Network/netx /usr/local/bin/netx

RUN chmod +x \
      /usr/local/bin/gitx \
      /usr/local/bin/certify \
      /usr/local/bin/mkhost \
      /usr/local/bin/delhost \
      /usr/local/bin/show-banner \
      /usr/local/bin/chromacat \
      /usr/local/bin/sqlitex \
      /usr/local/bin/netx \
      /usr/local/bin/notifierd \
      /usr/local/bin/notify \
      /usr/local/bin/entrypoint \
      /usr/local/bin/mkcert \
      /usr/local/bin/lazydocker \
  && touch /etc/environment \
  && chmod -R 755 /etc/share/vhosts \
  && chmod 644 /etc/environment \
  && echo 'ACTIVE_PHP_PROFILE=""' >> /etc/environment \
  && echo 'APACHE_ACTIVE=""' >> /etc/environment \
  && mkdir -p /etc/profile.d \
  && { \
      echo '#!/bin/sh'; \
      echo 'if [ -n "$PS1" ] && [ -z "${BANNER_SHOWN-}" ]; then'; \
      echo '  export BANNER_SHOWN=1'; \
      echo '  show-banner "Tools"'; \
      echo 'fi'; \
    } > /etc/profile.d/banner-hook.sh \
  && chmod +x /etc/profile.d/banner-hook.sh \
  && { \
      echo 'if [ -n "$PS1" ] && [ -z "${BANNER_SHOWN-}" ]; then'; \
      echo '  export BANNER_SHOWN=1'; \
      echo '  show-banner "Tools"'; \
      echo 'fi'; \
    } >> /root/.bashrc

WORKDIR /app
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["/usr/local/bin/notifierd"]
