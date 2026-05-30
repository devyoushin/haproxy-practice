# AL2023 HAProxy RPM 설치 가이드

## 1. 사전 준비

### 시스템 요구사항
- Amazon Linux 2023 (AL2023)
- 최소 1GB RAM 권장 (프로덕션 환경은 2GB 이상)
- root 또는 sudo 권한
- 인터넷 연결 (패키지 다운로드 시)

### AL2023에서 dnf로 설치가 안 되는 이유

AL2023의 기본 리포지토리에는 HAProxy가 포함되어 있지 않습니다.
EPEL(Extra Packages for Enterprise Linux) 리포지토리도 AL2023과 완전히
호환되지 않는 경우가 있습니다. AL2023은 RHEL 9 / Fedora 34 기반이지만,
패키지 네이밍 및 버전 충돌로 인해 직접 HAProxy RPM을 설치해야 합니다.

```bash
# AL2023에서 기본 설치 시도 시 실패하는 경우
sudo dnf install haproxy
# Error: Unable to find a match: haproxy

# EPEL 활성화 후 시도해도 버전 충돌 또는 미존재
sudo dnf install -y epel-release
sudo dnf install haproxy
# 결과: 버전 불일치 또는 의존성 충돌 가능
```

### 환경 정보 확인

```bash
# OS 버전 확인
cat /etc/os-release
# NAME="Amazon Linux"
# VERSION="2023"

# 아키텍처 확인
uname -m
# x86_64 또는 aarch64 (ARM)

# 커널 버전 확인
uname -r

# 사용 가능한 메모리 확인
free -h

# 디스크 공간 확인
df -h /
```

---

## 2. RPM 파일 직접 다운로드 설치 방법

### 방법 1: Fedora/RHEL 호환 RPM 다운로드

AL2023은 Fedora 기반이므로 Fedora 38/39용 RPM 또는 RHEL9용 RPM이 호환됩니다.

```bash
# 의존성 패키지 먼저 설치 (dnf로 설치 가능한 것들)
sudo dnf install -y pcre2 openssl lua systemd-libs zlib

# RPM 다운로드 디렉토리 생성
mkdir -p ~/haproxy-rpms
cd ~/haproxy-rpms

# === x86_64 아키텍처 ===
# HAProxy 2.8 LTS RPM 다운로드 (Fedora 38 기준)
# rpmfind.net 또는 packages.fedoraproject.org 에서 최신 URL 확인
wget https://dl.fedoraproject.org/pub/fedora/linux/releases/38/Everything/x86_64/os/Packages/h/haproxy-2.8.1-1.fc38.x86_64.rpm

# === aarch64 (ARM) 아키텍처 ===
wget https://dl.fedoraproject.org/pub/fedora/linux/releases/38/Everything/aarch64/os/Packages/h/haproxy-2.8.1-1.fc38.aarch64.rpm

# 다운로드한 RPM 정보 확인
rpm -qpi haproxy-*.rpm

# rpm으로 직접 설치 (의존성 미해결 시 오류 발생)
sudo rpm -ivh haproxy-*.rpm

# 또는 dnf localinstall 사용 (의존성 자동 해결 - 권장)
sudo dnf localinstall haproxy-*.rpm -y

# 설치 확인
rpm -q haproxy
haproxy -v
```

#### RPM 검색 사이트
| 사이트 | URL | 설명 |
|--------|-----|------|
| Fedora 공식 | https://packages.fedoraproject.org | 최신 Fedora 패키지 |
| rpmfind.net | https://rpmfind.net | RPM 검색 엔진 |
| pkgs.org | https://pkgs.org | 다중 배포판 패키지 검색 |
| EPEL | https://dl.fedoraproject.org/pub/epel/ | Enterprise Linux 추가 패키지 |

---

### 방법 2: 소스에서 직접 빌드 후 설치

소스에서 직접 빌드하면 원하는 기능을 정확히 포함시킬 수 있습니다.

