# HAProxy global 섹션 완전 딥다이브

## 개요

`global` 섹션은 HAProxy 프로세스 전체에 적용되는 설정을 담고 있습니다.
이 섹션은 HAProxy가 어떻게 동작할지 근본적인 동작 방식을 결정합니다.
설정 파일 전체에서 **단 하나만 존재**해야 합니다.

```haproxy
global
    # 여기에 전역 설정을 작성
```

---

## 1. 프로세스 관리 설정

### daemon
```haproxy
global
    daemon
```
- **설명**: HAProxy를 백그라운드 데몬으로 실행
- **기본값**: 미설정 (포그라운드 실행)
- **사용 시점**: 프로덕션 환경 (systemd와 함께 사용)
- **주의**: systemd `Type=notify` 사용 시에는 `-Ws` 옵션과 함께 사용

### nbproc (HAProxy 2.6 이하, 현재 deprecated)
```haproxy
global
    nbproc 4   # 4개의 프로세스 실행
```
- **설명**: 멀티 프로세스 모드 (2.7 이후 제거됨)
- **현재**: `nbthread` 사용 권장

### nbthread
```haproxy
global
    nbthread 8   # 8개 스레드 (CPU 코어 수에 맞게)
```
- **설명**: HAProxy 프로세스 내의 스레드 수
- **기본값**: 1 (단일 스레드)
- **권장값**: CPU 코어 수 (또는 코어 수 - 1)
- **최대값**: 하드웨어 스레드 수 (논리 CPU 수)
- **효과**: CPU 바운드 작업의 처리량 향상

```bash
# 시스템 CPU 수 확인
nproc                    # 물리 코어 수
nproc --all              # 논리 코어 수 (하이퍼스레딩 포함)
cat /proc/cpuinfo | grep processor | wc -l
```

### cpu-map
```haproxy
global
    nbthread 4
    # 형식: cpu-map <thread-set> <cpu-set>

    # 스레드 1-4를 CPU 0-3에 1:1 매핑
    cpu-map auto:1/1-4 0-3

    # 개별 매핑
    cpu-map 1/1 0
    cpu-map 1/2 1
    cpu-map 1/3 2
    cpu-map 1/4 3

    # 하이퍼스레딩 고려 (8코어 HT CPU)
    cpu-map auto:1/1-8 0-15
```
- **설명**: 스레드와 CPU 코어의 어피니티(affinity) 설정
- **효과**: CPU 캐시 활용 최적화, NUMA 아키텍처에서 성능 향상
- **형식**: `auto:proc/thread cpu` 또는 `proc/thread cpu`

### ulimit-n
```haproxy
global
    ulimit-n 200000   # 최대 파일 디스크립터 수
```
- **설명**: HAProxy 프로세스의 파일 디스크립터 제한 설정
- **계산**: `maxconn * 2 + 여유분` (각 연결은 2개의 FD 사용)
- **OS 설정 필요**:
```bash
# /etc/security/limits.conf
* soft nofile 200000
* hard nofile 200000

# /etc/sysctl.conf
fs.file-max = 2000000

# 확인
ulimit -n
cat /proc/sys/fs/file-max
```

---

## 2. 보안 설정

### chroot
```haproxy
global
    chroot /var/lib/haproxy
```
- **설명**: HAProxy 프로세스를 지정한 디렉토리로 chroot
- **효과**: 보안 강화 (파일시스템 접근 제한)
- **주의사항**:
  - chroot 디렉토리는 반드시 **빈 디렉토리**여야 함
  - Stats 소켓도 chroot 안에 위치해야 함 (또는 전체 경로 지정)
  - SSL 인증서는 chroot 전에 로드됨

```bash
# chroot 디렉토리 준비
sudo mkdir -p /var/lib/haproxy
sudo chown root:root /var/lib/haproxy
sudo chmod 750 /var/lib/haproxy

# 디렉토리가 비어있어야 함
ls /var/lib/haproxy   # 출력 없어야 함
```

### user / group
```haproxy
global
    user haproxy
    group haproxy
```
- **설명**: HAProxy 프로세스가 실행될 사용자/그룹
- **효과**: root 권한을 포기하여 보안 강화
- **주의**: 1024 이하 포트 사용 시 `CAP_NET_BIND_SERVICE` 캐퍼빌리티 필요

