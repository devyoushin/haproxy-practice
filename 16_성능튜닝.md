# HAProxy 성능 튜닝 완전 가이드

HAProxy는 기본 설정으로도 높은 성능을 발휘하지만, 워크로드와 하드웨어에 맞게 튜닝하면
더욱 높은 처리량과 낮은 지연 시간을 달성할 수 있습니다.

---

## 1. 성능 기준 지표

튜닝 전에 현재 성능을 측정합니다.

```bash
# 현재 연결 수 및 초당 요청 수 확인
echo "show info" | socat /run/haproxy/admin.sock stdio | grep -E "CurrConns|CurrSessRate|MaxConn|Idle_pct"

# CPU 사용률 확인
top -b -n 1 -p $(cat /run/haproxy.pid)

# 메모리 사용량 확인
cat /proc/$(cat /run/haproxy.pid)/status | grep -E "VmRSS|VmPeak"

# 네트워크 통계
ss -s

# 파일 디스크립터 사용량
lsof -p $(cat /run/haproxy.pid) | wc -l
```

---

## 2. 커넥션 수 튜닝

```haproxy
global
    # HAProxy 전체 최대 동시 연결 수
    # (각 연결당 약 2-3개의 파일 디스크립터 필요)
    maxconn 100000

    # 초당 최대 새 연결 수 (0=제한없음)
    maxconnrate 10000

    # 초당 최대 새 세션 수
    maxsessrate 10000

    # 초당 최대 SSL 핸드셰이크 수 (0=제한없음)
    maxsslrate 5000

    # 헬스체크 분산 (0-50%, 기본값 0)
    # 헬스체크를 균등하게 분산하여 체크 피크 방지
    spread-checks 5
```

### 연결 수 계산
```
maxconn 계산 공식:
maxconn = (사용 가능한 파일 디스크립터 수) / 2 - (여유분)

파일 디스크립터 확인:
ulimit -n  또는  cat /proc/sys/fs/file-max

예시:
ulimit -n = 200000
maxconn = 200000 / 2 - 1000 = 99000 → 100000으로 설정
```

---

## 3. 멀티스레딩

```haproxy
global
    # 스레드 수 (논리 CPU 수와 일치 권장)
    nbthread 8

    # CPU 어피니티 설정 (스레드를 특정 CPU 코어에 바인딩)
    # 형식: cpu-map <process>/<thread_range> <cpu_range>
    cpu-map auto:1/1-8 0-7  # 스레드 1-8을 CPU 코어 0-7에 매핑

    # NUMA 노드를 고려한 CPU 매핑
    # NUMA 노드 0: CPU 0-7, NUMA 노드 1: CPU 8-15
    # cpu-map auto:1/1-8 0-7    # 첫 번째 NUMA 노드
    # cpu-map auto:1/9-16 8-15  # 두 번째 NUMA 노드
```

### 최적 스레드 수 결정
```bash
# 논리 CPU 수 확인
nproc

# CPU 토폴로지 확인 (NUMA 등)
lscpu

# NUMA 노드 확인
numactl --hardware

# HAProxy 스레드 상태 확인
echo "show threads" | socat /run/haproxy/admin.sock stdio
```

### 스레드 수 권장사항

| 상황 | 권장 스레드 수 |
|------|-------------|
| 단순 TCP 프록시 | 논리 CPU의 50-75% |
| HTTP 로드밸런서 | 논리 CPU의 75-100% |
| SSL 집약적 | 논리 CPU의 100% |
| 고성능 필요 | 논리 CPU의 100% + CPU 어피니티 |

---

## 4. 버퍼 튜닝

