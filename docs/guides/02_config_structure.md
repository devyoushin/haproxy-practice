# HAProxy 설정 파일 구조 완전 가이드

## 1. 설정 파일 위치 및 기본 구조

### 기본 위치
```
/etc/haproxy/haproxy.cfg     # 메인 설정 파일 (표준 경로)
/etc/haproxy/conf.d/         # 추가 설정 파일 디렉토리 (선택적)
```

### 설정 파일의 전체 구조

HAProxy 설정 파일은 여러 **섹션(section)**으로 구성됩니다.
각 섹션은 특정 목적을 가지며, 섹션 내부에 지시어(directive)를 작성합니다.

```haproxy
#---------------------------------------------------------------------
# global: 전역 설정 (HAProxy 프로세스 자체 설정)
#---------------------------------------------------------------------
global
    maxconn 50000
    log 127.0.0.1 local0
    user haproxy
    group haproxy
    daemon

#---------------------------------------------------------------------
# defaults: 기본값 설정 (이후 섹션에 상속됨)
#---------------------------------------------------------------------
defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s

#---------------------------------------------------------------------
# frontend: 클라이언트 요청을 수신하는 섹션
#---------------------------------------------------------------------
frontend web_frontend
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    default_backend web_backend

#---------------------------------------------------------------------
# backend: 실제 서버들을 정의하는 섹션
#---------------------------------------------------------------------
backend web_backend
    balance roundrobin
    server web1 192.168.1.10:8080 check
    server web2 192.168.1.11:8080 check

#---------------------------------------------------------------------
# listen: frontend + backend 합친 간단한 형태
#---------------------------------------------------------------------
listen mysql_cluster
    bind *:3306
    mode tcp
    server db1 192.168.1.20:3306 check
    server db2 192.168.1.21:3306 check backup

#---------------------------------------------------------------------
# userlist: 사용자 인증 목록
#---------------------------------------------------------------------
userlist stats_users
    group admin
    user admin insecure-password secretpass
    user readonly insecure-password readpass

#---------------------------------------------------------------------
# peers: HAProxy 인스턴스 간 데이터 동기화
#---------------------------------------------------------------------
peers mypeers
    peer haproxy1 192.168.1.1:1024
    peer haproxy2 192.168.1.2:1024

#---------------------------------------------------------------------
# resolvers: DNS 설정
#---------------------------------------------------------------------
resolvers mydns
    nameserver dns1 8.8.8.8:53
    nameserver dns2 8.8.4.4:53
    hold valid 10s
    hold other 30s

#---------------------------------------------------------------------
# mailers: 이메일 알림 설정
#---------------------------------------------------------------------
mailers mymailers
    mailer smtp1 192.168.1.100:25

#---------------------------------------------------------------------
# ring: 공유 메모리 링 버퍼 (로그용)
#---------------------------------------------------------------------
ring myring
    description "My Ring Buffer"
    format rfc5424
    maxlen 1200
    size 32767
    server rsyslog 127.0.0.1:6514 log-proto octet-count

#---------------------------------------------------------------------
# program: 외부 프로그램 실행
#---------------------------------------------------------------------
program spoe-checker
    command /usr/local/bin/spoe-checker
    option start-on-reload
```

---

## 2. 모든 섹션 종류 상세 설명

### 2.1 global 섹션
- **역할**: HAProxy 프로세스 전체에 적용되는 전역 설정
- **특징**: 설정 파일에 하나만 존재해야 함
- **포함 내용**: maxconn, 로그, 보안(chroot/user/group), Stats 소켓, SSL 기본값

```haproxy
global
    maxconn 50000
    log /dev/log local0
    chroot /var/lib/haproxy
    user haproxy
    group haproxy
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin
```

### 2.2 defaults 섹션
- **역할**: 이후 나오는 frontend, backend, listen 섹션의 기본값 설정
- **특징**: 여러 개 정의 가능 (각각 이후 섹션에 적용)
- **포함 내용**: mode, timeout, option, balance, maxconn

```haproxy
defaults
    mode http
    log global
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client 30s
    timeout server 30s
```

### 2.3 frontend 섹션
- **역할**: 클라이언트 연결을 수신하고 처리 규칙 정의
- **특징**: bind(수신 주소/포트) 지시어 필수, default_backend로 트래픽 전달
- **포함 내용**: bind, acl, use_backend, http-request, rate-limit

```haproxy
frontend http_in
    bind *:80
    acl is_api path_beg /api/
    use_backend api_servers if is_api
    default_backend web_servers
```

