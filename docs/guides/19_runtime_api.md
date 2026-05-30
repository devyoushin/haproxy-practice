# HAProxy Runtime API (소켓 API) 완전 가이드

Runtime API를 통해 HAProxy를 재시작하지 않고 실시간으로 서버 상태 변경,
설정 조회, 세션 제어, ACL/맵 수정 등을 할 수 있습니다.

---

## 1. 소켓 설정

```haproxy
global
    # Unix 도메인 소켓 (파일 시스템)
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners

    # TCP 소켓 (원격 접근)
    stats socket ipv4@127.0.0.1:9999 level operator

    # 외부 접근용 (주의: 방화벽으로 보호 필요)
    stats socket ipv4@0.0.0.0:9999 level user

    # 소켓 타임아웃
    stats timeout 2m
```

---

## 2. 권한 레벨

| 레벨 | 설명 | 허용 작업 |
|------|------|---------|
| `user` | 읽기 전용 | 통계, 상태 조회만 |
| `operator` | 운영자 | 통계 조회 + 서버 상태 변경 |
| `admin` | 관리자 | 모든 작업 |

```haproxy
# 레벨별 소켓 예시
stats socket /run/haproxy/admin.sock    mode 660 level admin
stats socket /run/haproxy/operator.sock mode 664 level operator
stats socket /run/haproxy/monitor.sock  mode 666 level user
```

---

## 3. 소켓 접근 방법

```bash
# socat (권장)
echo "show info" | socat /run/haproxy/admin.sock stdio

# nc (netcat)
echo "show info" | nc -U /run/haproxy/admin.sock

# TCP 소켓
echo "show info" | socat TCP:127.0.0.1:9999 stdio

# Python으로 접근
python3 -c "
import socket
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect('/run/haproxy/admin.sock')
s.send(b'show info\n')
print(s.recv(65536).decode())
s.close()
"
```

---

## 4. 정보 조회 명령어

### 4.1 도움말
```bash
echo "help" | socat /run/haproxy/admin.sock stdio
```

### 4.2 HAProxy 전체 정보
```bash
echo "show info" | socat /run/haproxy/admin.sock stdio
```

주요 출력:
```
Name: HAProxy
Version: 2.8.3
Release_date: 2023/09/11
Nbthread: 4
Pid: 12345
Uptime: 1d 5h 30m
CurrConns: 523
MaxConn: 50000
CurrSessRate: 150
MaxSessRate: 5000
BytesIn: 1234567890
BytesOut: 9876543210
Idle_pct: 87
```

### 4.3 통계 (CSV 형식)
```bash
echo "show stat" | socat /run/haproxy/admin.sock stdio

# 특정 frontend/backend만
echo "show stat web_frontend" | socat /run/haproxy/admin.sock stdio

# CSV를 보기 쉽게 출력
echo "show stat" | socat /run/haproxy/admin.sock stdio | \
    awk -F',' '{print $1, $2, $18, $5}' | column -t

# 헤더 포함 (# 주석 제거)
echo "show stat" | socat /run/haproxy/admin.sock stdio | grep -v "^#" | \
    awk -F',' '{printf "%-20s %-20s %-10s %s\n", $1, $2, $18, $5}'
```

### 4.4 헬스체크 상태
```bash
echo "show health" | socat /run/haproxy/admin.sock stdio
```

### 4.5 서버 상태 상세
```bash
echo "show servers state" | socat /run/haproxy/admin.sock stdio
echo "show servers state web_backend" | socat /run/haproxy/admin.sock stdio
```

출력 형식:
```
1
# be_id be_name srv_id srv_name srv_addr srv_op_state srv_admin_state srv_uweight srv_iweight srv_time_since_last_change srv_check_status srv_check_result srv_check_health srv_check_state srv_agent_state bk_f_forced_id srv_f_forced_id srv_fqdn srv_port srvrecord
3 web_backend 1 web1 10.0.0.1 2 0 100 100 300 6 3 4 6 0 0 0 - 80 -
3 web_backend 2 web2 10.0.0.2 2 0 100 100 295 6 3 4 6 0 0 0 - 80 -
```