```haproxy
global
    # 읽기/쓰기 버퍼 크기 (기본값: 16384 = 16KB)
    # 큰 HTTP 헤더, 쿠키, URL이 있는 경우 늘려야 함
    tune.bufsize 32768   # 32KB

    # 헤더 재작성용 예약 공간 (tune.bufsize의 일부)
    tune.maxrewrite 8192

    # TCP 수신/송신 버퍼 (0=OS 기본값, 즉 OS가 자동 조정)
    tune.rcvbuf.client 0
    tune.sndbuf.client 0
    tune.rcvbuf.server 0
    tune.sndbuf.server 0

    # 파이프 크기 (splice 기능용)
    tune.pipesize 16384

    # SSL 최대 레코드 크기 (TLS 레코드)
    tune.ssl.maxrecord 1460    # MTU에 맞게 (기본값: 16384)

    # SSL 세션 캐시 크기
    tune.ssl.cachesize 20000

    # SSL 핸드셰이크 타임아웃
    tune.ssl.lifetime 300
```

### 버퍼 크기 결정 기준

| 상황 | 권장 bufsize |
|------|------------|
| 기본 HTTP 서비스 | 16384 (기본) |
| 큰 쿠키/세션 | 32768 |
| 큰 헤더 (JWT 토큰 등) | 65536 |
| 파일 업로드 프록시 | 16384 (파일은 body, 헤더만 처리) |

---

## 5. Splice (커널 레벨 데이터 전송)

`splice(2)` 시스템 콜을 사용하면 데이터를 사용자 공간으로 복사하지 않고
커널 내에서 직접 전달할 수 있어 성능이 향상됩니다.

```haproxy
defaults
    # 자동: 가능한 경우 splice 사용
    option splice-auto

    # 요청만 splice
    # option splice-request

    # 응답만 splice
    # option splice-response
```

### Splice 제약사항
- HTTP 모드에서는 제한적으로 동작 (헤더 수정 시 비활성화됨)
- TCP 모드에서 가장 효과적
- 특정 운영체제/커널에서만 지원

---

## 6. HTTP 연결 최적화

```haproxy
defaults
    # 권장: 클라이언트 keep-alive + 서버 connection close
    # 서버 연결을 재사용하면서도 서버에 부담을 줄임
    option http-server-close

    # 또는: 양쪽 모두 keep-alive (높은 처리량)
    # option http-keep-alive

    # 또는: 항상 연결 종료 (레거시 서버)
    # option forceclose

    # 또는: 모든 keep-alive 비활성화 (가장 단순)
    # option httpclose

    # HTTP 요청 완료 타임아웃 (헤더까지)
    timeout http-request    10s

    # Keep-alive 유휴 타임아웃 (클라이언트)
    timeout http-keep-alive 2s
```

### 연결 옵션 비교

| 옵션 | 클라이언트 연결 | 서버 연결 | 사용 시나리오 |
|------|--------------|---------|------------|
| `http-server-close` | Keep-alive | Close | 일반적 권장 |
| `http-keep-alive` | Keep-alive | Keep-alive | 고처리량 서비스 |
| `forceclose` | Close | Close | 레거시 서버 |
| `httpclose` | Close | Close | 단순 프록시 |

---

## 7. 커널 파라미터 튜닝

### /etc/sysctl.d/99-haproxy.conf

```bash
# TCP 연결 큐
net.ipv4.tcp_max_syn_backlog = 65536
net.core.somaxconn = 65536

# TIME_WAIT 소켓 재사용 (연결 고갈 방지)
net.ipv4.tcp_tw_reuse = 1

# FIN_WAIT2 타임아웃 단축
net.ipv4.tcp_fin_timeout = 30

# 로컬 포트 범위 확장 (백엔드 연결용)
net.ipv4.ip_local_port_range = 1024 65535

# TCP 수신 버퍼 크기
net.core.rmem_max = 134217728
net.core.rmem_default = 65536
net.ipv4.tcp_rmem = 4096 65536 134217728

# TCP 송신 버퍼 크기
net.core.wmem_max = 134217728
net.core.wmem_default = 65536
net.ipv4.tcp_wmem = 4096 65536 134217728

# 네트워크 디바이스 큐 크기
net.core.netdev_max_backlog = 65536

# TCP Keep-alive 설정
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

# 파일 디스크립터 최대 수
fs.file-max = 2000000

# 소켓 버퍼 자동 조정 활성화
net.ipv4.tcp_moderate_rcvbuf = 1

# 포트 재사용 확인 (중복 TIME_WAIT 방지)
net.ipv4.tcp_timestamps = 1
```

