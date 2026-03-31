# HAProxy ACL (Access Control List) 완전 가이드

ACL은 요청/연결에 대해 조건을 평가하여 참(true) 또는 거짓(false)을 반환합니다.
이를 통해 트래픽 라우팅, 접근 제어, 요청 변환 등을 동적으로 제어합니다.

---

## 1. 기본 문법

```
acl <name> <fetch_method>[(<args>)] [flags] [operator] <value(s)>
```

| 구성 요소 | 설명 | 예시 |
|---------|------|------|
| `name` | ACL 이름 (재사용 가능) | `is_api` |
| `fetch_method` | 가져올 데이터 (fetch) | `path`, `hdr`, `src` |
| `args` | fetch의 인자 | `hdr(Host)`, `urlp(id)` |
| `flags` | 매칭 옵션 | `-i`, `-f`, `-m` |
| `operator` | 비교 연산자 | `-m str`, `-m reg`, `eq`, `gt` |
| `value` | 비교할 값 | `/api/`, `80`, `192.168.1.0/24` |

---

## 2. 레이어 4 (TCP) Fetch 메서드

```haproxy
frontend tcp_front
    mode tcp
    bind *:443

    # 소스 IP
    acl is_private src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
    acl is_localhost src 127.0.0.1

    # 목적지 IP
    acl is_local_dst dst 127.0.0.1

    # 소스 포트
    acl high_port src_port 1024:65535

    # 목적지 포트
    acl is_https dst_port 443
    acl is_http  dst_port 80

    # 로컬 주소 여부
    acl is_src_local src_is_local
    acl is_dst_local dst_is_local

    # 소켓 ID (listen 여러 개일 때 구분)
    acl is_listener1 so_id 1
```

---

## 3. 레이어 5 (SSL/TLS) Fetch 메서드

```haproxy
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/

    # SSL 연결 여부
    acl is_ssl ssl_fc

    # SNI (Server Name Indication) - 클라이언트가 요청한 도메인
    acl is_api_domain    ssl_fc_sni api.example.com
    acl is_admin_domain  ssl_fc_sni admin.example.com
    acl sni_ends_example ssl_fc_sni -m end .example.com

    # SSL/TLS 프로토콜 버전
    acl uses_tls12 ssl_fc_protocol TLSv1.2
    acl uses_tls13 ssl_fc_protocol TLSv1.3

    # Cipher suite
    acl uses_aes ssl_fc_cipher ECDHE-RSA-AES256-GCM-SHA384

    # 클라이언트 인증서 사용 여부
    acl has_client_cert ssl_c_used

    # 클라이언트 인증서 검증 결과 (0=성공)
    acl cert_valid ssl_c_verify 0

    # 클라이언트 인증서 Subject DN
    acl is_admin_cert ssl_c_s_dn "CN=admin,O=Example Corp"
    acl has_cn        ssl_c_s_dn(cn) -m found

    # 클라이언트 인증서 Issuer DN
    acl from_internal_ca ssl_c_i_dn(o) "Internal CA"

    # 서버 인증서 CN
    acl srv_cn ssl_f_cn example.com

    # 서버 인증서 SAN (DNS)
    acl srv_san ssl_f_san_dns api.example.com
```

---

## 4. 레이어 7 (HTTP 요청) Fetch 메서드

