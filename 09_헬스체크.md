# HAProxy 헬스체크 완전 가이드

헬스체크는 백엔드 서버의 상태를 주기적으로 확인하여 정상 서버에만 트래픽을 전달합니다.
서버 장애 시 자동으로 해당 서버를 제외하고, 복구 시 자동으로 재투입합니다.

---

## 1. 헬스체크 종류 개요

| 종류 | 방식 | 활성화 | 적합한 서비스 |
|------|------|--------|-------------|
| TCP 헬스체크 | TCP 연결만 확인 | `check` | 모든 TCP 서비스 |
| HTTP 헬스체크 | HTTP 요청/응답 | `option httpchk` + `check` | HTTP/HTTPS 서비스 |
| TCP 체크 시퀀스 | send/expect 패턴 | `option tcp-check` + `check` | 특정 프로토콜 (Redis, SMTP 등) |
| 외부 에이전트 체크 | 에이전트 서버 | `agent-check` + `agent-port` | 고급 상태 관리 |
| SSL 헬스체크 | SSL 핸드셰이크 | `ssl` + `check` | HTTPS 백엔드 |

---

## 2. TCP 헬스체크 (기본)

### 동작 방식
서버에 TCP 연결만 시도하여 연결 성공/실패로 서버 상태를 판단합니다.
가장 단순한 방식으로, 포트가 열려 있으면 UP으로 판단합니다.

```haproxy
backend web_servers
    # 기본 TCP 헬스체크 (check 만 추가)
    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check

    # 헬스체크 파라미터 상세 설정
    server web3 192.168.1.12:80 check inter 2s fastinter 500ms downinter 5s rise 3 fall 2
```

### 주의사항
- 포트만 열려 있으면 정상으로 판단 → 애플리케이션 오류 감지 불가
- HTTP 서비스에는 `option httpchk` 사용 권장

---

## 3. HTTP 헬스체크 (option httpchk)

### 기본 설정
```haproxy
backend app_servers
    option httpchk

    # 기본값: OPTIONS / HTTP/1.0
    # 커스텀 설정
    option httpchk GET /health HTTP/1.1\r\nHost:\ app.example.com

    server app1 10.0.0.1:8080 check
    server app2 10.0.0.2:8080 check
```

### HTTP 체크 응답 검증 (http-check expect)
```haproxy
backend app_servers
    option httpchk GET /health HTTP/1.1\r\nHost:\ app.example.com

    # 상태 코드로 검증
    http-check expect status 200

    # 여러 상태 코드 허용 (정규식)
    # http-check expect rstatus (2|3)[0-9][0-9]

    # 응답 body 문자열 포함 여부
    # http-check expect string "healthy"

    # 응답 body 문자열 미포함 여부
    # http-check expect ! string "down"

    # 응답 body 정규식 매칭
    # http-check expect rstring "status.*ok"

    server app1 10.0.0.1:8080 check
```

### http-check 상세 옵션 (HAProxy 2.2+)
```haproxy
backend advanced_check
    # 체크 전 연결 설정
    http-check connect ssl alpn http/1.1

    # 커스텀 헤더로 요청 구성
    http-check send meth GET uri /health ver HTTP/1.1 \
        hdr Host app.example.com \
        hdr Authorization "Bearer health-check-token" \
        hdr Accept application/json

    # 상태 코드 검증
    http-check expect status 200

    # 응답 내용 검증
    http-check expect string "\"status\":\"ok\""

    server app1 10.0.0.1:8080 check
```

### HTTP 체크로 특정 경로 확인
```haproxy
# JSON API 상태 확인
backend api
    option httpchk GET /api/v1/health HTTP/1.1\r\nHost:\ api.example.com\r\nAccept:\ application/json
    http-check expect string "\"healthy\":true"
    server api1 10.0.0.10:3000 check

# 쿠버네티스 readiness probe 스타일
backend k8s_app
    option httpchk GET /readyz HTTP/1.1\r\nHost:\ k8s.local
    http-check expect status 200
    server pod1 10.244.0.10:8080 check
    server pod2 10.244.0.11:8080 check
```

---

## 4. TCP 체크 시퀀스 (tcp-check)

특정 프로토콜의 요청/응답 패턴을 정의하여 애플리케이션 수준 헬스체크를 수행합니다.

### 기본 문법
```
tcp-check connect [<options>]
tcp-check send <string>
tcp-check send-binary <hex_string>
tcp-check expect [!] <match_type> <string>
```

### Redis 헬스체크
```haproxy
backend redis_servers
    mode tcp
    option tcp-check

    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    server redis1 10.0.0.10:6379 check
    server redis2 10.0.0.11:6379 check
```