```bash
# 사용자/그룹 생성
sudo groupadd -r haproxy
sudo useradd -r -g haproxy -d /var/lib/haproxy -s /sbin/nologin haproxy

# 또는 uid/gid로 지정
# user 998
# group 998
```

### capabilities (HAProxy 2.8+)
```haproxy
global
    # 특정 Linux 캐퍼빌리티 부여
    # 낮은 포트(< 1024) 바인딩을 위해
```
```bash
# 바이너리에 직접 캐퍼빌리티 설정
sudo setcap 'cap_net_bind_service=+ep' /usr/sbin/haproxy
```

---

## 3. 로그 설정

### log
```haproxy
global
    # 형식: log <address> [len <length>] [format <format>] <facility> [<level> [<minlevel>]]

    # 기본 형태: UDP syslog
    log 127.0.0.1 local0 info

    # 두 번째 로그 서버
    log 127.0.0.1 local1 notice

    # Unix 소켓으로 로그
    log /dev/log local0

    # 원격 syslog 서버
    log 192.168.1.100:514 local0 info

    # 길이 제한
    log 127.0.0.1 len 4096 local0 info

    # RFC 5424 형식
    log 127.0.0.1 format rfc5424 local0 info
```

#### Facility 목록
| Facility | 설명 | 관례적 용도 |
|----------|------|------------|
| kern | 커널 메시지 | 일반적으로 사용 안 함 |
| user | 사용자 프로그램 | |
| mail | 메일 시스템 | |
| daemon | 시스템 데몬 | |
| auth | 인증 | |
| syslog | syslogd 내부 | |
| lpr | 프린터 | |
| news | 뉴스 | |
| uucp | UUCP | |
| cron | cron 데몬 | |
| local0~local7 | 로컬 사용 | **HAProxy 권장** |

#### Level 목록 (심각도 순)
| Level | 값 | 설명 |
|-------|-----|------|
| emerg | 0 | 시스템 사용 불가 |
| alert | 1 | 즉각 조치 필요 |
| crit | 2 | 치명적 상태 |
| err | 3 | 오류 |
| warning | 4 | 경고 |
| notice | 5 | 정상이지만 중요 |
| info | 6 | 정보 메시지 |
| debug | 7 | 디버그 메시지 |

```haproxy
global
    # local0: info 이상만 로그
    log 127.0.0.1 local0 info

    # local0: warning 이상만 로그
    log 127.0.0.1 local0 warning

    # local0: debug ~ notice 사이만 로그 (minlevel 설정)
    log 127.0.0.1 local0 notice debug
    # notice: 최대 레벨, debug: 최소 레벨
```

---

## 4. 연결 수 제한

### maxconn
```haproxy
global
    maxconn 50000   # 동시 연결 최대 수
```
- **설명**: HAProxy 전체의 최대 동시 연결 수
- **기본값**: 2000
- **영향**: ulimit-n (파일 디스크립터), 메모리 사용량
- **계산**: 각 연결은 약 1-5KB 메모리 사용

```bash
# 권장 설정 계산
# 사용 가능한 메모리의 절반을 연결에 할당
# 연결당 약 2KB (여유분 포함 5KB)
# 예: 4GB RAM에서 maxconn = (4*1024*1024 / 2) / 5 ≈ 400000

# 실제로는 더 보수적으로 설정
# maxconn = 50000 ~ 100000 (일반적)
```

### maxconnrate
```haproxy
global
    maxconnrate 1000   # 초당 최대 새 연결 수
```
- **설명**: 초당 새로 수락할 수 있는 최대 연결 수
- **효과**: DDoS 방어, 연결 폭풍(thundering herd) 방지

### maxsessrate
```haproxy
global
    maxsessrate 2000   # 초당 최대 세션 수
```
- **설명**: 초당 최대 새 세션 생성 수 (HTTP 레이어 기준)

### maxsslconn
```haproxy
global
    maxsslconn 20000   # SSL/TLS 최대 동시 연결 수
```
- **설명**: SSL 연결 수 별도 제한 (SSL은 더 많은 리소스 사용)
- **권장**: maxconn의 40-50%

