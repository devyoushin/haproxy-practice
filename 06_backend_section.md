# HAProxy backend 섹션 완전 가이드

backend 섹션은 실제 서버(업스트림)들을 정의하고, 트래픽 분산 방식과 각종 처리 규칙을 설정합니다.
frontend에서 `use_backend` 또는 `default_backend`로 연결된 backend가 실제 요청을 처리할 서버를 선택합니다.

---

## 1. 기본 구조

```
backend <이름>
    balance     <알고리즘>
    option      <옵션>
    server      <이름> <주소:포트> [파라미터...]
```

예시:
```
backend web_servers
    balance     roundrobin
    option      httpchk GET /health HTTP/1.1\r\nHost:\ example.com
    server      web1 192.168.1.10:80 check weight 100
    server      web2 192.168.1.11:80 check weight 100
    server      web3 192.168.1.12:80 check weight 100 backup
```

---

## 2. server 지시어 상세

server 지시어는 backend에 실제 서버를 등록하는 핵심 지시어입니다.

### 기본 문법
```
server <name> <address>[:<port>] [param*]
```

- `name`: 서버의 고유 이름 (통계, 로그, Runtime API에서 사용)
- `address`: IP 주소 또는 호스트명
- `port`: 포트 번호 (backend의 기본 포트와 다를 경우 명시)

### server 파라미터 목록

#### 연결 관련
| 파라미터 | 설명 | 예시 |
|---------|------|------|
| `addr <ip>` | 헬스체크용 별도 IP | `addr 192.168.1.10` |
| `port <n>` | 헬스체크용 별도 포트 | `port 9000` |
| `send-proxy` | PROXY 프로토콜 v1 전송 | `send-proxy` |
| `send-proxy-v2` | PROXY 프로토콜 v2 전송 | `send-proxy-v2` |
| `proxy-v2-options` | PROXY v2 옵션 | `proxy-v2-options ssl,cert-cn` |

#### 헬스체크 관련
| 파라미터 | 설명 | 기본값 |
|---------|------|--------|
| `check` | 헬스체크 활성화 | 비활성 |
| `no-check` | 헬스체크 비활성화 | - |
| `inter <ms>` | 체크 간격 | 2000ms |
| `fastinter <ms>` | 장애 시 체크 간격 | inter 값 |
| `downinter <ms>` | 다운 상태 체크 간격 | inter 값 |
| `rise <n>` | UP 판정 연속 성공 횟수 | 2 |
| `fall <n>` | DOWN 판정 연속 실패 횟수 | 3 |
| `agent-check` | 에이전트 체크 활성화 | - |
| `agent-addr <ip>` | 에이전트 IP | - |
| `agent-port <n>` | 에이전트 포트 | - |
| `agent-inter <ms>` | 에이전트 체크 간격 | inter 값 |

#### 상태 관련
| 파라미터 | 설명 |
|---------|------|
| `backup` | 백업 서버 (모든 primary DOWN 시 사용) |
| `disabled` | 서버 비활성화 (MAINT 상태로 시작) |
| `weight <n>` | 서버 가중치 (0-256, 기본 1) |
| `maxconn <n>` | 서버당 최대 동시 연결 수 |
| `maxqueue <n>` | 큐 최대 대기 요청 수 |
| `minconn <n>` | 동적 연결 수 최솟값 (maxconn과 함께) |
| `slowstart <ms>` | 복구 후 점진적 가중치 증가 시간 |

#### 세션/연결 지속성
| 파라미터 | 설명 |
|---------|------|
| `cookie <value>` | 쿠키 세션 고정 값 |
| `observe <mode>` | 에러 관찰 (layer4, layer7) |
| `on-error <mode>` | 에러 시 동작 (fastinter, fail-check, sudden-death, mark-down) |
| `on-marked-down <action>` | 서버 다운 시 동작 |
| `on-marked-up <action>` | 서버 복구 시 동작 |