### 4.6 현재 세션 목록
```bash
# 모든 세션
echo "show sess" | socat /run/haproxy/admin.sock stdio

# 최근 20개만
echo "show sess" | socat /run/haproxy/admin.sock stdio | head -20

# 특정 세션 상세 정보
echo "show sess <session_id>" | socat /run/haproxy/admin.sock stdio
```

### 4.7 메모리 풀 정보
```bash
echo "show pools" | socat /run/haproxy/admin.sock stdio
```

### 4.8 스레드 정보
```bash
echo "show threads" | socat /run/haproxy/admin.sock stdio
```

---

## 5. 서버 제어 명령어

### 5.1 서버 활성화/비활성화
```bash
# 서버 활성화 (ready 상태로)
echo "enable server web_backend/web1" | socat /run/haproxy/admin.sock stdio

# 서버 비활성화 (MAINT 상태로)
echo "disable server web_backend/web1" | socat /run/haproxy/admin.sock stdio
```

### 5.2 서버 상태 직접 설정
```bash
# READY 상태 (정상 운영)
echo "set server web_backend/web1 state ready" | socat /run/haproxy/admin.sock stdio

# MAINT 상태 (유지보수 모드 - 헬스체크 중지, 새 연결 거부)
echo "set server web_backend/web1 state maint" | socat /run/haproxy/admin.sock stdio

# DRAIN 상태 (새 연결 거부, 기존 연결 유지)
echo "set server web_backend/web1 state drain" | socat /run/haproxy/admin.sock stdio
```

### 5.3 가중치 변경
```bash
# 절대값으로 가중치 설정 (0-256)
echo "set weight web_backend/web1 50" | socat /run/haproxy/admin.sock stdio

# 퍼센트로 설정 (설정 파일의 가중치 기준)
echo "set weight web_backend/web1 50%" | socat /run/haproxy/admin.sock stdio

# 현재 가중치 조회
echo "get weight web_backend/web1" | socat /run/haproxy/admin.sock stdio
```

### 5.4 헬스체크 결과 강제 설정
```bash
# 헬스체크 결과 무시하고 UP으로 강제 설정
echo "set server web_backend/web1 health up" | socat /run/haproxy/admin.sock stdio

# DOWN으로 강제 설정
echo "set server web_backend/web1 health down" | socat /run/haproxy/admin.sock stdio

# 헬스체크 결과 사용 (기본값으로 돌아감)
echo "set server web_backend/web1 check-port 80" | socat /run/haproxy/admin.sock stdio
```

### 5.5 서버 주소 동적 변경
```bash
# IP 주소 변경
echo "set server web_backend/web1 addr 10.0.0.5" | socat /run/haproxy/admin.sock stdio

# IP + 포트 변경
echo "set server web_backend/web1 addr 10.0.0.5 port 8080" | socat /run/haproxy/admin.sock stdio

# FQDN으로 변경
echo "set server web_backend/web1 fqdn new-web-server.example.com" | socat /run/haproxy/admin.sock stdio
```

### 5.6 헬스체크 포트 변경
```bash
echo "set server web_backend/web1 check-port 9090" | socat /run/haproxy/admin.sock stdio
```

---

## 6. 세션 제어

```bash
# 특정 서버의 모든 세션 종료
echo "shutdown sessions server web_backend/web1" | socat /run/haproxy/admin.sock stdio

# 특정 세션 종료 (세션 ID 필요)
echo "shutdown session <session_id>" | socat /run/haproxy/admin.sock stdio

# 세션 ID는 show sess로 확인
echo "show sess" | socat /run/haproxy/admin.sock stdio | awk '{print $1}'
```

---

## 7. 맵(Map) 동적 수정

맵 파일은 키-값 매핑을 제공하며, Runtime API로 동적으로 수정 가능합니다.

```bash
# 맵 목록 확인
echo "show map" | socat /run/haproxy/admin.sock stdio

# 특정 맵 내용 확인
echo "show map /etc/haproxy/domains.map" | socat /run/haproxy/admin.sock stdio

# 항목 추가
echo "add map /etc/haproxy/domains.map example.com api_backend" | socat /run/haproxy/admin.sock stdio

# 항목 수정 (기존 값 덮어쓰기)
echo "set map /etc/haproxy/domains.map example.com new_backend" | socat /run/haproxy/admin.sock stdio

# 항목 삭제 (키로)
echo "del map /etc/haproxy/domains.map example.com" | socat /run/haproxy/admin.sock stdio

# ID로 삭제
echo "del map #1" | socat /run/haproxy/admin.sock stdio

# 특정 키 값 조회
echo "get map /etc/haproxy/domains.map example.com" | socat /run/haproxy/admin.sock stdio
```

