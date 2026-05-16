FROM golang:1.22-bookworm AS rcon-builder

ARG RCON_CLI_VERSION=0.10.3
RUN CGO_ENABLED=0 go install github.com/gorcon/rcon-cli/cmd/gorcon@v${RCON_CLI_VERSION}

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    STEAMCMDDIR=/opt/steamcmd \
    HOME=/home/pokuser

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        lib32gcc-s1 \
        lib32stdc++6 \
        libatomic1 \
        libpulse0 \
        locales \
        procps \
        sqlite3 \
        sudo \
        tini \
        tzdata \
        util-linux \
    && locale-gen en_US.UTF-8 \
    && (userdel -r ubuntu 2>/dev/null || true) \
    && useradd --create-home --shell /bin/bash --uid 1000 --user-group pokuser \
    && mkdir -p /opt/steamcmd /data/server /data/steam /data/backups \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
        | tar -xz -C /opt/steamcmd \
    && chown -R pokuser:pokuser /data /home/pokuser /opt/steamcmd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=rcon-builder /go/bin/gorcon /usr/local/bin/rcon

COPY scripts/ /usr/local/bin/

RUN chmod +x /usr/local/bin/*.sh \
    && chmod +x /usr/local/bin/entrypoint /usr/local/bin/root-entrypoint \
    && printf '%s\n' \
        'pokuser ALL=(root) NOPASSWD:SETENV: /usr/local/bin/root-entrypoint *' \
        > /etc/sudoers.d/pokuser-root-entrypoint \
    && chmod 0440 /etc/sudoers.d/pokuser-root-entrypoint

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PUID=1000 \
    PGID=1000 \
    TZ=UTC \
    SERVER_DIR=/data/server \
    STEAM_DIR=/data/steam \
    BACKUP_DIR=/data/backups \
    AUTO_UPDATE=true \
    STEAM_BRANCH=public \
    STEAM_VALIDATE=false \
    SERVER_NAME="Conan Exiles Enhanced Server" \
    MAX_PLAYERS=40 \
    SERVER_PORT=7777 \
    QUERY_PORT=27015 \
    RAW_UDP_PORT=7778 \
    MULTIHOME=0.0.0.0 \
    RCON_ENABLED=true \
    RCON_PORT=25575 \
    BACKUP_ENABLED=true \
    BACKUP_INTERVAL_MINUTES=60 \
    BACKUP_RETENTION_COUNT=30 \
    BACKUP_ON_STOP=true \
    SAVE_VERIFY_TIMEOUT=60

VOLUME ["/data/server", "/data/steam", "/data/backups"]

EXPOSE 7777/udp 7778/udp 27015/udp 25575/tcp

USER pokuser
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
CMD ["start"]