### URL/경로 관련
```haproxy
frontend http_front
    mode http
    bind *:80

    # HTTP 메서드
    acl is_get    method GET
    acl is_post   method POST
    acl is_put    method PUT
    acl is_delete method DELETE
    acl is_options method OPTIONS
    acl is_safe   method GET HEAD    # 여러 값 OR

    # URL 전체 (경로 + 쿼리 문자열)
    acl is_api_url url_beg /api/
    acl has_query  url_sub ?

    # 경로만 (쿼리 문자열 제외)
    acl is_api    path_beg /api/
    acl is_health path_beg /health /status /ping   # 여러 경로 OR
    acl is_index  path     /                       # 정확히 일치
    acl is_js     path_end .js .jsx .ts            # 특정 확장자
    acl is_static path_reg \.(css|js|png|jpg|gif|ico|svg|woff2?)$

    # 쿼리 문자열
    acl has_debug_param query -m sub debug=true

    # Host 헤더
    acl is_api_host hdr(host) -i api.example.com
    acl is_www_host hdr_beg(host) -i www.
    acl is_sub_host hdr_end(host) -i .example.com

    # 호스트 + 경로 조합 (base = Host + Path)
    acl is_api_base base_beg api.example.com/api

    # HTTP 버전
    acl is_http11 req.ver 1.1
    acl is_http2  req.ver 2.0
```

### 헤더 관련
```haproxy
frontend http_front
    mode http

    # 헤더 값 확인
    acl is_json           hdr(Content-Type) -i -m sub application/json
    acl is_websocket      hdr(Upgrade) -i websocket
    acl has_auth          hdr(Authorization) -m found
    acl is_bearer         hdr_beg(Authorization) -i Bearer

    # 헤더 개수
    acl multi_host        hdr_cnt(host) gt 1   # Host 헤더 여러 개 (비정상)
    acl has_content_type  hdr_cnt(content-type) ge 1

    # 헤더 수치값
    acl large_content     hdr_val(Content-Length) gt 10000000  # 10MB 초과

    # User-Agent
    acl is_mobile         hdr(User-Agent) -i -m sub mobile android iphone
    acl is_bot            hdr(User-Agent) -i -m sub bot crawler spider
    acl is_curl           hdr(User-Agent) -i -m beg curl

    # Accept 헤더
    acl accepts_json      hdr(Accept) -i -m sub application/json
    acl accepts_html      hdr(Accept) -i -m sub text/html

    # Referer
    acl internal_referer  hdr(Referer) -i -m sub example.com

    # X-Forwarded-For
    acl from_cdn          hdr(X-Forwarded-For) -m found

    # Cookie
    acl has_session       cook(SESSIONID) -m found
    acl admin_cookie      cook(role) -m str admin

    # URL 파라미터
    acl debug_mode        urlp(debug) -m str 1
    acl has_user_param    urlp(user_id) -m found
```

### 요청 body 관련
```haproxy
frontend http_front
    mode http

    # body 크기
    acl has_body      req.body_len gt 0
    acl large_body    req.body_size gt 1048576   # 1MB 초과

    # body 내용 (option http-buffer-request 필요)
    acl body_has_sql  req.body -m sub -i "drop table" "union select"
```

---

## 5. 레이어 7 (HTTP 응답) Fetch 메서드

```haproxy
frontend http_front
    mode http

    # 응답 상태 코드 (http-response 규칙에서 사용)
    # acl is_ok        status 200
    # acl is_redirect  status 301 302 307 308
    # acl is_error     status 500 502 503 504

    # 응답 헤더
    # acl is_json_response  res.hdr(Content-Type) -i -m sub application/json
    # acl has_server_header res.hdr(Server) -m found

    # 응답 HTTP 버전
    # acl server_http11 res.ver 1.1

    # 응답 쿠키
    # acl srv_set_cookie scook(SESSID) -m found
```

---

## 6. 환경/통계 Fetch 메서드

```haproxy
frontend http_front
    mode http

    # 항상 참/거짓 (테스트용)
    acl always_match   always_true
    acl never_match    always_false

    # 환경 변수
    acl is_debug_env   env(APP_ENV) -m str development

    # 백엔드 가용 서버 수
    acl has_servers    nbsrv(web_backend) ge 1
    acl low_servers    nbsrv(web_backend) lt 2

    # 백엔드 큐 대기 수
    acl queue_full     queue(web_backend) gt 100
    acl avg_queue_high avg_queue(web_backend) gt 10

    # 연결 수
    acl be_overloaded  be_conn(web_backend) gt 1000
    acl fe_busy        fe_conn(http_front) gt 5000
```