#### SSL 관련
| 파라미터 | 설명 |
|---------|------|
| `ssl` | 백엔드 SSL 연결 활성화 |
| `ssl-min-ver <ver>` | 최소 TLS 버전 |
| `ssl-max-ver <ver>` | 최대 TLS 버전 |
| `verify none` | 인증서 검증 비활성화 |
| `verify required` | 인증서 검증 필수 |
| `ca-file <file>` | CA 인증서 파일 |
| `crt <file>` | 클라이언트 인증서 파일 |
| `sni <expr>` | SNI 값 |
| `alpn <protocols>` | ALPN 프로토콜 목록 |

#### 기타
| 파라미터 | 설명 |
|---------|------|
| `id <n>` | 고정 서버 ID (Runtime API용) |
| `namespace <ns>` | Linux 네트워크 네임스페이스 |
| `track <be>/<srv>` | 다른 서버 상태 추적 |
| `init-addr <method>` | 초기 주소 해결 방법 |
| `resolvers <id>` | DNS 리졸버 설정 참조 |
| `resolve-prefer <ipv4/ipv6>` | DNS 해결 선호 프로토콜 |

---

## 3. default-server

서버 공통 파라미터를 한 번에 설정합니다. 개별 server 설정이 우선합니다.
반복적인 파라미터 설정을 줄여주고 실수를 방지합니다.

```
backend web_servers
    default-server inter 3s fall 3 rise 2 on-error fastinter slowstart 60s maxconn 100
    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
    server web3 192.168.1.12:80 check weight 200   # weight만 개별 오버라이드
```

여러 `default-server` 지시어를 순서대로 선언할 수 있으며, 마지막으로 지정된 값이 적용됩니다.

```
backend flexible_servers
    default-server inter 2s fall 3 rise 2
    default-server maxconn 100 slowstart 30s

    # 위 두 default-server의 설정이 모두 적용됨
    server app1 10.0.0.1:8080 check
    server app2 10.0.0.2:8080 check maxconn 200  # maxconn만 개별 설정
```

---

## 4. 로드밸런싱 (balance)

```
backend web
    balance roundrobin   # 기본값 - 순서대로 분산
    # balance leastconn  # 현재 연결 수 가장 적은 서버
    # balance source     # 클라이언트 IP 해시
    # balance uri        # URI 해시 (캐시에 적합)
    # balance hdr(X-User-Id)  # 특정 헤더 값 해시
    # balance random     # 무작위
    # balance first      # 첫 번째 서버 우선
```

상세 내용은 [로드밸런싱 알고리즘 문서](08_로드밸런싱_알고리즘.md) 참고.

---

## 5. 헬스체크 설정

### HTTP 헬스체크
```
backend app_servers
    option httpchk
    # 기본: OPTIONS / HTTP/1.0

    # 커스텀 경로 지정
    option httpchk GET /health HTTP/1.1\r\nHost:\ app.example.com

    http-check expect status 200
    # 또는 여러 상태코드
    http-check expect rstatus (2|3)[0-9][0-9]

    server app1 10.0.0.1:8080 check
    server app2 10.0.0.2:8080 check
```

### HTTP 체크 응답 매칭
```
backend api_servers
    option httpchk GET /status
    http-check expect string "OK"
    # http-check expect ! string "ERROR"
    # http-check expect rstring "status.*healthy"
    server api1 10.0.0.1:3000 check
```

### TCP 체크
```
backend db_servers
    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string "+PONG"
    server redis1 10.0.0.1:6379 check
```

### 헬스체크 관련 전역 설정
```
defaults
    timeout check 5s          # 헬스체크 응답 대기 시간
    option log-health-checks  # 헬스체크 결과 로깅
```

---

## 6. HTTP 요청/응답 수정