### Redis Sentinel 헬스체크
```haproxy
backend redis_sentinel
    mode tcp
    option tcp-check

    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG
    tcp-check send INFO replication\r\n
    tcp-check expect string role:master

    server sentinel1 10.0.0.10:26379 check
    server sentinel2 10.0.0.11:26379 check
```

### SMTP 서버 헬스체크
```haproxy
backend smtp_servers
    mode tcp
    option tcp-check

    tcp-check connect
    tcp-check expect string "220"          # 220 SMTP 준비 메시지
    tcp-check send EHLO haproxy\r\n
    tcp-check expect string "250"
    tcp-check send QUIT\r\n

    server smtp1 10.0.0.10:25 check
    server smtp2 10.0.0.11:25 check
```

### MySQL 헬스체크 (바이너리 프로토콜)
```haproxy
backend mysql_servers
    mode tcp
    option tcp-check

    tcp-check connect
    # MySQL 핸드셰이크 패킷 시작 바이트 확인
    tcp-check expect binary 0a   # Protocol version 10 (0x0a)

    server mysql1 10.0.0.10:3306 check
    server mysql2 10.0.0.11:3306 check
```

### Memcached 헬스체크
```haproxy
backend memcached_servers
    mode tcp
    option tcp-check

    tcp-check connect
    tcp-check send version\r\n
    tcp-check expect string VERSION

    server mc1 10.0.0.10:11211 check
    server mc2 10.0.0.11:11211 check
```

### RabbitMQ 헬스체크 (HTTP Management API)
```haproxy
backend rabbitmq
    mode http
    option httpchk GET /api/health/checks/aliveness HTTP/1.1\r\nHost:\ rabbitmq.local\r\nAuthorization:\ Basic Z3Vlc3Q6Z3Vlc3Q=
    http-check expect string "\"status\":\"ok\""

    server rmq1 10.0.0.10:15672 check
    server rmq2 10.0.0.11:15672 check
```

---

## 5. 외부 에이전트 체크 (agent-check)

### 개요
별도의 에이전트 서버/포트에 연결하여 서버 상태, 가중치, 드레인 여부를 수신합니다.
애플리케이션이 직접 자신의 상태를 HAProxy에 알릴 수 있습니다.

### 에이전트 프로토콜
에이전트는 TCP 연결을 수락하고 다음 형식으로 응답을 보냅니다:

| 응답 | 의미 |
|------|------|
| `up` | 서버 UP |
| `down` | 서버 DOWN |
| `ready` | 즉시 UP (slowstart 무시) |
| `drain` | 새 연결 거부, 기존 연결 유지 |
| `maint` | 유지보수 모드 |
| `stopped` | 서버 중지 |
| `50%` | 가중치를 50%로 변경 |
| `maxconn:200` | maxconn을 200으로 변경 |

### 설정 예시
```haproxy
backend app_servers
    # 기본 TCP 헬스체크 + 에이전트 체크 동시 사용
    option httpchk GET /health

    server app1 10.0.0.1:8080 check inter 3s agent-check agent-addr 10.0.0.1 agent-port 9000 agent-inter 5s

    # default-server로 일괄 설정
    default-server check inter 3s fall 3 rise 2 agent-check agent-inter 5s agent-port 9000
    server app2 10.0.0.2:8080
    server app3 10.0.0.3:8080
```

### 간단한 에이전트 스크립트 (Python)
```python
#!/usr/bin/env python3
# simple_agent.py - HAProxy 에이전트 체크 서버

import socket
import subprocess
import sys

def check_health():
    """애플리케이션 상태 확인"""
    # CPU 사용률 확인 (예시)
    try:
        with open('/proc/loadavg') as f:
            load = float(f.read().split()[0])

        if load > 4.0:
            return "drain"    # 과부하: 새 연결 거부
        elif load > 2.0:
            return "50%"      # 부하 높음: 가중치 50%로
        else:
            return "up"       # 정상
    except Exception:
        return "down"

def run_agent(port=9000):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', port))
    s.listen(5)

    print(f"Agent listening on port {port}")

    while True:
        conn, addr = s.accept()
        status = check_health()
        conn.sendall((status + "\n").encode())
        conn.close()

if __name__ == '__main__':
    run_agent()
```

---

## 6. SSL 헬스체크

```haproxy
# HTTPS 백엔드 헬스체크 (SSL 핸드셰이크 포함)
backend https_backend
    option httpchk GET /health HTTP/1.1\r\nHost:\ app.example.com

    server app1 10.0.0.1:443 check ssl verify none
    server app2 10.0.0.2:443 check ssl verify required ca-file /etc/ssl/certs/ca.pem

# 헬스체크는 별도 포트로, 메인 연결은 SSL
backend mixed_backend
    option httpchk GET /health

    # 메인: 443 SSL, 헬스체크: 8080 HTTP
    server app1 10.0.0.1:443 ssl verify none check addr 10.0.0.1 port 8080
```

