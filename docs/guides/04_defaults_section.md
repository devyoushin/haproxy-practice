# HAProxy defaults 섹션 완전 딥다이브

## 개요

`defaults` 섹션은 이후에 나오는 `frontend`, `backend`, `listen` 섹션의 **기본값**을 설정합니다.
각 섹션에서 개별적으로 재정의(override)할 수 있으며, 재정의하지 않으면 defaults의 값이 적용됩니다.

### 핵심 특징
- **여러 개 정의 가능**: 여러 defaults 섹션이 있으면 각각 이후 섹션에 순차 적용
- **상속 구조**: defaults → frontend/backend/listen (재정의 가능)
- **reset 가능**: `defaults` 새 섹션 정의 시 이전 defaults 값 초기화

```haproxy
# defaults 섹션 1 (처음 적용)
defaults
    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend fe1
    # timeout connect: 5s (defaults 1 상속)
    bind *:80
    default_backend bk1

# defaults 섹션 2 (이후 섹션에 적용, 이전 값 초기화)
defaults
    timeout connect 10s    # 새 값
    timeout client 60s     # 새 값
    timeout server 60s     # 새 값

frontend fe2
    # timeout connect: 10s (defaults 2 상속)
    bind *:8080
    default_backend bk2
```

---

## 1. mode (동작 모드)

```haproxy
defaults
    mode http   # HTTP/HTTPS 프록시 모드 (L7)
    # mode tcp  # TCP 프록시 모드 (L4)
    # mode health # 헬스체크 전용 모드 (deprecated)
```

### mode http
- **레이어**: L7 (애플리케이션 레이어)
- **특징**:
  - HTTP 헤더 분석 및 수정 가능
  - URL/경로 기반 라우팅 가능
  - 쿠키 기반 세션 고정 가능
  - HTTP 로그 포맷 사용
  - 연결 재사용 (keep-alive)
- **사용 시**: 웹 애플리케이션, HTTP API

### mode tcp
- **레이어**: L4 (전송 레이어)
- **특징**:
  - TCP 패킷만 전달 (내용 분석 불가)
  - HTTP 헤더 조작 불가
  - 모든 TCP 기반 프로토콜 지원 (MySQL, Redis, SMTP 등)
  - TCP 로그 포맷 사용
  - SSL pass-through 가능
- **사용 시**: 데이터베이스, 캐시, 메시지 큐, 이메일 서버

```haproxy
# HTTP 모드 예시
defaults
    mode http
    option httplog

# TCP 모드 예시
defaults
    mode tcp
    option tcplog
```

---

## 2. timeout 설정 (모든 타임아웃 상세)

### timeout connect
```haproxy
defaults
    timeout connect 5s   # 백엔드 서버에 연결 수립 최대 시간
```
- **설명**: HAProxy가 백엔드 서버에 TCP 연결을 시도하는 최대 시간
- **기본값**: 없음 (무제한, 권장하지 않음)
- **권장값**: 2s ~ 10s (내부 네트워크: 2-5s, 외부: 5-15s)
- **너무 짧으면**: 정상 서버도 연결 실패 처리
- **너무 길면**: 죽은 서버 감지가 느려짐

### timeout client
```haproxy
defaults
    timeout client 30s   # 클라이언트 비활성 최대 시간
```
- **설명**: 클라이언트와 HAProxy 사이의 최대 비활성 시간
  - 데이터를 기다리는 클라이언트가 이 시간 동안 아무것도 보내지 않으면 연결 종료
- **권장값**:
  - 일반 웹: 30s ~ 60s
  - API: 10s ~ 30s
  - WebSocket: 시간 길게 또는 tunnel timeout 사용

### timeout server
```haproxy
defaults
    timeout server 30s   # 서버 응답 최대 대기 시간
```
- **설명**: 서버가 데이터를 전송하는 동안 최대 비활성 시간
- **주의**: 서버가 처리하는 총 시간이 아니라 **비활성(idle)** 시간
- **권장값**:
  - 일반 웹: 30s ~ 60s
  - 긴 처리: 300s ~ 600s (파일 업로드, 긴 쿼리 등)

