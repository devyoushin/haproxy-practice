#!/usr/bin/env bash
set -euo pipefail

HAPROXY_VERSION="${HAPROXY_VERSION:-2.8.5}"
HAPROXY_INSTALL_METHOD="${HAPROXY_INSTALL_METHOD:-source}"
HAPROXY_RPM_DIR="${HAPROXY_RPM_DIR:-/tmp/haproxy-rpms}"
BUILD_DIR="${BUILD_DIR:-/usr/local/src}"

log() {
  printf '[haproxy-install] %s\n' "$*"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root or with sudo." >&2
    exit 1
  fi
}

install_common_packages() {
  dnf install -y pcre2 openssl lua systemd-libs zlib shadow-utils
}

install_with_dnf() {
  log "Installing HAProxy with dnf"
  dnf install -y haproxy
}

install_with_local_rpm() {
  log "Installing HAProxy from local RPMs: ${HAPROXY_RPM_DIR}"
  if ! compgen -G "${HAPROXY_RPM_DIR}/*.rpm" >/dev/null; then
    echo "No RPM files found in ${HAPROXY_RPM_DIR}" >&2
    exit 1
  fi
  dnf localinstall -y "${HAPROXY_RPM_DIR}"/*.rpm
}

install_from_source() {
  log "Installing build dependencies"
  dnf install -y \
    gcc \
    make \
    openssl-devel \
    pcre2-devel \
    lua-devel \
    systemd-devel \
    zlib-devel \
    wget \
    tar

  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}"

  if [ ! -f "haproxy-${HAPROXY_VERSION}.tar.gz" ]; then
    log "Downloading HAProxy ${HAPROXY_VERSION}"
    wget "https://www.haproxy.org/download/${HAPROXY_VERSION%.*}/src/haproxy-${HAPROXY_VERSION}.tar.gz"
  fi

  rm -rf "haproxy-${HAPROXY_VERSION}"
  tar xzf "haproxy-${HAPROXY_VERSION}.tar.gz"
  cd "haproxy-${HAPROXY_VERSION}"

  log "Building HAProxy ${HAPROXY_VERSION}"
  make -j"$(nproc)" TARGET=linux-glibc \
    USE_OPENSSL=1 \
    USE_LUA=1 \
    USE_PCRE2=1 \
    USE_PCRE2_JIT=1 \
    USE_SYSTEMD=1 \
    USE_ZLIB=1 \
    USE_PROMEX=1 \
    USE_THREAD=1

  make install-bin
}

create_user_and_dirs() {
  if ! id haproxy >/dev/null 2>&1; then
    useradd --system --home-dir /var/lib/haproxy --shell /sbin/nologin haproxy
  fi

  mkdir -p /etc/haproxy /var/lib/haproxy /run/haproxy
  chown -R haproxy:haproxy /var/lib/haproxy /run/haproxy
}

write_default_config_if_missing() {
  if [ -f /etc/haproxy/haproxy.cfg ]; then
    log "/etc/haproxy/haproxy.cfg already exists; leaving it unchanged"
    return
  fi

  log "Writing default /etc/haproxy/haproxy.cfg"
  cat >/etc/haproxy/haproxy.cfg <<'EOF'
global
    log stdout format raw local0
    user haproxy
    group haproxy
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners

defaults
    mode http
    log global
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend http_in
    bind *:80
    default_backend app

backend app
    http-request return status 200 content-type text/plain string "haproxy ok\n"
EOF
}

write_systemd_unit_if_missing() {
  if [ -f /etc/systemd/system/haproxy.service ] || [ -f /usr/lib/systemd/system/haproxy.service ]; then
    log "systemd unit already exists; leaving it unchanged"
    return
  fi

  log "Writing /etc/systemd/system/haproxy.service"
  cat >/etc/systemd/system/haproxy.service <<'EOF'
[Unit]
Description=HAProxy Load Balancer
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/sbin/haproxy -Ws -f /etc/haproxy/haproxy.cfg -p /run/haproxy.pid
ExecReload=/usr/local/sbin/haproxy -Ws -f /etc/haproxy/haproxy.cfg -c -q
ExecReload=/bin/kill -USR2 $MAINPID
KillMode=mixed
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

enable_service() {
  systemctl daemon-reload
  haproxy -c -f /etc/haproxy/haproxy.cfg
  systemctl enable --now haproxy
  systemctl --no-pager --full status haproxy
}

main() {
  require_root
  install_common_packages

  case "${HAPROXY_INSTALL_METHOD}" in
    dnf)
      install_with_dnf
      ;;
    local-rpm)
      install_with_local_rpm
      ;;
    source)
      install_from_source
      ;;
    *)
      echo "Unsupported HAPROXY_INSTALL_METHOD: ${HAPROXY_INSTALL_METHOD}" >&2
      exit 1
      ;;
  esac

  create_user_and_dirs
  write_default_config_if_missing
  write_systemd_unit_if_missing
  enable_service
  log "Done"
}

main "$@"
