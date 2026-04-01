# HAProxy 트러블슈팅 가이드

---

## 1. 설정 파일 검증

### 설정 문법 검증
```bash
# 기본 검증
sudo haproxy -f /etc/haproxy/haproxy.cfg -c

# 여러 파일 검증
sudo haproxy -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d/ -c

# 자세한 출력
sudo haproxy -f /etc/haproxy/haproxy.cfg -c -V

# 정상 시 출력:
# Configuration file is valid
```

### 자주 나오는 설정 오류
| 오류 메시지 | 원인 | 해결 방법 |
|------------|------|-----------|
| `parsing [haproxy.cfg:10]: unknown keyword 'xxx'` | 오타 또는 잘못된 섹션에 지시어 | 지시어 위치와 스펠링 확인 |
| `timeout: missing value` | timeout 값 누락 | 시간 단위 포함한 값 추가 |
| `server xxx: unknown keyword 'yyy'` | server 파라미터 오타 | 파라미터 스펠링 확인 |
| `bind: address already in use` | 포트 충돌 | `ss -tlnp \| grep <port>` 로 확인 |
| `cannot bind socket` | 권한 없음 (1024 이하 포트) | root 실행 또는 cap_net_bind_service |

---

## 2. 서비스 상태 확인

```bash
# 서비스 상태
sudo systemctl status haproxy

# 상세 로그
sudo journalctl -u haproxy -f
sudo journalctl -u haproxy --since "1 hour ago"

# 프로세스 확인
ps aux | grep haproxy
ls -la /proc/$(cat /run/haproxy.pid)/

# 파일 디스크립터 수 확인
cat /proc/$(cat /run/haproxy.pid)/limits | grep "open files"
ls /proc/$(cat /run/haproxy.pid)/fd | wc -l
```

---

## 3. 서버 상태 확인

```bash
# 모든 서버/백엔드 상태
echo "show servers state" | socat /run/haproxy/admin.sock stdio

# 통계 CSV (pxname, svname, status, check_status 등)
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' 'NR==1 || $18=="DOWN" || $18=="MAINT"'

# 특정 백엔드만
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    grep "^web_backend"

# 서버 상태 요약
echo "show health" | socat /run/haproxy/admin.sock stdio

# 서버 상태 의미
# UP    - 정상
# DOWN  - 헬스체크 실패
# NOLB  - 헬스체크 NOLB 응답 (로드밸런서에서 제외)
# MAINT - 수동으로 관리 모드
# DRAIN - 새 연결 거부, 기존 연결만 유지
```

---

## 4. 연결 문제 진단

### 클라이언트가 연결 안 됨
```bash
# 1. HAProxy 포트 리스닝 확인
ss -tlnp | grep haproxy
# 또는
netstat -tlnp | grep haproxy

# 2. 방화벽 확인
sudo firewall-cmd --list-all
# 또는
sudo iptables -L -n | grep <port>

# 3. SELinux 확인 (AL2023)
sudo sestatus
sudo ausearch -m avc -ts recent
sudo sealert -a /var/log/audit/audit.log

# SELinux 포트 허용
sudo semanage port -a -t http_port_t -p tcp 8080

# 4. 연결 테스트
curl -v http://localhost:80/
telnet localhost 80

# 5. 실시간 연결 수 확인
echo "show info" | socat /run/haproxy/admin.sock stdio | grep "CurrConns"
```

### 백엔드 서버 연결 안 됨
```bash
# 1. 서버 직접 연결 테스트 (HAProxy 건너뜀)
curl -v http://10.0.0.1:8080/health

# 2. HAProxy 서버에서 백엔드 서버 연결 테스트
nc -zv 10.0.0.1 8080
telnet 10.0.0.1 8080

# 3. 라우팅 확인
traceroute 10.0.0.1
ip route get 10.0.0.1

# 4. DNS 해결 확인
nslookup backend.example.com
dig backend.example.com

# 5. 서버 측 방화벽 확인 (HAProxy IP → 서버 포트)
```

---

## 5. 헬스체크 실패 원인 분석

```bash
# 헬스체크 상태 확인
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' '{print $1,$2,$18,$19,$20}' | column -t

# 헬스체크 로그 활성화
# haproxy.cfg에 추가:
# option log-health-checks

# 로그에서 헬스체크 실패 확인
grep "health check" /var/log/haproxy.log | tail -20

# 직접 헬스체크 시뮬레이션
# HTTP 헬스체크
curl -v -o /dev/null -w "%{http_code}" http://10.0.0.1:8080/health

# TCP 헬스체크
nc -zv -w 3 10.0.0.1 8080

# Redis 헬스체크
echo -e "PING\r\n" | nc -q 1 10.0.0.1 6379

# MySQL 헬스체크
mysql -h 10.0.0.1 -P 3306 -u haproxy_check -e "SELECT 1;"
```

