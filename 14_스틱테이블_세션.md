# HAProxy Stick Table & 세션 고정 완전 가이드

Stick Table은 HAProxy의 강력한 상태 추적 기능입니다.
클라이언트별 연결 정보, 요청 빈도, 세션 정보를 메모리에 저장하여
세션 고정(Session Persistence), 속도 제한(Rate Limiting), 보안 제어에 활용합니다.

---

## 1. Stick Table 기본 개념

Stick Table은 키-값 형태의 인메모리 테이블입니다.

```
키(Key)     → 저장 필드(Store)
─────────────────────────────
192.168.1.1 → {server_id: 2, conn_cur: 5, http_req_rate: 100}
192.168.1.2 → {server_id: 1, conn_cur: 3, http_req_rate: 25}
"SESSID123" → {server_id: 3, conn_cur: 1}
```

---

## 2. 기본 문법

```haproxy
stick-table type <type> size <size> [expire <time>] [nopurge] [peers <name>] [store <field,...>]
```

| 파라미터 | 설명 | 예시 |
|---------|------|------|
| `type` | 키 데이터 타입 | `ip`, `ipv6`, `integer`, `string`, `binary` |
| `size` | 최대 항목 수 | `100k`, `1m`, `10000` |
| `expire` | 항목 만료 시간 | `30s`, `10m`, `1h` |
| `nopurge` | 만료 시 즉시 삭제 안 함 | - |
| `peers` | 피어 동기화 그룹 이름 | `mypeers` |
| `store` | 저장할 필드 목록 | `conn_cur,http_req_rate(10s)` |

---

## 3. 키 타입 (type)

| 타입 | 설명 | 예시 값 |
|------|------|---------|
| `ip` | IPv4 주소 | `192.168.1.1` |
| `ipv6` | IPv6 주소 (IPv4 포함) | `::ffff:192.168.1.1` |
| `integer` | 정수 (0~2^32-1) | `12345` |
| `string [len <n>]` | 문자열 (기본 32바이트) | `"SESSIONID123"` |
| `binary [len <n>]` | 바이너리 (기본 32바이트) | - |

```haproxy
# IP 키 (IPv4)
stick-table type ip size 100k expire 30s

# IPv6 포함 IP 키
stick-table type ipv6 size 100k expire 30s

# 문자열 키 (최대 64바이트)
stick-table type string len 64 size 50k expire 10m

# 정수 키
stick-table type integer size 10k expire 5m
```

---

## 4. 저장 가능한 필드 (store)

| 필드 | 타입 | 설명 |
|------|------|------|
| `server_id` | integer | 연결된 서버의 ID |
| `server_key` | string | 연결된 서버의 키 (이름) |
| `conn_cur` | integer | 현재 동시 연결 수 |
| `conn_rate(<period>)` | rate | 연결 속도 (초당) |
| `conn_cnt` | integer | 총 연결 수 |
| `sess_cnt` | integer | 총 세션 수 |
| `sess_rate(<period>)` | rate | 세션 속도 |
| `http_req_cnt` | integer | HTTP 요청 총 수 |
| `http_req_rate(<period>)` | rate | HTTP 요청 속도 |
| `http_err_cnt` | integer | HTTP 에러 총 수 |
| `http_err_rate(<period>)` | rate | HTTP 에러 속도 |
| `http_fail_cnt` | integer | HTTP 실패 총 수 |
| `http_fail_rate(<period>)` | rate | HTTP 실패 속도 |
| `bytes_in_cnt` | integer | 수신 바이트 총 수 |
| `bytes_in_rate(<period>)` | rate | 수신 속도 |
| `bytes_out_cnt` | integer | 송신 바이트 총 수 |
| `bytes_out_rate(<period>)` | rate | 송신 속도 |
| `gpc0` | integer | 범용 카운터 0 (사용자 정의) |
| `gpc1` | integer | 범용 카운터 1 (사용자 정의) |
| `gpc2` | integer | 범용 카운터 2 |
| `gpc0_rate(<period>)` | rate | gpc0 변화율 |
| `gpc1_rate(<period>)` | rate | gpc1 변화율 |
| `gpt0` | boolean | 범용 태그 0 (1비트) |

---

## 5. Stick Table 위치

Stick Table은 frontend 또는 backend에 정의할 수 있습니다.

```haproxy
# frontend에 정의 (rate limiting에 주로 사용)
frontend web_front
    bind *:80
    mode http
    stick-table type ip size 100k expire 30s store http_req_rate(10s),conn_cur
    # ...

# backend에 정의 (세션 고정에 주로 사용)
backend web_backend
    stick-table type ip size 100k expire 30m store server_id
    stick on src
    server web1 10.0.0.1:80 check
    server web2 10.0.0.2:80 check
```

