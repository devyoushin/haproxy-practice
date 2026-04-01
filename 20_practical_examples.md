# HAProxy 실전 예제 모음

실제 운영 환경에서 자주 사용되는 HAProxy 설정 예제를 모았습니다.

---

## 예제 1: 기본 HTTP 로드밸런서

가장 기본적인 형태의 HTTP 로드밸런서입니다.

```
global
    log 127.0.0.1 local0 info
    maxconn 50000
    user haproxy
    group haproxy
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin

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

frontend http_in
    bind *:80
    default_backend web_servers

backend web_servers
    balance roundrobin
    option httpchk GET /health HTTP/1.1\r\nHost:\ example.com
    http-check expect status 200
    server web1 192.168.1.10:8080 check inter 3s fall 3 rise 2
    server web2 192.168.1.11:8080 check inter 3s fall 3 rise 2
    server web3 192.168.1.12:8080 check inter 3s fall 3 rise 2
```

---

## 예제 2: HTTPS 종단점 + HTTP → HTTPS 리다이렉트

```
global
    log 127.0.0.1 local0 info
    maxconn 50000
    user haproxy
    group haproxy
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin

    # SSL 기본 설정
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options prefer-client-ciphers no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets
    ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-server-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

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
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# HTTP → HTTPS 리다이렉트
frontend http_in
    bind *:80
    # Let's Encrypt ACME 챌린지는 리다이렉트 제외
    acl is_acme path_beg /.well-known/acme-challenge/
    use_backend letsencrypt_backend if is_acme
    http-request redirect scheme https code 301 if !is_acme

# HTTPS 프론트엔드
frontend https_in
    bind *:443 ssl crt /etc/haproxy/certs/example.pem alpn h2,http/1.1

    # HSTS
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"

    # 보안 헤더
    http-response set-header X-Frame-Options "SAMEORIGIN"
    http-response set-header X-Content-Type-Options "nosniff"
    http-response del-header Server

    default_backend web_servers

backend letsencrypt_backend
    server letsencrypt 127.0.0.1:8888

backend web_servers
    balance leastconn
    option httpchk GET /health
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 slowstart 30s
    server web1 192.168.1.10:8080 check
    server web2 192.168.1.11:8080 check
    server web3 192.168.1.12:8080 check
```

### 인증서 파일 준비 (Let's Encrypt)
```bash
# Certbot으로 인증서 발급
certbot certonly --standalone -d example.com -d www.example.com

# HAProxy용 PEM 파일 생성 (cert + privkey 합치기)
cat /etc/letsencrypt/live/example.com/fullchain.pem \
    /etc/letsencrypt/live/example.com/privkey.pem \
    > /etc/haproxy/certs/example.pem

chmod 600 /etc/haproxy/certs/example.pem

# 자동 갱신 후 PEM 생성 (cron 또는 systemd timer)
# /etc/letsencrypt/renewal-hooks/deploy/haproxy.sh
#!/bin/bash
DOMAIN="example.com"
cat /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
    /etc/letsencrypt/live/$DOMAIN/privkey.pem \
    > /etc/haproxy/certs/$DOMAIN.pem
systemctl reload haproxy
```

---

## 예제 3: 마이크로서비스 API 게이트웨이 (경로 기반 라우팅)

여러 마이크로서비스를 단일 진입점으로 라우팅합니다.