### 헬스체크 실패 원인별 해결
| 증상 | 원인 | 해결 방법 |
|------|------|-----------|
| `Connection refused` | 서버 포트 닫힘 | 서버 애플리케이션 실행 확인 |
| `Connection timeout` | 네트워크 문제 또는 방화벽 | 라우팅/방화벽 확인 |
| `HTTP 404` | 헬스체크 경로 없음 | option httpchk 경로 확인 |
| `HTTP 500` | 서버 오류 | 서버 로그 확인 |
| `SSL handshake failed` | SSL 인증서 문제 | 인증서 유효성 확인 |

---

## 6. 타임아웃 문제

### 타임아웃 유형별 분석
```
# 로그에서 타임아웃 코드 확인
# tsc 필드의 값:
# cD - client disconnect
# sD - server disconnect
# cT - client timeout
# sT - server timeout
# cR - client request timeout
# sQ - server queue timeout
# sC - server connect timeout
# --  - 정상

grep " 408 " /var/log/haproxy.log | tail -10  # 요청 타임아웃
grep " 504 " /var/log/haproxy.log | tail -10  # 게이트웨이 타임아웃

# 타임아웃 설정 확인
echo "show info" | socat /run/haproxy/admin.sock stdio | grep -i timeout
```

### 타임아웃 조정
```
defaults
    timeout connect  5s     # 서버 연결 타임아웃 (짧게)
    timeout client   60s    # 클라이언트 유휴 타임아웃
    timeout server   60s    # 서버 응답 타임아웃 (느린 쿼리 고려)
    timeout http-request 30s  # HTTP 요청 완료 타임아웃 (너무 작으면 대용량 업로드 실패)
    timeout tunnel  1h      # WebSocket, 터널 타임아웃

# WebSocket/SSE 연결이 끊기는 경우:
# timeout tunnel 충분히 크게 설정
```

---

## 7. 성능 문제 진단

### 연결 수 확인
```bash
# 현재 연결 수
echo "show info" | socat /run/haproxy/admin.sock stdio | \
    grep -E "CurrConns|MaxConn|Uptime"

# 초당 요청 수
watch -n 1 'echo "show info" | socat /run/haproxy/admin.sock stdio | grep -E "Req|Conn"'

# 큐 대기 중인 요청
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' '{if ($3+0 > 0) print $1,$2,"queue="$3}'
```

### 높은 큐 대기 시간
원인: 서버의 maxconn 초과
```bash
# 해결: maxconn 증가 또는 서버 추가
echo "show servers state" | socat /run/haproxy/admin.sock stdio

# 임시 해결: 서버 maxconn 늘리기 (Runtime API)
# (서버 재시작 불필요)
# 설정 파일에서 server 지시어의 maxconn 값 증가 후 reload
```

### maxconn 부족
```bash
# maxconn 한계에 도달했는지 확인
echo "show info" | socat /run/haproxy/admin.sock stdio | \
    grep -E "MaxConn|CurrConns|MaxConnReached"

# global maxconn 증가 후 reload 필요
```

---

## 8. SSL/TLS 문제

```bash
# SSL 연결 테스트
openssl s_client -connect example.com:443 -servername example.com

# 인증서 정보 확인
openssl x509 -in /etc/haproxy/certs/example.pem -text -noout | head -30

# 인증서 만료 확인
openssl x509 -in /etc/haproxy/certs/example.pem -noout -enddate

# 인증서 유효성 (체인 포함)
openssl verify -CAfile /etc/ssl/certs/ca-bundle.crt /etc/haproxy/certs/example.pem

# SNI 테스트
openssl s_client -connect 10.0.0.1:443 -servername example.com

# TLS 버전 테스트
openssl s_client -connect example.com:443 -tls1_2  # TLS 1.2 강제
openssl s_client -connect example.com:443 -tls1_3  # TLS 1.3 강제

# Cipher suite 확인
nmap --script ssl-enum-ciphers -p 443 example.com

# 일반적인 SSL 오류
# SSL_ERROR_RX_RECORD_TOO_LONG - HTTP 포트로 HTTPS 요청
# NO_SHARED_CIPHER - 클라이언트/서버 cipher 불일치
# CERTIFICATE_VERIFY_FAILED - 인증서 검증 실패
```

---

## 9. 로그 분석

### 주요 로그 패턴 분석
```bash
# 에러 코드별 통계
grep -oP '"[A-Z]+ .+? HTTP/[0-9.]+"' /var/log/haproxy.log | \
    sort | uniq -c | sort -rn | head -20

# 상태 코드별 통계
awk '{print $NF}' /var/log/haproxy.log | sort | uniq -c | sort -rn

# 특정 클라이언트 IP 추적
grep "192.168.1.100" /var/log/haproxy.log | tail -20

# 느린 요청 (응답 시간 > 5초 = 5000ms)
awk -F'/' '$7 > 5000 {print}' /var/log/haproxy.log | tail -20

# 5xx 에러 추적
grep " 5[0-9][0-9] " /var/log/haproxy.log | tail -30

# 서버별 에러 통계
grep " 5[0-9][0-9] " /var/log/haproxy.log | \
    awk '{print $9}' | sort | uniq -c | sort -rn
```