---

## 7. 인증 관련 ACL

```haproxy
# userlist 정의
userlist admin_users
    user admin   password $6$rounds=100000$salt$hashedpassword
    user readonly password $6$rounds=100000$salt$hashedpassword
    group admins users admin
    group readers users readonly

frontend http_front
    mode http

    # HTTP Basic Auth 인증 여부
    acl is_authenticated http_auth(admin_users)

    # 특정 그룹 멤버 여부
    acl is_admin http_auth_group(admin_users) admins

    # 인증 필요
    http-request auth realm "Admin Area" if !is_authenticated { path_beg /admin }
    http-request deny if { path_beg /admin } !is_admin
```

---

## 8. 매칭 메서드 (Match Methods, -m 플래그)

| 매칭 방법 | 설명 | 예시 |
|---------|------|------|
| `-m str` | 정확히 일치 (기본) | `path -m str /api/` |
| `-m sub` | 포함 (부분 문자열) | `url -m sub debug` |
| `-m beg` | 시작 (`path_beg`과 동일) | `path -m beg /api` |
| `-m end` | 끝 (`path_end`과 동일) | `path -m end .php` |
| `-m dir` | 디렉토리 경로 매칭 | `path -m dir /api` |
| `-m dom` | 도메인 매칭 (`.`으로 구분) | `hdr(host) -m dom example.com` |
| `-m reg` | 정규식 매칭 (느림) | `path -m reg ^/api/v[0-9]+` |
| `-m int` | 정수 비교 | `hdr_val(Content-Length) -m int ge 1000` |
| `-m ip` | IP/네트워크 주소 매칭 | `src -m ip 192.168.0.0/16` |
| `-m len` | 길이 비교 | `url -m len gt 1024` |
| `-m found` | 존재 여부 (fetch 결과 있으면 참) | `hdr(Authorization) -m found` |
| `-m bool` | 참/거짓 (fetch 결과 자체) | `ssl_fc -m bool` |

### 단축형 fetch (내장 매칭 포함)
```haproxy
# 단축형 (매칭 포함)
acl is_api path_beg /api     # -m beg 포함
acl is_php path_end .php     # -m end 포함
acl is_static path_reg \.(jpg|png)$  # -m reg 포함

# 풀 표기형 (동일한 의미)
acl is_api path -m beg /api
acl is_php path -m end .php
acl is_static path -m reg \.(jpg|png)$
```

---

## 9. 플래그 (Flags)

### -i (대소문자 무시)
```haproxy
acl is_mobile hdr(User-Agent) -i -m sub "mobile"
# "Mobile", "MOBILE", "mobile" 모두 매칭
```

### -n (묵시적 매칭 비활성화)
```haproxy
# 일반적으로 값이 없으면 "found" 매칭으로 간주되는데, -n으로 비활성화
acl has_no_value hdr(X-Custom) -n -m str ""
```

### -f (파일에서 값 로드)
```haproxy
acl blacklist src -f /etc/haproxy/blacklist.txt
acl whitelist hdr(host) -i -f /etc/haproxy/allowed_hosts.txt
```

blacklist.txt 파일 형식:
```
# 주석
192.168.1.100
10.0.0.0/8
172.16.5.50
```

### -M (맵 파일 사용)
```haproxy
# 맵 파일은 "키 값" 형식
acl use_backend_a path -M -m str /api   # /api → backend_a 같은 맵 사용
```

### -u (고유 ID)
```haproxy
# 같은 이름의 ACL을 ID로 구분 (고급)
acl -u 1 is_api path_beg /api/v1
acl -u 2 is_api path_beg /api/v2
```

---

## 10. 숫자 비교 연산자

정수 비교가 필요한 fetch에서 사용합니다.