### 2.4 backend 섹션
- **역할**: 요청을 처리할 실제 서버 풀 정의
- **특징**: server 지시어로 서버 등록, balance로 분산 알고리즘 설정
- **포함 내용**: server, balance, option httpchk, cookie, stick-table

```haproxy
backend web_servers
    balance leastconn
    option httpchk GET /health
    server web1 10.0.1.10:8080 check weight 2
    server web2 10.0.1.11:8080 check weight 1
```

### 2.5 listen 섹션
- **역할**: frontend + backend를 하나로 합친 간단한 형태
- **특징**: 간단한 TCP 프록시나 소규모 설정에 적합
- **포함 내용**: bind, server, balance 등 (frontend + backend 내용 모두)

```haproxy
listen ssh_proxy
    bind *:2222
    mode tcp
    server ssh1 192.168.1.10:22
```

### 2.6 userlist 섹션
- **역할**: 기본 인증(Basic Auth)을 위한 사용자/그룹 목록 정의
- **특징**: Stats 페이지나 특정 경로 접근 제어에 사용

```haproxy
userlist admin_users
    group admins
    group readers
    user alice password $6$saltvalue$hashedpassword groups admins
    user bob insecure-password plaintext123 groups readers
```

### 2.7 peers 섹션
- **역할**: 여러 HAProxy 인스턴스 간 Stick Table 데이터 동기화
- **특징**: HA 환경에서 세션 데이터 공유에 필수

```haproxy
peers haproxy_cluster
    bind 0.0.0.0:1024
    peer haproxy1 192.168.1.1:1024
    peer haproxy2 192.168.1.2:1024
    peer haproxy3 192.168.1.3:1024
    table shared_sessions type ip size 1m expire 30m
```

### 2.8 resolvers 섹션
- **역할**: HAProxy에서 사용할 DNS 리졸버 설정
- **특징**: 백엔드 서버를 IP 대신 도메인으로 지정할 때 필요

```haproxy
resolvers mydns
    nameserver dns1 8.8.8.8:53
    nameserver dns2 1.1.1.1:53
    resolve_retries 3
    timeout resolve 1s
    timeout retry 1s
    hold other 30s
    hold refused 30s
    hold nx 30s
    hold timeout 30s
    hold valid 10s
    hold obsolete 30s
```

### 2.9 mailers 섹션
- **역할**: 서버 상태 변경 시 이메일 알림 발송
- **특징**: health check 결과에 따른 알림

```haproxy
mailers mymailers
    mailer smtp1 192.168.1.100:25
    timeout mail 20s
```

### 2.10 program 섹션
- **역할**: HAProxy와 함께 실행할 외부 프로그램 관리
- **특징**: SPOE(Stream Processing Offload Engine) 에이전트 등에 사용

```haproxy
program my-agent
    command /usr/local/bin/my-spoe-agent
    option start-on-reload
    no option oom-score-adjust
```

### 2.11 ring 섹션
- **역할**: 공유 메모리 링 버퍼 (주로 로그 전달용)
- **특징**: HAProxy 2.2+에서 도입, 네트워크 로그 서버로 전달 시 사용

```haproxy
ring syslog_ring
    description "Syslog ring buffer"
    format rfc5424
    maxlen 1200
    size 32767
    timeout connect 5s
    timeout server 10s
    server rsyslog 127.0.0.1:6514 log-proto octet-count
```

---

## 3. 설정 파일 문법 규칙

### 3.1 들여쓰기와 공백

```haproxy
# 섹션 키워드는 줄 맨 앞에 위치 (들여쓰기 없음)
global
defaults
frontend my_frontend
backend my_backend

# 지시어는 반드시 들여쓰기 (스페이스 또는 탭 사용)
backend my_backend
    balance roundrobin          # 스페이스 들여쓰기 (권장)
	server web1 10.0.0.1:80    # 탭 들여쓰기 (가능하지만 비권장)

# 지시어의 파라미터는 공백으로 구분
server web1 10.0.0.1:80 check weight 2 maxconn 100
#      이름  주소:포트  파라미터...
```

### 3.2 주석 처리

```haproxy
# 이것은 주석입니다 (# 사용)
# HAProxy는 // 또는 /* */ 스타일 주석을 지원하지 않습니다

global
    maxconn 50000  # 인라인 주석도 가능
    # 한 줄 전체를 주석으로 처리
    log 127.0.0.1 local0  # 로그 서버 설정
```

### 3.3 줄 이음 (Line Continuation)