### 로그 형식 이해
```
# HTTP 로그 예시:
# Feb 15 10:30:01 haproxy[1234]: 192.168.1.1:45678 [15/Feb/2024:10:30:01.123] front~back/web1 10/0/1/15/26 200 1234 - - ---- 5/4/3/1/0 0/0 "GET /api/users HTTP/1.1"
#
# 필드 설명:
# 192.168.1.1:45678  → 클라이언트 IP:포트
# [타임스탬프]        → 요청 수신 시각
# front~back/web1    → 프론트엔드~백엔드/서버
# 10/0/1/15/26       → Tq/Tw/Tc/Tr/Ta (ms)
#   Tq: 요청 수신까지
#   Tw: 큐 대기 시간
#   Tc: 서버 연결 시간
#   Tr: 서버 응답 시간
#   Ta: 총 시간
# 200                → HTTP 상태 코드
# 1234               → 응답 바이트
# ---- 5/4/3/1/0 0/0 → 세션 카운터
```

---

## 10. 디버그 모드

```bash
# 포그라운드 디버그 모드 (별도 터미널에서)
sudo haproxy -f /etc/haproxy/haproxy.cfg -d

# 연결 추적 (socat으로)
echo "debug dev" | socat /run/haproxy/admin.sock stdio

# 특정 요청 추적 (로그 레벨 높이기)
# global에 추가:
# log 127.0.0.1 local0 debug

# 실시간 로그 스트리밍
sudo journalctl -u haproxy -f --output cat

# tcpdump로 패킷 분석
sudo tcpdump -i any -n "port 80 or port 443" -w /tmp/haproxy.pcap
# Wireshark로 /tmp/haproxy.pcap 분석

# strace로 시스템 콜 추적
sudo strace -p $(cat /run/haproxy.pid) -e trace=network -s 200
```

---

## 11. 일반적인 문제와 해결책

### 503 Service Unavailable
```bash
# 원인 1: 모든 서버 DOWN
echo "show servers state" | socat /run/haproxy/admin.sock stdio

# 서버를 강제로 UP 표시 (임시)
echo "set server backend/server1 health up" | socat /run/haproxy/admin.sock stdio

# 원인 2: maxconn 초과
echo "show info" | socat /run/haproxy/admin.sock stdio | grep Conn

# 원인 3: 큐 가득 참
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' '{print $1,$2,$3}'  # $3 = queue 수
```

### 연결이 특정 서버에만 집중되는 경우
```bash
# 서버 가중치 확인
echo "show servers state" | socat /run/haproxy/admin.sock stdio

# 로드밸런싱 알고리즘 확인 (설정 파일에서 balance 지시어)

# roundrobin인데 한 서버에 집중 → 다른 서버 DOWN 상태일 수 있음
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' '{print $1,$2,$18}'  # status 컬럼
```

### 메모리 사용량 높음
```bash
# 메모리 사용 확인
echo "show info" | socat /run/haproxy/admin.sock stdio | grep -i mem
# MemMax_MB, MemSo_MB, PoolUsed_MB, PoolFailed

# stick-table 크기 확인
echo "show table" | socat /run/haproxy/admin.sock stdio

# tune.bufsize, maxconn 조정 검토
```

### reload 후 구 연결이 끊기는 경우
```bash
# -sf 옵션 사용 (soft finish: 기존 연결 완료 후 종료)
haproxy -f /etc/haproxy/haproxy.cfg -sf $(cat /run/haproxy.pid)

# systemctl reload도 -sf 사용 (ExecReload 설정 확인)
# ExecReload=/bin/kill -USR2 $MAINPID
```

---

## 12. 유용한 진단 스크립트

### 전체 상태 요약
```bash
#!/bin/bash
# haproxy-status.sh

SOCK=/run/haproxy/admin.sock

echo "=== HAProxy 기본 정보 ==="
echo "show info" | socat $SOCK stdio | grep -E "Version|Uptime|Process_num|CurrConns|MaxConn"

echo ""
echo "=== 서버 상태 요약 ==="
echo "show servers state" | socat $SOCK stdio | \
    awk 'NR>1 {printf "%-20s %-15s %-10s %-10s\n", $2, $3, $4, $5}' | head -30

echo ""
echo "=== DOWN 서버 ==="
echo "show stat" | socat $SOCK stdio | \
    awk -F',' '$18=="DOWN" {print $1"/"$2" - 체크:"$22" 마지막:"$28}'

echo ""
echo "=== 초당 요청 수 ==="
echo "show info" | socat $SOCK stdio | grep -E "Req|Sess"
```

### 자동 알림 스크립트
```bash
#!/bin/bash
# haproxy-alert.sh - DOWN 서버 감지 시 슬랙 알림

SOCK=/run/haproxy/admin.sock
SLACK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

DOWN_SERVERS=$(echo "show stat" | socat $SOCK stdio | \
    awk -F',' '$18=="DOWN" && $1!="BACKEND" {print $1"/"$2}')

if [ -n "$DOWN_SERVERS" ]; then
    MSG="HAProxy DOWN 서버 감지!\n${DOWN_SERVERS}"
    curl -s -X POST $SLACK_URL \
        -H 'Content-type: application/json' \
        --data "{\"text\":\"$MSG\"}"
fi
```
