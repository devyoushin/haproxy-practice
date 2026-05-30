# HAProxy listen 섹션 완전 가이드

`listen` 섹션은 `frontend`와 `backend`를 하나로 합친 통합 섹션입니다.
간단한 TCP/HTTP 로드밸런서를 한 블록으로 정의할 때 사용합니다.

---

## 1. 기본 개념

### frontend + backend vs listen

```
# 방법 1: frontend + backend 분리 (권장 방식)
frontend web_front
    bind *:80
    mode http
    default_backend web_back

backend web_back
    balance roundrobin
    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check

# -----------------------------------

# 방법 2: listen 통합 (간단한 경우에 적합)
listen web
    bind *:80
    mode http
    balance roundrobin
    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
```

두 방식은 기능적으로 동일하지만, `listen`은 복잡한 라우팅 (여러 backend로 분기)이 불가능합니다.

---

## 2. 기본 문법

```
listen <이름>
    bind <주소>:<포트> [파라미터...]
    mode <tcp|http>
    balance <알고리즘>
    option <옵션>
    server <이름> <주소:포트> [파라미터...]
```

---

## 3. listen vs frontend/backend 선택 기준

| 기준 | listen 사용 | frontend/backend 분리 사용 |
|------|------------|--------------------------|
| 라우팅 복잡도 | 단일 백엔드로만 전달 | 여러 backend로 분기 필요 |
| 재사용성 | 백엔드 재사용 불필요 | 여러 frontend가 같은 backend 사용 |
| 가독성 | 설정이 짧고 단순 | 역할 분리로 유지보수 용이 |
| TCP 서비스 | 매우 적합 | 가능하지만 오버엔지니어링 |
| HTTP 라우팅 | 단순 HTTP만 가능 | 경로/호스트 기반 라우팅 가능 |
| 통계 표시 | 단일 행으로 표시 | 프론트엔드/백엔드 분리 표시 |

### 권장 사용 시나리오

**listen이 적합한 경우:**
- TCP 포트 포워딩 (MySQL, Redis, Memcached 등)
- 단순한 HTTP 로드밸런서 (경로 분기 불필요)
- 내부 서비스 간 통신
- 개발/테스트 환경의 빠른 설정

**frontend/backend 분리가 적합한 경우:**
- 마이크로서비스 아키텍처 (경로별 라우팅)
- 여러 도메인 처리 (SNI 기반)
- 복잡한 ACL 조합
- 동일 backend를 여러 frontend에서 공유

---

## 4. TCP 프록시 예시

### 4.1 MySQL 로드밸런서
```haproxy
listen mysql_cluster
    bind *:3306
    mode tcp
    balance leastconn

    # TCP 헬스체크
    option tcp-check
    tcp-check connect

    timeout connect 5s
    timeout server  30s
    timeout client  30s

    server mysql1 10.0.0.10:3306 check inter 2s rise 2 fall 3
    server mysql2 10.0.0.11:3306 check inter 2s rise 2 fall 3
    server mysql3 10.0.0.12:3306 check inter 2s rise 2 fall 3 backup
```

### 4.2 Redis 로드밸런서
```haproxy
listen redis_cluster
    bind *:6379
    mode tcp
    balance roundrobin

    # Redis PING/PONG 헬스체크
    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    timeout connect 3s
    timeout server  10s
    timeout client  10s

    server redis1 10.0.0.20:6379 check
    server redis2 10.0.0.21:6379 check
```

### 4.3 PostgreSQL 로드밸런서
```haproxy
listen postgres_pool
    bind *:5432
    mode tcp
    balance leastconn

    option tcp-check
    tcp-check connect

    timeout connect 5s
    timeout server  60s
    timeout client  60s

    default-server inter 3s fall 3 rise 2

    server pg_primary 10.0.0.30:5432 check maxconn 100
    server pg_replica1 10.0.0.31:5432 check maxconn 100
    server pg_replica2 10.0.0.32:5432 check maxconn 100
```

