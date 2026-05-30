# HAProxy frontend 섹션 완전 딥다이브

## 개요

`frontend` 섹션은 클라이언트로부터 연결을 수신하고, 요청을 분석하여
적절한 `backend`로 라우팅하는 역할을 합니다.
HAProxy의 L7 기능(헤더 분석, URL 라우팅, ACL 등)이 주로 여기서 이루어집니다.

```haproxy
frontend <이름>
    bind <주소>:<포트> [파라미터...]
    mode http|tcp
    [option ...]
    [acl ...]
    [use_backend <backend이름> if <조건>]
    default_backend <backend이름>
```

---

## 1. bind 지시어 (수신 주소/포트 설정)

### 기본 형태
```haproxy
frontend ft_web
    # 모든 인터페이스, 포트 80
    bind *:80
    bind 0.0.0.0:80    # 동일

    # 특정 IP
    bind 192.168.1.1:80

    # IPv6
    bind :::80             # IPv6 모든 인터페이스
    bind [::1]:80          # IPv6 루프백

    # IPv4+IPv6 동시 (v4v6)
    bind *:80 v4v6

    # 여러 포트
    bind *:80
    bind *:8080
    bind *:8888
```

### 포트 범위 및 여러 주소
```haproxy
frontend ft_multi
    # 여러 bind (같은 frontend)
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    bind *:8080
    bind 10.0.0.1:9000
```

### Unix 도메인 소켓
```haproxy
frontend ft_unix
    # Unix 소켓으로 수신 (nginx와 연동 시 유용)
    bind /run/haproxy.sock user nginx group nginx mode 660
    bind unix@/run/haproxy/frontend.sock
```

### bind 파라미터

```haproxy
frontend ft_advanced
    # SSL/TLS 관련
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    bind *:443 ssl crt /etc/haproxy/certs/         # 디렉토리 (SNI)
    bind *:443 ssl crt /etc/haproxy/certs/server.pem ca-file /etc/haproxy/ca.pem verify required  # mTLS

    # TLS 버전 제어
    bind *:443 ssl crt /etc/haproxy/certs/server.pem ssl-min-ver TLSv1.2

    # ALPN (프로토콜 협상)
    bind *:443 ssl crt /etc/haproxy/certs/server.pem alpn h2,http/1.1

    # 인터페이스 지정
    bind *:80 interface eth0

    # TCP Keep-Alive
    bind *:80 accept-netscaler-cip 1234     # NetScaler CIP 헤더 수신

    # Proxy Protocol
    bind *:80 accept-proxy            # PROXY 프로토콜 v1/v2 수신
    bind *:80 accept-proxy-v2         # PROXY 프로토콜 v2만 수신

    # 포트 재사용
    bind *:80 reuse-port              # SO_REUSEPORT (성능 향상)

    # TCP 백로그 큐 크기
    bind *:80 backlog 4096

    # 최대 연결 수
    bind *:80 maxconn 10000

    # 이름 지정 (로그/통계용)
    bind *:80 name http-in
    bind *:443 name https-in

    # defer-accept: 데이터 도착까지 accept 지연
    bind *:80 defer-accept

    # tfo: TCP Fast Open
    bind *:80 tfo
```

---

## 2. mode 설정

```haproxy
frontend ft_http
    mode http   # HTTP 모드 (L7 분석 가능)
    bind *:80

frontend ft_tcp
    mode tcp    # TCP 모드 (L4, SSL pass-through 등)
    bind *:443
```

---

## 3. default_backend

```haproxy
frontend ft_web
    bind *:80
    # 다른 조건에 해당하지 않는 모든 요청의 기본 목적지
    default_backend bk_web
```

---

## 4. use_backend (조건부 라우팅)

```haproxy
frontend ft_web
    bind *:80

    # ACL 정의
    acl is_api      path_beg /api/
    acl is_static   path_end .css .js .png .jpg .ico .woff2 .gif
    acl is_ws       hdr(Upgrade) -i WebSocket
    acl host_admin  hdr(host) -i admin.example.com

    # 조건에 따라 백엔드 선택 (위에서 아래로 평가, 첫 매치 사용)
    use_backend bk_api     if is_api
    use_backend bk_static  if is_static
    use_backend bk_ws      if is_ws
    use_backend bk_admin   if host_admin

    # 위 조건에 해당하지 않으면 기본 백엔드
    default_backend bk_web
```