```
frontend api_gateway
    bind *:443 ssl crt /etc/haproxy/certs/api.example.com.pem alpn h2,http/1.1

    # 경로 기반 ACL 정의
    acl is_auth       path_beg /auth/
    acl is_users      path_beg /users/
    acl is_orders     path_beg /orders/
    acl is_products   path_beg /products/
    acl is_payments   path_beg /payments/
    acl is_websocket  hdr(Upgrade) -i WebSocket

    # 내부망만 허용할 관리 경로
    acl is_admin      path_beg /admin/
    acl is_internal   src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

    # 관리 경로 접근 제한
    http-request deny if is_admin !is_internal

    # API 키 헤더 검증 (없으면 인증 서비스로)
    acl has_api_key   req.hdr(X-API-Key) -m found

    # 라우팅
    use_backend auth_service      if is_auth
    use_backend users_service     if is_users
    use_backend orders_service    if is_orders
    use_backend products_service  if is_products
    use_backend payments_service  if is_payments
    use_backend ws_service        if is_websocket
    default_backend frontend_app

backend auth_service
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    http-request set-header X-Forwarded-For %[src]
    http-request set-header X-Forwarded-Proto https
    default-server inter 5s fall 3 rise 2
    server auth1 10.0.1.10:3000 check
    server auth2 10.0.1.11:3000 check

backend users_service
    balance leastconn
    option httpchk GET /health
    http-request set-header X-Forwarded-For %[src]
    http-request set-header X-Forwarded-Proto https
    default-server inter 5s fall 3 rise 2
    server users1 10.0.2.10:3001 check
    server users2 10.0.2.11:3001 check
    server users3 10.0.2.12:3001 check

backend orders_service
    balance leastconn
    option httpchk GET /health
    http-request set-header X-Forwarded-For %[src]
    default-server inter 5s fall 3 rise 2
    server orders1 10.0.3.10:3002 check
    server orders2 10.0.3.11:3002 check

backend products_service
    balance roundrobin
    option httpchk GET /health
    http-request set-header X-Forwarded-For %[src]
    default-server inter 5s fall 3 rise 2
    server products1 10.0.4.10:3003 check
    server products2 10.0.4.11:3003 check
    server products3 10.0.4.12:3003 check

backend payments_service
    # 결제 서비스: 엄격한 타임아웃
    balance roundrobin
    option httpchk GET /health
    timeout server 60s
    default-server inter 5s fall 3 rise 2 maxconn 50
    server payments1 10.0.5.10:3004 check
    server payments2 10.0.5.11:3004 check

backend ws_service
    # WebSocket: tunnel 타임아웃 필요
    balance source
    timeout tunnel 3600s
    option http-server-close
    server ws1 10.0.6.10:3005 check
    server ws2 10.0.6.11:3005 check

backend frontend_app
    balance roundrobin
    option httpchk GET /
    default-server inter 5s fall 3 rise 2
    server frontend1 10.0.7.10:3006 check
    server frontend2 10.0.7.11:3006 check
```

---

## 예제 4: WebSocket 프록시

WebSocket은 HTTP 업그레이드 요청을 통해 연결되며, 장시간 연결을 유지합니다.

```
defaults
    mode    http
    timeout connect  5s
    timeout client   30s
    timeout server   30s

frontend ws_frontend
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/example.pem

    # WebSocket 업그레이드 요청 감지
    acl is_websocket hdr(Upgrade) -i WebSocket
    acl is_websocket hdr_beg(Host) -i ws.

    use_backend ws_backend if is_websocket
    default_backend web_backend

backend ws_backend
    mode http
    balance source              # 같은 클라이언트는 같은 서버로

    # WebSocket 핵심 설정
    timeout tunnel  3600s       # 1시간 (연결 지속 시간)
    timeout connect 5s
    timeout server  30s

    option http-server-close    # 서버 측 연결 관리
    option forwardfor

    # WebSocket 관련 헤더 전달
    http-request set-header X-Forwarded-For %[src]
    http-request set-header X-Forwarded-Proto http if !{ ssl_fc }
    http-request set-header X-Forwarded-Proto https if { ssl_fc }

    server ws1 10.0.0.1:8080 check
    server ws2 10.0.0.2:8080 check

backend web_backend
    balance roundrobin
    option httpchk GET /health
    server web1 10.0.0.1:3000 check
    server web2 10.0.0.2:3000 check
```

---

## 예제 5: MySQL/MariaDB 로드밸런서 (TCP 모드)