---

## 6. stick on / stick match / stick store

### stick on (추적 + 세션 고정)
요청에서 키를 추출하여 테이블에 저장하고, 기존 매핑이 있으면 해당 서버로 라우팅합니다.

```haproxy
backend web
    stick-table type ip size 100k expire 10m store server_id

    # 소스 IP로 세션 고정
    stick on src

    server web1 10.0.0.1:80 check
    server web2 10.0.0.2:80 check
```

### stick match (조회만, 서버 고정)
키로 테이블을 조회하여 기존 서버 매핑을 찾습니다. 저장은 하지 않습니다.

```haproxy
backend web
    stick-table type string len 32 size 100k expire 30m store server_id

    # 쿠키에서 세션 ID로 서버 조회
    stick match req.cook(JSESSIONID)

    # 서버 응답의 Set-Cookie에서 세션 ID 저장
    stick store-response res.cook(JSESSIONID)

    server web1 10.0.0.1:8080 check
    server web2 10.0.0.2:8080 check
```

### stick store-request / stick store-response
요청/응답에서 키를 추출하여 테이블에 저장합니다.

```haproxy
backend web
    stick-table type string len 64 size 100k expire 1h store server_id

    # 요청 URL 파라미터에서 사용자 ID 추출
    stick on urlp(user_id)

    # 또는 응답 쿠키에서 저장
    stick store-response res.cook(MYAPP_SESSION)
    stick match req.cook(MYAPP_SESSION)

    server web1 10.0.0.1:8080 check
    server web2 10.0.0.2:8080 check
```

---

## 7. 세션 고정 전략별 완전 예시

### 7.1 소스 IP 기반 세션 고정
```haproxy
backend sticky_by_ip
    balance roundrobin
    stick-table type ip size 100k expire 30m store server_id
    stick on src

    server app1 10.0.0.1:8080 check
    server app2 10.0.0.2:8080 check
    server app3 10.0.0.3:8080 check
```

### 7.2 쿠키 기반 세션 고정 (JSESSIONID)
```haproxy
backend java_app
    balance roundrobin
    stick-table type string len 64 size 100k expire 30m store server_id

    # 요청의 JSESSIONID 쿠키로 서버 조회
    stick match req.cook(JSESSIONID)

    # 응답의 Set-Cookie에서 JSESSIONID 저장
    stick store-response res.cook(JSESSIONID)

    server app1 10.0.0.1:8080 check
    server app2 10.0.0.2:8080 check
```

### 7.3 URL 파라미터 기반
```haproxy
backend user_api
    balance roundrobin
    stick-table type string len 32 size 100k expire 1h store server_id

    # GET /api/user?id=123 → "123"을 키로 사용
    stick on urlp(id)

    server api1 10.0.0.1:8080 check
    server api2 10.0.0.2:8080 check
```

### 7.4 HTTP 헤더 기반
```haproxy
backend tenant_app
    balance roundrobin
    stick-table type string len 64 size 100k expire 2h store server_id

    # X-Tenant-ID 헤더로 테넌트별 서버 고정
    stick on req.hdr(X-Tenant-ID)

    server app1 10.0.0.1:8080 check
    server app2 10.0.0.2:8080 check
    server app3 10.0.0.3:8080 check
```

---

## 8. Rate Limiting (속도 제한)

Stick Table을 이용한 IP별 요청 속도 제한은 DDoS/브루트포스 방어의 핵심입니다.

### 기본 Rate Limiting
```haproxy
frontend web_front
    bind *:80
    mode http

    # stick-table 정의
    stick-table type ip size 100k expire 30s store http_req_rate(10s),conn_cur

    # 요청 추적 (sc = sticky counter)
    http-request track-sc0 src

    # 조건 정의
    acl too_many_requests sc_http_req_rate(0) gt 100   # 10초에 100개 초과
    acl too_many_conn     sc_conn_cur(0) gt 50          # 동시 연결 50개 초과

    # 차단 (429 Too Many Requests)
    http-request deny deny_status 429 if too_many_requests
    http-request deny deny_status 429 if too_many_conn

    default_backend web_backend
```