### http-request 규칙
```
backend web
    # 헤더 추가
    http-request add-header X-Backend-Server %[srv_name]
    http-request set-header X-Real-IP %[src]
    http-request set-header X-Forwarded-Proto https if { ssl_fc }

    # 헤더 삭제
    http-request del-header X-Internal-Token

    # URL 재작성
    http-request set-path /api%[path]

    # 인증 (userlist 기반)
    http-request auth realm "Protected" if !{ http_auth(admin_users) }

    # 요청 거부
    http-request deny if { src -f /etc/haproxy/blacklist.txt }

    # 요청 리다이렉트
    http-request redirect location https://%[req.hdr(Host)]%[path] if !{ ssl_fc }

    # 변수 설정
    http-request set-var(req.user_id) req.hdr(X-User-Id)

    server web1 192.168.1.10:80 check
```

### http-response 규칙
```
backend web
    # 보안 헤더 추가
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    http-response set-header X-Frame-Options DENY
    http-response set-header X-Content-Type-Options nosniff
    http-response set-header X-XSS-Protection "1; mode=block"

    # 서버 정보 헤더 제거
    http-response del-header Server
    http-response del-header X-Powered-By

    # 압축 활성화
    compression algo gzip
    compression type text/html text/plain text/css application/javascript application/json

    server web1 192.168.1.10:80 check
```

---

## 7. 쿠키 기반 세션 고정

세션 친화성(Sticky Sessions)이 필요한 경우 쿠키를 사용하여 동일 클라이언트를 같은 서버로 라우팅합니다.

```
backend web
    balance roundrobin

    # insert 방식: HAProxy가 쿠키를 삽입
    cookie SERVERID insert indirect nocache httponly secure

    server web1 192.168.1.10:80 check cookie web1
    server web2 192.168.1.11:80 check cookie web2
    server web3 192.168.1.12:80 check cookie web3
```

### 쿠키 방식 옵션
| 옵션 | 설명 |
|------|------|
| `insert` | 응답에 쿠키 삽입 (HAProxy가 직접) |
| `rewrite` | 기존 Set-Cookie 헤더 값 변경 |
| `prefix` | 기존 쿠키에 접두사 추가 |
| `indirect` | 백엔드에 쿠키 전달 안 함 (백엔드는 쿠키 인식 못 함) |
| `nocache` | Cache-Control: no-cache 추가 |
| `postonly` | POST 요청에만 쿠키 설정 |
| `preserve` | 서버가 이미 쿠키 보낸 경우 유지 |
| `httponly` | HttpOnly 플래그 (XSS 방지) |
| `secure` | Secure 플래그 (HTTPS만) |
| `domain <d>` | 쿠키 도메인 |
| `maxidle <s>` | 쿠키 비활성 만료 시간 (초) |
| `maxlife <s>` | 쿠키 최대 수명 (초) |
| `dynamic` | 동적 쿠키 (HMAC 기반, 서버 목록 변경에 강함) |

### dynamic 쿠키 예시 (HMAC)
```
backend web
    cookie SERVERID insert indirect nocache dynamic
    dynamic-cookie-key "mysecretkey1234"

    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
    # dynamic 사용 시 cookie <value>를 각 서버에 명시할 필요 없음
```

---

## 8. stick-table 연동

```
backend web
    # stick-table 직접 정의
    stick-table type ip size 1m expire 30m store conn_cur,conn_rate(3s),http_req_rate(10s)

    # 소스 IP를 키로 서버 고정
    stick on src

    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
```

상세 내용은 [스틱테이블 문서](14_스틱테이블_세션.md) 참고.

---

## 9. 큐잉 (Queueing)

서버가 `maxconn`에 도달하면 요청을 큐에 대기시킵니다.
큐가 꽉 찼거나 `timeout queue`가 초과되면 503을 반환합니다.

```
backend web
    timeout queue 30s       # 큐 대기 최대 시간
    server web1 192.168.1.10:80 check maxconn 50 maxqueue 100
    server web2 192.168.1.11:80 check maxconn 50 maxqueue 100
```

### 큐 동작 흐름
```
새 요청 도착
    → 서버 선택 시도
    → 서버 maxconn 초과?
        → 아니오: 즉시 전달
        → 예: 큐에 대기
            → maxqueue 미만이고 timeout queue 미초과?
                → 예: 대기 후 서버 슬롯 확보되면 전달
                → 아니오: 503 반환
```

---