### timeout http-request
```haproxy
defaults
    timeout http-request 10s   # HTTP 요청 헤더 수신 최대 시간
```
- **설명**: 클라이언트가 전체 HTTP 요청 헤더를 전송하는 최대 시간
- **보안**: Slowloris 공격 방어에 필수
- **권장값**: 5s ~ 15s
- **주의**: 너무 짧으면 느린 네트워크에서 정상 요청도 차단

### timeout http-keep-alive
```haproxy
defaults
    timeout http-keep-alive 10s   # HTTP Keep-Alive 연결 유지 시간
```
- **설명**: HTTP Keep-Alive 상태에서 다음 요청을 기다리는 최대 시간
- **효과**: 연결 재사용으로 성능 향상
- **권장값**: 5s ~ 15s
- **관련**: `option http-keep-alive` 또는 `option http-server-close`와 함께 사용

### timeout queue
```haproxy
defaults
    timeout queue 30s   # 큐 대기 최대 시간
```
- **설명**: `maxconn` 초과 시 요청이 큐에서 기다리는 최대 시간
- **이후**: 큐 타임아웃 시 503 에러 반환
- **권장값**: 30s ~ 60s

### timeout tunnel
```haproxy
defaults
    timeout tunnel 3600s   # 터널 모드 타임아웃
```
- **설명**: CONNECT 메서드, WebSocket, SSL pass-through 등 터널링된 연결의 타임아웃
- **권장값**: WebSocket: 3600s (1시간), 일반 터널: 3600s
- **주의**: client/server timeout보다 길게 설정

```haproxy
# WebSocket 설정 예시
defaults
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    timeout tunnel 3600s    # WebSocket 연결 유지

frontend ws_frontend
    bind *:80
    default_backend ws_backend

backend ws_backend
    option http-server-close
    timeout server 3600s    # backend별 재정의 가능
    server ws1 10.0.0.1:8080 check
```

### timeout check
```haproxy
defaults
    timeout check 5s   # 헬스체크 응답 최대 시간
```
- **설명**: 서버 헬스체크 응답 대기 최대 시간
- **기본값**: `timeout connect` 값
- **권장값**: 2s ~ 10s

### timeout client-fin
```haproxy
defaults
    timeout client-fin 10s   # 클라이언트 FIN 후 대기 시간
```
- **설명**: 클라이언트가 TCP FIN을 보낸 후 HAProxy가 기다리는 시간
- **용도**: Half-closed 연결 처리

### timeout server-fin
```haproxy
defaults
    timeout server-fin 10s   # 서버 FIN 후 대기 시간
```

---

## 3. option 설정

### option httplog
```haproxy
defaults
    option httplog   # HTTP 상세 로그 활성화
```
- **설명**: HTTP 요청에 대한 상세 로그 (URL, 상태코드, 바이트 수 등)
- **mode http에서만 유효**

### option tcplog
```haproxy
defaults
    option tcplog   # TCP 상세 로그 활성화
```
- **설명**: TCP 연결에 대한 로그 (IP, 포트, 바이트 수)
- **mode tcp에서만 유효**

### option dontlognull
```haproxy
defaults
    option dontlognull   # 빈 연결 로그 제외
```
- **설명**: 데이터 없이 바로 끊긴 연결은 로그에 기록하지 않음
- **효과**: 헬스체크 연결, TCP 포트 스캔 로그 감소
- **주의**: 일부 헬스체크 도구가 빈 TCP 연결 사용

### option http-server-close
```haproxy
defaults
    option http-server-close   # 서버 측 연결 즉시 종료
```
- **설명**: 응답 후 서버와의 연결을 즉시 종료 (클라이언트와는 keep-alive 유지)
- **효과**: 서버 연결 수 감소, 메모리 절약
- **권장**: 대부분의 HTTP 프록시에서 권장

### option http-keep-alive (기본값)
```haproxy
defaults
    option http-keep-alive   # 클라이언트-서버 모두 keep-alive
```
- **설명**: 클라이언트와 서버 양쪽 모두 연결 유지
- **효과**: 연결 오버헤드 최소화, 지연시간 감소
- **주의**: 서버 연결 수 증가 가능