### maxsslrate
```haproxy
global
    maxsslrate 500   # 초당 최대 SSL 핸드셰이크 수
```
- **설명**: SSL 핸드셰이크는 CPU 집약적이므로 별도 제한

---

## 5. PID 파일

### pidfile
```haproxy
global
    pidfile /run/haproxy.pid
```
- **설명**: HAProxy의 PID를 저장할 파일 경로
- **사용 용도**: 시그널 전송, 모니터링 도구

```bash
# PID 파일 사용 예시
kill -USR2 $(cat /run/haproxy.pid)   # graceful reload
kill -TERM $(cat /run/haproxy.pid)   # 정상 종료
```

---

## 6. Stats 소켓 (Runtime API)

### stats socket
```haproxy
global
    # Unix 도메인 소켓 (권장)
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners

    # 파라미터 상세:
    # mode 660: 소켓 파일 권한 (소유자+그룹 읽기/쓰기)
    # level admin: 관리자 권한 (모든 명령 허용)
    # level operator: 운영자 (서버 on/off, 읽기)
    # level user: 읽기 전용
    # expose-fd listeners: fd 핸들 노출 (소프트 리로드용)

    # TCP 소켓 (원격 접속 가능, 보안 주의)
    stats socket ipv4@127.0.0.1:9999 level admin

    stats timeout 30s   # 소켓 연결 타임아웃
```

```bash
# Stats 소켓 사용 예시
echo "show info" | sudo socat stdio /run/haproxy/admin.sock
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock
echo "show servers state" | sudo socat stdio /run/haproxy/admin.sock
echo "disable server backend1/web1" | sudo socat stdio /run/haproxy/admin.sock

# socat 설치
sudo dnf install -y socat
```

### stats bind-process (deprecated in 2.7+)
```haproxy
global
    # 이전 버전 호환성
    stats bind-process 1
```

---

## 7. tune.* 파라미터 (성능 튜닝)

### tune.bufsize
```haproxy
global
    tune.bufsize 32768   # 버퍼 크기 (바이트), 기본값: 16384
```
- **설명**: HTTP 요청/응답 버퍼 크기
- **영향**: 큰 헤더, 큰 쿠키 처리 가능
- **메모리**: 각 연결당 최소 2개의 버퍼 사용
- **주의**: 늘리면 메모리 사용량 증가

```
메모리 계산: maxconn * 2 * tune.bufsize
예: 50000 * 2 * 32768 = 3.2GB
→ 적절한 균형 필요
```

### tune.maxaccept
```haproxy
global
    tune.maxaccept 100   # 한 번의 accept() 루프에서 최대 연결 수
```
- **설명**: 한 번에 수락할 최대 연결 수
- **기본값**: -1 (자동, 싱글스레드: 1, 멀티스레드: nbthread * 64)
- **효과**: 높은 값 = 더 빠른 연결 수락, 낮은 응답 지연 가능성

### tune.maxrewrite
```haproxy
global
    tune.maxrewrite 1024   # HTTP 재작성에 사용할 최대 바이트
```
- **설명**: HTTP 헤더 추가/수정 시 사용할 버퍼 크기
- **기본값**: tune.bufsize의 1/8 (최대 1024)
- **주의**: tune.bufsize 보다 작아야 함

### tune.rcvbuf.client / tune.rcvbuf.server
```haproxy
global
    tune.rcvbuf.client 32768   # 클라이언트 수신 소켓 버퍼
    tune.rcvbuf.server 32768   # 서버 수신 소켓 버퍼
```
- **설명**: 소켓 수준 수신 버퍼 크기 (SO_RCVBUF)
- **기본값**: OS 기본값 사용 (0)

### tune.sndbuf.client / tune.sndbuf.server
```haproxy
global
    tune.sndbuf.client 32768   # 클라이언트 송신 소켓 버퍼
    tune.sndbuf.server 32768   # 서버 송신 소켓 버퍼
```