| 연산자 | 의미 | 예시 |
|--------|------|------|
| `eq` | 같음 (==) | `nbsrv(web) eq 0` |
| `ne` | 다름 (!=) | `status ne 200` |
| `lt` | 미만 (<) | `nbsrv(web) lt 2` |
| `le` | 이하 (<=) | `hdr_val(Content-Length) le 0` |
| `gt` | 초과 (>) | `fe_conn gt 1000` |
| `ge` | 이상 (>=) | `be_conn(api) ge 500` |

---

## 11. 변환 함수 (Converters)

Fetch 결과를 변환하여 비교합니다.

### 문자열 변환
```haproxy
# 소문자/대문자 변환
acl is_get_lower method,lower -m str get

# 길이 확인
acl long_url path,len gt 200

# 정규식 치환
# regsub(<패턴>,<치환>)  변환 후 값 사용
acl modified path,regsub(^/v[0-9]+,) -m beg /api

# 특정 필드 추출 (구분자, 인덱스)
acl first_dir path,field(/,2) -m str api  # /api/v1/users → api
```

### 해시/인코딩
```haproxy
# Base64 디코딩 후 비교
# Authorization: Basic <base64>
acl is_admin hdr(Authorization),lower,word(2),base64 -m str admin:password

# MD5 해시
# acl check_md5 ...
```

### 맵 파일 (Map)
```haproxy
# domains.map 파일: "도메인 backend이름" 형식
# api.example.com    api_backend
# www.example.com    web_backend
# admin.example.com  admin_backend

frontend http_front
    mode http
    bind *:80

    use_backend %[req.hdr(host),lower,map_dom(/etc/haproxy/domains.map,web_backend)]
```

map 파일 예시 (/etc/haproxy/domains.map):
```
api.example.com      api_backend
www.example.com      web_backend
admin.example.com    admin_backend
static.example.com   static_backend
```

### IP 마스킹
```haproxy
# /24 서브넷으로 그룹화
acl same_subnet src,ipmask(24) 192.168.1.0
```

### 테이블 조회
```haproxy
# stick-table에서 카운터 조회
acl too_many_reqs src,table_http_req_rate(web) gt 100
acl in_blacklist  src,in_table(blacklist_table)
```

---

## 12. ACL 조합 (논리 연산)

### AND (기본)
```haproxy
# 암묵적 AND: 여러 조건을 나열하면 AND
http-request deny if is_api !is_authenticated

# 명시적 AND (&&)
http-request deny if { is_api && !is_authenticated }
```

### OR
```haproxy
# OR: 하나의 acl 줄에 여러 값 = OR
acl is_static path_end .css .js .png .jpg .gif .ico .svg .woff .woff2 .ttf

# 또는 use_backend/http-request에서
http-request deny if is_bot || is_blacklisted

# ||를 사용한 명시적 OR
acl is_admin_or_api path_beg /admin || path_beg /api
```

### NOT
```haproxy
# !로 부정
acl !is_local src !127.0.0.1 !10.0.0.0/8   # 로컬이 아닌 경우
http-request deny if !is_whitelisted
```

### 괄호 그룹
```haproxy
# 복잡한 논리식
http-request deny if { src -f /etc/haproxy/blacklist.txt } || { method POST && path_beg /api && !is_authenticated }
```

---

## 13. 실전 ACL 예제 모음

### 13.1 경로 기반 라우팅 (마이크로서비스)
```haproxy
frontend api_gateway
    bind *:80
    mode http

    # 서비스별 경로 ACL
    acl is_auth_service   path_beg /auth/ /login /logout /refresh
    acl is_user_service   path_beg /users/ /profile/
    acl is_order_service  path_beg /orders/
    acl is_product_service path_beg /products/ /catalog/
    acl is_static         path_beg /static/ /assets/ /public/
    acl is_health         path /health /ready /live

    # 라우팅
    use_backend auth_backend     if is_auth_service
    use_backend user_backend     if is_user_service
    use_backend order_backend    if is_order_service
    use_backend product_backend  if is_product_service
    use_backend static_backend   if is_static
    use_backend monitoring_backend if is_health
    default_backend frontend_app
```

