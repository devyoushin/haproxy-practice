# HAProxy SSL/TLS 완전 가이드

HAProxy는 강력한 SSL/TLS 처리 기능을 제공합니다. 클라이언트와의 SSL 연결 처리부터
백엔드와의 재암호화, SNI 기반 다중 인증서까지 다양한 시나리오를 지원합니다.

---

## 1. SSL 운영 모드

### 1.1 SSL Termination (SSL 종단점) - 가장 일반적

클라이언트 ←SSL→ HAProxy ←HTTP→ Backend

```
클라이언트 --- TLS 암호화 --- HAProxy --- 평문 HTTP --- 백엔드 서버
```

- HAProxy가 SSL/TLS를 처리하고 백엔드에 HTTP로 전달
- 백엔드 서버는 SSL 처리 부하 없음
- 내부 네트워크가 신뢰할 수 있어야 함

```haproxy
frontend https_termination
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    bind *:80
    mode http

    http-request redirect scheme https code 301 if !{ ssl_fc }
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-request set-header X-Forwarded-Proto http if !{ ssl_fc }

    default_backend web_backend

backend web_backend
    mode http
    server web1 10.0.0.10:80 check   # HTTP로 전달
    server web2 10.0.0.11:80 check
```

### 1.2 SSL Pass-through (SSL 패스쓰루)

클라이언트 ←SSL→ HAProxy ←SSL→ Backend (TCP 모드)

```
클라이언트 --- TLS 암호화 --- HAProxy --- TLS 암호화 (그대로 전달) --- 백엔드 서버
```

- HAProxy는 SSL을 해독하지 않고 TCP 패킷을 그대로 전달
- HAProxy가 HTTP 레이어를 볼 수 없음 (HTTP 헤더 수정 불가)
- SNI를 이용한 라우팅만 가능

```haproxy
frontend ssl_passthrough
    bind *:443
    mode tcp

    # SNI 기반 TCP 라우팅
    acl is_api    req.ssl_sni -i api.example.com
    acl is_admin  req.ssl_sni -i admin.example.com

    use_backend api_ssl_backend   if is_api
    use_backend admin_ssl_backend if is_admin
    default_backend default_ssl_backend

backend api_ssl_backend
    mode tcp
    server api1 10.0.0.10:443 check send-proxy-v2

backend admin_ssl_backend
    mode tcp
    server admin1 10.0.0.20:443 check
```

### 1.3 SSL Re-encryption (SSL 재암호화)

클라이언트 ←SSL→ HAProxy ←SSL→ Backend

```
클라이언트 --- TLS 암호화 --- HAProxy --- TLS 암호화 (새로 생성) --- 백엔드 서버
```

- 클라이언트-HAProxy 간 SSL + HAProxy-백엔드 간 SSL
- 가장 보안이 높은 방식
- 모든 구간 암호화

```haproxy
frontend https_reencrypt
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    mode http
    default_backend secure_backend

backend secure_backend
    mode http
    server app1 10.0.0.10:443 ssl verify required ca-file /etc/ssl/certs/ca.pem
    server app2 10.0.0.11:443 ssl verify required ca-file /etc/ssl/certs/ca.pem
```

---

## 2. bind SSL 파라미터 전체

```haproxy
frontend https
    bind *:443 ssl \
        crt /etc/haproxy/certs/server.pem \        # 인증서+키 파일
        ca-file /etc/ssl/certs/ca-bundle.crt \     # CA 인증서 (클라이언트 검증용)
        verify optional \                           # 클라이언트 인증서 검증 (none/optional/required)
        crl-file /etc/haproxy/crl.pem \            # 인증서 폐기 목록
        ssl-min-ver TLSv1.2 \                      # 최소 TLS 버전
        ssl-max-ver TLSv1.3 \                      # 최대 TLS 버전
        ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384 \
        ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256 \
        alpn h2,http/1.1 \                         # ALPN (HTTP/2 지원)
        ecdh-curves P-256:P-384 \                  # ECDH 곡선
        prefer-client-ciphers \                    # 클라이언트 cipher 우선 (기본: 서버 우선)
        npn                                        # NPN (구형 HTTP/2 협상)
```

### bind SSL 파라미터 요약 표