```bash
# ============================================================
# 빌드 의존성 설치
# ============================================================
sudo dnf install -y \
    gcc \
    make \
    openssl-devel \
    pcre2-devel \
    lua-devel \
    systemd-devel \
    zlib-devel \
    wget \
    tar

# ============================================================
# HAProxy 소스 다운로드
# ============================================================
cd /tmp
# HAProxy 2.8 LTS (안정 버전)
HAPROXY_VERSION="2.8.5"
wget https://www.haproxy.org/download/2.8/src/haproxy-${HAPROXY_VERSION}.tar.gz

# 다운로드 확인
ls -lh haproxy-${HAPROXY_VERSION}.tar.gz

# 압축 해제
tar xzf haproxy-${HAPROXY_VERSION}.tar.gz
cd haproxy-${HAPROXY_VERSION}

# 소스 구조 확인
ls -la

# ============================================================
# 빌드 옵션 설명
# ============================================================
# TARGET: 빌드 대상 OS
#   - linux-glibc: 최신 Linux (glibc 기반) - 권장
#   - linux-glibc-legacy: 구버전 Linux
#   - linux-musl: Alpine Linux 등 musl 기반
#
# USE_OPENSSL=1: OpenSSL을 이용한 SSL/TLS 지원
# USE_OPENSSL_WOLFSSL=1: wolfSSL 사용 (임베디드 환경)
# USE_LUA=1: Lua 5.3/5.4 스크립팅 지원
# USE_PCRE2=1: PCRE2 정규식 라이브러리 (USE_PCRE보다 빠름)
# USE_PCRE2_JIT=1: PCRE2 JIT 컴파일러 활성화
# USE_SYSTEMD=1: systemd 통합 (sd_notify 지원)
# USE_ZLIB=1: zlib 압축 지원
# USE_PROMEX=1: Prometheus exporter 내장 (/metrics 엔드포인트)
# USE_THREAD=1: 멀티스레딩 지원 (nbthread 사용 가능)
# USE_STATIC_PCRE2=1: PCRE2 정적 링크 (이식성 증가)
# USE_QUIC=1: QUIC/HTTP3 지원 (실험적, quictls 필요)

# ============================================================
# 빌드 실행
# ============================================================
make TARGET=linux-glibc \
    USE_OPENSSL=1 \
    USE_LUA=1 \
    USE_PCRE2=1 \
    USE_PCRE2_JIT=1 \
    USE_SYSTEMD=1 \
    USE_ZLIB=1 \
    USE_PROMEX=1 \
    USE_THREAD=1 \
    -j$(nproc)

# 빌드 확인 (에러 없이 완료되어야 함)
echo "Build exit code: $?"

# ============================================================
# 설치
# ============================================================
# PREFIX=/usr 로 설치하면 /usr/sbin/haproxy에 설치됨
sudo make install PREFIX=/usr

# 설치된 파일 확인
which haproxy
haproxy -v
# HAProxy version 2.8.5-...

# ============================================================
# 추가 디렉토리 및 파일 생성
# ============================================================
# 설정 디렉토리
sudo mkdir -p /etc/haproxy/conf.d
sudo mkdir -p /var/lib/haproxy

# 기본 설정 파일 복사 (소스에 샘플 있음)
sudo cp examples/haproxy.cfg /etc/haproxy/haproxy.cfg

# Man 페이지 설치 (선택)
sudo cp doc/haproxy.1 /usr/share/man/man1/
sudo gzip /usr/share/man/man1/haproxy.1
```

---

### 방법 3: rpmbuild로 RPM 패키지 직접 생성

팀 내 여러 서버에 배포하거나 패키지 관리를 원할 때 사용합니다.