## 10. 연결 재사용 (Connection Reuse)

HAProxy 2.1+에서 HTTP/1.1 연결 재사용 기능:

```
backend web
    # 연결 재사용 모드
    http-reuse safe       # 안전한 재사용 (기본) - 완전히 처리된 요청의 연결만 재사용
    # http-reuse aggressive  # 공격적 재사용 - 멱등한(idempotent) 요청에도 재사용
    # http-reuse always      # 항상 재사용 (위험할 수 있음)
    # http-reuse never       # 재사용 안 함 (매 요청마다 새 연결)

    server web1 192.168.1.10:80 check
```

### 재사용 모드 비교
| 모드 | 설명 | 적합한 경우 |
|------|------|------------|
| `never` | 연결 재사용 없음 | 레거시 서버, 상태 유지 프로토콜 |
| `safe` | 완료된 요청의 연결만 재사용 | 일반적인 HTTP 서비스 |
| `aggressive` | 멱등 요청도 재사용 | 성능 최적화가 필요한 경우 |
| `always` | 항상 재사용 | 신뢰할 수 있는 백엔드 |

---

## 11. 에러 처리

```
backend web
    # HTTP 에러 응답 파일 (파일에 HTTP 응답 전체를 저장)
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

    # 또는 리다이렉트
    errorloc 503 /maintenance.html         # 301 리다이렉트
    errorloc302 503 https://status.example.com  # 302 리다이렉트

    server web1 192.168.1.10:80 check
```

### errorfile 형식 예시
```
# /etc/haproxy/errors/503.http
HTTP/1.1 503 Service Unavailable
Content-Type: text/html; charset=utf-8
Cache-Control: no-cache
Connection: close

<html>
<head><title>503 Service Unavailable</title></head>
<body>
<h1>서비스 일시 중단</h1>
<p>현재 서버 점검 중입니다. 잠시 후 다시 이용해주세요.</p>
</body>
</html>
```

---

## 12. 재시도 (Retry)

```
backend web
    retries 3                    # 연결 실패 시 재시도 횟수 (기본값 3)
    retry-on conn-failure empty-response  # 재시도 조건

    # retry-on 조건들:
    # conn-failure       - 연결 실패 (네트워크 오류)
    # empty-response     - 빈 응답 (서버가 아무것도 보내지 않음)
    # junk-response      - 잘못된 HTTP 응답
    # response-timeout   - 응답 타임아웃
    # 0rtt-rejected      - TLS 0-RTT 거부
    # all-retryable-errors - 위의 모든 조건

    # 재시도 시 다음 서버로 (option redispatch)
    option redispatch          # 재시도 시 다른 서버 시도

    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
```

---

## 13. 타임아웃 (Timeout)

```
backend web
    timeout connect  5s     # 서버 TCP 연결 수립 타임아웃
    timeout server   30s    # 서버 응답 대기 타임아웃 (첫 바이트)
    timeout tunnel   1h     # 터널 모드 타임아웃 (WebSocket, CONNECT 등)
    timeout queue    10s    # 큐 대기 타임아웃
    timeout check    5s     # 헬스체크 타임아웃

    server web1 192.168.1.10:80 check
```

### 타임아웃 적용 순서
```
클라이언트 연결 수락 (timeout client)
    → HAProxy → 백엔드 연결 시도 (timeout connect)
    → 큐 대기 (timeout queue)
    → 백엔드 응답 대기 (timeout server)
    → 터널 유휴 (timeout tunnel)
```

---

## 14. HTTP/2 & gRPC 지원

```
backend grpc_servers
    # gRPC는 HTTP/2 기반, alpn h2로 협상
    server grpc1 192.168.1.10:50051 check ssl verify none alpn h2

    # gRPC 헬스체크 (grpc.health.v1.Health 프로토콜)
    option httpchk
    http-check send meth POST uri /grpc.health.v1.Health/Check \
        ver HTTP/2 \
        hdr content-type application/grpc
    http-check expect status 200
```

