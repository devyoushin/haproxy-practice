# HAProxy 보안 설정 완전 가이드

HAProxy는 다양한 보안 기능을 제공합니다. 속도 제한, 접근 제어, SSL 보안, 요청 검증 등을 통해
웹 애플리케이션을 보호합니다.

---

## 1. Rate Limiting (속도 제한)

### 1.1 기본 IP 기반 속도 제한
```haproxy
frontend web
    bind *:80
    mode http

    # stick-table 정의
    stick-table type ip size 100k expire 30s store http_req_rate(10s),conn_cur,gpc0

    # 요청 추적
    http-request track-sc0 src

    # IP당 10초에 200 요청 초과 시 차단
    acl abuse sc_http_req_rate(0) gt 200
    acl mark_as_abuser sc_inc_gpc0(0) ge 0  # 항상 참 반환
    http-request deny deny_status 429 if abuse mark_as_abuser

    # 현재 연결 수 50개 초과 시 차단
    acl too_many_connections sc_conn_cur(0) gt 50
    http-request deny deny_status 429 if too_many_connections

    default_backend web_backend
```

### 1.2 429 Too Many Requests 커스텀 응답
```haproxy
frontend web
    bind *:80
    mode http

    # 커스텀 에러 파일 설정
    errorfile 429 /etc/haproxy/errors/429.http

    stick-table type ip size 100k expire 30s store http_req_rate(10s)
    http-request track-sc0 src

    acl rate_limited sc_http_req_rate(0) gt 100
    http-request deny deny_status 429 if rate_limited

    default_backend web_backend
```

429 에러 파일 (/etc/haproxy/errors/429.http):
```
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 10
Cache-Control: no-cache

{"error":"rate_limit_exceeded","message":"Too many requests. Please wait before retrying.","retry_after":10}
```

### 1.3 TCP 연결 레벨 속도 제한 (레이어 4)
```haproxy
frontend tcp_front
    bind *:80
    mode tcp

    stick-table type ip size 100k expire 10s store conn_rate(10s)
    tcp-request connection track-sc0 src

    # 10초에 100개 이상 연결 시도 차단 (SYN 플러딩 방지)
    acl syn_flood sc_conn_rate(0) gt 100
    tcp-request connection reject if syn_flood

    default_backend tcp_backend
```

---

## 2. HTTP 보안 헤더

### 2.1 표준 보안 헤더
```haproxy
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/server.pem

    # HSTS: 브라우저가 1년간 HTTPS만 사용
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"

    # 클릭재킹 방지
    http-response set-header X-Frame-Options "SAMEORIGIN"
    # 또는 완전히 금지: http-response set-header X-Frame-Options "DENY"

    # MIME 스니핑 방지
    http-response set-header X-Content-Type-Options "nosniff"

    # XSS 필터 (구형 브라우저용)
    http-response set-header X-XSS-Protection "1; mode=block"

    # 리퍼러 정책
    http-response set-header Referrer-Policy "strict-origin-when-cross-origin"

    # 권한 정책 (카메라, 마이크, 위치 정보 차단)
    http-response set-header Permissions-Policy "camera=(), microphone=(), geolocation=(), interest-cohort=()"

    # 콘텐츠 보안 정책 (CSP)
    http-response set-header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:;"

    # 서버 정보 제거 (정보 노출 방지)
    http-response del-header Server
    http-response del-header X-Powered-By
    http-response del-header X-AspNet-Version
    http-response del-header X-AspNetMvc-Version

    default_backend web_backend
```

### 2.2 CORS 설정
```haproxy
frontend api_front
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    mode http

    # 허용할 Origin 목록
    acl allowed_origin req.hdr(Origin) -i -m str \
        https://app.example.com \
        https://admin.example.com

    # OPTIONS preflight 요청 처리
    acl is_options method OPTIONS

    # CORS 헤더 추가
    http-response set-header Access-Control-Allow-Origin "%[req.hdr(Origin)]" if allowed_origin
    http-response set-header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" if allowed_origin
    http-response set-header Access-Control-Allow-Headers "Authorization, Content-Type, X-Request-ID" if allowed_origin
    http-response set-header Access-Control-Max-Age "3600" if allowed_origin is_options
    http-response set-header Access-Control-Allow-Credentials "true" if allowed_origin

    # OPTIONS preflight에 즉시 204 응답
    http-request return status 204 if is_options allowed_origin

    # 허용되지 않은 Origin 차단
    http-request deny if !allowed_origin { req.hdr(Origin) -m found }

    default_backend api_backend
```

