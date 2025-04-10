FROM alpine:latest
LABEL org.opencontainers.image.source="https://github.com/infocyph/docker-tools"
LABEL org.opencontainers.image.description="Tools"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="infocyph,abmmhasan"
ENV PATH="/usr/local/bin:/usr/bin:/bin:/usr/games:$PATH"
ENV CAROOT=/etc/share/rootCA
RUN apk update && apk add --no-cache curl git wget ca-certificates bash coreutils net-tools nss iputils-ping ncdu jq tree nmap openssl ncurses
SHELL ["/bin/bash", "-c"]
RUN curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64" && \
    mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert && \
    chmod +x /usr/local/bin/mkcert && \
    mkdir -p /etc/mkcert /etc/share/rootCA /etc/share/vhosts
ENV DIR=/usr/local/bin
RUN curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
COPY scripts/certify.sh /usr/local/bin/certify
ADD https://raw.githubusercontent.com/infocyph/Toolset/main/Git/gitx /usr/local/bin/gitx
RUN chmod +x /usr/local/bin/gitx /usr/local/bin/certify && chmod -R 755 /etc/share/vhosts
WORKDIR /app
CMD ["/bin/bash", "-c", "/usr/local/bin/certify && tail -f /dev/null"]
