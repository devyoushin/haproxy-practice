# HAProxy 통계 및 모니터링 완전 가이드

HAProxy는 웹 기반 통계 페이지, Prometheus Exporter, Runtime API를 통해 상세한 운영 지표를 제공합니다.

---

## 1. Stats 페이지 설정

```haproxy
frontend stats
    bind *:8404
    mode http

    # 기본 통계 활성화
    stats enable
    stats uri /stats                           # 접근 URI
    stats realm "HAProxy Statistics"           # Basic Auth 영역
    stats auth admin:StrongPassword123         # 사용자:비밀번호
    stats auth readonly:readpass               # 추가 사용자

    # 자동 새로고침 (초)
    stats refresh 30s

    # 추가 정보 표시
    stats show-legends                         # 범례 표시
    stats show-node                            # 서버 노드 이름 표시
    stats show-desc "Production Load Balancer" # 설명 표시

    # 버전 정보 숨김 (보안)
    stats hide-version

    # 관리 기능 활성화 (서버 활성화/비활성화 등)
    stats admin if TRUE

    # 특정 IP만 접근 허용
    acl local_network src 10.0.0.0/8 192.168.0.0/16
    http-request deny if !local_network

    timeout connect 5s
    timeout client  60s
    timeout server  60s
```

---

## 2. Stats 페이지 항목 설명

### 상단 정보 영역
| 항목 | 설명 |
|------|------|
| HAProxy version | 현재 실행 중인 HAProxy 버전 |
| PID | 프로세스 ID |
| nbthread | 실행 중인 스레드 수 |
| Uptime | 실행 시간 |
| System time | 현재 시스템 시각 |
| Total sessions | 누적 세션 수 |
| Max sessions | 최대 동시 세션 수 |
| Limit sessions | 설정된 maxconn 값 |
| Current session rate | 현재 초당 세션 수 |

### 서버 상태 테이블 컬럼

| 컬럼 | 설명 |
|------|------|
| `Name` | 프론트엔드/백엔드/서버 이름 |
| `Status` | 현재 상태 (UP, DOWN, MAINT, DRAIN 등) |
| `Weight` | 현재 가중치 |
| `Act` | 활성 서버 수 |
| `Bck` | 백업 서버 수 |
| `Chk` | 헬스체크 상태 |
| `Down` | 헬스체크 실패 횟수 |
| `Downtime` | 총 다운타임 |
| `Throttle` | Slowstart 진행률 (%) |
| `Rate` | 현재 초당 요청 수 |
| `Rate_Lim` | 초당 요청 제한값 |
| `Rate_Max` | 최대 초당 요청 수 |
| `Req_Rate` | 현재 초당 HTTP 요청 수 |
| `Req_Rate_Max` | 최대 초당 HTTP 요청 수 |
| `Req_Tot` | 누적 HTTP 요청 수 |
| `Cur` | 현재 활성 세션 수 |
| `Max` | 최대 활성 세션 수 |
| `Limit` | 세션 제한 (maxconn) |
| `Total` | 누적 세션 수 |
| `Bin` | 수신 바이트 |
| `Bout` | 송신 바이트 |
| `In_Rate` | 현재 수신 속도 |
| `Out_Rate` | 현재 송신 속도 |
| `SCur` | 현재 세션 수 |
| `SMax` | 최대 동시 세션 수 |
| `SLimit` | 세션 제한값 |
| `STotal` | 누적 세션 수 |
| `Denied Req` | 차단된 요청 수 |
| `Denied Resp` | 차단된 응답 수 |
| `Err Req` | 요청 에러 수 |
| `Err Conn` | 연결 에러 수 |
| `Err Resp` | 응답 에러 수 |
| `Wredis` | 다른 서버로 재분배된 요청 수 |
| `Wretr` | 재시도된 요청 수 |
| `QCur` | 현재 큐 대기 수 |
| `QMax` | 최대 큐 대기 수 |
| `QLimit` | 큐 제한 |
| `Connect` | 서버 연결 성공 수 |
| `Reuse` | 연결 재사용 수 |

---

## 3. Prometheus Exporter

HAProxy 2.0.0+에서 내장 Prometheus 메트릭 엔드포인트를 제공합니다.