---

## 3. IP 블랙리스트/화이트리스트

### 3.1 파일 기반 블랙리스트
```haproxy
frontend web
    bind *:80
    mode http

    # 블랙리스트 (IP, CIDR 모두 지원)
    acl blacklist src -f /etc/haproxy/blacklist.txt

    # TCP 레벨에서 차단 (HTTP 처리 전, 더 효율적)
    tcp-request connection reject if blacklist

    default_backend web_backend
```

blacklist.txt 예시:
```
# 알려진 악성 IP
1.2.3.4
5.6.7.0/24
# Tor 출구 노드
10.20.30.0/24
```

### 3.2 화이트리스트
```haproxy
frontend admin_front
    bind *:8080
    mode http

    # 허용할 IP 대역
    acl whitelist src 10.0.0.0/8 192.168.0.0/16
    acl whitelist src -f /etc/haproxy/admin_whitelist.txt

    # 화이트리스트에 없으면 차단 (TCP 레벨)
    tcp-request connection reject if !whitelist

    default_backend admin_backend
```

### 3.3 동적 블랙리스트 (Runtime API 활용)
```bash
# 실시간 IP 차단
echo "add acl /etc/haproxy/blacklist.txt 1.2.3.4" | socat /run/haproxy/admin.sock stdio

# 차단 해제
echo "del acl /etc/haproxy/blacklist.txt 1.2.3.4" | socat /run/haproxy/admin.sock stdio

# 현재 블랙리스트 확인
echo "show acl /etc/haproxy/blacklist.txt" | socat /run/haproxy/admin.sock stdio
```

### 3.4 Stick Table 기반 자동 차단
```haproxy
frontend web
    bind *:80
    mode http

    stick-table type ip size 100k expire 1h store gpc0,http_req_rate(10s),http_err_rate(30s)
    http-request track-sc0 src

    # gpc0가 1이면 블랙리스트에 등록된 것으로 간주 → 차단
    acl is_banned sc_get_gpc0(0) ge 1
    http-request deny deny_status 403 if is_banned

    # 에러율이 높으면 자동으로 gpc0 설정 (자동 차단)
    acl high_errors sc_http_err_rate(0) gt 30
    http-request sc-inc-gpc0(0) if high_errors !is_banned
    http-request deny deny_status 429 if high_errors

    default_backend web_backend
```

---

## 4. 요청 검증

### 4.1 기본 요청 검증
```haproxy
frontend web
    bind *:80
    mode http

    # Host 헤더 중복 차단 (HTTP Smuggling 방지)
    http-request deny if { req.hdr_cnt(host) gt 1 }

    # Content-Length 헤더 중복 차단 (HTTP Smuggling 방지)
    http-request deny if { req.hdr_cnt(content-length) gt 1 }

    # 너무 큰 요청 차단 (10MB)
    http-request deny if { req.hdr_val(content-length) gt 10485760 }

    # 비정상적으로 긴 URL 차단 (8KB)
    http-request deny if { url,len gt 8192 }

    # 비정상적으로 긴 헤더 차단
    http-request deny if { req.hdr(host),len gt 255 }

    # HTTP 메서드 제한 (알려진 메서드만 허용)
    acl valid_method method GET HEAD POST PUT PATCH DELETE OPTIONS TRACE
    http-request deny if !valid_method

    default_backend web_backend
```

### 4.2 관리자 경로 보호
```haproxy
frontend web
    bind *:80
    mode http

    # 관리자 경로는 내부 IP만 접근 가능
    acl is_admin_path path_beg /admin /manage /monitoring /metrics /_internal
    acl is_internal   src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

    http-request deny if is_admin_path !is_internal

    # 특정 파일 직접 접근 차단
    acl dangerous_files path_end .env .git .svn .htaccess .htpasswd
    acl hidden_dirs path_beg /.
    http-request deny if dangerous_files
    http-request deny if hidden_dirs

    default_backend web_backend
```

### 4.3 SQL Injection / XSS 기본 방어
```haproxy
frontend web
    bind *:80
    mode http

    # 기본적인 악성 패턴 차단 (WAF 수준은 아님, 보조 수단)
    acl sql_injection url -m sub -i "union+select" "drop+table" "'OR'1'='1" "1=1--"
    acl xss_attempt   url -m sub -i "<script" "javascript:" "onerror=" "onload="

    http-request deny if sql_injection
    http-request deny if xss_attempt

    default_backend web_backend
```