```bash
# ============================================================
# RPM 빌드 환경 설정
# ============================================================
sudo dnf install -y rpm-build rpmdevtools

# RPM 빌드 트리 생성 (~/.rpmbuild 구조 생성)
rpmdev-setuptree

# 생성된 디렉토리 구조 확인
ls ~/rpmbuild/
# BUILD  BUILDROOT  RPMS  SOURCES  SPECS  SRPMS

# ============================================================
# SPEC 파일 생성
# ============================================================
cat > ~/rpmbuild/SPECS/haproxy.spec << 'EOF'
Name:           haproxy
Version:        2.8.5
Release:        1%{?dist}
Summary:        HAProxy - The Reliable Solution for High Availability Load Balancing
License:        GPLv2+
URL:            https://www.haproxy.org/
Source0:        haproxy-%{version}.tar.gz

BuildRequires:  gcc make openssl-devel pcre2-devel lua-devel systemd-devel zlib-devel
Requires:       openssl pcre2 lua systemd
Requires(pre):  shadow-utils

%description
HAProxy is a free, very fast and reliable solution offering high availability,
load balancing, and proxying for TCP and HTTP-based applications.
It is particularly suited for very high traffic web sites and powers quite a
number of the world's most visited ones.

%pre
# haproxy 사용자 및 그룹 생성
getent group haproxy >/dev/null || groupadd -r haproxy
getent passwd haproxy >/dev/null || \
    useradd -r -g haproxy -d /var/lib/haproxy \
    -s /sbin/nologin -c "HAProxy" haproxy
exit 0

%prep
%setup -q

%build
make TARGET=linux-glibc \
    USE_OPENSSL=1 \
    USE_LUA=1 \
    USE_PCRE2=1 \
    USE_PCRE2_JIT=1 \
    USE_SYSTEMD=1 \
    USE_ZLIB=1 \
    USE_PROMEX=1 \
    USE_THREAD=1 \
    -j%{?_smp_mflags}

%install
make install PREFIX=%{buildroot}/usr SBINDIR=%{buildroot}/usr/sbin

# 디렉토리 생성
mkdir -p %{buildroot}/etc/haproxy/conf.d
mkdir -p %{buildroot}/var/lib/haproxy
mkdir -p %{buildroot}/run/haproxy
mkdir -p %{buildroot}/usr/lib/systemd/system
mkdir -p %{buildroot}/etc/sysconfig
mkdir -p %{buildroot}/etc/rsyslog.d
mkdir -p %{buildroot}/etc/logrotate.d

# 기본 설정 파일 설치
install -m 644 examples/haproxy.cfg %{buildroot}/etc/haproxy/haproxy.cfg

# systemd 서비스 파일 생성
cat > %{buildroot}/usr/lib/systemd/system/haproxy.service << 'SYSTEMD'
[Unit]
Description=HAProxy Load Balancer
Documentation=man:haproxy(1)
Documentation=file:/usr/share/doc/haproxy/configuration.txt.gz
After=network-online.target rsyslog.service
Wants=network-online.target

[Service]
Environment="CONFIG=/etc/haproxy/haproxy.cfg" "PIDFILE=/run/haproxy.pid"
EnvironmentFile=-/etc/sysconfig/haproxy
ExecStartPre=/usr/sbin/haproxy -f $CONFIG -c -q $OPTIONS
ExecStart=/usr/sbin/haproxy -Ws -f $CONFIG -p $PIDFILE $OPTIONS
ExecReload=/usr/sbin/haproxy -f $CONFIG -c -q $OPTIONS
ExecReload=/bin/kill -USR2 $MAINPID
KillMode=mixed
Restart=always
SuccessExitStatus=143
Type=notify
User=haproxy
Group=haproxy
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SYSTEMD

# sysconfig 파일
cat > %{buildroot}/etc/sysconfig/haproxy << 'SYSCONFIG'
# HAProxy 추가 옵션
OPTIONS=""
SYSCONFIG

# rsyslog 설정
cat > %{buildroot}/etc/rsyslog.d/haproxy.conf << 'RSYSLOG'
# HAProxy 로그를 별도 파일에 저장
$ModLoad imudp
$UDPServerRun 514
local0.*    /var/log/haproxy.log
& stop
RSYSLOG

# logrotate 설정
cat > %{buildroot}/etc/logrotate.d/haproxy << 'LOGROTATE'
/var/log/haproxy.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        /bin/kill -HUP $(cat /run/rsyslogd.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
LOGROTATE

%post
systemctl daemon-reload >/dev/null 2>&1 || :

%preun
if [ $1 -eq 0 ]; then
    systemctl stop haproxy >/dev/null 2>&1 || :
    systemctl disable haproxy >/dev/null 2>&1 || :
fi

%postun
systemctl daemon-reload >/dev/null 2>&1 || :

%files
%doc CHANGELOG README doc/
%license LICENSE
/usr/sbin/haproxy
%config(noreplace) /etc/haproxy/haproxy.cfg
%dir /etc/haproxy
%dir /etc/haproxy/conf.d
%dir /var/lib/haproxy
/usr/lib/systemd/system/haproxy.service
%config(noreplace) /etc/sysconfig/haproxy
%config(noreplace) /etc/rsyslog.d/haproxy.conf
%config(noreplace) /etc/logrotate.d/haproxy

%changelog
* Mon Jan 01 2024 Admin <admin@example.com> - 2.8.5-1
- Initial RPM package for Amazon Linux 2023
EOF

# ============================================================
# 소스 다운로드 및 RPM 빌드
# ============================================================
cd ~/rpmbuild/SOURCES
wget https://www.haproxy.org/download/2.8/src/haproxy-2.8.5.tar.gz

# RPM 빌드 시작
rpmbuild -ba ~/rpmbuild/SPECS/haproxy.spec

# 빌드된 RPM 위치 확인
ls -la ~/rpmbuild/RPMS/x86_64/

# ============================================================
# 생성된 RPM 설치
# ============================================================
sudo rpm -ivh ~/rpmbuild/RPMS/x86_64/haproxy-2.8.5-1.*.rpm

# 또는
sudo dnf localinstall ~/rpmbuild/RPMS/x86_64/haproxy-2.8.5-1.*.rpm -y
```