| 파라미터 | 설명 | 기본값 |
|---------|------|--------|
| `ssl` | SSL 활성화 | - |
| `crt <file>` | 인증서+키 PEM 파일 | - |
| `crt-list <file>` | 인증서 목록 파일 | - |
| `ca-file <file>` | CA 인증서 파일 | - |
| `verify none` | 클라이언트 인증서 검증 안 함 | none |
| `verify optional` | 클라이언트 인증서 선택적 검증 | - |
| `verify required` | 클라이언트 인증서 필수 검증 | - |
| `crl-file <file>` | 인증서 폐기 목록 | - |
| `ssl-min-ver <ver>` | 최소 TLS 버전 | TLSv1.0 |
| `ssl-max-ver <ver>` | 최대 TLS 버전 | TLSv1.3 |
| `no-sslv3` | SSLv3 비활성화 | - |
| `no-tlsv10` | TLSv1.0 비활성화 | - |
| `no-tlsv11` | TLSv1.1 비활성화 | - |
| `no-tlsv12` | TLSv1.2 비활성화 | - |
| `ciphers <list>` | TLS 1.2 cipher suite | OS 기본값 |
| `ciphersuites <list>` | TLS 1.3 cipher suite | OS 기본값 |
| `alpn <protos>` | ALPN 프로토콜 목록 | - |
| `ecdh-curves <curves>` | ECDH 곡선 목록 | - |
| `dhparam <file>` | DH 파라미터 파일 | - |
| `prefer-client-ciphers` | 클라이언트 cipher 우선 | 서버 우선 |
| `strict-sni` | SNI 없는 연결 거부 | - |
| `allow-0rtt` | TLS 1.3 0-RTT 허용 | 비활성 |

---

## 3. 인증서 파일 구조 (PEM 형식)

HAProxy는 하나의 PEM 파일에 인증서, 개인키, 중간 인증서를 모두 포함할 수 있습니다.

```
/etc/haproxy/certs/server.pem 파일 구조:

-----BEGIN CERTIFICATE-----
... (서버 인증서) ...
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
... (중간 인증서 1) ...
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
... (중간 인증서 2 - 루트에 가까울수록 나중) ...
-----END CERTIFICATE-----
-----BEGIN RSA PRIVATE KEY-----
... (개인키) ...
-----END RSA PRIVATE KEY-----
```

### PEM 파일 생성
```bash
# Let's Encrypt 인증서를 HAProxy 형식으로 변환
cat /etc/letsencrypt/live/example.com/fullchain.pem \
    /etc/letsencrypt/live/example.com/privkey.pem \
    > /etc/haproxy/certs/example.com.pem

# 권한 설정 (HAProxy는 haproxy 사용자로 실행)
chmod 600 /etc/haproxy/certs/example.com.pem
chown haproxy:haproxy /etc/haproxy/certs/example.com.pem
```

---

## 4. SNI 기반 다중 인증서

### 4.1 디렉토리 방식 (권장)
```haproxy
frontend https_multi_cert
    # /etc/haproxy/certs/ 디렉토리에 있는 모든 .pem 파일을 로드
    # SNI에 맞는 인증서 자동 선택
    bind *:443 ssl crt /etc/haproxy/certs/

    # 인증서 파일 명명 규칙:
    # /etc/haproxy/certs/example.com.pem
    # /etc/haproxy/certs/api.example.com.pem
    # /etc/haproxy/certs/admin.example.com.pem
```

### 4.2 crt-list 방식 (세밀한 제어)
```haproxy
frontend https_crt_list
    bind *:443 ssl crt-list /etc/haproxy/crt-list.txt

    default_backend web_backend
```

crt-list.txt 파일 형식:
```
# 인증서파일 [SNI 패턴] [SSL 옵션들]
/etc/haproxy/certs/example.com.pem example.com www.example.com
/etc/haproxy/certs/api.example.com.pem api.example.com
/etc/haproxy/certs/wildcard.pem *.example.com

# 특정 도메인에 다른 TLS 설정
/etc/haproxy/certs/legacy.pem legacy.example.com ssl-min-ver TLSv1.0 ciphers HIGH:!aNULL:!MD5
```

### 4.3 SNI 기반 라우팅
```haproxy
frontend https_sni_routing
    bind *:443 ssl crt /etc/haproxy/certs/

    mode http

    # SNI 기반 backend 선택
    acl is_api    ssl_fc_sni api.example.com
    acl is_admin  ssl_fc_sni admin.example.com
    acl is_static ssl_fc_sni static.example.com

    use_backend api_backend    if is_api
    use_backend admin_backend  if is_admin
    use_backend static_backend if is_static
    default_backend web_backend
```

