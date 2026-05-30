# HAProxy 고가용성 (HA) 구성 완전 가이드

HAProxy 자체의 고가용성을 위해 다양한 방법을 사용합니다.
가장 일반적인 방법은 Keepalived + VRRP를 통한 가상 IP 플로팅입니다.

---

## 1. 아키텍처 개요

### 기본 Active-Passive HA

```
클라이언트
    ↓ (VIP: 192.168.1.100)
[MASTER - haproxy1] ← Keepalived VRRP → [BACKUP - haproxy2]
    ↓                                        ↓
[웹 서버 1][웹 서버 2][웹 서버 3]        (대기 중)
```

### Active-Active HA (DNS Round Robin 또는 ECMP)

```
클라이언트
    ↓
[DNS/Router] → haproxy1 (192.168.1.10) ─┐
             → haproxy2 (192.168.1.11) ─┤→ [백엔드 서버]
             → haproxy3 (192.168.1.12) ─┘
```

---

## 2. Keepalived + HAProxy (VRRP)

### 설치
```bash
# Ubuntu/Debian
apt-get install keepalived

# CentOS/RHEL
yum install keepalived
```

### MASTER 노드 설정 (/etc/keepalived/keepalived.conf)
```
# HAProxy 상태 체크 스크립트
vrrp_script chk_haproxy {
    script "kill -0 $(cat /run/haproxy.pid 2>/dev/null)"
    interval 2      # 2초마다 체크
    weight 2        # 성공 시 priority +2
    fall 2          # 2번 실패 시 DOWN 판정
    rise 1          # 1번 성공 시 UP 판정
}

# HAProxy 포트 체크 스크립트 (더 정확한 방법)
vrrp_script chk_haproxy_port {
    script "/bin/bash -c 'echo '' > /dev/tcp/127.0.0.1/80' 2>/dev/null"
    interval 2
    weight -20      # 실패 시 priority -20 (MASTER → BACKUP 전환)
    fall 2
    rise 1
}

vrrp_instance VI_1 {
    state MASTER          # 이 노드가 MASTER
    interface eth0        # VIP를 바인딩할 네트워크 인터페이스
    virtual_router_id 51  # VRID (0-255, 같은 네트워크에서 고유해야 함)
    priority 101          # 높을수록 MASTER가 됨 (BACKUP은 100 이하)
    advert_int 1          # 광고 간격 (초)
    nopreempt            # 선택: MASTER가 복구되어도 자동으로 돌아오지 않음

    authentication {
        auth_type PASS
        auth_pass MySecretVRRPPass123  # MASTER와 BACKUP이 동일해야 함
    }

    virtual_ipaddress {
        192.168.1.100/24 dev eth0 label eth0:vip  # 가상 IP
    }

    # 여러 VIP
    # virtual_ipaddress {
    #     192.168.1.100/24
    #     192.168.1.101/24
    # }

    track_script {
        chk_haproxy
        chk_haproxy_port
    }

    # MASTER 전환 시 실행할 스크립트
    notify_master /etc/keepalived/master.sh
    notify_backup /etc/keepalived/backup.sh
    notify_fault  /etc/keepalived/fault.sh
}
```

### BACKUP 노드 설정 (/etc/keepalived/keepalived.conf)
```
vrrp_script chk_haproxy {
    script "kill -0 $(cat /run/haproxy.pid 2>/dev/null)"
    interval 2
    weight 2
    fall 2
    rise 1
}

vrrp_instance VI_1 {
    state BACKUP         # 이 노드가 BACKUP
    interface eth0
    virtual_router_id 51 # MASTER와 동일해야 함
    priority 100         # MASTER보다 낮아야 함
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass MySecretVRRPPass123  # MASTER와 동일
    }

    virtual_ipaddress {
        192.168.1.100/24 dev eth0 label eth0:vip
    }

    track_script {
        chk_haproxy
    }

    notify_master /etc/keepalived/master.sh
    notify_backup /etc/keepalived/backup.sh
}
```

