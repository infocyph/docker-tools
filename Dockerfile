# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: fetch mkcert + lazydocker
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:latest AS fetch
SHELL ["/bin/sh", "-euo", "pipefail", "-c"]
ENV DIR=/usr/local/bin
RUN apk add --no-cache curl bash ca-certificates && update-ca-certificates && \
  mkdir -p /out && \
  curl -fsSJL -o /out/mkcert "https://dl.filippo.io/mkcert/latest?for=linux/amd64" && \
  chmod +x /out/mkcert && \
  curl -fsSL "https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh" | bash && \
  cp /usr/local/bin/lazydocker /out/lazydocker && \
  chmod +x /out/lazydocker

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
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN apk add --no-cache \
      curl git wget ca-certificates bash coreutils net-tools nss iputils-ping ncdu jq tree \
      nmap openssl ncurses tzdata figlet musl-locales gawk sqlite socat \
  && update-ca-certificates \
  && mkdir -p /etc/mkcert /etc/share/rootCA /etc/share/vhosts/apache /etc/share/vhosts/nginx \
  && rm -rf /tmp/* /var/tmp/*

SHELL ["/bin/bash", "-c"]

# bring binaries from stage 1
COPY --from=fetch /out/mkcert /usr/local/bin/mkcert
COPY --from=fetch /out/lazydocker /usr/local/bin/lazydocker

COPY scripts/certify.sh /usr/local/bin/certify
COPY scripts/mkhost.sh /usr/local/bin/mkhost
COPY scripts/notifierd.sh /usr/local/bin/notifierd
COPY scripts/notify.sh /usr/local/bin/notify
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint
COPY scripts/http-templates/ /etc/http-templates/

ADD https://raw.githubusercontent.com/infocyph/Toolset/main/Git/gitx /usr/local/bin/gitx
ADD https://raw.githubusercontent.com/infocyph/Scriptomatic/master/bash/banner.sh /usr/local/bin/show-banner
ADD https://raw.githubusercontent.com/infocyph/Toolset/main/ChromaCat/chromacat /usr/local/bin/chromacat
ADD https://raw.githubusercontent.com/infocyph/Toolset/main/Sqlite/sqlitex /usr/local/bin/sqlitex

RUN chmod +x \
      /usr/local/bin/gitx \
      /usr/local/bin/certify \
      /usr/local/bin/mkhost \
      /usr/local/bin/show-banner \
      /usr/local/bin/chromacat \
      /usr/local/bin/sqlitex \
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