커널 파라미터 적용:
```bash
sysctl -p /etc/sysctl.d/99-haproxy.conf

# 또는 모든 sysctl.d 파일 적용
sysctl --system
```

---

## 8. ulimit 설정

HAProxy 프로세스의 리소스 제한을 조정합니다.

### /etc/security/limits.d/haproxy.conf
```
# haproxy 사용자의 파일 디스크립터 제한
haproxy soft nofile 200000
haproxy hard nofile 200000

# 프로세스 수 제한 (데몬 모드에서 필요한 경우)
haproxy soft nproc  65536
haproxy hard nproc  65536
```

### systemd 서비스 파일에서 설정 (/etc/systemd/system/haproxy.service.d/limits.conf)
```ini
[Service]
LimitNOFILE=200000
LimitNPROC=65536
```

```bash
systemctl daemon-reload
systemctl restart haproxy

# 적용 확인
cat /proc/$(cat /run/haproxy.pid)/limits | grep "open files"
```

---

## 9. NUMA 최적화

멀티소켓 서버에서 NUMA(Non-Uniform Memory Access) 토폴로지를 고려한 튜닝:

```bash
# NUMA 토폴로지 확인
numactl --hardware
lstopo  # hwloc 패키지 설치 필요

# NUMA 노드별 CPU 목록 확인
cat /sys/devices/system/node/node0/cpulist  # 노드 0
cat /sys/devices/system/node/node1/cpulist  # 노드 1
```

```haproxy
global
    # NUMA 노드 0에 스레드 1-8 바인딩 (CPU 0-7)
    # NUMA 노드 1에 스레드 9-16 바인딩 (CPU 8-15)
    nbthread 16
    cpu-map auto:1/1-8 0-7
    cpu-map auto:1/9-16 8-15
```

### numactl로 HAProxy 실행
```bash
# NUMA 노드 0에서만 HAProxy 실행 (메모리 지역성 최대화)
numactl --membind=0 --cpunodebind=0 haproxy -f /etc/haproxy/haproxy.cfg

# 모든 NUMA 노드 사용 (기본)
haproxy -f /etc/haproxy/haproxy.cfg
```

---

## 10. 성능 측정 도구

### ab (Apache Benchmark)
```bash
# 기본 벤치마크
ab -n 100000 -c 1000 http://192.168.1.10/

# Keep-alive 활성화
ab -n 100000 -c 1000 -k http://192.168.1.10/

# POST 요청
ab -n 10000 -c 100 -p payload.json -T application/json http://192.168.1.10/api/

# 결과 해석:
# Requests per second: 초당 처리 요청 수
# Time per request: 평균 응답 시간 (ms)
# Transfer rate: 초당 전송 데이터 (KB/s)
# 50%, 66%, 75%, 80%, 90%, 95%, 98%, 99%: 퍼센타일별 응답 시간
```

### wrk (현대적 HTTP 벤치마크)
```bash
# 설치
apt-get install wrk  또는  brew install wrk

# 기본 벤치마크 (4 스레드, 100 연결, 30초)
wrk -t4 -c100 -d30s http://192.168.1.10/

# 더 많은 연결
wrk -t8 -c1000 -d60s http://192.168.1.10/

# Lua 스크립트로 커스텀 요청
wrk -t4 -c100 -d30s -s post.lua http://192.168.1.10/api/
```

### hey (Go 기반 벤치마크)
```bash
# 설치
go install github.com/rakyll/hey@latest

# 기본 벤치마크
hey -n 100000 -c 200 http://192.168.1.10/

# 초당 요청 수 제한 (QPS 테스트)
hey -n 100000 -c 200 -q 1000 http://192.168.1.10/
```