```haproxy
# 긴 설정을 여러 줄로 나누기: 역슬래시(\) 사용
backend my_backend
    server web1 \
        10.0.0.1:80 \
        check \
        weight 2 \
        maxconn 100

# 실제로는 한 줄로 처리됨:
# server web1 10.0.0.1:80 check weight 2 maxconn 100
```

### 3.4 대소문자 규칙

```haproxy
# 섹션 이름: 소문자 (global, defaults, frontend, backend, listen)
global          # O
Global          # X (오류)
GLOBAL          # X (오류)

# 지시어 이름: 소문자 (대부분)
maxconn         # O
MAXCONN         # X

# 섹션 레이블 이름: 임의 (대소문자 구분)
frontend Web_Frontend    # 허용
frontend web_frontend    # 허용 (다른 섹션)
# 위 두 섹션은 이름이 다른 별개 섹션

# 값: 대소문자 구분 (일부)
mode HTTP       # X (소문자 필요)
mode http       # O
mode tcp        # O
```

### 3.5 특수 문자 및 문자열

```haproxy
# 공백 포함 문자열: 따옴표 사용
http-request set-header X-Custom-Header "Hello World"

# 특수 문자 이스케이프: 필요 시 \ 사용
# ACL에서 정규식 내 특수문자
acl is_php path_reg \.php$

# 중괄호: ACL 이름에 사용
http-request deny if { src 192.168.1.0/24 }
```

### 3.6 숫자 단위

```haproxy
# 시간 단위
timeout connect 5s      # 초 (seconds)
timeout client 1m       # 분 (minutes)
timeout server 2h       # 시간 (hours)
timeout tunnel 7200000  # 밀리초 (단위 없으면 ms)

# 크기 단위
tune.bufsize 32768      # 바이트 (단위 없음)
maxconn 50000           # 개수 (단위 없음)

# 단위 표
# ms (또는 단위 없음): 밀리초
# s: 초
# m: 분
# h: 시간
# d: 일
```

---

## 4. 여러 파일로 설정 분리

### 4.1 -f 옵션 사용

```bash
# 단일 파일
haproxy -f /etc/haproxy/haproxy.cfg

# 여러 파일 (순서대로 로드, 합쳐서 처리)
haproxy -f /etc/haproxy/global.cfg \
        -f /etc/haproxy/defaults.cfg \
        -f /etc/haproxy/frontends.cfg \
        -f /etc/haproxy/backends.cfg

# 디렉토리 전체 로드 (*.cfg 파일을 알파벳 순으로)
haproxy -f /etc/haproxy/haproxy.cfg \
        -f /etc/haproxy/conf.d/

# systemd 서비스 파일에서 설정
# /usr/lib/systemd/system/haproxy.service
# ExecStart=/usr/sbin/haproxy -Ws -f /etc/haproxy/ -p /run/haproxy.pid
```

### 4.2 파일 분리 구조 예시

```
/etc/haproxy/
├── haproxy.cfg              # 메인: global + defaults만 포함
└── conf.d/
    ├── 00-global.cfg        # global 섹션
    ├── 01-defaults.cfg      # defaults 섹션
    ├── 10-frontend-web.cfg  # 웹 프론트엔드
    ├── 10-frontend-api.cfg  # API 프론트엔드
    ├── 20-backend-web.cfg   # 웹 백엔드
    ├── 20-backend-api.cfg   # API 백엔드
    ├── 30-stats.cfg         # 통계 페이지
    └── 99-peers.cfg         # Peers 설정
```

```haproxy
# /etc/haproxy/conf.d/00-global.cfg
global
    maxconn 50000
    log 127.0.0.1 local0
    user haproxy
    group haproxy
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin

# /etc/haproxy/conf.d/01-defaults.cfg
defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    option httplog

# /etc/haproxy/conf.d/10-frontend-web.cfg
frontend web_frontend
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/
    acl is_api path_beg /api/
    use_backend api_servers if is_api
    default_backend web_servers

# /etc/haproxy/conf.d/20-backend-web.cfg
backend web_servers
    balance roundrobin
    option httpchk GET /health
    server web1 10.0.1.10:8080 check
    server web2 10.0.1.11:8080 check
```

### 4.3 include 지시어 (HAProxy 2.4+)

```haproxy
# haproxy.cfg에서 다른 파일 포함
global
    maxconn 50000

defaults
    mode http
    timeout connect 5s

# 다른 설정 파일 포함
include /etc/haproxy/conf.d/*.cfg
include /etc/haproxy/sites-enabled/mysite.cfg
```

---

## 5. 설정 검증 방법