```
defaults
    mode    tcp
    timeout connect  5s
    timeout client   1h     # MySQL 쿼리 실행 시간 고려
    timeout server   1h
    option  tcplog

frontend mysql_frontend
    bind *:3306
    default_backend mysql_backend

backend mysql_backend
    mode tcp
    balance leastconn       # 가장 적은 연결 서버로

    # MySQL 핸드셰이크 확인
    option tcp-check
    tcp-check connect
    tcp-check expect binary 5a  # MySQL 초기 패킷 시작 바이트

    # 또는 MySQL 모니터 사용자로 체크
    # option mysql-check user haproxy_check

    server mysql_master 10.0.1.10:3306 check inter 3s fall 3 rise 2
    server mysql_slave1 10.0.1.11:3306 check inter 3s fall 3 rise 2 backup
    server mysql_slave2 10.0.1.12:3306 check inter 3s fall 3 rise 2 backup
```

### MySQL 헬스체크 사용자 설정
```sql
-- MySQL에서 HAProxy 헬스체크 전용 사용자 생성
CREATE USER 'haproxy_check'@'%' IDENTIFIED BY '';
-- 비밀번호 없는 사용자 (HAProxy mysql-check 기본)
-- 또는
CREATE USER 'haproxy_check'@'10.0.0.%';
FLUSH PRIVILEGES;
```

---

## 예제 6: Redis 클러스터 프록시

```
defaults
    mode    tcp
    timeout connect  3s
    timeout client   30s
    timeout server   30s

frontend redis_frontend
    bind *:6379
    default_backend redis_backend

backend redis_backend
    mode tcp
    balance first           # 첫 번째 서버(마스터)를 우선

    # Redis PING/PONG 헬스체크
    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    server redis_master 10.0.2.10:6379 check inter 3s fall 3 rise 2
    server redis_replica1 10.0.2.11:6379 check inter 3s fall 3 rise 2 backup
    server redis_replica2 10.0.2.12:6379 check inter 3s fall 3 rise 2 backup
```

### Redis Sentinel 연동
Sentinel을 통해 마스터 자동 전환 시 HAProxy Runtime API로 서버 상태를 동적으로 변경합니다.

```bash
#!/bin/bash
# redis-sentinel-monitor.sh
# Sentinel에서 failover 감지 시 실행

SOCKET=/run/haproxy/admin.sock
NEW_MASTER=$1
NEW_MASTER_PORT=$2

echo "set server redis_backend/redis_master addr $NEW_MASTER port $NEW_MASTER_PORT" \
    | socat $SOCKET stdio

echo "set server redis_backend/redis_master state ready" \
    | socat $SOCKET stdio
```

---

## 예제 7: gRPC 로드밸런서

gRPC는 HTTP/2 기반이므로 ALPN 설정이 필요합니다.

```
global
    ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11

frontend grpc_frontend
    bind *:443 ssl crt /etc/haproxy/certs/api.pem alpn h2

    # gRPC 서비스별 라우팅
    acl is_user_svc   path_beg /userservice.UserService/
    acl is_order_svc  path_beg /orderservice.OrderService/

    use_backend grpc_users  if is_user_svc
    use_backend grpc_orders if is_order_svc
    default_backend grpc_default

backend grpc_users
    balance leastconn
    option httpchk
    # gRPC 헬스체크 프로토콜
    http-check send meth POST uri /grpc.health.v1.Health/Check \
        hdr content-type application/grpc \
        body "\x00\x00\x00\x00\x00"
    http-check expect status 200

    server grpc_user1 10.0.1.10:50051 check ssl verify none alpn h2
    server grpc_user2 10.0.1.11:50051 check ssl verify none alpn h2

backend grpc_orders
    balance leastconn
    option httpchk
    http-check send meth POST uri /grpc.health.v1.Health/Check \
        hdr content-type application/grpc \
        body "\x00\x00\x00\x00\x00"
    http-check expect status 200

    server grpc_order1 10.0.2.10:50051 check ssl verify none alpn h2
    server grpc_order2 10.0.2.11:50051 check ssl verify none alpn h2

backend grpc_default
    server grpc1 10.0.3.10:50051 check ssl verify none alpn h2
```