### 13.2 호스트 기반 가상 호스팅
```haproxy
frontend vhost_front
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/
    mode http

    acl is_api_host    hdr(host) -i api.example.com
    acl is_admin_host  hdr(host) -i admin.example.com
    acl is_www_host    hdr(host) -i www.example.com example.com
    acl is_static_host hdr(host) -i static.example.com cdn.example.com

    # HTTP → HTTPS 리다이렉트
    http-request redirect scheme https if !{ ssl_fc }

    use_backend api_backend    if is_api_host
    use_backend admin_backend  if is_admin_host
    use_backend static_backend if is_static_host
    default_backend www_backend
```

### 13.3 IP 기반 접근 제어
```haproxy
frontend secure_front
    bind *:80
    mode http

    # 내부 네트워크 정의
    acl is_internal    src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
    acl is_localhost   src 127.0.0.1 ::1
    acl is_office      src 203.0.113.0/24   # 사무실 IP 대역
    acl is_blacklisted src -f /etc/haproxy/blacklist.txt

    # 블랙리스트 즉시 차단 (TCP 레벨)
    tcp-request connection reject if is_blacklisted

    # 관리 경로는 내부 또는 사무실 IP만 허용
    http-request deny if { path_beg /admin /monitoring /metrics } !is_internal !is_office

    # 특정 경로는 내부 전용
    http-request deny if { path_beg /internal/ } !is_internal !is_localhost

    default_backend web_backend
```

### 13.4 User-Agent 기반 차단
```haproxy
frontend http_front
    bind *:80
    mode http

    # 악성 봇/스캐너 차단
    acl is_scanner   hdr(User-Agent) -i -m sub nikto nmap masscan sqlmap
    acl is_bad_bot   hdr(User-Agent) -i -m sub SemrushBot AhrefsBot MJ12bot DotBot
    acl empty_ua     hdr_cnt(User-Agent) eq 0

    http-request deny if is_scanner
    http-request deny if is_bad_bot
    # 빈 User-Agent는 선택적으로 차단 (일부 정상 요청도 포함될 수 있음)
    # http-request deny if empty_ua

    default_backend web_backend
```

### 13.5 요청 속도 제한 (Rate Limiting)
```haproxy
frontend web_front
    bind *:80
    mode http

    # stick-table 정의 (이 frontend에 연결)
    stick-table type ip size 100k expire 30s store http_req_rate(10s),conn_cur

    # 요청 추적
    http-request track-sc0 src

    # 10초에 100개 초과 요청 차단
    acl too_many_requests sc_http_req_rate(0) gt 100

    # 동시 연결 50개 초과 차단
    acl too_many_connections sc_conn_cur(0) gt 50

    http-request deny deny_status 429 if too_many_requests
    http-request deny deny_status 429 if too_many_connections

    default_backend web_backend
```

### 13.6 HTTP 메서드 제한
```haproxy
frontend api_front
    bind *:80
    mode http

    # 허용할 메서드 정의
    acl allowed_methods method GET HEAD POST PUT PATCH DELETE OPTIONS

    # 허용되지 않은 메서드 차단
    http-request deny if !allowed_methods

    # 특정 경로에서만 DELETE 허용
    acl is_delete method DELETE
    acl is_api_resource path_reg ^/api/v[0-9]+/(users|orders|products)/[0-9]+$
    http-request deny if is_delete !is_api_resource

    default_backend api_backend
```