### 4.4 User-Agent 검증
```haproxy
frontend web
    bind *:80
    mode http

    # 알려진 공격 도구 차단
    acl scanner_agent hdr(User-Agent) -i -m sub \
        nikto \
        sqlmap \
        nmap \
        masscan \
        acunetix \
        nessus \
        burpsuite \
        ZAP \
        w3af

    # 불량 봇 차단 (SEO/스크래핑 봇 중 정책 위반)
    acl bad_bot hdr(User-Agent) -i -m sub \
        "MJ12bot" \
        "AhrefsBot" \
        "SemrushBot" \
        "DotBot" \
        "Baiduspider"

    http-request deny if scanner_agent
    # http-request deny if bad_bot  # 선택적 적용

    default_backend web_backend
```

---

## 5. chroot 설정

```haproxy
global
    # HAProxy 프로세스를 chroot 디렉토리로 격리
    chroot /var/lib/haproxy

    # chroot 디렉토리 준비
    # mkdir -p /var/lib/haproxy
    # chown haproxy:haproxy /var/lib/haproxy
    # chmod 755 /var/lib/haproxy
```

chroot 디렉토리 준비 스크립트:
```bash
#!/bin/bash
CHROOT_DIR="/var/lib/haproxy"

# 디렉토리 생성
mkdir -p "${CHROOT_DIR}"
mkdir -p "${CHROOT_DIR}/dev"
mkdir -p "${CHROOT_DIR}/etc/haproxy"

# 필요한 디바이스 파일
mknod -m 666 "${CHROOT_DIR}/dev/null" c 1 3
mknod -m 666 "${CHROOT_DIR}/dev/urandom" c 1 9
mknod -m 666 "${CHROOT_DIR}/dev/log" c 1 8  # syslog 소켓 (필요시)

# 권한 설정
chown -R haproxy:haproxy "${CHROOT_DIR}"
chmod 755 "${CHROOT_DIR}"
```

---

## 6. 프로세스 보안 (최소 권한 원칙)

```haproxy
global
    # 비특권 사용자로 실행
    user  haproxy
    group haproxy

    # 데몬 모드
    daemon

    # 관리 소켓 권한 제한
    stats socket /run/haproxy/admin.sock mode 660 level admin user haproxy group haproxy

    # 읽기 전용 소켓 (모니터링 툴용)
    stats socket /run/haproxy/monitor.sock mode 664 level operator user haproxy group monitoring

    # 파일 디스크립터 제한 설정 필요
    # /etc/security/limits.d/haproxy.conf에서 설정
```

---

## 7. Slowloris 방어

Slowloris는 HTTP 요청을 매우 느리게 전송하여 서버 연결을 고갈시키는 공격입니다.

```haproxy
defaults
    # HTTP 요청 수신 타임아웃 (헤더 완료까지)
    timeout http-request    10s

    # Keep-alive 유휴 타임아웃
    timeout http-keep-alive 2s

    # 클라이언트 응답 타임아웃
    timeout client          30s

    # 클라이언트 FIN 대기 타임아웃
    timeout client-fin      5s

frontend web
    bind *:80
    mode http

    # maxconn으로 프론트엔드 연결 제한
    maxconn 10000

    # stick-table로 IP당 연결 수 제한
    stick-table type ip size 100k expire 30s store conn_cur,conn_rate(10s)
    tcp-request connection track-sc0 src
    tcp-request connection reject if { sc_conn_cur(0) gt 100 }

    default_backend web_backend
```

---

## 8. DDoS 대응 계층별 설정

```haproxy
frontend anti_ddos
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/
    mode http

    #--- 레이어 3/4 (TCP 레벨) ---
    # TCP 연결 수 제한
    stick-table type ip size 1m expire 10s store conn_rate(10s),conn_cur
    tcp-request connection track-sc0 src

    acl tcp_syn_flood sc_conn_rate(0) gt 200
    tcp-request connection reject if tcp_syn_flood

    #--- 레이어 7 (HTTP 레벨) ---
    stick-table type ip size 1m expire 30s store http_req_rate(10s),http_err_rate(30s),gpc0 peers haproxy_cluster

    http-request track-sc1 src

    # 레벨 1: 경고 (10초에 300개 이상)
    acl level1_abuse sc_http_req_rate(1) gt 300
    http-request sc-inc-gpc0(1) if level1_abuse

    # 레벨 2: 속도 제한 (10초에 500개 이상)
    acl level2_abuse sc_http_req_rate(1) gt 500
    http-request deny deny_status 429 if level2_abuse

    # 레벨 3: 영구 차단 (gpc0 누적 5 이상)
    acl permanent_ban sc_get_gpc0(1) ge 5
    http-request deny deny_status 403 if permanent_ban

    # HTTP Flood 방어: 동일 User-Agent + 빠른 요청
    stick-table type string len 100 size 100k expire 30s store http_req_rate(10s)
    http-request track-sc2 req.hdr(User-Agent) table anti_ddos if { req.hdr(User-Agent) -m found }

    default_backend web_backend
```