---

## 예제 8: 블루-그린 배포

두 개의 환경(Blue/Green)을 번갈아 배포하는 방식. Runtime API로 트래픽 전환.

```
backend blue_servers
    balance roundrobin
    option httpchk GET /health
    server blue1 10.0.1.10:8080 check
    server blue2 10.0.1.11:8080 check

backend green_servers
    balance roundrobin
    option httpchk GET /health
    server green1 10.0.2.10:8080 check
    server green2 10.0.2.11:8080 check

# 맵 파일로 트래픽 라우팅 제어
# /etc/haproxy/active_env.map
# default green_servers

frontend web
    bind *:80
    default_backend green_servers
    # use_backend blue_servers  ← 이 줄을 주석 처리/해제로 전환
```

### Runtime API로 블루-그린 전환
```bash
#!/bin/bash
# blue-green-switch.sh

SOCKET=/run/haproxy/admin.sock
TARGET=${1:-green}  # blue 또는 green

if [ "$TARGET" = "green" ]; then
    DISABLE="blue"
    ENABLE="green"
else
    DISABLE="green"
    ENABLE="blue"
fi

echo "트래픽을 ${ENABLE}으로 전환합니다..."

# 새 환경 서버 활성화 (DRAIN → READY)
for srv in 1 2; do
    echo "set server ${ENABLE}_servers/${ENABLE}${srv} state ready" | socat $SOCKET stdio
done

# 잠시 대기 (헬스체크 통과 대기)
sleep 10

# 기존 환경 서버 드레인
for srv in 1 2; do
    echo "set server ${DISABLE}_servers/${DISABLE}${srv} state drain" | socat $SOCKET stdio
done

echo "전환 완료: ${ENABLE} 환경이 활성화되었습니다."

# 기존 연결이 끝날 때까지 대기 후 완전 비활성화
sleep 30
for srv in 1 2; do
    echo "set server ${DISABLE}_servers/${DISABLE}${srv} state maint" | socat $SOCKET stdio
done
```

---

## 예제 9: 카나리 배포 (Canary Deployment)

새 버전에 소량의 트래픽만 먼저 보내 테스트하는 방식.

```
backend production_v1
    balance roundrobin
    option httpchk GET /health
    server v1_1 10.0.1.10:8080 check weight 90
    server v1_2 10.0.1.11:8080 check weight 90
    server v1_3 10.0.1.12:8080 check weight 90

backend production_v2_canary
    balance roundrobin
    option httpchk GET /health
    server v2_1 10.0.2.10:8080 check weight 10

# 방법 1: weight 조합으로 비율 조정 (단일 backend)
backend mixed_backend
    balance roundrobin
    option httpchk GET /health
    server v1_1 10.0.1.10:8080 check weight 90
    server v1_2 10.0.1.11:8080 check weight 90
    server v2_1 10.0.2.10:8080 check weight 20  # 약 10% 트래픽
```

### Runtime API로 카나리 비율 조정
```bash
#!/bin/bash
# canary-ramp.sh - 카나리 비율을 점진적으로 늘리기

SOCKET=/run/haproxy/admin.sock

for percent in 10 20 30 50 70 100; do
    v1_weight=$((100 - percent))
    echo "카나리 비율 ${percent}% 적용..."

    echo "set weight mixed_backend/v1_1 ${v1_weight}" | socat $SOCKET stdio
    echo "set weight mixed_backend/v1_2 ${v1_weight}" | socat $SOCKET stdio
    echo "set weight mixed_backend/v2_1 ${percent}" | socat $SOCKET stdio

    echo "현재 서버 가중치:"
    echo "show servers state mixed_backend" | socat $SOCKET stdio

    # 각 단계별 대기 (에러율 모니터링 시간)
    sleep 300  # 5분
done

echo "카나리 배포 완료: v2로 100% 전환"
```