### 설정
```haproxy
frontend prometheus
    bind *:9100
    mode http
    http-request use-service prometheus-exporter if { path /metrics }
    # 기본 통계 페이지도 같은 포트로 제공 가능
    stats enable
    stats uri /stats

    # 접근 제한
    acl internal src 10.0.0.0/8 172.16.0.0/12
    http-request deny if !internal

    timeout connect 5s
    timeout client  30s
    timeout server  30s
```

### Prometheus 설정 (prometheus.yml)
```yaml
scrape_configs:
  - job_name: 'haproxy'
    static_configs:
      - targets: ['192.168.1.10:9100']
    metrics_path: '/metrics'
    scrape_interval: 15s
    scrape_timeout: 10s
```

### 주요 Prometheus 메트릭

| 메트릭 | 설명 |
|--------|------|
| `haproxy_process_nbthread` | 현재 스레드 수 |
| `haproxy_process_current_connections` | 현재 연결 수 |
| `haproxy_process_max_connections` | 최대 연결 수 설정값 |
| `haproxy_frontend_current_sessions` | 프론트엔드 현재 세션 수 |
| `haproxy_frontend_max_sessions` | 프론트엔드 최대 세션 수 |
| `haproxy_frontend_connections_total` | 프론트엔드 누적 연결 수 |
| `haproxy_frontend_bytes_in_total` | 프론트엔드 수신 바이트 |
| `haproxy_frontend_bytes_out_total` | 프론트엔드 송신 바이트 |
| `haproxy_frontend_http_requests_total` | HTTP 요청 총계 |
| `haproxy_backend_current_sessions` | 백엔드 현재 세션 수 |
| `haproxy_backend_current_queue` | 백엔드 현재 큐 수 |
| `haproxy_backend_connection_errors_total` | 연결 에러 수 |
| `haproxy_backend_response_errors_total` | 응답 에러 수 |
| `haproxy_server_current_sessions` | 서버 현재 세션 수 |
| `haproxy_server_check_status` | 서버 헬스체크 상태 (0=DOWN, 1=UP) |
| `haproxy_server_check_duration_seconds` | 헬스체크 소요 시간 |
| `haproxy_server_current_weight` | 서버 현재 가중치 |
| `haproxy_server_selected_total` | 서버 선택 횟수 |
| `haproxy_server_connection_reuses_total` | 연결 재사용 횟수 |

---

## 4. Runtime API로 통계 조회

```bash
# 기본 통계 (CSV 형식)
echo "show stat" | socat /run/haproxy/admin.sock stdio

# 읽기 쉽게 포맷
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' 'NR==1{print; next} {print}' | column -t -s','

# HAProxy 전체 정보
echo "show info" | socat /run/haproxy/admin.sock stdio

# 서버 상태 상세
echo "show servers state" | socat /run/haproxy/admin.sock stdio

# 현재 세션 목록
echo "show sess" | socat /run/haproxy/admin.sock stdio

# 세션 수 (연결 중)
echo "show info" | socat /run/haproxy/admin.sock stdio | grep "^Curr"

# 특정 백엔드의 통계만
echo "show stat" | socat /run/haproxy/admin.sock stdio | grep "^web_backend"
```

---

## 5. show stat CSV 필드 설명

`show stat` 명령의 CSV 출력 주요 필드:

| 인덱스 | 필드명 | 설명 |
|--------|--------|------|
| 0 | `pxname` | 프록시 이름 (frontend/backend/server) |
| 1 | `svname` | 서버 이름 또는 FRONTEND/BACKEND |
| 2 | `qcur` | 현재 큐 대기 수 |
| 3 | `qmax` | 최대 큐 대기 수 |
| 4 | `scur` | 현재 세션 수 |
| 5 | `smax` | 최대 세션 수 |
| 6 | `slim` | 세션 제한 |
| 7 | `stot` | 누적 세션 수 |
| 8 | `bin` | 수신 바이트 |
| 9 | `bout` | 송신 바이트 |
| 10 | `dreq` | 차단된 요청 수 |
| 11 | `dresp` | 차단된 응답 수 |
| 12 | `ereq` | 요청 에러 수 |
| 13 | `econ` | 연결 에러 수 |
| 14 | `eresp` | 응답 에러 수 |
| 15 | `wretr` | 재시도 수 |
| 16 | `wredis` | 재분배 수 |
| 17 | `status` | 상태 (UP/DOWN/OPEN/CLOSED) |
| 18 | `weight` | 가중치 |
| 19 | `act` | 활성 서버 수 |
| 20 | `bck` | 백업 서버 수 |
| 21 | `chkfail` | 헬스체크 실패 횟수 |
| 22 | `chkdown` | UP→DOWN 전환 횟수 |
| 23 | `lastchg` | 마지막 상태 변경 이후 초 |
| 24 | `downtime` | 총 다운타임 (초) |
| 33 | `rate` | 현재 세션 비율 |
| 34 | `rate_lim` | 세션 비율 제한 |
| 35 | `rate_max` | 최대 세션 비율 |
| 40 | `req_rate` | 요청 비율 (HTTP) |
| 41 | `req_rate_max` | 최대 요청 비율 |
| 42 | `req_tot` | 총 HTTP 요청 수 |
| 43 | `cli_abrt` | 클라이언트 중단 수 |
| 44 | `srv_abrt` | 서버 중단 수 |

---

## 6. show info 주요 출력

```bash
echo "show info" | socat /run/haproxy/admin.sock stdio
```

주요 출력 항목:
```
Name: HAProxy
Version: 2.8.3
Release_date: 2023/09/11
Nbthread: 4
Nbproc: 1
Process_num: 1
Pid: 12345
Uptime: 10d 5h 30m 15s
Uptime_sec: 893415

CurrConns: 1523           # 현재 연결 수
MaxConn: 50000            # 최대 연결 설정값
HardMaxConn: 50000        # 하드 최대 연결
CumConns: 45234567        # 누적 연결 수
CumReq: 123456789         # 누적 요청 수

MaxSessRate: 15000        # 최대 세션 비율
CurrSessRate: 1200        # 현재 세션 비율
SessRateLimit: 0          # 세션 비율 제한

SslCacheLookups: 9876543  # SSL 캐시 조회 수
SslCacheMisses: 123456    # SSL 캐시 미스 수
SslFrontendKeyRate: 150   # SSL 키 협상 비율

BytesIn: 1234567890       # 수신 바이트
BytesOut: 9876543210      # 송신 바이트

Tasks: 1600               # 스케줄러 태스크 수
Run_queue: 2              # 실행 큐 크기
Idle_pct: 87              # 유휴 시간 비율 (%)

node: haproxy-01          # 서버 노드 이름
description: Production   # 서버 설명
```

---

## 7. Grafana 대시보드 연동

### Prometheus + Grafana 스택

```yaml
# docker-compose.yml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  grafana-data:
```

### Grafana 대시보드 쿼리 예시

#### 현재 활성 연결 수 (PromQL)
```
haproxy_process_current_connections
```

#### 초당 HTTP 요청 수
```
sum(rate(haproxy_frontend_http_requests_total[5m])) by (proxy)
```

#### 서버별 현재 세션 수
```
haproxy_server_current_sessions{proxy="web_backend"}
```

#### 서버 상태 (0=DOWN, 1=UP)
```
haproxy_server_check_status{proxy="web_backend"}
```

#### 에러율 계산
```
sum(rate(haproxy_backend_response_errors_total[5m])) by (proxy)
/
sum(rate(haproxy_backend_http_responses_total[5m])) by (proxy)
```

#### 큐 대기 수 알림 규칙
```yaml
# prometheus-rules.yml
groups:
  - name: haproxy
    rules:
      - alert: HAProxyHighQueueLength
        expr: haproxy_backend_current_queue > 10
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "HAProxy backend queue is high"
          description: "Backend {{ $labels.proxy }} has {{ $value }} queued requests"

      - alert: HAProxyServerDown
        expr: haproxy_server_check_status == 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "HAProxy server is DOWN"
          description: "Server {{ $labels.server }} in backend {{ $labels.proxy }} is DOWN"

      - alert: HAProxyHighConnectionsUsage
        expr: haproxy_process_current_connections / haproxy_process_max_connections > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "HAProxy connection usage is above 80%"
```

---

## 8. 모니터링 스크립트