### option forwardfor
```haproxy
defaults
    option forwardfor
    # 또는
    option forwardfor except 127.0.0.0/8   # 루프백은 제외
    # 또는
    option forwardfor header X-Real-IP     # 헤더명 변경
```
- **설명**: `X-Forwarded-For` 헤더에 클라이언트 실제 IP 추가
- **효과**: 백엔드 서버가 클라이언트 IP를 알 수 있음
- **except**: 지정 IP 대역에서 온 요청은 기존 헤더 제거
- **보안**: 신뢰할 수 없는 XFF 헤더 처리 주의

### option redispatch
```haproxy
defaults
    option redispatch         # 재시도 마지막 서버에서 다른 서버로 재배포
    option redispatch 1       # 마지막 재시도 전에 재배포
```
- **설명**: 서버 장애 시 연결을 다른 서버로 재배포
- **효과**: 세션 고정된 서버가 죽어도 다른 서버로 전환
- **주의**: 세션 데이터 손실 가능성

### option abortonclose
```haproxy
defaults
    option abortonclose   # 클라이언트 연결 끊기면 서버 연결도 종료
```
- **설명**: 클라이언트가 연결을 끊으면 큐의 요청을 취소
- **효과**: 서버 과부하 시 불필요한 요청 취소

### option allbackups
```haproxy
defaults
    option allbackups   # 모든 백업 서버 동시 사용
```
- **설명**: 기본 서버 모두 다운 시 백업 서버를 동시에 사용
- **기본**: 백업 서버 중 첫 번째만 사용

### option persist
```haproxy
defaults
    option persist   # 다운된 서버로도 지속
```
- **설명**: 세션 고정(sticky) 서버가 다운됐어도 계속 시도
- **주의**: 서버 장애 시 요청 실패 가능, 일반적으로 `option redispatch`와 함께 사용

### option http-pretend-keepalive
```haproxy
defaults
    option http-pretend-keepalive
```
- **설명**: 서버가 HTTP/1.0만 지원해도 keep-alive처럼 동작
- **용도**: 레거시 서버 호환성

### option independent-streams
```haproxy
defaults
    option independent-streams
```
- **설명**: 각 방향(클라이언트→서버, 서버→클라이언트)의 timeout을 독립적으로 적용

### option splice-auto
```haproxy
defaults
    option splice-auto   # 가능한 경우 커널 splice() 사용
```
- **설명**: 커널 레벨 데이터 복사 (성능 향상)
- **주의**: L7 처리(헤더 수정 등)와 함께 사용 불가

### option tcp-smart-accept
```haproxy
defaults
    option tcp-smart-accept
```
- **설명**: 데이터와 함께 SYN이 오면 accept() 최적화

### option tcp-smart-connect
```haproxy
defaults
    option tcp-smart-connect
```
- **설명**: 연결 및 데이터 전송을 한 번에 (TCP Fast Open)

---

## 4. retries (재시도)

```haproxy
defaults
    retries 3   # 백엔드 서버 연결 실패 시 최대 재시도 횟수
```
- **설명**: 서버 연결 실패 시 재시도 횟수
- **기본값**: 3
- **주의**: 재시도마다 다른 서버를 시도할 수 있음 (roundrobin)
- **주의**: 멱등하지 않은 요청(POST)에서는 주의 필요

---

## 5. maxconn (최대 연결 수)

```haproxy
defaults
    maxconn 3000   # frontend 기본 최대 동시 연결 수
```
- **설명**: 각 frontend/listen의 기본 최대 동시 연결 수
- **global maxconn**: 전체 합계 제한
- **frontend maxconn**: 해당 frontend의 제한

---

## 6. balance (로드밸런싱 알고리즘)

```haproxy
defaults
    balance roundrobin   # 기본 로드밸런싱 알고리즘

    # 사용 가능한 알고리즘:
    # balance roundrobin    - 순환 (기본)
    # balance static-rr     - 정적 순환
    # balance leastconn     - 최소 연결
    # balance first         - 첫 번째 서버 우선
    # balance source        - 소스 IP 해시
    # balance uri           - URI 해시
    # balance url_param id  - URL 파라미터 해시
    # balance hdr(host)     - HTTP 헤더 해시
    # balance random        - 무작위
    # balance rdp-cookie    - RDP 쿠키 기반
```