### 다단계 Rate Limiting
```haproxy
frontend advanced_ratelimit
    bind *:80
    mode http

    # 3개의 stick counter 사용
    # sc0: IP 기반, sc1: User-Agent 기반, sc2: API 키 기반
    stick-table type ip size 1m expire 30s store http_req_rate(10s),http_err_rate(10s),conn_cur,gpc0

    http-request track-sc0 src

    # 1단계: 10초에 200개 이상 → 경고 (gpc0 증가)
    acl moderate_abuse sc_http_req_rate(0) gt 200
    http-request sc-inc-gpc0(0) if moderate_abuse

    # 2단계: 10초에 500개 이상 → 즉시 차단
    acl severe_abuse sc_http_req_rate(0) gt 500
    http-request deny deny_status 429 if severe_abuse

    # 3단계: 이미 gpc0가 5 이상인 클라이언트 차단 (반복 위반자)
    acl repeat_offender sc_get_gpc0(0) ge 5
    http-request deny deny_status 403 if repeat_offender

    # 에러율이 높은 클라이언트 차단 (10초에 에러 20개 이상)
    acl high_error_rate sc_http_err_rate(0) gt 20
    http-request deny deny_status 403 if high_error_rate

    default_backend web_backend
```

### TCP 연결 속도 제한
```haproxy
frontend tcp_front
    bind *:80
    mode tcp

    # TCP 연결 레벨 stick-table
    stick-table type ip size 100k expire 10s store conn_rate(10s),conn_cur

    # 연결 추적
    tcp-request connection track-sc0 src

    # 10초에 100개 이상 연결 시도 차단
    acl conn_rate_abuse sc_conn_rate(0) gt 100
    tcp-request connection reject if conn_rate_abuse

    default_backend tcp_backend
```

---

## 9. sc (Stick Counter) 함수 전체 목록

`sc_*(n)` 형식에서 n은 track-sc<n>의 번호입니다 (0, 1, 2).

| 함수 | 설명 | 반환 타입 |
|------|------|---------|
| `sc_conn_cur(n)` | 현재 동시 연결 수 | integer |
| `sc_conn_rate(n)` | 연결 속도 | integer |
| `sc_conn_cnt(n)` | 총 연결 수 | integer |
| `sc_sess_cnt(n)` | 총 세션 수 | integer |
| `sc_sess_rate(n)` | 세션 속도 | integer |
| `sc_http_req_cnt(n)` | HTTP 요청 총 수 | integer |
| `sc_http_req_rate(n)` | HTTP 요청 속도 | integer |
| `sc_http_err_cnt(n)` | HTTP 에러 총 수 | integer |
| `sc_http_err_rate(n)` | HTTP 에러 속도 | integer |
| `sc_bytes_in_rate(n)` | 수신 속도 | integer |
| `sc_bytes_out_rate(n)` | 송신 속도 | integer |
| `sc_get_gpc0(n)` | gpc0 현재 값 조회 | integer |
| `sc_get_gpc1(n)` | gpc1 현재 값 조회 | integer |
| `sc_inc_gpc0(n)` | gpc0 증가 (항상 참 반환) | boolean |
| `sc_inc_gpc1(n)` | gpc1 증가 (항상 참 반환) | boolean |
| `sc_clr_gpc0(n)` | gpc0 초기화 | boolean |
| `sc_clr_gpc1(n)` | gpc1 초기화 | boolean |
| `sc_tracked(n)` | 현재 추적 중인지 여부 | boolean |
| `sc_kbytes_in(n)` | 수신 킬로바이트 | integer |
| `sc_kbytes_out(n)` | 송신 킬로바이트 | integer |

---

## 10. Peers를 이용한 Stick Table 동기화

여러 HAProxy 인스턴스가 있을 때 Stick Table을 실시간으로 동기화합니다.

```haproxy
# /etc/haproxy/haproxy.cfg on haproxy1 (192.168.1.10)
peers haproxy_cluster
    bind 192.168.1.10:1024  # 이 노드의 bind 주소
    peer haproxy1 192.168.1.10:1024
    peer haproxy2 192.168.1.11:1024
    peer haproxy3 192.168.1.12:1024

frontend web_front
    bind *:80
    mode http
    stick-table type ip size 1m expire 30s peers haproxy_cluster store http_req_rate(10s),conn_cur
    http-request track-sc0 src
    acl abuse sc_http_req_rate(0) gt 200
    http-request deny if abuse
    default_backend web_backend

backend web_backend
    stick-table type ip size 100k expire 30m peers haproxy_cluster store server_id
    stick on src
    server web1 10.0.0.1:80 check
    server web2 10.0.0.2:80 check
```

```haproxy
# /etc/haproxy/haproxy.cfg on haproxy2 (192.168.1.11)
peers haproxy_cluster
    bind 192.168.1.11:1024  # 이 노드의 bind 주소 (각 인스턴스마다 다름)
    peer haproxy1 192.168.1.10:1024
    peer haproxy2 192.168.1.11:1024
    peer haproxy3 192.168.1.12:1024

# 나머지 설정은 haproxy1과 동일
```

---

## 11. Runtime API로 Stick Table 관리