---

## 8. ACL 동적 수정

```bash
# ACL 목록 확인
echo "show acl" | socat /run/haproxy/admin.sock stdio

# 특정 ACL 파일 내용 확인
echo "show acl /etc/haproxy/blacklist.txt" | socat /run/haproxy/admin.sock stdio

# 항목 추가 (IP 차단)
echo "add acl /etc/haproxy/blacklist.txt 1.2.3.4" | socat /run/haproxy/admin.sock stdio
echo "add acl /etc/haproxy/blacklist.txt 10.20.30.0/24" | socat /run/haproxy/admin.sock stdio

# 항목 삭제 (값으로)
echo "del acl /etc/haproxy/blacklist.txt 1.2.3.4" | socat /run/haproxy/admin.sock stdio

# 특정 패턴 검색
echo "get acl /etc/haproxy/blacklist.txt 1.2.3.4" | socat /run/haproxy/admin.sock stdio
```

---

## 9. Stick Table 조작

```bash
# 테이블 목록 확인
echo "show table" | socat /run/haproxy/admin.sock stdio

# 특정 테이블 내용 확인 (전체)
echo "show table web_frontend" | socat /run/haproxy/admin.sock stdio

# 특정 키 조회
echo "show table web_frontend key 192.168.1.1" | socat /run/haproxy/admin.sock stdio

# 필터링 (data.conn_cur > 10인 항목)
echo "show table web_frontend data.conn_cur gt 10" | socat /run/haproxy/admin.sock stdio

# 데이터 수정 (gpc0를 1로 설정 = 차단 플래그)
echo "set table web_frontend key 1.2.3.4 data.gpc0 1" | socat /run/haproxy/admin.sock stdio

# 데이터 수정 (http_req_rate 초기화)
echo "set table web_frontend key 1.2.3.4 data.http_req_rate 0" | socat /run/haproxy/admin.sock stdio

# 특정 항목 삭제
echo "clear table web_frontend key 1.2.3.4" | socat /run/haproxy/admin.sock stdio

# 테이블 전체 삭제 (주의!)
echo "clear table web_frontend" | socat /run/haproxy/admin.sock stdio
```

---

## 10. 헬스체크 제어

```bash
# 헬스체크 활성화/비활성화
echo "enable health web_backend/web1" | socat /run/haproxy/admin.sock stdio
echo "disable health web_backend/web1" | socat /run/haproxy/admin.sock stdio

# 에이전트 체크 활성화/비활성화
echo "enable agent web_backend/web1" | socat /run/haproxy/admin.sock stdio
echo "disable agent web_backend/web1" | socat /run/haproxy/admin.sock stdio

# 즉시 헬스체크 실행 (디버깅용)
# (직접 명령어는 없으나 inter를 0으로 설정하면 즉시 체크)
```

---

## 11. 프론트엔드 제어

```bash
# 프론트엔드 활성화/비활성화
echo "enable frontend web_frontend" | socat /run/haproxy/admin.sock stdio
echo "disable frontend web_frontend" | socat /run/haproxy/admin.sock stdio

# 프론트엔드 maxconn 변경
echo "set maxconn frontend web_frontend 20000" | socat /run/haproxy/admin.sock stdio

# 전역 maxconn 변경
echo "set maxconn global 100000" | socat /run/haproxy/admin.sock stdio
```

---

## 12. 실용적인 스크립트 예시