### 전환 알림 스크립트
```bash
#!/bin/bash
# /etc/keepalived/master.sh - MASTER가 되었을 때

STATE="MASTER"
INTERFACE="eth0"
VRRP_ID=$3

logger "VRRP: Transitioning to $STATE (VR_ID: $VRRP_ID)"

# HAProxy 시작 (혹시 중지된 경우)
systemctl start haproxy

# 알림 이메일 발송 (옵션)
# echo "HAProxy node $(hostname) is now MASTER" | mail -s "HA Failover" admin@example.com

# 슬랙/텔레그램 알림 (옵션)
# curl -s -X POST "https://hooks.slack.com/..." \
#     -d '{"text":"HAProxy MASTER: '$(hostname)' has become the active node"}'
```

```bash
#!/bin/bash
# /etc/keepalived/backup.sh - BACKUP이 되었을 때

STATE="BACKUP"
logger "VRRP: Transitioning to $STATE"
# BACKUP이 되었을 때 특별한 조치 없음
# HAProxy는 계속 실행 (모니터링 목적)
```

---

## 3. Keepalived 관리

```bash
# 서비스 시작/중지
systemctl start keepalived
systemctl stop keepalived
systemctl restart keepalived

# 상태 확인
systemctl status keepalived

# VRRP 상태 확인
ip addr show eth0  # VIP가 eth0에 있으면 MASTER

# 로그 확인
journalctl -u keepalived -f
grep keepalived /var/log/syslog

# 수동으로 MASTER/BACKUP 전환 테스트
# MASTER에서 keepalived 중지 → BACKUP이 MASTER로 승격
systemctl stop keepalived  # MASTER 노드에서 실행
# BACKUP이 MASTER로 전환되는지 확인
ip addr show eth0  # BACKUP 노드에서
```

---

## 4. Peers 섹션 (Stick Table 동기화)

여러 HAProxy 인스턴스 간에 Stick Table을 실시간으로 동기화합니다.

```haproxy
# haproxy1 (192.168.1.10)의 설정
peers haproxy_cluster
    bind 192.168.1.10:1024   # 이 노드가 수신할 주소
    peer haproxy1 192.168.1.10:1024
    peer haproxy2 192.168.1.11:1024

    # 선택: Stick Table을 peers 섹션에 직접 정의
    table web_sessions type ip size 1m expire 30m store server_id,gpc0,http_req_rate(10s)

frontend web_front
    bind *:80
    mode http
    stick-table type ip size 1m expire 30s peers haproxy_cluster store http_req_rate(10s),conn_cur
    http-request track-sc0 src
    default_backend web_backend

backend web_backend
    stick-table type ip size 100k expire 30m peers haproxy_cluster store server_id
    stick on src
    server web1 10.0.0.1:80 check
    server web2 10.0.0.2:80 check
```

```haproxy
# haproxy2 (192.168.1.11)의 설정 (bind 주소만 다름)
peers haproxy_cluster
    bind 192.168.1.11:1024   # 이 노드의 주소로 변경
    peer haproxy1 192.168.1.10:1024
    peer haproxy2 192.168.1.11:1024

# 나머지 설정은 haproxy1과 동일
```

### 피어 동기화 상태 확인
```bash
echo "show peers" | socat /run/haproxy/admin.sock stdio
```

---

## 5. 무중단 재시작/리로드

### 설정 파일 검증
```bash
# 설정 파일 문법 검사 (항상 먼저 실행)
haproxy -f /etc/haproxy/haproxy.cfg -c

# 여러 파일 사용 시
haproxy -f /etc/haproxy/haproxy.cfg \
        -f /etc/haproxy/conf.d/ \
        -c
```