---

## 7. default-server (서버 기본 파라미터)

```haproxy
defaults
    # 모든 서버에 적용될 기본 파라미터
    default-server inter 10s fall 3 rise 2 weight 1
    default-server check on
    default-server maxconn 100 maxqueue 50

    # 개별 파라미터:
    # inter <시간>: 헬스체크 간격
    # fastinter <시간>: 서버 다운 시 빠른 체크 간격
    # downinter <시간>: 서버 다운 상태에서 체크 간격
    # rise <횟수>: UP으로 판단하기 위한 연속 성공 횟수
    # fall <횟수>: DOWN으로 판단하기 위한 연속 실패 횟수
    # weight <값>: 기본 가중치 (1-256)
    # maxconn <수>: 서버당 최대 연결 수
    # maxqueue <수>: 서버당 최대 큐 크기
    # check: 헬스체크 활성화
    # no-check: 헬스체크 비활성화
    # slowstart <시간>: 서버 복구 후 트래픽 서서히 증가
    # on-error fastinter: 오류 시 빠른 체크로 전환
    # error-limit <횟수>: 오류 한계 도달 시 상태 변경
```

```haproxy
# 실전 예시
defaults
    default-server \
        inter 30s \
        fastinter 5s \
        downinter 60s \
        rise 2 \
        fall 3 \
        weight 1 \
        maxconn 500 \
        check

backend web_servers
    server web1 10.0.0.1:80   # defaults의 default-server 설정 상속
    server web2 10.0.0.2:80 weight 2  # 가중치만 재정의
    server web3 10.0.0.3:80 no-check  # 헬스체크만 비활성화
```

---

## 8. 에러 파일 설정

```haproxy
defaults
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http
```

```bash
# 에러 파일 예시 생성
mkdir -p /etc/haproxy/errors

cat > /etc/haproxy/errors/503.http << 'EOF'
HTTP/1.0 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<!DOCTYPE html>
<html>
<head><title>서비스 점검 중</title></head>
<body>
<h1>서비스 점검 중입니다</h1>
<p>잠시 후 다시 시도해 주세요.</p>
</body>
</html>
EOF

cat > /etc/haproxy/errors/502.http << 'EOF'
HTTP/1.0 502 Bad Gateway
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<!DOCTYPE html>
<html>
<head><title>게이트웨이 오류</title></head>
<body>
<h1>서버에 연결할 수 없습니다</h1>
</body>
</html>
EOF
```

### errorloc / errorloc302
```haproxy
defaults
    # 에러 발생 시 특정 URL로 리다이렉트
    errorloc 503 /maintenance.html
    errorloc302 503 https://maintenance.example.com/
    errorloc303 503 https://status.example.com/
```

---

## 9. 압축 설정

```haproxy
defaults
    # gzip 압축 활성화 (mode http에서만)
    compression algo gzip          # 압축 알고리즘
    compression type text/html text/plain text/css application/json application/javascript
    compression offload            # 서버 압축 응답도 그대로 전달
```

---

## 10. 로그 설정

```haproxy
defaults
    log global          # global 섹션의 log 설정 사용
    # log 127.0.0.1local0  # 별도 로그 서버 지정

    option httplog      # HTTP 상세 로그
    option dontlognull  # 빈 연결 로그 제외

    # 특정 HTTP 상태 코드 로그 설정
    # option log-health-checks  # 헬스체크 결과 로그
```

---

## 11. 완전한 defaults 섹션 예시

### 개발 환경
```haproxy
defaults
    mode http
    log global
    option httplog
    option dontlognull
    option forwardfor
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    maxconn 500
    retries 3
```

### 일반 웹 서비스용
```haproxy
defaults
    mode http
    log global
    option httplog
    option dontlognull
    option http-server-close
    option forwardfor except 127.0.0.0/8
    option redispatch
    retries 3

    timeout http-request    10s
    timeout queue           30s
    timeout connect         5s
    timeout client          30s
    timeout server          30s
    timeout http-keep-alive 10s
    timeout check           5s

    maxconn 10000

    default-server inter 30s fall 3 rise 2

    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http
```