### tune.ssl.*
```haproxy
global
    tune.ssl.cachesize 20000       # SSL 세션 캐시 크기 (엔트리 수)
    tune.ssl.lifetime 300          # SSL 세션 캐시 유지 시간 (초)
    tune.ssl.maxrecord 0           # TLS 레코드 최대 크기 (0=최대)
    tune.ssl.default-dh-param 2048 # DH 파라미터 비트 수
    tune.ssl.capture-cipherlist-size 100  # 캡처할 cipher 목록 크기
    tune.ssl.capture-buffer-size 128      # SSL 캡처 버퍼 크기
```

### tune.http.*
```haproxy
global
    tune.http.maxhdr 100           # 최대 HTTP 헤더 수 (기본: 101)
    tune.http.cookielen 1024       # 쿠키 최대 길이
    tune.http.logurilen 1024       # 로그에 기록할 URI 최대 길이
```

### tune.comp.maxlevel
```haproxy
global
    tune.comp.maxlevel 1   # gzip 압축 레벨 (1-9, 기본: 1)
```

### tune.pool-high-fd-ratio / tune.pool-low-fd-ratio
```haproxy
global
    tune.pool-high-fd-ratio 0      # 파일 디스크립터 고갈 방지
    tune.pool-low-fd-ratio 0
```

---

## 8. SSL/TLS 전역 설정

### ssl-default-bind-options
```haproxy
global
    # 클라이언트(bind) SSL 기본 옵션
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

    # 개별 옵션 설명:
    # ssl-min-ver TLSv1.2: TLS 1.2 이상만 허용
    # ssl-min-ver TLSv1.3: TLS 1.3 이상만 허용
    # no-tls-tickets: TLS 세션 티켓 비활성화 (forward secrecy)
    # no-sslv3: SSLv3 비활성화 (deprecated)
    # no-tlsv10: TLS 1.0 비활성화
    # no-tlsv11: TLS 1.1 비활성화
    # force-tlsv12: TLS 1.2 강제
    # force-tlsv13: TLS 1.3 강제
    # allow-0rtt: TLS 1.3 0-RTT 허용
```

### ssl-default-server-options
```haproxy
global
    # 백엔드 서버 연결 시 SSL 기본 옵션
    ssl-default-server-options ssl-min-ver TLSv1.2 no-tls-tickets
```

### ssl-default-bind-ciphers
```haproxy
global
    # TLS 1.2 이하용 cipher suite (OpenSSL 형식)
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384

    # 서버 사이드
    ssl-default-server-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
```

### ssl-default-bind-ciphersuites
```haproxy
global
    # TLS 1.3용 cipher suite
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256

    ssl-default-server-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
```

### ssl-dh-param-file
```haproxy
global
    ssl-dh-param-file /etc/haproxy/dhparam.pem
```
```bash
# DH 파라미터 생성
openssl dhparam -out /etc/haproxy/dhparam.pem 2048
# 또는 4096 비트 (더 안전하지만 느림)
openssl dhparam -out /etc/haproxy/dhparam.pem 4096
```

### ssl-server-verify
```haproxy
global
    # 백엔드 서버의 SSL 인증서 검증 여부
    ssl-server-verify required  # 기본값: 검증 필요
    # ssl-server-verify none    # 검증 안 함 (개발 환경)
```

---

## 9. 기타 전역 설정

### log-send-hostname
```haproxy
global
    log-send-hostname "haproxy-01"   # syslog 메시지에 호스트명 포함
    # 미설정 시 시스템 호스트명 사용
```

### log-tag
```haproxy
global
    log-tag haproxy   # syslog 메시지 태그 (프로그램명)
```

### spread-checks
```haproxy
global
    spread-checks 5   # 헬스체크 분산 (0-50%)
```
- **설명**: 헬스체크가 동시에 실행되는 것을 방지
- **값**: 0-50 (퍼센트 기준 무작위 지연 추가)
- **예**: 5 = ±5% 지연으로 동시 체크 분산

### tune.idle-pool-shared
```haproxy
global
    tune.idle-pool-shared on   # 유휴 연결 풀 스레드 간 공유
```

### server-state-file
```haproxy
global
    server-state-file /etc/haproxy/server-state
```
- **설명**: 서버 상태를 파일에 저장/복원 (재시작 시 이전 상태 유지)