---

## 3. 설치 후 설정

### haproxy 사용자 생성 (소스 설치 시)

RPM 설치 시에는 자동으로 생성되지만, 소스 설치 시에는 수동으로 생성해야 합니다.

```bash
# HAProxy는 권한 분리를 위해 별도 사용자 계정이 필요합니다
# -r: 시스템 계정 (UID < 1000)
# -s /sbin/nologin: 로그인 불가
# -d /var/lib/haproxy: 홈 디렉토리
sudo useradd -r -s /sbin/nologin -d /var/lib/haproxy -c "HAProxy" haproxy

# 디렉토리 소유자 설정
sudo mkdir -p /var/lib/haproxy
sudo chown haproxy:haproxy /var/lib/haproxy
sudo chmod 750 /var/lib/haproxy

# 사용자 확인
id haproxy
# uid=998(haproxy) gid=998(haproxy) groups=998(haproxy)
```

### 디렉토리 구조

```
/etc/haproxy/
├── haproxy.cfg          # 메인 설정 파일
└── conf.d/              # 추가 설정 파일 디렉토리 (선택)
    ├── backends.cfg     # 백엔드 분리 파일 예시
    └── frontends.cfg    # 프론트엔드 분리 파일 예시

/var/lib/haproxy/        # HAProxy 런타임 데이터 (chroot 디렉토리)
/run/haproxy.pid         # PID 파일
/run/haproxy/admin.sock  # Runtime API 소켓 (선택)
/var/log/haproxy.log     # 로그 파일 (rsyslog 설정 필요)
```

### 기본 설정 파일 생성

```bash
sudo tee /etc/haproxy/haproxy.cfg << 'EOF'
#---------------------------------------------------------------------
# 전역 설정
#---------------------------------------------------------------------
global
    # 로그 설정 (syslog로 전송)
    log         127.0.0.1 local0 notice
    log         127.0.0.1 local1 notice

    # 보안: chroot 및 권한 낮추기
    chroot      /var/lib/haproxy
    user        haproxy
    group       haproxy
    daemon

    # 최대 연결 수
    maxconn     4000

    # PID 파일
    pidfile     /run/haproxy.pid

    # Stats 소켓 (Runtime API)
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s

#---------------------------------------------------------------------
# 기본값 설정
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

#---------------------------------------------------------------------
# 통계 페이지
#---------------------------------------------------------------------
frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats auth admin:password
    stats admin if LOCALHOST

#---------------------------------------------------------------------
# 메인 프론트엔드
#---------------------------------------------------------------------
frontend main
    bind *:80
    default_backend             app

#---------------------------------------------------------------------
# 백엔드
#---------------------------------------------------------------------
backend app
    balance     roundrobin
    server  app1 127.0.0.1:5001 check
    server  app2 127.0.0.1:5002 check
    server  app3 127.0.0.1:5003 check backup
EOF
```

### rsyslog 설정 (로그)