### 4.4 Memcached 로드밸런서
```haproxy
listen memcached
    bind *:11211
    mode tcp
    balance source    # 같은 클라이언트는 같은 서버로 (캐시 히트율 향상)

    option tcp-check
    tcp-check connect
    tcp-check send version\r\n
    tcp-check expect string VERSION

    timeout connect 3s
    timeout server  5s
    timeout client  5s

    server mc1 10.0.0.40:11211 check
    server mc2 10.0.0.41:11211 check
    server mc3 10.0.0.42:11211 check
```

---

## 5. HTTP 로드밸런서 예시

### 5.1 기본 HTTP 로드밸런서
```haproxy
listen http_lb
    bind *:80
    mode http
    balance roundrobin

    option httplog
    option forwardfor
    option http-server-close

    # 헬스체크
    option httpchk GET /health
    http-check expect status 200

    timeout connect 5s
    timeout client  30s
    timeout server  30s

    server web1 10.0.0.50:80 check
    server web2 10.0.0.51:80 check
    server web3 10.0.0.52:80 check
```

### 5.2 내부 API 게이트웨이 (단순)
```haproxy
listen internal_api
    bind 0.0.0.0:8080
    mode http
    balance leastconn

    option httplog
    option forwardfor

    # 헬스체크
    option httpchk GET /api/health HTTP/1.1\r\nHost:\ internal.svc

    # 요청 헤더 추가
    http-request set-header X-Real-IP %[src]
    http-request set-header X-Forwarded-For %[src]

    # 응답 헤더 정리
    http-response del-header Server
    http-response del-header X-Powered-By

    timeout connect 3s
    timeout client  15s
    timeout server  15s

    default-server inter 2s fall 3 rise 2 maxconn 100

    server api1 10.0.1.10:8080 check
    server api2 10.0.1.11:8080 check
    server api3 10.0.1.12:8080 check
```

### 5.3 SSL 종단점 (간단한 HTTPS)
```haproxy
listen https_service
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    bind *:80

    mode http
    balance roundrobin

    # HTTP → HTTPS 리다이렉트
    http-request redirect scheme https code 301 if !{ ssl_fc }

    option httplog
    option forwardfor
    option http-server-close

    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    http-request set-header X-Forwarded-Proto http if !{ ssl_fc }

    http-response set-header Strict-Transport-Security "max-age=31536000"

    option httpchk GET /health
    http-check expect status 200

    timeout connect 5s
    timeout client  30s
    timeout server  30s

    server web1 10.0.0.50:80 check
    server web2 10.0.0.51:80 check
```

---

## 6. 통계(Stats) 페이지 listen

```haproxy
listen stats_page
    bind *:8404
    mode http

    # 통계 기능 활성화
    stats enable
    stats uri /stats
    stats realm "HAProxy Statistics"
    stats auth admin:StrongPassword123
    stats refresh 30s

    # 추가 정보 표시
    stats show-legends
    stats show-node
    stats show-desc "Production HAProxy"

    # 관리 기능 (서버 활성화/비활성화 등)
    stats admin if TRUE

    # 접근 제한 (특정 IP만 허용)
    acl admin_net src 10.0.0.0/8 192.168.0.0/16
    tcp-request connection reject if !admin_net

    timeout connect 5s
    timeout client  60s
    timeout server  60s
```

---

## 7. 헬스체크 전용 listen (모니터링)

```haproxy
listen healthcheck
    bind *:9090
    mode http

    # 모니터링 URI (서버 없이 HAProxy 자체 상태 반환)
    monitor-uri /haproxy-alive

    # 특정 backend가 정상이면 200, 아니면 503
    monitor fail if { nbsrv(web_backend) lt 1 }

    # 이 listen에는 server 지시어 없음
    # HAProxy 자체가 응답을 생성
```

---

## 8. PROXY 프로토콜과 listen

```haproxy
# 클라이언트 IP를 PROXY 프로토콜로 받는 경우
listen proxy_protocol_receiver
    bind *:80 accept-proxy   # 업스트림(예: Nginx, AWS NLB)에서 PROXY 프로토콜 수신

    mode http
    balance roundrobin

    option httplog
    option forwardfor

    server app1 10.0.0.10:8080 check
    server app2 10.0.0.11:8080 check

# 백엔드로 PROXY 프로토콜 전달
listen proxy_protocol_sender
    bind *:80
    mode tcp
    balance roundrobin

    server backend1 10.0.0.10:80 check send-proxy-v2
    server backend2 10.0.0.11:80 check send-proxy-v2
```