### 무중단 리로드 방법
```bash
# 방법 1: systemctl reload (권장)
systemctl reload haproxy

# 방법 2: SIGUSR2 시그널 (기존 연결 유지하며 리로드)
kill -USR2 $(cat /run/haproxy.pid)

# 방법 3: -sf (soft finish) - 기존 연결이 끝날 때까지 기다림
haproxy -f /etc/haproxy/haproxy.cfg -sf $(cat /run/haproxy.pid)

# 방법 4: -st (soft terminate) - 기존 연결 즉시 종료 후 재시작
haproxy -f /etc/haproxy/haproxy.cfg -st $(cat /run/haproxy.pid)
```

### 리로드 vs 재시작 차이

| 방법 | 기존 연결 | 새 연결 | 다운타임 |
|------|---------|--------|---------|
| `reload` (`-sf`) | 처리 완료 후 종료 | 새 프로세스가 처리 | 없음 |
| `restart` | 즉시 종료 | 새 프로세스가 처리 | 짧게 있음 |
| `SIGUSR2` | 처리 완료 후 종료 | 새 프로세스가 처리 | 없음 |

---

## 6. 무중단 배포 스크립트

```bash
#!/bin/bash
# /usr/local/bin/haproxy-reload.sh

set -euo pipefail

CONFIG="/etc/haproxy/haproxy.cfg"
PIDFILE="/run/haproxy.pid"
LOG_TAG="haproxy-reload"

log() {
    logger -t "$LOG_TAG" "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 1. 설정 파일 검증
log "Validating HAProxy configuration..."
if ! haproxy -f "$CONFIG" -c; then
    log "ERROR: Configuration validation failed!"
    exit 1
fi
log "Configuration is valid."

# 2. 현재 실행 중인 프로세스 확인
if [ ! -f "$PIDFILE" ]; then
    log "HAProxy is not running. Starting..."
    systemctl start haproxy
    exit 0
fi

OLD_PID=$(cat "$PIDFILE")

# 3. 무중단 리로드
log "Reloading HAProxy (old PID: $OLD_PID)..."
haproxy -f "$CONFIG" -sf "$OLD_PID"

# 4. 리로드 확인
sleep 1
NEW_PID=$(cat "$PIDFILE" 2>/dev/null)
if [ -n "$NEW_PID" ] && [ "$NEW_PID" != "$OLD_PID" ]; then
    log "Reload successful! New PID: $NEW_PID"
else
    log "WARNING: PID file unchanged. Reload may have failed."
    exit 1
fi

log "HAProxy reload completed."
```

---

## 7. 헬스체크와 HA 시나리오

### 서버 장애 감지 및 복구 흐름

```
정상 상태:
web1 (UP) ← 트래픽
web2 (UP) ← 트래픽
web3 (UP) ← 트래픽

web1 장애 발생:
web1: 연속 3번 헬스체크 실패 (fall=3)
HAProxy: web1을 DOWN으로 표시
web1 (DOWN) ← 트래픽 없음
web2 (UP) ← 트래픽 (더 많이)
web3 (UP) ← 트래픽 (더 많이)
로그: "Server backend/web1 is DOWN, reason: Layer7 timeout"

web1 복구:
web1: 연속 2번 헬스체크 성공 (rise=2)
slowstart 30s: 0% → 30초에 걸쳐 100%로 점진적 증가
web1 (UP, throttle: 50%) ← 트래픽 (적게)
web2 (UP) ← 트래픽 (정상)
web3 (UP) ← 트래픽 (정상)
```

### 전체 서버 DOWN 시 동작
```haproxy
backend web
    # 모든 primary DOWN 시 backup 서버 사용
    server web1 10.0.0.1:80 check
    server web2 10.0.0.2:80 check
    server web_backup 10.0.0.100:80 check backup   # primary 모두 DOWN 시 사용

    # 모든 서버 DOWN 시 에러 페이지 (backup도 없는 경우)
    errorfile 503 /etc/haproxy/errors/503.http
```

---

## 8. 모니터링 기반 HA

```haproxy
# HAProxy 상태 확인용 엔드포인트 (Keepalived 스크립트에서 사용)
frontend healthcheck
    bind *:9090
    mode http
    monitor-uri /haproxy-alive

    # 백엔드 서버가 1개 이상 있어야 정상
    acl has_backend nbsrv(web_backend) ge 1
    monitor fail if !has_backend
```

