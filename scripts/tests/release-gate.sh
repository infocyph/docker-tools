#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-infocyph/tools:ci}"
COMPOSE_FILE="${2:-}"

fail() {
  echo "release gate failed: $*" >&2
  exit 1
}

[[ -n "$COMPOSE_FILE" && -f "$COMPOSE_FILE" ]] || fail 'LocalDevStack companion compose file is required'

grep -Eq '^[[:space:]]*server-tools:' "$COMPOSE_FILE" || fail 'LocalDevStack server-tools service missing'
grep -Fq 'image: infocyph/tools:latest' "$COMPOSE_FILE" || fail 'LocalDevStack does not consume infocyph/tools:latest'
for contract in \
  '/app' \
  '/etc/share/rootCA' \
  '/etc/share/vhosts/apache' \
  '/etc/share/vhosts/nginx' \
  '/etc/share/vhosts/fpm' \
  '/etc/share/vhosts/composer' \
  '/etc/share/scheduler/cron-jobs' \
  '/etc/share/scheduler/supervisor' \
  '/var/run/docker.sock'; do
  grep -Fq "$contract" "$COMPOSE_FILE" || fail "LocalDevStack mount contract missing: $contract"
done

docker run --rm --entrypoint bash "$IMAGE" -lc '
  set -euo pipefail
  test -x /usr/local/bin/mkcert
  test -x /usr/local/bin/lazydocker
  test -x /usr/local/bin/composer
  test -x /usr/local/bin/gitx
  test -x /usr/local/bin/docstruct
  command -v pandoc >/dev/null
  command -v magick >/dev/null
  command -v ffmpeg >/dev/null
  command -v ffprobe >/dev/null
  command -v sox >/dev/null
  command -v soxi >/dev/null
  command -v mkvmerge >/dev/null
  command -v mkvinfo >/dev/null
  command -v mkvextract >/dev/null
  command -v mkvpropedit >/dev/null
  command -v mediainfo >/dev/null
  test -x /usr/local/bin/askai
  test -x /usr/local/bin/aiops
  test -r "$LDS_AI_PROVIDER_LIB"
  test "$LDS_AI_RUNTIME" = "cpu"
  test -x /usr/local/bin/chromacat
  test -x /usr/local/bin/sqlitex
  test -x /usr/local/bin/netx
  test -x /usr/local/bin/certify
  test -x /usr/local/bin/mkhost
  test -x /usr/local/bin/rmhost
  test -x /usr/local/bin/es-policy
  test -x /usr/local/bin/notifierd
  test -x /usr/local/bin/notify
  test -x /usr/local/bin/senv
  test -x /usr/local/bin/domain-which
  test -x /usr/local/bin/status
  test -x /usr/local/bin/monitor-flows
  test -x /usr/local/bin/monitor-runtime
  test -x /usr/local/bin/monitor-tls
  test -x /usr/local/bin/monitor-db
  test -x /usr/local/bin/monitor-volumes
  test -x /usr/local/bin/monitor-queue
  test -x /usr/local/bin/monitor-slo
  test -x /usr/local/bin/monitor-log-heatmap
  test -x /usr/local/bin/monitor-drift
  test -x /usr/local/bin/monitor-alerts
  test -x /usr/local/bin/env-store
  test -x /usr/local/bin/profile-chooser
  test -x /usr/local/bin/init-php-dirs
  test -x /usr/local/bin/git-default
  test -x /usr/local/bin/entrypoint
  test -x /usr/local/bin/show-banner
  ! command -v ollama >/dev/null 2>&1
  mkcert -version >/dev/null
  lazydocker --version >/dev/null
  composer --version --no-ansi >/dev/null
  gitx --version >/dev/null
  docstruct --help >/dev/null
  magick -size 2x2 xc:red /tmp/lds-image.png
  magick /tmp/lds-image.png /tmp/lds-image.jpg
  magick /tmp/lds-image.png /tmp/lds-image.gif
  magick /tmp/lds-image.png /tmp/lds-image.webp
  magick -delay 10 -size 2x2 xc:red -size 2x2 xc:blue -loop 0 /tmp/lds-animated.gif
  magick /tmp/lds-animated.gif /tmp/lds-animated.webp
  test "$(magick identify /tmp/lds-animated.gif | wc -l | tr -d " ")" -ge 2
  test "$(magick identify /tmp/lds-animated.webp | wc -l | tr -d " ")" -ge 2
  magick "/tmp/lds-animated.gif[0]" /tmp/lds-preview.jpg
  test "$(magick identify /tmp/lds-preview.jpg | wc -l | tr -d " ")" -eq 1
  magick identify /tmp/lds-image.jpg >/dev/null
  magick identify /tmp/lds-image.gif >/dev/null
  magick identify /tmp/lds-image.webp >/dev/null
  magick -list format | grep -Eq "^[[:space:]]*JPEG"
  magick -list format | grep -Eq "^[[:space:]]*PNG"
  magick -list format | grep -Eq "^[[:space:]]*GIF"
  magick -list format | grep -Eq "^[[:space:]]*WEBP"

  ffmpeg -hide_banner -loglevel error -f lavfi -i sine=frequency=1000:duration=0.2 -c:a pcm_s16le /tmp/lds-audio.wav
  ffmpeg -hide_banner -loglevel error -y -i /tmp/lds-audio.wav -c:a libmp3lame /tmp/lds-audio.mp3
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nk=1:nw=1 /tmp/lds-audio.mp3 | grep -qx mp3
  soxi /tmp/lds-audio.wav >/dev/null
  sox /tmp/lds-audio.wav /tmp/lds-audio-gain.wav gain -n -3
  soxi /tmp/lds-audio-gain.wav >/dev/null

  ffmpeg -hide_banner -encoders | grep -Eq "[[:space:]]libxvid[[:space:]]"
  ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=blue:s=32x32:d=0.3 -c:v libxvid -an -y /tmp/lds-xvid.avi
  test -e /usr/lib/libxvidcore.so.4
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nk=1:nw=1 /tmp/lds-xvid.avi | grep -qx mpeg4

  mkvmerge --version >/dev/null
  mkvinfo --version >/dev/null
  mkvextract --version >/dev/null
  mkvpropedit --version >/dev/null
  mkvmerge -q -o /tmp/lds-media.mkv /tmp/lds-xvid.avi /tmp/lds-audio.mp3
  mkvmerge -J /tmp/lds-media.mkv | jq -e '.tracks | length >= 2' >/dev/null
  mkvinfo /tmp/lds-media.mkv >/dev/null
  mediainfo --Output=JSON /tmp/lds-media.mkv | jq -e '.media.track | length >= 2' >/dev/null
  DOCSTRUCT_BIN=/usr/local/bin/docstruct \
  DOCSTRUCT_IMPL=/usr/local/lib/docker-tools/docstruct.php \
  DOCSTRUCT_CONTEXT_IMPL=/usr/local/lib/docker-tools/docstruct-context.php \
  DOCSTRUCT_GRAPHIFY_IMPL=/usr/local/lib/docker-tools/docstruct-graphify.php \
  DOCSTRUCT_GRAPHIFY_MERGE_IMPL=/usr/local/lib/docker-tools/docstruct-graphify-merge.php \
  bash /etc/share/scripts/tests/docstruct-contract.sh >/dev/null
  askai --help >/dev/null
  aiops --help >/dev/null
  status --help >/dev/null
  monitor-flows --help >/dev/null
  monitor-runtime --help >/dev/null
  monitor-tls --help >/dev/null
  monitor-db --help >/dev/null
  monitor-volumes --help >/dev/null
  monitor-queue --help >/dev/null
  monitor-slo --help >/dev/null
  monitor-log-heatmap --help >/dev/null
  monitor-drift --help >/dev/null
  chromacat --version >/dev/null
  sqlitex --version >/dev/null
  netx --version >/dev/null
  bash -n /usr/local/bin/show-banner
  jq -e ".generated_at | type == \"string\"" "$RUNTIME_VERSIONS_DB" >/dev/null
  jq -e ".php.active | type == \"array\" and length > 0" "$RUNTIME_VERSIONS_DB" >/dev/null
  jq -e ".node.active | type == \"array\" and length > 0" "$RUNTIME_VERSIONS_DB" >/dev/null
'

name="tools-release-gate-${RANDOM}"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$name" "$IMAGE" >/dev/null

for _ in $(seq 1 30); do
  if docker exec "$name" tools-healthcheck >/dev/null 2>&1 \
    && docker exec "$name" sh -lc 'tr "\0" " " </proc/1/cmdline | grep -q notifierd' \
    && docker exec "$name" sh -lc 'tr "\0" "\n" </proc/1/environ | grep -qx "NOTIFY_TOKEN="' \
    && docker exec "$name" sh -lc 'wget -qO- http://127.0.0.1:9911/ >/dev/null'; then
    echo 'release gate: ok'
    exit 0
  fi
  sleep 1
done

docker logs "$name" >&2 || true
fail 'container runtime did not reach the full release-ready state'