---

## 9. 인증 설정

### 9.1 HTTP Basic Auth
```haproxy
# 사용자 목록 정의
userlist monitoring_users
    user nagios   password $6$rounds=100000$x72RGsEQC.BxQE$.../hashedpass
    user readonly password $6$rounds=100000$x72RGsEQC.BxQE$.../hashedpass2
    group viewers users nagios readonly

userlist admin_users
    user admin    password $6$rounds=100000$x72RGsEQC.BxQE$.../adminpass
    group admins  users admin

frontend protected
    bind *:8080
    mode http

    acl is_monitoring_user http_auth(monitoring_users)
    acl is_admin           http_auth_group(admin_users) admins

    # 인증 요구
    http-request auth realm "Protected Area" unless is_monitoring_user

    # 관리 경로는 admin만
    http-request deny if { path_beg /admin } !is_admin

    default_backend monitoring_backend
```

### 비밀번호 해시 생성 방법
```bash
# mkpasswd 사용 (whois 패키지에 포함)
mkpasswd -m sha-512 "mypassword"

# Python 사용
python3 -c "import crypt; print(crypt.crypt('mypassword', crypt.mksalt(crypt.METHOD_SHA512)))"

# openssl 사용 (SHA-256)
openssl passwd -6 "mypassword"
```

---

## 10. 완전한 보안 설정 예시

```haproxy
#---------------------------------------------------------------------
# 프로덕션 보안 강화 HAProxy 설정
#---------------------------------------------------------------------
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin user haproxy group haproxy
    maxconn 50000
    nbthread 4
    user haproxy
    group haproxy
    daemon

    # SSL 보안 설정 (Mozilla Intermediate)
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    option  forwardfor
    option  http-server-close

    timeout connect  5s
    timeout client   30s
    timeout server   30s
    timeout http-request 10s
    timeout http-keep-alive 2s

#---------------------------------------------------------------------
# 보안 프론트엔드
#---------------------------------------------------------------------
frontend secure_front
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/

    # HTTP → HTTPS 리다이렉트
    http-request redirect scheme https code 301 if !{ ssl_fc }

    # 보안 헤더
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    http-response set-header X-Frame-Options "SAMEORIGIN"
    http-response set-header X-Content-Type-Options "nosniff"
    http-response set-header Referrer-Policy "strict-origin-when-cross-origin"
    http-response set-header X-XSS-Protection "1; mode=block"
    http-response del-header Server
    http-response del-header X-Powered-By

    # 블랙리스트 차단 (TCP 레벨)
    acl blacklist src -f /etc/haproxy/blacklist.txt
    tcp-request connection reject if blacklist

    # Rate Limiting
    stick-table type ip size 1m expire 30s store http_req_rate(10s),conn_cur,gpc0
    http-request track-sc0 src

    acl rate_limit sc_http_req_rate(0) gt 300
    acl banned     sc_get_gpc0(0) ge 3

    http-request deny deny_status 429 if rate_limit
    http-request deny deny_status 403 if banned

    # 요청 검증
    http-request deny if { req.hdr_cnt(host) gt 1 }
    http-request deny if { req.hdr_val(content-length) gt 10485760 }
    http-request deny if { url,len gt 8192 }
    http-request deny if { path_end .env .git .htaccess .htpasswd }
    http-request deny if { hdr(User-Agent) -i -m sub sqlmap nikto nmap }

    # X-Forwarded-For 설정
    http-request set-header X-Real-IP %[src]
    http-request set-header X-Forwarded-Proto https if { ssl_fc }

    use_backend api_backend    if { path_beg /api/ }
    default_backend web_backend

backend web_backend
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 slowstart 30s
    server web1 10.0.0.10:80 check
    server web2 10.0.0.11:80 check

backend api_backend
    balance leastconn
    option httpchk GET /api/health
    http-check expect status 200
    default-server inter 3s fall 3 rise 2
    server api1 10.0.1.10:8080 check
    server api2 10.0.1.11:8080 check
```