---

## 5. Let's Encrypt 연동

### 5.1 Certbot으로 인증서 발급
```bash
# 독립 모드 (HAProxy 일시 중지 필요)
certbot certonly --standalone -d example.com -d www.example.com

# 또는 webroot 모드 (HAProxy 계속 운영)
certbot certonly --webroot -w /var/www/letsencrypt -d example.com
```

### 5.2 HAProxy에서 ACME 챌린지 허용 설정
```haproxy
frontend http_front
    bind *:80
    mode http

    # Let's Encrypt 챌린지 경로는 HTTP로 허용 (80 포트)
    acl is_letsencrypt path_beg /.well-known/acme-challenge/
    use_backend letsencrypt_backend if is_letsencrypt
    http-request redirect scheme https code 301 if !is_letsencrypt

backend letsencrypt_backend
    mode http
    server certbot 127.0.0.1:8888 check
```

### 5.3 자동 갱신 스크립트
```bash
#!/bin/bash
# /etc/cron.d/haproxy-ssl-renew
# 매일 2번 실행

DOMAIN="example.com"
CERT_DIR="/etc/haproxy/certs"
LE_DIR="/etc/letsencrypt/live/${DOMAIN}"

# 인증서 갱신 시도
certbot renew --quiet

# HAProxy PEM 파일 업데이트
if [ -f "${LE_DIR}/fullchain.pem" ]; then
    cat "${LE_DIR}/fullchain.pem" "${LE_DIR}/privkey.pem" \
        > "${CERT_DIR}/${DOMAIN}.pem"
    chmod 600 "${CERT_DIR}/${DOMAIN}.pem"
    chown haproxy:haproxy "${CERT_DIR}/${DOMAIN}.pem"

    # HAProxy 무중단 리로드
    systemctl reload haproxy

    echo "Certificate updated and HAProxy reloaded for ${DOMAIN}"
fi
```

Crontab 설정:
```bash
# /etc/cron.d/haproxy-ssl-renew
0 2,14 * * * root /usr/local/bin/haproxy-ssl-renew.sh >> /var/log/ssl-renew.log 2>&1
```

---

## 6. OCSP Stapling

OCSP Stapling은 인증서 폐기 정보를 HAProxy가 미리 가져와 클라이언트에 제공합니다.
클라이언트가 직접 OCSP 서버에 연결할 필요 없이 핸드셰이크 시간이 단축됩니다.

### 설정
```haproxy
global
    # OCSP 응답 업데이트 간격 (초)
    ssl-default-bind-options ssl-min-ver TLSv1.2
    tune.ssl.ocsp-update.maxdelay 3600    # 최대 1시간마다 갱신

frontend https
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    # .ocsp 파일이 있으면 자동으로 OCSP Stapling 활성화
    # /etc/haproxy/certs/server.pem.ocsp
```

### OCSP 응답 파일 생성
```bash
# OCSP 응답 URL 확인
openssl x509 -in /etc/haproxy/certs/server.pem -noout -ocsp_uri

# OCSP 응답 가져오기
OCSP_URL=$(openssl x509 -in /etc/haproxy/certs/server.pem -noout -ocsp_uri)
openssl ocsp \
    -no_nonce \
    -issuer /etc/haproxy/certs/intermediate.pem \
    -cert /etc/haproxy/certs/server.pem \
    -url "$OCSP_URL" \
    -respout /etc/haproxy/certs/server.pem.ocsp

# HAProxy 리로드
systemctl reload haproxy
```

### 자동 OCSP 갱신 스크립트
```bash
#!/bin/bash
# /etc/cron.hourly/haproxy-ocsp-update

CERT="/etc/haproxy/certs/server.pem"
INTERMEDIATE="/etc/haproxy/certs/intermediate.pem"
OCSP_FILE="${CERT}.ocsp"

OCSP_URL=$(openssl x509 -in "$CERT" -noout -ocsp_uri 2>/dev/null)

if [ -n "$OCSP_URL" ]; then
    openssl ocsp \
        -no_nonce \
        -issuer "$INTERMEDIATE" \
        -cert "$CERT" \
        -url "$OCSP_URL" \
        -respout "$OCSP_FILE" \
        -timeout 10 2>/dev/null

    if [ $? -eq 0 ]; then
        # HAProxy에 OCSP 파일 리로드 신호
        echo "set ssl ocsp-response $(base64 -w 0 $OCSP_FILE)" | \
            socat /run/haproxy/admin.sock stdio
    fi
fi
```