```bash
# ============================================================
# 기본 문법 검증 (-c 옵션)
# ============================================================
sudo haproxy -f /etc/haproxy/haproxy.cfg -c
# 성공: Configuration file is valid
# 실패: [ALERT] ... : parsing [/etc/haproxy/haproxy.cfg:15]: ...

# ============================================================
# 여러 파일 검증
# ============================================================
sudo haproxy -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d/ -c

# ============================================================
# 상세 검증 출력
# ============================================================
sudo haproxy -f /etc/haproxy/haproxy.cfg -c -dS
# 경고(warning) 및 정보(info) 메시지도 출력

# ============================================================
# 설정 파일 파싱 디버그
# ============================================================
sudo haproxy -f /etc/haproxy/haproxy.cfg -d
# -d: 디버그 모드 (포그라운드 실행, 상세 로그)

# ============================================================
# 일반적인 검증 오류 예시
# ============================================================

# 오류 1: 알 수 없는 지시어
# [ALERT] ... : parsing [haproxy.cfg:5]: unknown keyword 'maxconns' in 'global' section

# 오류 2: 포트 범위 오류
# [ALERT] ... : parsing [haproxy.cfg:12]: invalid port '65536'

# 오류 3: backend 참조 오류
# [ALERT] ... : Proxy 'web_frontend': unable to find required default_backend 'web_backkend'

# 오류 4: 시간 단위 오류
# [ALERT] ... : parsing [haproxy.cfg:20]: timer overflow in argument '99d' to 'timeout client'

# ============================================================
# 경고(Warning) vs 오류(Alert)
# ============================================================
# [WARNING]: 설정 가능하지만 권고하지 않는 설정
# [ALERT]: 치명적 오류, HAProxy가 시작되지 않음
# [NOTICE]: 정보성 메시지
```

---

## 6. 설정 Reload 방법

### 6.1 systemd reload (권장)

```bash
# 무중단 설정 재로드 (기존 연결 유지)
sudo systemctl reload haproxy

# 동작 방식:
# 1. 새 설정 파일 유효성 검사
# 2. 새 프로세스 시작
# 3. 기존 연결은 기존 프로세스에서 계속 처리
# 4. 새 연결은 새 프로세스에서 처리
# 5. 기존 프로세스는 연결이 모두 종료되면 자동 종료
```

### 6.2 시그널을 이용한 reload

```bash
# USR2 시그널: 무중단 reload (graceful restart)
sudo kill -USR2 $(cat /run/haproxy.pid)
# 또는
sudo pkill -USR2 haproxy

# HUP 시그널: 설정 재로드 (일부 버전에서 지원)
sudo kill -HUP $(cat /run/haproxy.pid)

# TERM 시그널: 정상 종료 (기존 연결 완료 후 종료)
sudo kill -TERM $(cat /run/haproxy.pid)

# INT 시그널: 즉시 종료
sudo kill -INT $(cat /run/haproxy.pid)
```

### 6.3 Runtime API를 통한 동적 변경

```bash
# 서버 추가 (reload 없이)
echo "add server backend1/web3 10.0.0.3:80" | \
    sudo socat stdio /run/haproxy/admin.sock

# 서버 가중치 변경 (reload 없이)
echo "set weight backend1/web1 50" | \
    sudo socat stdio /run/haproxy/admin.sock

# 서버 활성화/비활성화 (reload 없이)
echo "disable server backend1/web2" | \
    sudo socat stdio /run/haproxy/admin.sock

echo "enable server backend1/web2" | \
    sudo socat stdio /run/haproxy/admin.sock
```

---

## 7. 설정 파일 모범 사례

### 7.1 섹션 순서 권장

```haproxy
# 권장 순서:
# 1. global
# 2. defaults
# 3. userlist (인증 목록)
# 4. resolvers (DNS)
# 5. peers
# 6. mailers
# 7. listen / frontend + backend
```

### 7.2 주석 규칙

```haproxy
#======================================================================
# 섹션 구분자 (대형 주석)
#======================================================================

#----------------------------------------------------------------------
# 서브 섹션 구분자
#----------------------------------------------------------------------

# 단순 설명 주석

backend web_servers
    balance roundrobin           # 인라인 주석: 간단한 설명
    # 서버 목록
    server web1 10.0.0.1:80 check   # 첫 번째 서버
    server web2 10.0.0.2:80 check   # 두 번째 서버
```

### 7.3 네이밍 컨벤션