```bash
# /etc/rsyslog.d/haproxy.conf 생성
sudo tee /etc/rsyslog.d/haproxy.conf << 'EOF'
# HAProxy 로그를 별도 파일에 저장
# UDP 514 포트에서 syslog 수신
$ModLoad imudp
$UDPServerRun 514

# local0 -> haproxy.log
local0.*    /var/log/haproxy.log

# 중복 방지 (다른 파일에 저장 안 함)
& stop
EOF

# rsyslog 재시작
sudo systemctl restart rsyslog

# 로그 파일 권한 설정
sudo touch /var/log/haproxy.log
sudo chmod 644 /var/log/haproxy.log
```

### logrotate 설정

```bash
sudo tee /etc/logrotate.d/haproxy << 'EOF'
/var/log/haproxy.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /bin/kill -HUP $(cat /run/rsyslogd.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOF
```

### systemd 서비스 파일 생성 (소스 설치 시)

```bash
sudo tee /usr/lib/systemd/system/haproxy.service << 'EOF'
[Unit]
Description=HAProxy Load Balancer
Documentation=man:haproxy(1)
After=network-online.target rsyslog.service
Wants=network-online.target

[Service]
Environment="CONFIG=/etc/haproxy/haproxy.cfg" "PIDFILE=/run/haproxy.pid"
EnvironmentFile=-/etc/sysconfig/haproxy
ExecStartPre=/usr/sbin/haproxy -f $CONFIG -c -q $OPTIONS
ExecStart=/usr/sbin/haproxy -Ws -f $CONFIG -p $PIDFILE $OPTIONS
ExecReload=/usr/sbin/haproxy -f $CONFIG -c -q $OPTIONS
ExecReload=/bin/kill -USR2 $MAINPID
KillMode=mixed
Restart=always
SuccessExitStatus=143
Type=notify
User=haproxy
Group=haproxy
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
RuntimeDirectory=haproxy
RuntimeDirectoryMode=0775

[Install]
WantedBy=multi-user.target
EOF

# systemd 데몬 재로드
sudo systemctl daemon-reload
```

---

## 4. 서비스 시작 및 관리

```bash
# ============================================================
# 설정 파일 문법 검증 (시작 전 필수)
# ============================================================
sudo haproxy -f /etc/haproxy/haproxy.cfg -c
# 성공 시: Configuration file is valid

# 여러 파일 검증
sudo haproxy -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d/ -c

# ============================================================
# 서비스 시작
# ============================================================
sudo systemctl start haproxy

# 부팅 시 자동 시작 활성화
sudo systemctl enable haproxy

# 시작 + 자동 활성화 동시에
sudo systemctl enable --now haproxy

# ============================================================
# 서비스 상태 확인
# ============================================================
sudo systemctl status haproxy
# ● haproxy.service - HAProxy Load Balancer
#      Loaded: loaded (/usr/lib/systemd/system/haproxy.service; enabled)
#      Active: active (running) since ...

# 상세 로그 확인
sudo journalctl -u haproxy -f
sudo journalctl -u haproxy --since "10 minutes ago"

# ============================================================
# 서비스 제어
# ============================================================
# 중지
sudo systemctl stop haproxy

# 재시작 (설정 파일 재로드 포함)
sudo systemctl restart haproxy

# 무중단 설정 재로드 (기존 연결 유지)
sudo systemctl reload haproxy
# 또는
sudo kill -USR2 $(cat /run/haproxy.pid)
```

---

## 5. 설치 확인

```bash
# ============================================================
# 버전 및 빌드 정보 확인
# ============================================================
haproxy -v
# HAProxy version 2.8.5-...
# Status: long-term supported branch - will stop receiving fixes around Q2 2028.

# 빌드 옵션 확인 (상세 버전 정보)
haproxy -vv
# HAProxy version 2.8.5-...
# Build options :
#   TARGET  = linux-glibc
#   CPU     = generic
#   CC      = gcc
#   CFLAGS  = ...
#   OPTIONS = USE_PCRE2=1 USE_OPENSSL=1 USE_LUA=1 ...

# ============================================================
# 프로세스 확인
# ============================================================
ps aux | grep haproxy
pgrep -a haproxy

# ============================================================
# 포트 리스닝 확인
# ============================================================
sudo ss -tlnp | grep haproxy
# LISTEN 0 4096 0.0.0.0:80 0.0.0.0:* users:(("haproxy",pid=...,fd=...))

# ============================================================
# 실제 요청 테스트
# ============================================================
curl -v http://localhost/
curl -I http://localhost/

# Stats 페이지 확인
curl http://localhost:8404/stats

# ============================================================
# 연결 통계 확인
# ============================================================
# Runtime API (소켓이 설정된 경우)
echo "show info" | sudo socat stdio /run/haproxy/admin.sock
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock

# ============================================================
# RPM 설치 정보 확인 (RPM 방식 설치 시)
# ============================================================
rpm -qi haproxy
rpm -ql haproxy  # 설치된 파일 목록
```