---

## 7. mTLS (상호 TLS 인증)

클라이언트도 인증서를 제시하여 서로를 인증합니다.

### 서버 설정
```haproxy
frontend mtls_frontend
    bind *:8443 ssl \
        crt /etc/haproxy/certs/server.pem \
        ca-file /etc/haproxy/certs/client-ca.pem \
        verify required \          # 클라이언트 인증서 필수
        crl-file /etc/haproxy/certs/client-crl.pem   # 폐기 목록

    mode http

    # 인증서 검증 실패 시 차단
    acl cert_ok ssl_c_verify 0
    http-request deny if !cert_ok

    # 클라이언트 인증서 정보를 헤더로 전달
    http-request set-header X-SSL-Client-Verify %[ssl_c_verify]
    http-request set-header X-SSL-Client-DN     %{+Q}[ssl_c_s_dn]
    http-request set-header X-SSL-Client-CN     %[ssl_c_s_dn(cn)]
    http-request set-header X-SSL-Issuer-DN     %{+Q}[ssl_c_i_dn]
    http-request set-header X-SSL-Client-Serial %[ssl_c_serial,hex]
    http-request set-header X-SSL-Not-Before    %[ssl_c_notbefore]
    http-request set-header X-SSL-Not-After     %[ssl_c_notafter]

    # 특정 CN만 허용
    acl is_allowed_client ssl_c_s_dn(cn) -f /etc/haproxy/allowed_clients.txt
    http-request deny if !is_allowed_client

    default_backend secure_api_backend
```

### 클라이언트 인증서 생성 (테스트용)
```bash
# CA 키 및 인증서 생성
openssl genrsa -out client-ca.key 4096
openssl req -new -x509 -days 3650 -key client-ca.key \
    -out client-ca.pem \
    -subj "/C=KR/O=My Company/CN=Client CA"

# 클라이언트 인증서 생성
openssl genrsa -out client.key 2048
openssl req -new -key client.key \
    -out client.csr \
    -subj "/C=KR/O=My Company/CN=myapp-client"
openssl x509 -req -days 365 \
    -CA client-ca.pem -CAkey client-ca.key -CAcreateserial \
    -in client.csr -out client.pem
```

---

## 8. TLS 세션 재사용

### SSL 세션 캐시
```haproxy
global
    # SSL 세션 캐시 크기 (각 세션 약 200바이트)
    tune.ssl.cachesize 20000    # 20000개 세션 (기본값)
    tune.ssl.lifetime 300       # 세션 유효 시간 (초, 기본값 300)
```

### TLS 세션 티켓 (TLS 1.2)
```haproxy
global
    # TLS 세션 티켓 키 파일 (여러 HAProxy 인스턴스 간 공유 가능)
    # openssl rand 80 > /etc/haproxy/ssl-ticket.key
    ssl-default-bind-options ticket-key /etc/haproxy/ssl-ticket.key
```

여러 HAProxy 인스턴스에서 세션 재사용:
```bash
# 세션 티켓 키 생성 (80바이트: 16 이름 + 32 암호화 + 32 HMAC)
openssl rand 80 > /etc/haproxy/ssl-ticket.key
chmod 600 /etc/haproxy/ssl-ticket.key

# 모든 HAProxy 인스턴스에 같은 키 배포
scp /etc/haproxy/ssl-ticket.key haproxy2:/etc/haproxy/
scp /etc/haproxy/ssl-ticket.key haproxy3:/etc/haproxy/

# 주기적 키 교체 (보안을 위해 24시간마다)
# 키 교체 시 기존 키로 암호화된 세션이 만료될 때까지 유지
```

---

## 9. 보안 권장 설정

### Mozilla Intermediate 설정 (대부분의 환경에 적합)
```haproxy
global
    # Mozilla Intermediate 권장 cipher suite
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

    ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-server-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-server-options ssl-min-ver TLSv1.2 no-tls-tickets
```

### Mozilla Modern 설정 (최신 클라이언트만 지원)
```haproxy
global
    # TLS 1.3만 사용
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.3 no-tls-tickets
```