### TCP 서비스용 (DB, Cache 등)
```haproxy
defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    retries 3

    timeout connect 5s
    timeout client 1m
    timeout server 1m
    timeout check 5s

    maxconn 5000
    default-server inter 30s fall 3 rise 2

# 2번째 defaults (이후 섹션에 적용, 앞의 것 초기화)
defaults
    mode http
    log global
    option httplog
    timeout connect 5s
    timeout client 30s
    timeout server 30s
```

### 고성능 API 서비스용
```haproxy
defaults
    mode http
    log global
    option httplog
    option dontlognull
    option http-server-close
    option forwardfor
    option abortonclose     # 클라이언트 연결 끊기면 취소
    option redispatch
    retries 2              # 빠른 실패

    timeout http-request    5s     # 짧게 (DoS 방어)
    timeout queue           10s    # 짧은 큐 대기
    timeout connect         2s     # 빠른 연결 실패 감지
    timeout client          10s    # API는 짧게
    timeout server          60s    # 처리 시간 여유
    timeout http-keep-alive 5s
    timeout check           3s

    maxconn 20000
    balance roundrobin

    default-server inter 10s fastinter 2s downinter 30s fall 3 rise 2 maxconn 200
```

### WebSocket/스트리밍 서비스용
```haproxy
defaults
    mode http
    log global
    option httplog
    option dontlognull
    option http-server-close
    option forwardfor
    retries 1

    timeout http-request    10s
    timeout queue           30s
    timeout connect         5s
    timeout client          10m    # 긴 클라이언트 타임아웃
    timeout server          10m    # 긴 서버 타임아웃
    timeout http-keep-alive 10s
    timeout tunnel          24h    # WebSocket 연결 유지 (1일)
    timeout check           5s

    maxconn 5000
```

---

## 12. defaults 섹션 상속 동작 이해

```haproxy
# === defaults 1 (처음 정의) ===
defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    balance roundrobin

# frontend A: defaults 1 적용
frontend fe_a
    bind *:80
    # mode: http (상속)
    # timeout connect: 5s (상속)
    default_backend bk_a

# backend A: defaults 1 적용
backend bk_a
    # balance: roundrobin (상속)
    server s1 10.0.0.1:80 check

# === defaults 2 (재정의 - 이전 defaults 초기화) ===
defaults
    mode tcp            # http에서 tcp로 변경
    timeout connect 10s # 재정의
    timeout client 1m   # 재정의
    timeout server 1m   # 재정의
    # balance는 초기화됨 (명시 안 함)

# frontend B: defaults 2 적용 (defaults 1 무시)
frontend fe_b
    bind *:3306
    # mode: tcp (defaults 2)
    # timeout connect: 10s (defaults 2)
    default_backend bk_b

# backend B: defaults 2 적용
backend bk_b
    server db1 10.0.0.10:3306 check

# frontend B에서 개별 재정의
frontend fe_c
    bind *:8080
    mode http                   # defaults 2는 tcp지만 여기서 재정의
    timeout client 60s          # defaults 2는 1m이지만 재정의
    default_backend bk_c
```

---

## 13. 자주 하는 실수와 주의사항

```haproxy
# 실수 1: timeout 단위 누락
defaults
    timeout connect 5000   # 밀리초! (5000ms = 5s)
    timeout connect 5s     # 명시적 단위 사용 권장

# 실수 2: mode 불일치
defaults
    mode http

backend tcp_backend
    mode tcp               # 재정의 필요 (안 하면 http로 인식)
    server db1 10.0.0.1:3306 check

# 실수 3: option forwardfor + X-Forwarded-For 중복
defaults
    option forwardfor
# → 이미 X-Forwarded-For가 있으면 추가됨 (두 값이 쉼표로 이어짐)
# 신뢰할 수 없는 XFF 처리:
frontend ft_web
    option forwardfor
    http-request del-header X-Forwarded-For
    http-request set-header X-Forwarded-For %[src]

# 실수 4: timeout client < timeout http-request
defaults
    timeout http-request 30s   # 잘못: client보다 길면 의미 없음
    timeout client 10s
    # 권장: http-request < client
```