### 13.7 요청 크기 제한
```haproxy
frontend upload_front
    bind *:80
    mode http

    # 요청 크기 제한
    acl large_request hdr_val(Content-Length) gt 104857600   # 100MB
    acl no_content_length hdr_cnt(Content-Length) eq 0

    # POST/PUT에 Content-Length 없는 경우 차단 (Chunked는 예외 처리 필요)
    # http-request deny if { method POST } no_content_length

    # 100MB 초과 요청 차단
    http-request deny if large_request

    # 업로드 API는 50MB 제한
    acl is_upload path_beg /api/upload/
    acl medium_request hdr_val(Content-Length) gt 52428800   # 50MB
    http-request deny if is_upload medium_request

    default_backend api_backend
```

### 13.8 시간대 기반 접근 제어
```haproxy
frontend time_based_front
    bind *:80
    mode http

    # HAProxy는 내장 시간 fetch가 없으므로
    # 환경 변수 또는 Lua 스크립트로 구현

    # Lua 기반 시간 체크
    # acl is_business_hours lua.is_business_hours

    # 대안: 외부 스크립트로 파일을 생성하고 파일 기반 ACL 사용
    acl is_maintenance_mode src -f /etc/haproxy/maintenance.txt

    http-request deny if is_maintenance_mode

    default_backend web_backend
```

### 13.9 HTTPS 강제 리다이렉트
```haproxy
frontend http_https
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/
    mode http

    acl is_https ssl_fc
    acl is_letsencrypt path_beg /.well-known/acme-challenge/

    # Let's Encrypt 체크는 HTTP로 허용
    http-request allow if is_letsencrypt

    # 나머지는 HTTPS로 리다이렉트
    http-request redirect scheme https code 301 if !is_https !is_letsencrypt

    default_backend web_backend
```

### 13.10 인증 기반 접근 제어
```haproxy
userlist api_users
    user developer password $6$...hashedpass...
    user admin password $6$...hashedpass...
    group developers users developer
    group admins users admin developer

frontend admin_front
    bind *:8080
    mode http

    acl is_authenticated http_auth(api_users)
    acl is_admin http_auth_group(api_users) admins

    # 인증 필요
    http-request auth realm "Management API" unless is_authenticated

    # 관리자 경로는 admin 그룹만
    acl is_admin_path path_beg /admin /manage
    http-request deny if is_admin_path !is_admin

    default_backend admin_backend
```

---

## 14. ACL 디버깅

```bash
# 설정 파일에 ACL 문법 오류 확인
haproxy -f /etc/haproxy/haproxy.cfg -c

# ACL 목록 확인 (Runtime API)
echo "show acl" | socat /run/haproxy/admin.sock stdio

# 특정 ACL 파일 내용 확인
echo "show acl /etc/haproxy/blacklist.txt" | socat /run/haproxy/admin.sock stdio

# ACL 파일에 동적으로 항목 추가/삭제
echo "add acl /etc/haproxy/blacklist.txt 1.2.3.4" | socat /run/haproxy/admin.sock stdio
echo "del acl /etc/haproxy/blacklist.txt 1.2.3.4" | socat /run/haproxy/admin.sock stdio
```

---

## 15. 성능 고려사항

| ACL 타입 | 성능 | 비고 |
|---------|------|------|
| `path_beg`, `path_end` | 매우 빠름 | 문자열 접두사/접미사 매칭 |
| `hdr()`, `src` | 빠름 | 해시 기반 |
| `-m str` (정확 일치) | 매우 빠름 | 직접 비교 |
| `-m sub` (포함) | 보통 | 선형 검색 |
| `-m reg` (정규식) | 느림 | 가능한 피할 것 |
| `-f` (파일) | 빠름 | 파일 크기에 따라 다름 |
| `url` (전체 URL) | `path`보다 느림 | 쿼리 문자열 포함 |

정규식 사용 시 주의사항:
- 복잡한 정규식은 CPU 사용량 증가
- 단순 패턴은 `path_beg`, `path_end`, `-m sub` 등으로 대체 가능
- 정규식이 필요한 경우 최대한 단순하게 작성