### use_backend with negation
```haproxy
frontend ft_web
    acl is_maintenance src_is_addr /etc/haproxy/whitelist.txt

    # 화이트리스트가 아닌 IP는 유지보수 백엔드로
    use_backend bk_maintenance unless is_maintenance

    default_backend bk_web
```

---

## 5. acl (접근 제어 목록)

```haproxy
frontend ft_web
    bind *:80

    # === 경로 기반 ACL ===
    acl is_api          path_beg /api/
    acl is_health       path /health /ping /ready
    acl is_static       path_end .css .js .png .jpg .ico

    # === 호스트 기반 ACL ===
    acl host_www        hdr(host) -i www.example.com
    acl host_api        hdr(host) -i api.example.com
    acl host_admin      hdr(host) -i admin.example.com

    # === IP 기반 ACL ===
    acl internal_net    src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
    acl local           src 127.0.0.1

    # === HTTP 메서드 ACL ===
    acl is_post         method POST
    acl is_get          method GET
    acl is_options      method OPTIONS

    # === 헤더 기반 ACL ===
    acl is_websocket    hdr(Upgrade) -i WebSocket
    acl has_auth        hdr_cnt(Authorization) gt 0
    acl is_mobile       hdr_sub(User-Agent) -i Mobile Android iPhone

    # === SSL 관련 ACL ===
    acl is_ssl          ssl_fc
    acl sni_example     ssl_fc_sni example.com
```

---

## 6. http-request 규칙

```haproxy
frontend ft_web
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/server.pem

    # ============================================================
    # http-request allow / deny
    # ============================================================
    # 특정 경로 차단
    acl is_blocked_path  path_beg /admin/ /phpmyadmin/ /.env
    http-request deny if is_blocked_path

    # 특정 IP 차단
    acl is_banned_ip src -f /etc/haproxy/blacklist.txt
    http-request deny if is_banned_ip

    # 커스텀 응답 코드로 차단
    http-request deny deny_status 403 if is_blocked_path
    http-request deny deny_status 429 content-type "text/plain" string "Rate limit exceeded"

    # ============================================================
    # http-request redirect
    # ============================================================
    # HTTP → HTTPS 리다이렉트
    acl is_http  ssl_fc,not
    http-request redirect scheme https if is_http

    # 영구 리다이렉트 (301)
    http-request redirect scheme https code 301 if is_http

    # 경로 리다이렉트
    http-request redirect location /new-path if { path /old-path }

    # 도메인 변경
    http-request redirect location https://new.example.com%[capture.req.uri] if { hdr(host) -i old.example.com }

    # www 추가
    http-request redirect prefix https://www.example.com if { hdr(host) -i example.com }

    # ============================================================
    # http-request set-header / add-header / del-header
    # ============================================================
    # 헤더 설정 (기존 헤더 교체)
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-request set-header X-Forwarded-Proto http unless { ssl_fc }
    http-request set-header X-Real-IP %[src]
    http-request set-header X-Request-Start %[date()]

    # 헤더 추가 (기존 헤더에 덧붙임)
    http-request add-header X-Custom-Header "value"

    # 헤더 삭제
    http-request del-header X-Internal-Token
    http-request del-header Proxy-Connection

    # ============================================================
    # http-request set-var / set-path / set-uri / set-query
    # ============================================================
    # 변수 설정
    http-request set-var(req.client_ip) src
    http-request set-var(req.is_mobile) req.fhdr(User-Agent),lower,word(1,/) -m sub mobile

    # URI/경로 수정
    http-request set-path /api%[path]  # /health → /api/health
    http-request set-uri %[path]       # 쿼리스트링 제거

    # ============================================================
    # http-request replace-*
    # ============================================================
    # URL 정규식 치환
    http-request replace-path /api/(.*) /\1   # /api/users → /users

    # 헤더 값 치환
    http-request replace-header X-Forwarded-For (.*) [removed]

    # ============================================================
    # http-request capture
    # ============================================================
    # 요청 정보를 로그에 캡처 (로그 변수)
    http-request capture req.hdr(User-Agent) len 100
    http-request capture req.hdr(Referer) len 200
    http-request capture req.cook(sessionid) len 40

    # ============================================================
    # http-request rate-limit (stick-table 활용)
    # ============================================================
    # 요청 속도 제한 (Rate Limiting)
    acl too_many_requests sc_http_req_rate(0) ge 100
    http-request deny deny_status 429 if too_many_requests

    # ============================================================
    # http-request auth
    # ============================================================
    # Basic 인증 요구
    http-request auth realm "Admin Area" if { path_beg /admin/ } !{ http_auth(admin_users) }
    http-request auth unless { http_auth(admin_users) }

    # ============================================================
    # http-request use-service
    # ============================================================
    # Lua 서비스 사용
    http-request use-service lua.my-service if { path /special }

    # ============================================================
    # http-request track-sc* (Stick Table 트래킹)
    # ============================================================
    http-request track-sc0 src table ft_rate_limit
    http-request track-sc1 req.hdr(X-API-Key) table api_rate_limit

    default_backend bk_web
```