```bash
# 테이블 목록 확인
echo "show table" | socat /run/haproxy/admin.sock stdio

# 특정 테이블 내용 확인
echo "show table web_backend" | socat /run/haproxy/admin.sock stdio

# 특정 키의 항목 확인
echo "show table web_backend key 192.168.1.100" | socat /run/haproxy/admin.sock stdio

# 항목 값 수정 (gpc0를 1로 설정 = 차단 플래그)
echo "set table web_front key 192.168.1.100 data.gpc0 1" | socat /run/haproxy/admin.sock stdio

# 항목 삭제
echo "clear table web_front key 192.168.1.100" | socat /run/haproxy/admin.sock stdio

# 전체 테이블 삭제 (주의!)
echo "clear table web_front" | socat /run/haproxy/admin.sock stdio
```

### 테이블 조회 출력 예시
```
# table: web_front, type: ip, size:102400, used:3
0x7f8a1c002340: key=192.168.1.1 use=0 exp=29234 shard=0 http_req_rate(10000)=5 conn_cur=1
0x7f8a1c003680: key=192.168.1.2 use=0 exp=28891 shard=0 http_req_rate(10000)=150 conn_cur=5
0x7f8a1c004240: key=10.0.0.5 use=0 exp=30000 shard=0 http_req_rate(10000)=2 conn_cur=0
```

---

## 12. 브루트포스 보호 예시

로그인 엔드포인트에 대한 브루트포스 공격 방어:

```haproxy
frontend login_protection
    bind *:80
    mode http

    # 로그인 시도 추적용 stick-table
    stick-table type ip size 100k expire 10m store http_req_rate(60s),http_err_rate(60s),gpc0

    # 로그인 요청만 추적
    acl is_login_attempt path /login method POST

    # 로그인 요청 추적
    http-request track-sc0 src table login_protection if is_login_attempt

    # 1분에 10번 이상 로그인 실패 시 gpc0 증가
    # (응답 코드 401/403이 오면 에러로 카운트)
    acl login_failed status 401 403

    # 로그인 실패율이 높으면 차단
    acl brute_force sc_http_err_rate(0) gt 10
    acl flagged sc_get_gpc0(0) ge 3

    http-request deny deny_status 429 if is_login_attempt brute_force
    http-request deny deny_status 403 if is_login_attempt flagged

    default_backend web_backend
```

---

## 13. 메모리 사용량 계산

Stick Table 항목당 메모리 사용량:

```
기본 오버헤드: ~50바이트 per 항목
각 필드:
  server_id:     4바이트
  conn_cur:      4바이트
  conn_rate():   12바이트 (rate = counter + timestamp + period)
  http_req_rate(): 12바이트
  gpc0:          4바이트
  bytes_in_rate(): 12바이트

예시: type ip size 1m store conn_cur,http_req_rate(10s),gpc0
= (50 + 4 + 4 + 12 + 4) 바이트 × 1,000,000 항목
= 74 MB
```

---

## 14. 완전한 예시: 종합 보안 설정

```haproxy
#---------------------------------------------------------------------
# 종합 보안 설정 (Rate Limiting + Session Persistence + Brute Force Protection)
#---------------------------------------------------------------------

frontend secure_web
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    mode http

    # 메인 Rate Limiting 테이블
    stick-table type ip size 1m expire 30s store http_req_rate(10s),conn_cur,http_err_rate(30s),gpc0,gpc1

    # HTTP → HTTPS 리다이렉트
    http-request redirect scheme https if !{ ssl_fc }

    # 요청 추적
    http-request track-sc0 src

    # 단계별 차단
    # 1. 즉각 차단: 10초에 1000개 이상 (명백한 DDoS)
    acl ddos_attack sc_http_req_rate(0) gt 1000
    http-request deny deny_status 429 if ddos_attack

    # 2. 반복 위반자 (gpc0가 5 이상)
    acl repeat_offender sc_get_gpc0(0) ge 5
    http-request deny deny_status 403 if repeat_offender

    # 3. 에러율 높은 클라이언트 (30초에 50개 이상 에러)
    acl high_error sc_http_err_rate(0) gt 50
    http-request sc-inc-gpc0(0) if high_error
    http-request deny deny_status 429 if high_error

    # 4. 경고 수준 (10초에 300개 이상)
    acl moderate_abuse sc_http_req_rate(0) gt 300
    http-request sc-inc-gpc0(0) if moderate_abuse

    default_backend web_backend

backend web_backend
    mode http
    balance leastconn

    # 세션 고정 (소스 IP 기반)
    stick-table type ip size 100k expire 30m peers haproxy_peers store server_id
    stick on src

    option httpchk GET /health
    http-check expect status 200

    default-server inter 3s fall 3 rise 2 slowstart 30s

    server app1 10.0.0.1:8080 check
    server app2 10.0.0.2:8080 check
    server app3 10.0.0.3:8080 check
```