---

## 예제 10: 요청 미러링 (Traffic Mirroring)

운영 트래픽을 테스트 환경에도 복제하여 새 버전 검증에 활용.

```
# HAProxy 자체적으로는 미러링 기능이 없지만
# Lua 스크립트 또는 외부 툴(tc, iptables mirror)과 조합 가능.
# HAProxy에서는 log 기반 미러링 또는 분기(use_backend)로 구현 가능.

# 방법: 특정 % 요청을 미러 백엔드에도 전송
frontend web
    bind *:80

    # 요청 헤더에 랜덤 값 추가
    http-request set-header X-Mirror-Id %[rand]

    # 5% 요청을 미러 백엔드로 (랜덤)
    acl mirror_request rand le 5000  # 0~9999 중 0~4999: 약 50%
    # 실제로는 Lua 스크립트나 별도 구현 필요

    default_backend production_backend
```

---

## 예제 11: 멀티 도메인 가상 호스트 (SNI/Host 기반)

```
frontend https_vhost
    bind *:443 ssl crt /etc/haproxy/certs/

    # /etc/haproxy/certs/ 디렉토리에 파일 배치:
    # example.com.pem
    # api.example.com.pem
    # shop.example.com.pem

    # Host 헤더 기반 라우팅
    acl is_api   hdr(host) -i api.example.com
    acl is_shop  hdr(host) -i shop.example.com
    acl is_main  hdr(host) -i example.com www.example.com

    use_backend api_backend   if is_api
    use_backend shop_backend  if is_shop
    use_backend main_backend  if is_main
    default_backend main_backend

backend api_backend
    balance leastconn
    option httpchk GET /health
    server api1 10.0.1.10:3000 check
    server api2 10.0.1.11:3000 check

backend shop_backend
    balance roundrobin
    option httpchk GET /health
    server shop1 10.0.2.10:3001 check
    server shop2 10.0.2.11:3001 check

backend main_backend
    balance roundrobin
    option httpchk GET /
    server main1 10.0.3.10:3002 check
    server main2 10.0.3.11:3002 check
```

---

## 예제 12: Stats 페이지 + Prometheus 메트릭 동시 제공

```
frontend monitoring
    bind *:8404
    mode http
    option httplog

    acl is_stats   path_beg /stats
    acl is_metrics path /metrics
    acl is_local   src 127.0.0.0/8 10.0.0.0/8

    # 외부 접근 차단
    http-request deny if !is_local

    # Prometheus 메트릭
    http-request use-service prometheus-exporter if is_metrics

    # Stats 페이지
    stats enable
    stats uri /stats
    stats realm "HAProxy Statistics"
    stats auth admin:StrongPassword123
    stats refresh 10s
    stats show-legends
    stats show-node
    stats admin if TRUE
```

---

## 예제 13: 요청 Rate Limiting + DDoS 방어

```
global
    maxconn 100000

frontend web
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/example.pem

    # Stick Table: IP별 요청 추적
    stick-table type ip size 200k expire 30s \
        store http_req_rate(10s),conn_cur,gpc0,gpc0_rate(30s)

    # 추적 시작
    http-request track-sc0 src

    # 규칙 1: 10초에 200 요청 초과 → 차단 플래그
    acl too_many_req  sc_http_req_rate(0) gt 200
    # 규칙 2: 동시 연결 50개 초과
    acl too_many_conn sc_conn_cur(0) gt 50
    # 규칙 3: 이미 차단된 IP
    acl is_abuser    sc_get_gpc0(0) gt 0

    # 차단 플래그 설정 (gpc0 증가)
    http-request sc-inc-gpc0(0) if too_many_req
    http-request sc-inc-gpc0(0) if too_many_conn

    # 429 응답 (Too Many Requests)
    http-request deny deny_status 429 if too_many_req
    http-request deny deny_status 429 if too_many_conn
    http-request deny deny_status 403 if is_abuser

    # 화이트리스트 (내부 IP는 제외)
    acl is_internal src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
    http-request allow if is_internal

    default_backend web_servers

backend web_servers
    balance roundrobin
    server web1 192.168.1.10:8080 check
    server web2 192.168.1.11:8080 check
```