### 12.1 무중단 배포 스크립트 (블루-그린)
```bash
#!/bin/bash
# graceful-deploy.sh - 무중단 배포

SOCKET="/run/haproxy/admin.sock"
BACKEND="web_backend"
OLD_SERVERS=("web1" "web2" "web3")
NEW_SERVERS=("web4" "web5" "web6")

deploy() {
    echo "=== 무중단 배포 시작 ==="

    # 1. 새 서버 활성화 (MAINT → READY)
    for srv in "${NEW_SERVERS[@]}"; do
        echo "새 서버 활성화: $srv"
        echo "set server ${BACKEND}/${srv} state ready" | socat "$SOCKET" stdio
    done

    # 잠시 대기 (새 서버 워밍업)
    sleep 10

    # 2. 새 서버 헬스체크 확인
    for srv in "${NEW_SERVERS[@]}"; do
        status=$(echo "show servers state ${BACKEND}" | socat "$SOCKET" stdio | \
                 awk -v s="$srv" '$4==s {print $6}')
        if [ "$status" != "2" ]; then  # 2 = UP
            echo "ERROR: 새 서버 $srv가 UP 상태가 아닙니다 (상태: $status)"
            exit 1
        fi
        echo "새 서버 $srv 상태: UP ✓"
    done

    # 3. 기존 서버를 DRAIN 상태로 (새 연결 차단, 기존 연결 완료 대기)
    for srv in "${OLD_SERVERS[@]}"; do
        echo "기존 서버 DRAIN 처리: $srv"
        echo "set server ${BACKEND}/${srv} state drain" | socat "$SOCKET" stdio
    done

    echo "기존 서버 드레인 대기 중 (30초)..."
    sleep 30

    # 4. 기존 서버 세션 종료 및 MAINT로 변경
    for srv in "${OLD_SERVERS[@]}"; do
        echo "기존 서버 세션 종료: $srv"
        echo "shutdown sessions server ${BACKEND}/${srv}" | socat "$SOCKET" stdio
        echo "set server ${BACKEND}/${srv} state maint" | socat "$SOCKET" stdio
    done

    echo "=== 배포 완료 ==="
}

rollback() {
    echo "=== 롤백 시작 ==="

    # 기존 서버 복구
    for srv in "${OLD_SERVERS[@]}"; do
        echo "기존 서버 복구: $srv"
        echo "set server ${BACKEND}/${srv} state ready" | socat "$SOCKET" stdio
    done

    sleep 5

    # 새 서버 비활성화
    for srv in "${NEW_SERVERS[@]}"; do
        echo "새 서버 비활성화: $srv"
        echo "set server ${BACKEND}/${srv} state maint" | socat "$SOCKET" stdio
    done

    echo "=== 롤백 완료 ==="
}

case "${1:-}" in
    deploy)   deploy ;;
    rollback) rollback ;;
    *)
        echo "Usage: $0 {deploy|rollback}"
        exit 1
        ;;
esac
```

### 12.2 카나리 배포 스크립트
```bash
#!/bin/bash
# canary-deploy.sh - 카나리 배포

SOCKET="/run/haproxy/admin.sock"
BACKEND="web_backend"
CANARY_SERVER="web_canary"
NORMAL_WEIGHT=100

# 카나리 서버에 트래픽 점진적으로 증가
canary_deploy() {
    local percentages=(10 25 50 75 100)

    for pct in "${percentages[@]}"; do
        echo "카나리 서버 가중치 ${pct}%로 설정..."
        echo "set weight ${BACKEND}/${CANARY_SERVER} ${pct}%" | socat "$SOCKET" stdio

        echo "${pct}% 트래픽 라우팅 중... (30초 모니터링)"
        sleep 30

        # 에러율 확인
        error_rate=$(echo "show stat" | socat "$SOCKET" stdio | \
                     awk -F',' -v backend="$BACKEND" -v server="$CANARY_SERVER" \
                     '$1==backend && $2==server {print $15}')

        echo "현재 에러 수: ${error_rate:-0}"

        if [ "${error_rate:-0}" -gt 10 ]; then
            echo "에러율 높음! 롤백합니다."
            echo "set weight ${BACKEND}/${CANARY_SERVER} 0%" | socat "$SOCKET" stdio
            exit 1
        fi
    done

    echo "카나리 배포 완료! 카나리 서버가 100% 트래픽 수신 중."
}

canary_deploy
```