---

## 7. 헬스체크 파라미터 상세

### inter / fastinter / downinter

```haproxy
backend web
    # 정상 상태일 때 헬스체크 간격
    # server ... check inter 2s

    # 전환 중(DOWN → UP 또는 UP → DOWN) 헬스체크 간격
    # server ... check fastinter 500ms  (빠른 재확인)

    # DOWN 상태일 때 헬스체크 간격
    # server ... check downinter 5s     (다운 상태에서는 덜 자주)

    default-server check inter 2s fastinter 500ms downinter 5s
    server web1 192.168.1.10:80
    server web2 192.168.1.11:80
```

### rise / fall

```haproxy
backend web
    # fall: 연속 N번 실패 시 DOWN 판정
    # rise: 연속 N번 성공 시 UP 판정

    # 기본값: rise 2, fall 3
    default-server check rise 2 fall 3

    # 민감한 설정 (빠른 감지, 빠른 복구)
    # default-server check rise 1 fall 1

    # 안정적인 설정 (느린 감지, 안정적 복구)
    # default-server check rise 3 fall 5

    server web1 192.168.1.10:80
```

### 헬스체크 타임아웃 설정
```haproxy
defaults
    timeout check 5s    # 헬스체크 응답 대기 최대 시간

backend web
    # 특정 backend의 check timeout은 server의 inter 값보다 작아야 함
    server web1 192.168.1.10:80 check inter 3s
    # 위 경우 timeout check는 3s보다 작아야 함
```

---

## 8. 서버 상태 (Health Check States)

### 상태 종류

| 상태 | 설명 | 트래픽 수신 |
|------|------|------------|
| `UP` | 헬스체크 통과, 서버 정상 | 예 |
| `DOWN` | 헬스체크 실패, 서버 비정상 | 아니오 |
| `NOLB` | "No Load Balancing" - 헬스체크 통과하지만 새 연결 거부 | 아니오 (기존 유지) |
| `MAINT` | 유지보수 모드 - 헬스체크 중지, 연결 거부 | 아니오 |
| `DRAIN` | 드레인 모드 - 새 연결 거부, 기존 연결 유지 | 기존만 |
| `UNKNOWN` | 아직 헬스체크 미수행 | 설정에 따라 다름 |

### 상태 전환 흐름
```
시작 (UNKNOWN)
    → 첫 헬스체크 통과 → STOPPING (rise 횟수 카운트 중)
    → rise 횟수 달성 → UP
    → fall 횟수만큼 실패 → DOWN
    → rise 횟수만큼 성공 → UP

Runtime API로:
    UP → MAINT (set server web/web1 state maint)
    UP → DRAIN (set server web/web1 state drain)
    MAINT → READY (set server web/web1 state ready)
```

### 로깅으로 헬스체크 모니터링
```haproxy
defaults
    option log-health-checks   # 헬스체크 상태 변경 시 로깅
```

로그 예시:
```
Server web/web1 is DOWN, reason: Layer7 timeout, check duration: 5000ms
Server web/web1 is UP, reason: Layer7 check passed, check duration: 23ms
```

---

## 9. slowstart (점진적 가중치 증가)

### 개념
서버가 DOWN에서 UP으로 복구될 때, 즉시 전체 가중치를 받지 않고 지정된 시간 동안 점진적으로 가중치를 증가시킵니다.
갑자기 많은 트래픽이 몰리는 것을 방지하고, 서버가 웜업할 시간을 줍니다.

### 동작 방식
```
slowstart 60s 설정 시:
t=0s:   가중치 0% (트래픽 없음)
t=15s:  가중치 25%
t=30s:  가중치 50%
t=45s:  가중치 75%
t=60s:  가중치 100% (정상 운영)
```

### 설정 예시
```haproxy
backend app_servers
    balance roundrobin

    # slowstart: 서버 복구 후 60초 동안 점진적으로 가중치 증가
    default-server check inter 2s fall 3 rise 2 slowstart 60s

    server app1 10.0.0.1:8080 weight 100
    server app2 10.0.0.2:8080 weight 100
    server app3 10.0.0.3:8080 weight 100

# JVM 기반 애플리케이션 (워밍업 시간 필요)
backend java_app
    default-server check inter 3s slowstart 120s  # 2분 워밍업

    server java1 10.0.1.1:8080 check weight 100
    server java2 10.0.1.2:8080 check weight 100
```