---

## 6. 방화벽 설정

```bash
# ============================================================
# firewalld 사용 시
# ============================================================
# HAProxy가 사용할 포트 허용
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=8404/tcp   # Stats 페이지
sudo firewall-cmd --permanent --add-port=9000/tcp   # 커스텀 포트 (필요 시)
sudo firewall-cmd --reload

# 현재 허용된 포트 확인
sudo firewall-cmd --list-all

# ============================================================
# iptables 직접 사용 시
# ============================================================
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8404 -j ACCEPT

# iptables 규칙 저장
sudo service iptables save

# ============================================================
# AWS 보안 그룹
# ============================================================
# EC2 인스턴스 사용 시 AWS 콘솔 또는 CLI로 보안 그룹 설정:
aws ec2 authorize-security-group-ingress \
    --group-id sg-xxxxxxxx \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id sg-xxxxxxxx \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0
```

---

## 7. 업그레이드 방법

```bash
# ============================================================
# RPM 업그레이드
# ============================================================
# 새 버전 RPM 다운로드 후
sudo rpm -Uvh haproxy-新버전.rpm

# ============================================================
# 소스 빌드 업그레이드
# ============================================================
# 1. 새 소스 다운로드 및 빌드
cd /tmp
wget https://www.haproxy.org/download/2.8/src/haproxy-2.8.NEW.tar.gz
tar xzf haproxy-2.8.NEW.tar.gz
cd haproxy-2.8.NEW

make TARGET=linux-glibc \
    USE_OPENSSL=1 USE_LUA=1 USE_PCRE2=1 \
    USE_SYSTEMD=1 USE_ZLIB=1 USE_PROMEX=1 \
    -j$(nproc)

# 2. 무중단 업그레이드 (소프트 리스타트)
# 새 바이너리를 임시 경로에 저장
sudo cp haproxy /usr/sbin/haproxy.new

# 3. 설정 검증
sudo /usr/sbin/haproxy.new -f /etc/haproxy/haproxy.cfg -c

# 4. 원자적 교체 후 reload
sudo mv /usr/sbin/haproxy.new /usr/sbin/haproxy
sudo systemctl reload haproxy

# ============================================================
# 업그레이드 후 확인
# ============================================================
haproxy -v
sudo systemctl status haproxy
```

---

## 8. 문제 해결

### 설치 중 의존성 오류

```bash
# 오류: 의존성 패키지 누락
rpm -ivh haproxy-*.rpm
# error: Failed dependencies:
#     libssl.so.3 is needed by haproxy-...

# 해결: dnf로 의존성 설치
sudo dnf install -y openssl-libs pcre2 lua

# 또는 dnf localinstall 사용 (자동 해결)
sudo dnf localinstall haproxy-*.rpm
```

### 서비스 시작 실패

```bash
# 오류 확인
sudo systemctl status haproxy
sudo journalctl -xe -u haproxy

# 설정 파일 문법 오류 확인
sudo haproxy -f /etc/haproxy/haproxy.cfg -c

# 포트 이미 사용 중인지 확인
sudo ss -tlnp | grep :80
sudo fuser 80/tcp

# 디렉토리 권한 확인
ls -la /var/lib/haproxy
ls -la /run/haproxy/

# 소켓 디렉토리 생성
sudo mkdir -p /run/haproxy
sudo chown haproxy:haproxy /run/haproxy
```

### 권한 문제

```bash
# 1024 이하 포트 바인딩 시 root 권한 필요
# systemd 서비스에서 AmbientCapabilities 설정으로 해결
sudo setcap 'cap_net_bind_service=+ep' /usr/sbin/haproxy

# SELinux 관련 문제 (AL2023)
sudo ausearch -c haproxy --raw | audit2allow -M haproxy-local
sudo semodule -i haproxy-local.pp
```