### gRPC 완전 설정 예시
```
frontend grpc_frontend
    bind *:443 ssl crt /etc/haproxy/certs/server.pem alpn h2
    mode http
    default_backend grpc_backend

backend grpc_backend
    mode http
    balance roundrobin
    server grpc1 10.0.0.1:50051 check ssl verify none alpn h2
    server grpc2 10.0.0.2:50051 check ssl verify none alpn h2
```

---

## 15. TCP 모드 backend

```
backend mysql_cluster
    mode tcp
    balance leastconn
    option tcp-check
    tcp-check connect
    # MySQL 핸드셰이크 확인
    tcp-check expect binary 0a   # MySQL welcome packet 시작 바이트
    server mysql1 192.168.1.10:3306 check
    server mysql2 192.168.1.11:3306 check backup
```

---

## 16. 동적 서버 (DNS 해결)

```
resolvers mydns
    nameserver dns1 8.8.8.8:53
    nameserver dns2 8.8.4.4:53
    resolve_retries 3
    timeout resolve 1s
    timeout retry   1s
    hold valid      10s
    hold other      30s
    hold refused    30s
    hold nx         30s
    hold timeout    30s

backend dynamic_web
    server web1 web.example.com:80 check resolvers mydns resolve-prefer ipv4 init-addr none
```

---

## 17. 로깅 관련 backend 설정

```
backend web
    # 요청 캡처
    capture request header Host len 50
    capture request header User-Agent len 100
    capture response header Content-Type len 50

    # 에러만 로깅
    option dontlog-normal

    server web1 192.168.1.10:80 check
```

---

## 18. 완전한 프로덕션 예시

```haproxy
backend production_api
    mode http
    balance leastconn

    # 기본 서버 설정 (모든 서버에 공통 적용)
    default-server inter 3s fall 3 rise 2 slowstart 30s maxconn 200 weight 100

    # 헬스체크 설정
    option httpchk GET /api/health HTTP/1.1\r\nHost:\ api.example.com
    http-check expect status 200

    # 요청 수정
    http-request set-header X-Forwarded-For %[src]
    http-request set-header X-Forwarded-Proto https
    http-request add-header X-Request-ID %[uuid]
    http-request del-header X-Internal-Secret

    # 응답 수정
    http-response del-header Server
    http-response del-header X-Powered-By
    http-response set-header X-Content-Type-Options nosniff
    http-response set-header Strict-Transport-Security "max-age=31536000"

    # 압축
    compression algo gzip
    compression type application/json text/plain

    # 에러 처리
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 502 /etc/haproxy/errors/502.http

    # 재시도
    retries 2
    option redispatch
    retry-on conn-failure empty-response

    # 타임아웃
    timeout connect  3s
    timeout server   30s
    timeout queue    10s

    # 세션 고정 (쿠키 방식)
    cookie APISERVER insert indirect nocache httponly secure dynamic
    dynamic-cookie-key "supersecretkey123"

    # 연결 재사용
    http-reuse safe

    # 서버 목록
    server api1 10.0.1.10:8080 check weight 100 id 1 cookie api1
    server api2 10.0.1.11:8080 check weight 100 id 2 cookie api2
    server api3 10.0.1.12:8080 check weight 100 id 3 cookie api3
    server api_backup 10.0.1.20:8080 check backup id 10 cookie backup
```

---

## 19. backend 네이밍 컨벤션 권장사항

| 방식 | 예시 | 설명 |
|------|------|------|
| 서비스명_환경 | `web_prod`, `api_staging` | 서비스와 환경 구분 |
| 기능_프로토콜 | `auth_http`, `grpc_billing` | 기능과 프로토콜 구분 |
| 숫자 접미사 | `backend_v1`, `backend_v2` | 버전 관리 (블루-그린 배포) |

---

## 20. 참고: frontend에서 backend 선택

```haproxy
frontend main
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/

    acl is_api   path_beg /api/
    acl is_admin path_beg /admin/

    use_backend api_backend   if is_api
    use_backend admin_backend if is_admin
    default_backend web_backend   # 매칭되지 않는 경우 기본 backend
```