### 상태 체크 스크립트
```bash
#!/bin/bash
# haproxy-check.sh - HAProxy 상태 체크

SOCKET="/run/haproxy/admin.sock"
ALERT_EMAIL="admin@example.com"
MIN_SERVERS=1    # 최소 UP 서버 수

# 모든 백엔드 확인
check_backends() {
    echo "show stat" | socat "$SOCKET" stdio | \
    awk -F',' '
    $2 == "BACKEND" {
        split($18, status, " ")  # status 필드
        split($19, act, " ")     # act (활성 서버 수)
        if (act[1] < '"$MIN_SERVERS"') {
            printf "WARNING: Backend %s has only %s active server(s) (status: %s)\n", $1, act[1], status[1]
        }
    }'
}

# 연결 수 체크
check_connections() {
    local curr_conn max_conn usage
    curr_conn=$(echo "show info" | socat "$SOCKET" stdio | awk '/^CurrConns:/{print $2}')
    max_conn=$(echo "show info" | socat "$SOCKET" stdio | awk '/^MaxConn:/{print $2}')
    usage=$((curr_conn * 100 / max_conn))

    if [ "$usage" -gt 80 ]; then
        echo "WARNING: Connection usage at ${usage}% (${curr_conn}/${max_conn})"
    fi
}

# 메인 실행
echo "=== HAProxy Status Check $(date) ==="
check_backends
check_connections
echo "=== Check Complete ==="
```

### 통계 수집 스크립트
```bash
#!/bin/bash
# collect-stats.sh - 통계 수집 및 InfluxDB 전송

SOCKET="/run/haproxy/admin.sock"
INFLUX_URL="http://influxdb:8086"
INFLUX_DB="haproxy"

timestamp=$(date +%s%N)  # 나노초

# 연결 정보
info=$(echo "show info" | socat "$SOCKET" stdio)
curr_conn=$(echo "$info" | awk '/^CurrConns:/{print $2}')
curr_sess_rate=$(echo "$info" | awk '/^CurrSessRate:/{print $2}')
idle_pct=$(echo "$info" | awk '/^Idle_pct:/{print $2}')

# InfluxDB Line Protocol 형식으로 전송
curl -s -XPOST "${INFLUX_URL}/write?db=${INFLUX_DB}" --data-binary \
    "haproxy_stats,host=$(hostname) \
    curr_conn=${curr_conn},\
    curr_sess_rate=${curr_sess_rate},\
    idle_pct=${idle_pct} \
    ${timestamp}"

echo "Stats collected: conn=${curr_conn}, rate=${curr_sess_rate}, idle=${idle_pct}%"
```

---

## 9. 헬스체크 전용 엔드포인트

```haproxy
# HAProxy 자체 상태 확인용 (로드밸런서 앞단 NLB/ELB에서 사용)
frontend healthcheck
    bind *:9090
    mode http

    # HAProxy 자체가 200 OK 반환 (server 없이)
    monitor-uri /haproxy-alive

    # 특정 backend 정상 여부 확인
    acl web_ok nbsrv(web_backend) ge 1
    acl api_ok nbsrv(api_backend) ge 1
    monitor fail if !web_ok
    monitor fail if !api_ok

    # 이 프론트엔드는 server 지시어 없음
```

---

## 10. 실시간 모니터링 대시보드 CLI

```bash
#!/bin/bash
# haproxy-top.sh - 실시간 HAProxy 모니터링

SOCKET="/run/haproxy/admin.sock"
INTERVAL=2  # 새로고침 간격 (초)

watch -n $INTERVAL '
echo "=== HAProxy Live Monitor ===" $(date)
echo ""
echo "--- Connections ---"
echo "show info" | socat '"$SOCKET"' stdio | grep -E "CurrConns|MaxConn|CurrSessRate|Idle_pct"
echo ""
echo "--- Backend Status ---"
echo "show stat" | socat '"$SOCKET"' stdio | \
    awk -F"," "NR>1 && \$2==\"BACKEND\" {printf \"%-30s %s/%s servers, %s sessions, %s errors\n\", \$1, \$19, \$20, \$5, \$13}"
echo ""
echo "--- Server Status ---"
echo "show servers state" | socat '"$SOCKET"' stdio | \
    awk "NR>2 {printf \"%-20s %-20s %-10s %s\n\", \$2, \$4, \$6, \$9}"
'
```