### 주의사항
- `slowstart`는 `roundrobin`, `leastconn`, `random` 등 동적 알고리즘에서만 효과 있음
- `static-rr`, `first`에서는 효과 없음
- 처음 시작 시에는 적용되지 않고, DOWN → UP 전환 시에만 적용

---

## 10. 별도 헬스체크 포트/주소

### 개별 헬스체크 포트 사용
메인 서비스 포트와 다른 포트로 헬스체크를 수행합니다.

```haproxy
backend app_servers
    option httpchk GET /health

    # 메인: 8080, 헬스체크: 8081
    server app1 10.0.0.1:8080 check port 8081
    server app2 10.0.0.2:8080 check port 8081

    # 별도 주소 + 별도 포트 헬스체크
    server app3 10.0.0.3:8080 check addr 10.0.0.100 port 9000
```

### 사용 시나리오
- 헬스체크 엔드포인트가 별도 포트에 있는 경우
- 관리용 포트를 통한 헬스체크 (프로덕션 트래픽 포트와 분리)
- Kubernetes의 경우 readiness probe 포트 활용

---

## 11. 헬스체크 로그 분석

```bash
# 헬스체크 상태 변경 로그 확인
grep "is DOWN\|is UP" /var/log/haproxy.log

# 최근 DOWN 이벤트만 확인
grep "is DOWN" /var/log/haproxy.log | tail -20

# 특정 서버의 헬스체크 이력
grep "Server web/web1" /var/log/haproxy.log

# Runtime API로 현재 상태 확인
echo "show health" | socat /run/haproxy/admin.sock stdio

# 서버 상태 상세 확인
echo "show servers state" | socat /run/haproxy/admin.sock stdio
```

---

## 12. 헬스체크 트러블슈팅

### 일반적인 문제와 해결책

| 문제 | 원인 | 해결책 |
|------|------|--------|
| 서버 항상 DOWN | 방화벽 차단, 포트 닫힘 | 방화벽 규칙 확인, 포트 개방 |
| HTTP 체크 실패 | 잘못된 경로, 인증 필요 | 경로 확인, 헤더 추가 |
| 타임아웃 빈번 | 서버 느림, timeout check 짧음 | timeout check 늘리기, 서버 최적화 |
| 플랩핑 (UP/DOWN 반복) | rise/fall 너무 낮음 | rise/fall 값 증가 |
| 체크 과부하 | inter 너무 짧음 | inter 값 증가 |

### 헬스체크 디버깅
```bash
# 헬스체크 결과 수동 확인 (curl로 HTTP 체크 시뮬레이션)
curl -v -H "Host: app.example.com" http://10.0.0.1:8080/health

# TCP 연결 확인
nc -zv 10.0.0.1 8080

# Redis 헬스체크 수동 확인
redis-cli -h 10.0.0.1 PING

# HAProxy 로그에서 헬스체크 에러 확인
grep "health check\|DOWN\|Layer" /var/log/haproxy.log | tail -50
```

---

## 13. 완전한 헬스체크 설정 예시

```haproxy
#---------------------------------------------------------------------
# 다양한 서비스를 위한 헬스체크 설정 모음
#---------------------------------------------------------------------

# 1. HTTP 앱 서버 (상세 헬스체크)
backend production_app
    mode http
    balance leastconn

    option httpchk GET /health/live HTTP/1.1\r\nHost:\ app.prod.local\r\nX-Health-Check:\ haproxy
    http-check expect status 200

    option log-health-checks

    default-server inter 3s fastinter 500ms downinter 10s rise 2 fall 3 slowstart 60s

    server app1 10.0.0.1:8080 check weight 100
    server app2 10.0.0.2:8080 check weight 100
    server app3 10.0.0.3:8080 check weight 100

# 2. PostgreSQL 데이터베이스
backend postgres
    mode tcp
    balance leastconn

    option tcp-check
    tcp-check connect

    default-server inter 5s fall 3 rise 2 maxconn 50

    server pg1 10.0.1.10:5432 check
    server pg2 10.0.1.11:5432 check backup  # 백업 (primary 장애 시)

# 3. Redis 캐시 (PING/PONG 확인)
backend redis
    mode tcp
    balance source

    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    default-server inter 2s fall 3 rise 2

    server redis1 10.0.2.10:6379 check
    server redis2 10.0.2.11:6379 check

# 4. HTTPS 백엔드 (SSL 헬스체크)
backend secure_app
    mode http
    balance roundrobin

    option httpchk GET /api/health

    default-server inter 3s fall 3 rise 2

    server secure1 10.0.3.10:443 check ssl verify none port 443
    server secure2 10.0.3.11:443 check ssl verify none port 443
```