Keepalived에서 사용:
```
vrrp_script chk_haproxy_health {
    script "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9090/haproxy-alive | grep -q 200"
    interval 3
    weight -30    # 실패 시 priority -30 (확실한 전환)
    fall 2
    rise 1
}
```

---

## 9. 다중 데이터센터 HA

```
데이터센터 1 (Primary):           데이터센터 2 (Disaster Recovery):
haproxy1 (MASTER, VIP: DC1-VIP) ←→ haproxy3 (MASTER, VIP: DC2-VIP)
haproxy2 (BACKUP)                  haproxy4 (BACKUP)
    ↓                                   ↓
[앱 서버 DC1]                      [앱 서버 DC2]

DNS: example.com → DC1-VIP (주), DC2-VIP (보조)
     또는 AWS Route 53 Health Check 기반 Failover
```

### HAProxy 설정 (지리적 분산)
```haproxy
# 로컬 데이터센터 서버 우선
backend web_backend
    balance roundrobin

    # DC1 서버 (높은 가중치 = 우선)
    server dc1_web1 10.0.1.10:80 check weight 100
    server dc1_web2 10.0.1.11:80 check weight 100

    # DC2 서버 (낮은 가중치 = 백업 역할)
    server dc2_web1 10.0.2.10:80 check weight 10
    server dc2_web2 10.0.2.11:80 check weight 10
```

---

## 10. Docker/Kubernetes 환경 HA

### Docker Swarm 환경
```yaml
# docker-compose.yml
version: '3.8'
services:
  haproxy:
    image: haproxy:2.8
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
      - ./certs:/etc/haproxy/certs:ro
    deploy:
      replicas: 2                    # 2개 인스턴스
      update_config:
        parallelism: 1               # 1개씩 업데이트 (무중단)
        delay: 10s
      restart_policy:
        condition: on-failure
```

### Kubernetes 환경에서 HAProxy 리로드
```bash
# Kubernetes에서는 설정 변경 시 graceful reload 사용
# ConfigMap 변경 → Pod 재시작 없이 리로드 가능

# HAProxy Kubernetes Ingress Controller 사용 시 자동 처리
# https://github.com/haproxytech/kubernetes-ingress

# 수동 리로드 (Pod 내에서)
kubectl exec -it haproxy-pod -- haproxy -f /etc/haproxy/haproxy.cfg -sf $(cat /run/haproxy.pid)
```

---

## 11. HA 체크리스트

```
1. 기본 HA 구성
   ✓ HAProxy 2개 이상 설치 및 설정 동일 유지
   ✓ Keepalived 설치 및 VRRP 설정
   ✓ 가상 IP (VIP) 설정
   ✓ 인증 패스워드 일치 확인
   ✓ 같은 virtual_router_id 사용

2. 설정 동기화
   ✓ 설정 파일 동기화 (rsync, git, Ansible 등)
   ✓ 인증서 파일 동기화
   ✓ 에러 파일 동기화

3. Stick Table 동기화 (세션 고정 사용 시)
   ✓ peers 섹션 설정
   ✓ 방화벽에서 peers 포트 (기본 1024) 개방
   ✓ 동기화 상태 확인: echo "show peers" | socat ...

4. 모니터링
   ✓ HAProxy 프로세스 모니터링
   ✓ VIP 상태 모니터링
   ✓ 백엔드 서버 헬스체크 로그 확인
   ✓ Keepalived 로그 모니터링

5. 장애 복구 테스트
   ✓ MASTER HAProxy 중지 → BACKUP이 VIP 인수하는지 확인
   ✓ MASTER 복구 → VIP 반환 (또는 nopreempt로 유지)
   ✓ 백엔드 서버 장애 → 자동 제외 확인
   ✓ 세션 유지 여부 확인 (Stick Table 동기화)
```