```haproxy
# 프론트엔드: ft_ 접두사 또는 _frontend 접미사
frontend ft_http
frontend ft_https
frontend http_frontend

# 백엔드: bk_ 접두사 또는 _backend 접미사
backend bk_web
backend bk_api
backend web_backend

# Listen: lsn_ 접두사
listen lsn_stats
listen lsn_mysql

# ACL: 동사+명사 형태
acl is_ssl ssl_fc
acl has_cookie req.cook -m found
acl is_api path_beg /api/

# 서버: 서비스명+번호
server web01 10.0.1.1:80 check
server app-server-1 10.0.2.1:8080 check
```

### 7.4 설정 파일 보안

```bash
# 설정 파일 권한 (읽기는 haproxy 그룹, 쓰기는 root만)
sudo chmod 640 /etc/haproxy/haproxy.cfg
sudo chown root:haproxy /etc/haproxy/haproxy.cfg

# 디렉토리 권한
sudo chmod 750 /etc/haproxy/
sudo chown root:haproxy /etc/haproxy/

# 인증서 파일 권한
sudo chmod 600 /etc/haproxy/certs/*.pem
sudo chown haproxy:haproxy /etc/haproxy/certs/*.pem

# 설정 파일에 평문 패스워드 금지
# 나쁜 예:
# stats auth admin:mysecretpassword123

# 좋은 예 (userlist 사용 + 해시 패스워드):
userlist admin_users
    user admin password $6$rounds=100000$salt$hashedpassword
```

---

## 8. 전체 설정 파일 예시

실제 프로덕션에 가까운 완전한 설정 파일 예시:

```haproxy
#======================================================================
# HAProxy 프로덕션 설정 예시
# 버전: 2.8 LTS
# 최종 수정: 2024-01-01
#======================================================================

global
    # ---- 기본 설정 ----
    maxconn     50000
    ulimit-n    200000  # 파일 디스크립터 제한

    # ---- 프로세스 설정 ----
    user        haproxy
    group       haproxy
    daemon
    nbthread    4       # CPU 코어 수에 맞게 설정
    cpu-map     auto:1/1-4 0-3

    # ---- 보안 ----
    chroot      /var/lib/haproxy
    pidfile     /run/haproxy.pid

    # ---- 로그 ----
    log         127.0.0.1 local0 notice
    log         127.0.0.1 local1 notice

    # ---- Runtime API ----
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s

    # ---- SSL 기본값 ----
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    tune.ssl.default-dh-param 2048

defaults
    mode    http
    log     global
    option  httplog
    option  dontlognull
    option  http-server-close
    option  forwardfor      except 127.0.0.0/8
    option  redispatch
    retries 3

    timeout http-request    10s
    timeout queue           30s
    timeout connect         5s
    timeout client          30s
    timeout server          30s
    timeout http-keep-alive 10s
    timeout check           5s

    maxconn 25000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

userlist stats_users
    group admin users admin
    user admin insecure-password changeme

frontend ft_stats
    bind *:8404
    mode http
    stats enable
    stats uri /haproxy?stats
    stats refresh 30s
    stats show-legends
    stats show-node
    acl AUTH http_auth(stats_users)
    acl AUTH_ADMIN http_auth_group(stats_users) admin
    stats http-request auth unless AUTH
    stats admin if AUTH_ADMIN

frontend ft_http
    bind *:80
    # HTTP -> HTTPS 리다이렉트
    http-request redirect scheme https code 301 unless { ssl_fc }

frontend ft_https
    bind *:443 ssl crt /etc/haproxy/certs/server.pem alpn h2,http/1.1
    # HSTS 헤더
    http-response set-header Strict-Transport-Security "max-age=63072000"
    # 보안 헤더
    http-response set-header X-Frame-Options DENY
    http-response set-header X-Content-Type-Options nosniff
    # ACL 기반 라우팅
    acl is_api path_beg /api/v1/ /api/v2/
    acl is_static path_end .css .js .png .jpg .ico .woff2
    use_backend bk_api if is_api
    use_backend bk_static if is_static
    default_backend bk_web

backend bk_web
    balance leastconn
    option httpchk GET /health HTTP/1.1\r\nHost:\ example.com
    http-check expect status 200
    cookie SERVERID insert indirect nocache
    server web1 10.0.1.10:8080 check cookie web1 weight 10
    server web2 10.0.1.11:8080 check cookie web2 weight 10
    server web3 10.0.1.12:8080 check cookie web3 weight 10 backup

backend bk_api
    balance roundrobin
    option httpchk GET /api/health
    http-check expect status 200
    timeout server 60s
    server api1 10.0.2.10:8080 check
    server api2 10.0.2.11:8080 check
    server api3 10.0.2.12:8080 check

backend bk_static
    balance uri
    option httpchk HEAD /
    server static1 10.0.3.10:80 check
    server static2 10.0.3.11:80 check
```