### HSTS 설정
```haproxy
frontend https
    bind *:443 ssl crt /etc/haproxy/certs/server.pem ssl-min-ver TLSv1.2

    # HSTS: 브라우저가 1년간 HTTPS만 사용
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
```

---

## 10. SSL 성능 튜닝

```haproxy
global
    # SSL 세션 캐시 (성능 향상)
    tune.ssl.cachesize 20000

    # SSL 핸드셰이크 백로그 (고트래픽 시)
    tune.ssl.maxrecord 1460      # 네트워크 MTU에 맞게 조정

    # 비동기 SSL 처리 (멀티코어 최적화)
    ssl-engine rdrand            # Intel RDRAND 엔진 (있는 경우)
    ssl-mode-async               # 비동기 SSL 처리
```

---

## 11. SSL 디버깅 및 검증

```bash
# SSL 설정 검증
haproxy -f /etc/haproxy/haproxy.cfg -c

# SSL 연결 테스트
openssl s_client -connect example.com:443 -servername example.com

# TLS 버전 확인
openssl s_client -connect example.com:443 -tls1_2  # TLS 1.2
openssl s_client -connect example.com:443 -tls1_3  # TLS 1.3

# 인증서 정보 확인
openssl s_client -connect example.com:443 -servername example.com 2>/dev/null | \
    openssl x509 -text -noout

# Cipher suite 확인
openssl s_client -connect example.com:443 2>/dev/null | grep "Cipher is"

# 보안 등급 확인 (SSL Labs API)
curl "https://api.ssllabs.com/api/v3/analyze?host=example.com&publish=off&fromCache=on"

# HAProxy에서 SSL 통계 확인
echo "show info" | socat /run/haproxy/admin.sock stdio | grep -i ssl

# 현재 SSL 세션 캐시 사용량
echo "show info" | socat /run/haproxy/admin.sock stdio | grep SslCacheLookups
```

---

## 12. 완전한 HTTPS 설정 예시

```haproxy
#---------------------------------------------------------------------
# 프로덕션 HTTPS 로드밸런서 설정
#---------------------------------------------------------------------
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    maxconn 50000
    nbthread 4
    user haproxy
    group haproxy
    daemon

    # SSL 글로벌 설정 (Mozilla Intermediate)
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets
    tune.ssl.cachesize 20000

defaults
    log    global
    mode   http
    option httplog
    option dontlognull
    option forwardfor
    option http-server-close
    timeout connect 5s
    timeout client  30s
    timeout server  30s

#---------------------------------------------------------------------
# HTTP → HTTPS 리다이렉트 + Let's Encrypt
#---------------------------------------------------------------------
frontend http_front
    bind *:80
    mode http

    acl is_letsencrypt path_beg /.well-known/acme-challenge/
    use_backend letsencrypt if is_letsencrypt
    http-request redirect scheme https code 301 if !is_letsencrypt

#---------------------------------------------------------------------
# HTTPS 메인 프론트엔드 (다중 도메인)
#---------------------------------------------------------------------
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1

    # 보안 헤더
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    http-response set-header X-Frame-Options SAMEORIGIN
    http-response set-header X-Content-Type-Options nosniff
    http-response set-header Referrer-Policy strict-origin-when-cross-origin

    # 불필요한 헤더 제거
    http-response del-header Server
    http-response del-header X-Powered-By

    # X-Forwarded-* 헤더 설정
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Real-IP %[src]

    # 도메인별 라우팅
    acl is_api    hdr(host) -i api.example.com
    acl is_admin  hdr(host) -i admin.example.com

    use_backend api_backend   if is_api
    use_backend admin_backend if is_admin
    default_backend web_backend

#---------------------------------------------------------------------
# 백엔드
#---------------------------------------------------------------------
backend web_backend
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 slowstart 30s
    server web1 10.0.0.10:80 check
    server web2 10.0.0.11:80 check
    server web3 10.0.0.12:80 check

backend api_backend
    balance leastconn
    option httpchk GET /api/health
    http-check expect status 200
    default-server inter 3s fall 3 rise 2
    server api1 10.0.1.10:8080 check
    server api2 10.0.1.11:8080 check

backend admin_backend
    balance roundrobin
    option httpchk GET /admin/health
    http-check expect status 200
    # 관리 백엔드는 내부 IP만 허용
    http-request deny if !{ src 10.0.0.0/8 }
    server admin1 10.0.2.10:8080 check

backend letsencrypt
    server certbot 127.0.0.1:8888
```