---

## 예제 14: PostgreSQL 로드밸런서

```
defaults
    mode tcp
    timeout connect 5s
    timeout client  1h
    timeout server  1h
    option tcplog

frontend postgres_frontend
    bind *:5432
    default_backend postgres_backend

backend postgres_backend
    mode tcp
    balance leastconn

    # PostgreSQL 헬스체크 (TCP 연결만)
    option tcp-check
    tcp-check connect

    server pg_primary  10.0.1.10:5432 check inter 5s fall 3 rise 2
    server pg_standby1 10.0.1.11:5432 check inter 5s fall 3 rise 2 backup
    server pg_standby2 10.0.1.12:5432 check inter 5s fall 3 rise 2 backup
```

---

## 예제 15: 전체 완성된 프로덕션 설정

```
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 100000
    nbthread 4
    cpu-map auto:1/1-4 0-3

    # SSL 글로벌 설정
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options prefer-client-ciphers no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets
    ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-server-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

    tune.bufsize 32768
    tune.maxrewrite 1024
    tune.ssl.default-dh-param 2048

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    option  log-health-checks
    option  forwardfor
    option  http-server-close
    option  redispatch
    retries 3
    timeout connect  5s
    timeout client   30s
    timeout server   30s
    timeout http-request    10s
    timeout http-keep-alive 2s
    timeout queue    10s
    timeout check    5s
    maxconn 5000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# HTTP → HTTPS 리다이렉트
frontend http_in
    bind *:80
    acl is_acme path_beg /.well-known/acme-challenge/
    use_backend acme_backend if is_acme
    http-request redirect scheme https code 301 if !is_acme

# 메인 HTTPS 프론트엔드
frontend https_in
    bind *:443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1

    # 보안 헤더
    http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    http-response set-header X-Frame-Options "SAMEORIGIN"
    http-response set-header X-Content-Type-Options "nosniff"
    http-response set-header Referrer-Policy "strict-origin-when-cross-origin"
    http-response del-header Server
    http-response del-header X-Powered-By

    # Rate Limiting
    stick-table type ip size 200k expire 30s store http_req_rate(10s),conn_cur
    http-request track-sc0 src
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 500 }

    # 라우팅
    acl is_api  hdr(host) -i api.example.com
    acl is_www  hdr(host) -i example.com www.example.com

    use_backend api_backend if is_api
    default_backend www_backend

# 모니터링 프론트엔드
frontend monitoring
    bind *:8404
    mode http
    acl is_local src 127.0.0.0/8 10.0.0.0/8
    http-request deny if !is_local
    http-request use-service prometheus-exporter if { path /metrics }
    stats enable
    stats uri /stats
    stats realm HAProxy
    stats auth admin:SecurePass123
    stats refresh 10s
    stats admin if TRUE

backend acme_backend
    server acme 127.0.0.1:8888

backend api_backend
    balance leastconn
    option httpchk GET /health
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 slowstart 30s maxconn 200
    server api1 10.0.1.10:3000 check
    server api2 10.0.1.11:3000 check
    server api3 10.0.1.12:3000 check

backend www_backend
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 slowstart 30s
    server www1 10.0.2.10:3001 check
    server www2 10.0.2.11:3001 check
    server www3 10.0.2.12:3001 check
    server www_backup 10.0.2.20:3001 check backup
```