---

## 7. tcp-request 규칙

```haproxy
frontend ft_tcp
    bind *:443
    mode tcp

    # TCP 연결 허용/차단
    tcp-request connection accept if { src 10.0.0.0/8 }
    tcp-request connection reject if { src -f /etc/haproxy/blacklist.txt }

    # 속도 제한
    tcp-request connection track-sc0 src
    tcp-request connection reject if { sc_conn_rate(0) ge 50 }

    # Proxy Protocol 처리 후 검사
    tcp-request connection accept if { req_ssl_hello_type 1 }

    # SSL SNI 기반 라우팅 (SSL pass-through)
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    acl sni_app1 req.ssl_sni -i app1.example.com
    acl sni_app2 req.ssl_sni -i app2.example.com

    use_backend bk_app1 if sni_app1
    use_backend bk_app2 if sni_app2

    default_backend bk_default
```

---

## 8. http-response 규칙

```haproxy
frontend ft_web
    bind *:443 ssl crt /etc/haproxy/certs/server.pem

    # 응답 헤더 추가 (보안 헤더)
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    http-response set-header X-Frame-Options "DENY"
    http-response set-header X-Content-Type-Options "nosniff"
    http-response set-header X-XSS-Protection "1; mode=block"
    http-response set-header Referrer-Policy "strict-origin-when-cross-origin"
    http-response set-header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'"
    http-response set-header Permissions-Policy "geolocation=(), camera=(), microphone=()"

    # 서버 정보 숨기기
    http-response del-header Server
    http-response del-header X-Powered-By

    # 응답 헤더 조건부 설정
    acl is_html res.hdr(Content-Type) -i text/html
    http-response set-header Cache-Control "no-cache, no-store, must-revalidate" if is_html

    default_backend bk_web
```

---

## 9. capture (캡처)

```haproxy
frontend ft_web
    bind *:80

    # HTTP 헤더 캡처 (로그용)
    http-request capture req.hdr(Host) len 40
    http-request capture req.hdr(User-Agent) len 100
    http-request capture req.hdr(Referer) len 200
    http-request capture req.hdr(X-Request-ID) len 36

    # 쿠키 캡처
    http-request capture req.cook(sessionid) len 40

    # 응답 헤더 캡처
    http-response capture res.hdr(Content-Type) len 50
    http-response capture res.hdr(X-Cache) len 20

    # 로그 형식에서 %[capture.req.hdr(0)] 처럼 사용
    log-format "%ci:%cp [%tr] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %tsc %ac/%fc/%bc/%sc/%rc %{+Q}r %[capture.req.hdr(0)]"

    default_backend bk_web
```

---

## 10. rate limiting (속도 제한)

```haproxy
# Stick Table을 이용한 rate limiting
frontend ft_api
    bind *:80

    # Stick Table 정의 (요청 속도 추적)
    stick-table type ip size 200k expire 30s store http_req_rate(10s),conn_rate(10s),conn_cur

    # 클라이언트 IP를 stick table에 추적
    http-request track-sc0 src

    # 조건 정의
    acl too_many_req    sc_http_req_rate(0) gt 100   # 10초 내 100 요청 초과
    acl too_many_conn   sc_conn_rate(0) gt 20        # 10초 내 20 연결 초과
    acl too_many_concur sc_conn_cur(0) gt 50         # 동시 연결 50 초과

    # 제한 초과 시 차단
    http-request deny deny_status 429 if too_many_req
    http-request deny deny_status 429 if too_many_conn

    default_backend bk_api
```