```haproxy
# backend 또는 defaults에서 활성화
defaults
    load-server-state-from-file global
```

### description
```haproxy
global
    description "Production HAProxy - Web Cluster"
```
- **설명**: 통계 페이지에 표시될 설명

### node
```haproxy
global
    node "haproxy-prod-01"
```
- **설명**: HA 환경에서 노드 식별자 (통계 페이지에 표시)

### environment
```haproxy
global
    setenv MY_VAR "my_value"        # 환경 변수 설정
    setenv DEBUG_MODE "false"
    resetenv UNNEEDED_VAR           # 환경 변수 제거
```

---

## 10. 고급 global 설정

### presetenv / resetenv
```haproxy
global
    presetenv HAPROXY_VERSION "2.8"   # 시작 전 환경 변수 설정
```

### wurfl-data-file (모바일 디바이스 감지)
```haproxy
global
    wurfl-data-file /etc/haproxy/wurfl.xml
```

### 51degrees-data-file (디바이스 감지)
```haproxy
global
    51degrees-data-file /etc/haproxy/51degrees.dat
```

### deviceatlas-json-file
```haproxy
global
    deviceatlas-json-file /etc/haproxy/deviceatlas.json
```

### h1-case-adjust
```haproxy
global
    # HTTP/1.1 헤더 대소문자 조정 (레거시 서버 호환성)
    h1-case-adjust content-type Content-Type
    h1-case-adjust-file /etc/haproxy/h1-case-adjust.txt
```

---

## 11. 완전한 global 섹션 예시

### 개발 환경
```haproxy
global
    maxconn 1000
    log 127.0.0.1 local0 debug
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
```

### 소규모 프로덕션 (2-4 코어, 8GB RAM)
```haproxy
global
    maxconn 20000
    ulimit-n 100000

    user haproxy
    group haproxy
    daemon

    chroot /var/lib/haproxy
    pidfile /run/haproxy.pid

    log 127.0.0.1 local0 notice

    nbthread 4
    cpu-map auto:1/1-4 0-3

    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s

    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

    tune.ssl.default-dh-param 2048
    tune.bufsize 32768
    tune.maxrewrite 1024

    spread-checks 5
    server-state-file /etc/haproxy/server-state

    description "Production HAProxy v2.8"
    node "haproxy-prod-01"
```

### 대규모 프로덕션 (16+ 코어, 32GB RAM)
```haproxy
global
    maxconn 200000
    maxconnrate 10000
    maxsessrate 20000
    maxsslconn 100000
    maxsslrate 1000
    ulimit-n 500000

    user haproxy
    group haproxy
    daemon

    chroot /var/lib/haproxy
    pidfile /run/haproxy.pid

    log 127.0.0.1 local0 notice
    log 127.0.0.1 local1 notice

    nbthread 16
    cpu-map auto:1/1-16 0-15

    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s

    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    ssl-default-server-options ssl-min-ver TLSv1.2
    ssl-server-verify required

    tune.ssl.default-dh-param 2048
    tune.ssl.cachesize 100000
    tune.ssl.lifetime 300

    tune.bufsize 32768
    tune.maxrewrite 4096
    tune.maxaccept 200

    tune.rcvbuf.client 0
    tune.sndbuf.client 0

    spread-checks 5
    server-state-file /etc/haproxy/server-state

    description "High-Traffic Production HAProxy v2.8"
    node "haproxy-prod-cluster-01"
```

---

## 12. global 설정 확인 방법

```bash
# 현재 설정 확인
echo "show info" | sudo socat stdio /run/haproxy/admin.sock

# 주요 항목:
# MaxConn: 설정된 maxconn 값
# Maxpipes: 최대 파이프 수
# CurrConns: 현재 연결 수
# MaxConnRate: 초당 최대 연결 수
# Threads: 스레드 수

# 상세 정보
echo "show info typed" | sudo socat stdio /run/haproxy/admin.sock | head -50

# 버전 및 빌드 옵션
haproxy -vv

# 현재 설정 파일 덤프
echo "show config" | sudo socat stdio /run/haproxy/admin.sock
```