### 결과 분석
```bash
# HAProxy 응답 시간 분포
awk '{print $18}' /var/log/haproxy.log | \
    awk -F'/' '{print $5}' | \
    sort -n | \
    awk 'BEGIN{count=0; sum=0} {data[count++]=$1; sum+=$1} END{
        print "Count:", count
        print "Average:", sum/count "ms"
        p50=int(count*0.50); print "P50:", data[p50] "ms"
        p95=int(count*0.95); print "P95:", data[p95] "ms"
        p99=int(count*0.99); print "P99:", data[p99] "ms"
    }'
```

---

## 11. 완전한 성능 튜닝 설정 예시

```haproxy
#---------------------------------------------------------------------
# 고성능 HAProxy 설정 (100K+ rps 목표)
#---------------------------------------------------------------------
global
    log /dev/log local0 notice

    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s

    user haproxy
    group haproxy
    daemon

    # 멀티스레딩 (16코어 서버 가정)
    nbthread 16
    cpu-map auto:1/1-16 0-15

    # 최대 연결 수
    maxconn 200000
    maxconnrate 50000
    spread-checks 5

    # 버퍼 설정
    tune.bufsize 32768
    tune.maxrewrite 8192
    tune.ssl.cachesize 50000
    tune.ssl.maxrecord 1460

    # SSL 설정
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull

    # HTTP 연결 최적화
    option  http-server-close
    option  forwardfor

    # 타임아웃
    timeout connect     3s
    timeout client     30s
    timeout server     30s
    timeout http-request 10s
    timeout http-keep-alive 1s

    # 재시도 설정
    retries 3
    option  redispatch

    # 압축 (선택적)
    # compression algo gzip
    # compression type text/html text/plain text/css application/javascript application/json

frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1
    bind *:80

    # HTTP → HTTPS
    http-request redirect scheme https code 301 if !{ ssl_fc }

    # 요청/응답 헤더 최적화
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-response del-header Server
    http-response del-header X-Powered-By

    default_backend app_backend

backend app_backend
    balance roundrobin
    http-reuse aggressive    # 연결 적극 재사용

    option httpchk GET /health
    http-check expect status 200

    # 서버 기본 설정
    default-server inter 2s fastinter 500ms downinter 5s \
                         fall 3 rise 2 slowstart 30s \
                         maxconn 500 weight 100

    server app1 10.0.0.10:80 check
    server app2 10.0.0.11:80 check
    server app3 10.0.0.12:80 check
    server app4 10.0.0.13:80 check
```

---

## 12. 성능 문제 진단

### 병목 지점 식별

```bash
# 1. HAProxy 유휴율 확인 (낮으면 CPU 병목)
echo "show info" | socat /run/haproxy/admin.sock stdio | grep "Idle_pct"
# Idle_pct < 10 → CPU 병목 → 스레드 수 증가 고려

# 2. 큐 대기 확인 (높으면 백엔드 병목)
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' '$2=="BACKEND" && $3>0 {print $1, "queue:", $3}'

# 3. 에러율 확인
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' '$2!="FRONTEND" && $2!="BACKEND" {
        if($13>0 || $14>0 || $15>0)
            print $1"/"$2, "req_err:", $13, "conn_err:", $14, "resp_err:", $15
    }'

# 4. 연결 재시도 확인 (높으면 네트워크/서버 불안정)
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' '$16>0 {print $1"/"$2, "retries:", $16, "redispatch:", $17}'

# 5. 현재 세션 대비 최대 세션 비율
echo "show info" | socat /run/haproxy/admin.sock stdio | \
    awk '/CurrConns/{curr=$2} /MaxConn/{max=$2} END{printf "Connection usage: %d/%d (%.1f%%)\n", curr, max, curr*100/max}'
```