### 12.3 서버 상태 모니터링 스크립트
```bash
#!/bin/bash
# monitor-servers.sh - 서버 상태 모니터링

SOCKET="/run/haproxy/admin.sock"

while true; do
    clear
    echo "=== HAProxy Server Status $(date) ==="
    echo ""

    # 서버 상태 표시
    echo "BACKEND          SERVER               STATUS    WEIGHT  SESSIONS  ERRORS"
    echo "--------------------------------------------------------------------"

    echo "show stat" | socat "$SOCKET" stdio | \
    awk -F',' '
    NR > 1 && $2 != "FRONTEND" && $2 != "BACKEND" {
        status = $18
        if (status == "UP")   status_fmt = "\033[32m" status "\033[0m"
        else if (status == "DOWN") status_fmt = "\033[31m" status "\033[0m"
        else status_fmt = "\033[33m" status "\033[0m"

        printf "%-20s %-20s %-10s %-8s %-10s %s\n", $1, $2, status, $19, $5, $13
    }'

    echo ""
    echo "--- 전체 통계 ---"
    echo "show info" | socat "$SOCKET" stdio | \
        awk '/CurrConns|CurrSessRate|BytesIn|BytesOut|Idle_pct/{printf "%-20s %s\n", $1, $2}'

    sleep 5
done
```

---

## 13. API 명령어 전체 목록 요약

### 조회 명령어
| 명령어 | 설명 |
|--------|------|
| `help` | 도움말 |
| `show info` | HAProxy 상태 정보 |
| `show stat` | 통계 (CSV) |
| `show stat <proxy>` | 특정 프록시 통계 |
| `show health` | 헬스체크 상태 |
| `show pools` | 메모리 풀 정보 |
| `show sess` | 세션 목록 |
| `show sess <id>` | 특정 세션 상세 |
| `show table` | Stick Table 목록 |
| `show table <name>` | 테이블 내용 |
| `show table <name> key <k>` | 특정 키 조회 |
| `show map` | 맵 목록 |
| `show map <file>` | 맵 내용 |
| `show acl` | ACL 목록 |
| `show acl <file>` | ACL 내용 |
| `show servers state` | 서버 상태 |
| `show threads` | 스레드 정보 |
| `show peers` | 피어 동기화 상태 |
| `show resolvers` | DNS 리졸버 상태 |
| `get weight <be>/<srv>` | 서버 가중치 조회 |
| `get map <file> <key>` | 맵 항목 조회 |
| `get acl <file> <value>` | ACL 항목 조회 |

### 서버 제어
| 명령어 | 설명 |
|--------|------|
| `enable server <be>/<srv>` | 서버 활성화 |
| `disable server <be>/<srv>` | 서버 비활성화 (MAINT) |
| `set server <be>/<srv> state <state>` | 상태 설정 |
| `set server <be>/<srv> health <state>` | 헬스체크 결과 강제 설정 |
| `set server <be>/<srv> weight <n>` | 가중치 설정 |
| `set server <be>/<srv> addr <ip> [port <n>]` | 주소 변경 |
| `set server <be>/<srv> fqdn <name>` | FQDN 변경 |
| `set server <be>/<srv> check-port <n>` | 헬스체크 포트 변경 |
| `enable health <be>/<srv>` | 헬스체크 활성화 |
| `disable health <be>/<srv>` | 헬스체크 비활성화 |
| `enable agent <be>/<srv>` | 에이전트 체크 활성화 |
| `disable agent <be>/<srv>` | 에이전트 체크 비활성화 |

### 세션/연결 제어
| 명령어 | 설명 |
|--------|------|
| `shutdown sessions server <be>/<srv>` | 서버의 모든 세션 종료 |
| `shutdown session <id>` | 특정 세션 종료 |

### 프론트엔드 제어
| 명령어 | 설명 |
|--------|------|
| `enable frontend <fe>` | 프론트엔드 활성화 |
| `disable frontend <fe>` | 프론트엔드 비활성화 |
| `set maxconn frontend <fe> <n>` | 프론트엔드 maxconn 변경 |
| `set maxconn global <n>` | 전역 maxconn 변경 |

### 맵/ACL/테이블 수정
| 명령어 | 설명 |
|--------|------|
| `add map <file> <key> <value>` | 맵 항목 추가 |
| `set map <file> <key> <value>` | 맵 항목 수정 |
| `del map <file> <key>` | 맵 항목 삭제 |
| `add acl <file> <value>` | ACL 항목 추가 |
| `del acl <file> <value>` | ACL 항목 삭제 |
| `set table <name> key <k> data.<field> <v>` | 테이블 값 수정 |
| `clear table <name> [key <k>]` | 테이블 항목 삭제 |