---

## 9. listen 제약사항

### 9.1 단일 backend만 지원
`listen`은 여러 backend로의 라우팅을 지원하지 않습니다.

```haproxy
# 불가능한 예시 - listen에서는 use_backend 사용 불가
listen web
    bind *:80
    # use_backend api_backend if is_api   # 오류 발생!
    # use_backend web_backend             # 오류 발생!
```

경로 기반 라우팅이 필요하면 반드시 frontend + backend를 분리해야 합니다.

### 9.2 기타 제약사항

| 제약 | 설명 |
|------|------|
| `use_backend` 불가 | 여러 backend 선택 불가 |
| `default_backend` 불가 | 사용 불필요 (listen 자체가 backend) |
| ACL 라우팅 제한 | ACL은 사용 가능하지만 다른 backend로 보낼 수 없음 |
| 재사용 불가 | 같은 서버 그룹을 다른 listen에서 참조 불가 |

---

## 10. 완전한 실전 예시: 소규모 인프라

```haproxy
#---------------------------------------------------------------------
# 소규모 인프라용 전체 haproxy.cfg 예시
# (listen 섹션 중심으로 구성)
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

defaults
    log     global
    option  redispatch
    retries 3
    timeout connect  5s
    timeout client  30s
    timeout server  30s

#---------------------------------------------------------------------
# 웹 애플리케이션 (HTTP)
#---------------------------------------------------------------------
listen webapp
    bind *:80
    mode http
    balance roundrobin

    option httplog
    option forwardfor
    option http-server-close

    option httpchk GET /health
    http-check expect status 200

    http-request set-header X-Real-IP %[src]
    http-response del-header Server

    default-server inter 3s fall 3 rise 2 slowstart 30s

    server web1 10.0.0.10:8080 check
    server web2 10.0.0.11:8080 check
    server web3 10.0.0.12:8080 check

#---------------------------------------------------------------------
# MySQL 데이터베이스
#---------------------------------------------------------------------
listen mysql
    bind *:3306
    mode tcp
    balance leastconn

    option tcp-check
    tcp-check connect

    default-server inter 3s fall 3 rise 2

    server db1 10.0.1.10:3306 check maxconn 100
    server db2 10.0.1.11:3306 check maxconn 100 backup

#---------------------------------------------------------------------
# Redis 캐시
#---------------------------------------------------------------------
listen redis
    bind *:6379
    mode tcp
    balance source

    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    server redis1 10.0.2.10:6379 check
    server redis2 10.0.2.11:6379 check

#---------------------------------------------------------------------
# 통계 페이지
#---------------------------------------------------------------------
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats auth admin:password
    stats refresh 10s
    stats show-legends
    stats show-node
    acl local_net src 10.0.0.0/8
    tcp-request connection reject if !local_net
```

---

## 11. listen 디버깅 팁

```bash
# listen 섹션 파싱 확인
haproxy -f /etc/haproxy/haproxy.cfg -c

# 특정 listen의 서버 상태 확인
echo "show servers state" | socat /run/haproxy/admin.sock stdio | grep "mysql\|redis\|webapp"

# listen의 연결 통계
echo "show stat" | socat /run/haproxy/admin.sock stdio | grep "^webapp"

# 실시간 연결 수 확인
echo "show info" | socat /run/haproxy/admin.sock stdio | grep -E "CurrConns|MaxConn"
```

---

## 12. 정리

```
listen 사용 ✓         frontend/backend 분리 사용 ✓
─────────────────     ──────────────────────────────
단순 TCP 포워딩       복잡한 HTTP 라우팅
단일 서버 그룹        경로/호스트 기반 분기
내부 서비스           공용 서비스
소규모 인프라         마이크로서비스 아키텍처
빠른 프로토타이핑     프로덕션 환경
통계 페이지           다중 도메인 처리
```