---

## 11. 완전한 frontend 예시

### 웹 애플리케이션 + API + 정적 파일
```haproxy
frontend ft_https
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1
    mode http

    # HTTP -> HTTPS 강제
    http-request redirect scheme https code 301 unless { ssl_fc }

    # Rate Limiting
    stick-table type ip size 100k expire 60s store http_req_rate(60s)
    http-request track-sc0 src
    acl rate_exceeded sc_http_req_rate(0) gt 300
    http-request deny deny_status 429 if rate_exceeded

    # 보안: 위험한 경로 차단
    acl dangerous_path path_beg /wp-admin /phpmyadmin /.env /.git
    http-request deny deny_status 404 if dangerous_path

    # 요청 헤더 정리
    http-request del-header Proxy
    http-request del-header X-Forwarded-For
    http-request set-header X-Forwarded-For %[src]
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-request set-header X-Forwarded-Proto http unless { ssl_fc }

    # ACL 정의
    acl host_api    hdr(host) -i api.example.com
    acl host_static hdr(host) -i static.example.com
    acl host_admin  hdr(host) -i admin.example.com
    acl is_api      path_beg /api/
    acl is_static   path_end .css .js .png .jpg .gif .ico .woff .woff2 .ttf
    acl is_ws       hdr(Upgrade) -i websocket
    acl internal    src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

    # 관리자 페이지: 내부 IP만
    http-request deny deny_status 403 if host_admin !internal

    # 백엔드 라우팅
    use_backend bk_api    if host_api
    use_backend bk_api    if is_api
    use_backend bk_static if host_static
    use_backend bk_static if is_static
    use_backend bk_ws     if is_ws
    use_backend bk_admin  if host_admin

    default_backend bk_web

    # 응답 보안 헤더
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains"
    http-response set-header X-Frame-Options "SAMEORIGIN"
    http-response set-header X-Content-Type-Options "nosniff"
    http-response del-header Server
    http-response del-header X-Powered-By

    # 로그
    capture request header User-Agent len 100
    capture request header Referer len 100

### TCP 모드 (MySQL 클러스터)
frontend ft_mysql
    bind *:3306
    mode tcp

    # IP 화이트리스트
    acl allowed_apps src 10.0.1.0/24 10.0.2.0/24
    tcp-request connection reject if !allowed_apps

    default_backend bk_mysql

### HTTPS Pass-Through (SSL 종단점을 서버에서 처리)
frontend ft_ssl_passthrough
    bind *:443
    mode tcp

    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    acl sni_app1  req.ssl_sni -i app1.example.com
    acl sni_app2  req.ssl_sni -i app2.example.com

    use_backend bk_ssl_app1 if sni_app1
    use_backend bk_ssl_app2 if sni_app2

    default_backend bk_ssl_default
```

---

## 12. Logging 설정

```haproxy
frontend ft_web
    bind *:80

    # 기본 로그 포맷 사용
    option httplog

    # 커스텀 로그 포맷
    log-format "%ci:%cp [%tr] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %tsc %ac/%fc/%bc/%sc/%rc %{+Q}r"

    # 특정 상태 로그 제외
    # 헬스체크 요청 로그 안 함
    acl is_health_check path /health /ping
    http-request set-log-level silent if is_health_check

    # 특정 IP 로그 안 함
    acl is_monitoring_ip src 10.0.0.100
    http-request set-log-level silent if is_monitoring_ip

    default_backend bk_web
```

---

## 13. 에러 처리

```haproxy
frontend ft_web
    bind *:80
    mode http

    # 커스텀 에러 페이지
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 429 /etc/haproxy/errors/429.http
    errorfile 503 /etc/haproxy/errors/503.http

    # 에러 리다이렉트
    errorloc 503 https://status.example.com/

    # 조건부 에러
    acl maintenance_mode nbsrv(bk_web) eq 0
    http-request deny deny_status 503 if maintenance_mode

    default_backend bk_web
```
