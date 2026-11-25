#!/usr/bin/env bash
# ============================================================================
# Bring the db-config volume in line with the Postgres image that is about to start.
# ============================================================================
#   scripts/db-config-sync.sh            show what differs, change nothing
#   scripts/db-config-sync.sh --apply    copy the image's files into the volume
#
# Why: the named volume `db-config` is mounted over /etc/postgresql-custom. Docker fills a named
# volume from the image only when the volume is created, so after an image bump the volume still
# holds the OLD image's supautils.conf, extension-custom-scripts and conf.d — or, as in the
# 2026-11 rehearsal, a conf.d symlink to a path the new image no longer has, and Postgres then
# refuses to start ("could not open configuration directory /etc/postgresql-custom/conf.d").
#
# What --apply copies from the image (taken from the `db` service of docker-compose.yaml):
#   conf.d/*  supautils.conf  extension-custom-scripts/*
# It never touches pgsodium_root.key or any other file, and it deletes nothing. If conf.d in the
# volume is a symlink it stops and tells you; replace the symlink by hand first.
#
# Run it with the db container STOPPED, right before the first start of the new image.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="$(docker compose config --images db 2>/dev/null | head -n 1)"
PROJECT="$(docker compose config 2>/dev/null | sed -n 's/^name: //p' | head -n 1)"
VOLUME="${DB_CONFIG_VOLUME:-${PROJECT}_db-config}"
[ -n "$IMAGE" ] && [ -n "$PROJECT" ] || { echo "could not resolve image/project from docker compose config"; exit 1; }
docker volume inspect "$VOLUME" >/dev/null 2>&1 || { echo "volume $VOLUME does not exist"; exit 1; }

MODE=report
[ "${1:-}" = "--apply" ] && MODE=apply
echo "image:  $IMAGE"
echo "volume: $VOLUME   mode: $MODE"

docker run --rm -e MODE="$MODE" -v "$VOLUME":/vol --entrypoint sh "$IMAGE" -c '
    set -e
    S=/etc/postgresql-custom
    echo "--- volume now"; ls -ln /vol
    if [ -L /vol/conf.d ]; then
        echo "STOP: /vol/conf.d is a symlink -> $(readlink /vol/conf.d). Replace it by a real directory first."
        exit 3
    fi
    echo "--- key before: $(md5sum /vol/pgsodium_root.key 2>/dev/null | cut -c1-12)"
    echo "--- supautils.conf differs: $(cmp -s /vol/supautils.conf $S/supautils.conf && echo no || echo yes)"
    echo "--- conf.d in image:  $(ls $S/conf.d | tr "\n" " ")"
    echo "--- conf.d in volume: $(ls /vol/conf.d 2>/dev/null | tr "\n" " ")"
    echo "--- custom scripts only in image: $(for d in $(ls $S/extension-custom-scripts); do [ -e /vol/extension-custom-scripts/$d ] || printf "%s " $d; done)"
    [ "$MODE" = apply ] || { echo "report only; rerun with --apply"; exit 0; }
    mkdir -p /vol/conf.d
    cp -a $S/conf.d/. /vol/conf.d/
    cp -a $S/supautils.conf /vol/supautils.conf
    cp -a $S/extension-custom-scripts/. /vol/extension-custom-scripts/
    echo "--- applied"; ls -ln /vol /vol/conf.d
    echo "--- key after:  $(md5sum /vol/pgsodium_root.key 2>/dev/null | cut -c1-12)"
'
