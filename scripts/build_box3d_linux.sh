#!/bin/sh
# Historical upstream-only glibc build; these binaries lack our projectile
# query and cannot run current gameplay. Use scripts/install_box3d.sh for
# the patched build. Kept to reproduce the September physics trial. Needs Docker:
#   scripts/build_box3d_linux.sh [out_dir]
# Produces libbox3d_godot.linux.template_{debug,release}.x86_64.so in out_dir.
set -eu
TAG=v0.4.3
TAG_COMMIT=3ce52ff999f2509a89ec53538ff77c3cf35092fa
OUT=${1:-$PWD/out}
mkdir -p "$OUT"
docker run --rm --network host \
  -e HTTPS_PROXY -e HTTP_PROXY -e https_proxy -e http_proxy -e NO_PROXY -e no_proxy \
  ${CA_BUNDLE:+-v "$CA_BUNDLE:/ca.crt:ro"} -e CA_BUNDLE=${CA_BUNDLE:+/ca.crt} \
  -e TAG="$TAG" -e TAG_COMMIT="$TAG_COMMIT" -v "$OUT:/out" ubuntu:22.04 sh -euc '
    if [ -n "$CA_BUNDLE" ]; then
      echo "Acquire::https::CAInfo \"$CA_BUNDLE\";" > /etc/apt/apt.conf.d/99ca
      export SSL_CERT_FILE=$CA_BUNDLE GIT_SSL_CAINFO=$CA_BUNDLE PIP_CERT=$CA_BUNDLE
    fi
    [ -n "${https_proxy:-}" ] && echo "Acquire::http::Proxy \"$https_proxy\"; Acquire::https::Proxy \"$https_proxy\";" > /etc/apt/apt.conf.d/99proxy
    # The proxy here takes only HTTPS, so fetch the archive over it.
    sed -i "s|http://|https://|g" /etc/apt/sources.list
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq build-essential git python3-pip >/dev/null
    python3 -m pip install -q "scons==4.8.1"
    git clone -q --recursive --depth 1 --branch "$TAG" https://github.com/Stink-O/box3d-godot.git /src
    cd /src && test "$(git rev-parse HEAD)" = "$TAG_COMMIT"
    cd godot
    gcc --version | head -1; ldd --version | head -1
    start=$(date +%s)
    scons -j"$(nproc)" platform=linux target=template_debug
    mid=$(date +%s)
    scons -j"$(nproc)" platform=linux target=template_release
    end=$(date +%s)
    echo "BUILD_SECONDS debug=$((mid-start)) release=$((end-mid))"
    cp demo/addons/box3d/bin/libbox3d_godot.linux.template_*.x86_64.so /out/
  '
ls -la "$OUT"
