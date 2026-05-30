# HAProxy 로깅 완전 가이드

HAProxy는 상세한 로깅을 제공하여 트래픽 분석, 장애 진단, 보안 감사에 활용할 수 있습니다.
syslog 프로토콜을 사용하여 로컬 또는 원격 로그 서버로 전송합니다.

---

## 1. 로그 설정 기본

```haproxy
global
    log 127.0.0.1:514 local0 info        # UDP syslog (기본)
    log /dev/log local0 info              # 로컬 Unix 소켓
    log 192.168.1.100:514 local1 warning  # 원격 syslog 서버

defaults
    log     global        # global 섹션의 log 설정 사용
    option  httplog       # HTTP 상세 로그 활성화
    # option tcplog       # TCP 로그 활성화 (TCP 모드)
    # option log-health-checks  # 헬스체크 결과 로깅
    # option dontlognull  # 연결은 됐지만 데이터 없는 경우 로그 제외
    # option dontlog-normal  # 정상 요청 로그 제외 (에러만 로그)
```

---

## 2. rsyslog 설정

### /etc/rsyslog.d/haproxy.conf
```
# UDP 514 포트 수신 활성화
$ModLoad imudp
$UDPServerRun 514

# HAProxy 로그를 별도 파일로 저장
$template HAProxyLog,"%msg%\n"
local0.* -/var/log/haproxy.log;HAProxyLog
local0.* ~    # 다른 파일에는 기록 안 함

# 에러 레벨만 별도 파일로
local0.err    /var/log/haproxy-error.log

# 나머지 레벨 제외
local0.info   stop
```

### rsyslog 재시작
```bash
systemctl restart rsyslog

# 로그 파일 생성 및 권한 설정
touch /var/log/haproxy.log
chown syslog:adm /var/log/haproxy.log
chmod 644 /var/log/haproxy.log
```

### logrotate 설정 (/etc/logrotate.d/haproxy)
```
/var/log/haproxy.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /bin/kill -HUP $(cat /run/rsyslogd.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
```

---

## 3. HTTP 로그 포맷 (option httplog)

`option httplog` 활성화 시 생성되는 기본 로그 형식:

```
<날짜> <프론트엔드이름> <백엔드이름>/<서버이름>: <클라이언트IP>:<포트> [날짜/시간] <프론트엔드이름> <백엔드이름>/<서버이름> <Tq>/<Tw>/<Tc>/<Tr>/<Ta> <상태코드> <바이트> <요청쿠키> <응답쿠키> <종료플래그> <연결수> <큐수> "<HTTP메서드> <URL> <HTTP버전>"
```

예시:
```
Mar 30 10:15:23 haproxy[1234]: 192.168.1.100:54321 [30/Mar/2026:10:15:23.456] http_front web_backend/web1 0/0/1/25/26 200 1234 - - ---- 5/5/0/1/0 0/0 "GET /api/users HTTP/1.1"
```

### HTTP 로그 필드 설명

| 필드 | 기호 | 설명 |
|------|------|------|
| 클라이언트 IP:포트 | `%ci:%cp` | 요청 클라이언트 주소 |
| 요청 시간 | `[날짜]` | 요청 수신 시각 |
| 프론트엔드 이름 | `%f` | 트래픽을 수신한 frontend |
| 백엔드/서버 | `%b/%s` | 트래픽을 처리한 backend/server |
| 타이머 | `%Tq/%Tw/%Tc/%Tr/%Ta` | 각 단계별 시간 (ms) |
| 상태 코드 | `%ST` | HTTP 응답 상태 코드 |
| 바이트 | `%B` | 전송된 바이트 수 |
| 요청 쿠키 | `%CC` | 캡처된 요청 쿠키 |
| 응답 쿠키 | `%CS` | 캡처된 응답 쿠키 |
| 종료 플래그 | `%ts%tsc` | 연결 종료 이유 |
| 연결 수 | `%ac/%fc/%bc/%sc/%rc` | 각 수준의 연결 수 |
| 큐 수 | `%sq/%bq` | 큐 대기 수 |
| HTTP 요청 | `%m %HU %HV` | 메서드, URL, 버전 |

---

## 4. 타이머 필드 상세 설명

타이머 필드 형식: `%Tq/%Tw/%Tc/%Tr/%Ta`

| 기호 | 의미 | 값이 -1인 경우 |
|------|------|--------------|
| `%Tq` | 요청 완전 수신까지 시간 (HTTP 헤더 포함) | 요청 파싱 오류 |
| `%Tw` | 큐에서 대기한 시간 | 큐에 없었음 |
| `%Tc` | 서버 TCP 연결 수립 시간 | 연결 안 됨 |
| `%Tr` | 서버 응답 첫 바이트 수신까지 시간 | 응답 없음 |
| `%Ta` | 총 활성 시간 (Tq+Tw+Tc+Tr+전송 시간) | - |
| `%TR` | 요청 전체 수신 시간 (body 포함) | 요청 오류 |
| `%Td` | 응답 데이터 전송 시간 | - |

```
예시: 0/0/1/25/26
Tq=0ms: 요청 즉시 수신
Tw=0ms: 큐 대기 없음
Tc=1ms: 서버 연결 1ms
Tr=25ms: 서버 응답 25ms
Ta=26ms: 총 26ms
```

---

## 5. 종료 플래그 (Termination Flags)

형식: 4글자 (`%ts%tsc`)

### 첫 번째 글자 (세션 상태)
| 플래그 | 의미 |
|--------|------|
| `C` | 클라이언트가 연결 종료 |
| `S` | 서버가 연결 종료 |
| `P` | 프록시가 연결 종료 (타임아웃 등) |
| `R` | 리소스 부족 (메모리 등) |
| `I` | 내부 오류 |
| `D` | 서버 DOWN으로 인한 종료 |
| `L` | 로컬 종료 (HAProxy 종료 등) |
| `k` | Keep-alive 연결 종료 |

### 두 번째 글자 (현재 세션 상태)
| 플래그 | 의미 |
|--------|------|
| `R` | 요청 수신 중 |
| `Q` | 큐 대기 중 |
| `C` | 서버 연결 중 |
| `H` | 응답 헤더 수신 중 |
| `D` | 데이터 전송 중 |
| `L` | 마지막 데이터 전송 중 |
| `T` | 터널 모드 |

```
일반 완료: ----  (정상 완료)
클라이언트 타임아웃: cD--  (데이터 전송 중 클라이언트 연결 종료)
서버 오류: sD--  (데이터 전송 중 서버 연결 종료)
```

---

## 6. TCP 로그 포맷 (option tcplog)

```haproxy
listen mysql
    bind *:3306
    mode tcp
    option tcplog
    log global
    server db1 10.0.0.10:3306 check
```

TCP 로그 형식:
```
<클라이언트IP>:<포트> [날짜] <프론트엔드> <백엔드>/<서버> <Tw>/<Tc>/<Ta> <바이트> <종료플래그> <연결수> <큐수>
```

---

## 7. 커스텀 로그 포맷 (log-format)

### 기본 커스텀 포맷 변수

| 변수 | 설명 |
|------|------|
| `%t` | 날짜/시간 (기본 형식) |
| `%T` | 날짜/시간 (Unix timestamp) |
| `%ci` | 클라이언트 IP |
| `%cp` | 클라이언트 포트 |
| `%fi` | 프론트엔드 IP (수신 IP) |
| `%fp` | 프론트엔드 포트 (수신 포트) |
| `%f` | 프론트엔드 이름 |
| `%b` | 백엔드 이름 |
| `%s` | 서버 이름 |
| `%si` | 서버 IP |
| `%sp` | 서버 포트 |
| `%bi` | 백엔드에서 사용하는 소스 IP |
| `%bp` | 백엔드에서 사용하는 소스 포트 |
| `%ST` | HTTP 상태 코드 |
| `%B` | 응답 바이트 수 |
| `%U` | 요청 바이트 수 (업로드) |
| `%Tq` | 요청 수신 시간 (ms) |
| `%Tw` | 큐 대기 시간 (ms) |
| `%Tc` | 서버 연결 시간 (ms) |
| `%Tr` | 서버 응답 시간 (ms) |
| `%Ta` | 총 활성 시간 (ms) |
| `%m` | HTTP 메서드 |
| `%HU` | HTTP URL (경로 + 쿼리) |
| `%HP` | HTTP 경로 (쿼리 제외) |
| `%HQ` | HTTP 쿼리 문자열 |
| `%HV` | HTTP 버전 |
| `%hs` | HTTP 상태 문자열 |
| `%ac` | 전체 동시 연결 수 |
| `%fc` | 프론트엔드 연결 수 |
| `%bc` | 백엔드 연결 수 |
| `%sc` | 서버 연결 수 |
| `%rc` | 재시도 횟수 |
| `%sq` | 서버 큐 대기 수 |
| `%bq` | 백엔드 큐 대기 수 |
| `%ts` | 종료 상태 |
| `%tsc` | 종료 상태 코드 (4글자) |
| `%ID` | 고유 ID (option unique-id 필요) |
| `%pid` | HAProxy 프로세스 ID |

### 커스텀 포맷 예시

#### Apache Combined 유사 포맷
```haproxy
defaults
    log-format "%ci - - [%t] \"%m %HU %HV\" %ST %B \"%[capture.req.hdr(0)]\" \"%[capture.req.hdr(1)]\""
```

#### 상세 진단용 포맷
```haproxy
defaults
    log-format "%t %pid frontend=%f backend=%b server=%s src=%ci:%cp dst=%si:%sp timers=%Tq/%Tw/%Tc/%Tr/%Ta status=%ST bytes_out=%B bytes_in=%U retries=%rc flags=%tsc connections=%ac/%fc/%bc/%sc queues=%sq/%bq method=%m path=%HP"
```

#### JSON 로그 포맷
```haproxy
defaults
    log-format '{"time":"%t","pid":%pid,"frontend":"%f","backend":"%b","server":"%s","client_ip":"%ci","client_port":%cp,"server_ip":"%si","server_port":%sp,"method":"%m","path":"%HP","query":"%HQ","status":%ST,"bytes_out":%B,"bytes_in":%U,"duration_ms":%Ta,"queue_time":%Tw,"connect_time":%Tc,"response_time":%Tr,"retries":%rc,"termination":"%tsc"}'
```

---

## 8. 로그 레벨 제어

```haproxy
defaults
    # 빈 연결 (데이터 없는 연결) 로그 제외
    option dontlognull

    # 정상 응답(200, 301 등) 로그 제외 (에러만 기록)
    option dontlog-normal

    # 헬스체크 결과 로그 포함
    option log-health-checks

    # HTTP 연결 유지(Keep-alive) 로그
    option log-separate-errors    # 에러를 별도 syslog 시설로

frontend web
    # 특정 경로 로그 제외 (헬스체크 등)
    http-request set-log-level silent if { path /health /ping /favicon.ico }

    # 특정 조건에서 로그 레벨 변경
    http-request set-log-level err if { status ge 500 }
```

---

## 9. 헤더 캡처 (Capture)

로그에 특정 헤더 값을 포함시킵니다.

```haproxy
frontend web
    bind *:80
    mode http

    # 요청 헤더 캡처 (최대 길이 명시)
    capture request header Host        len 50
    capture request header User-Agent  len 150
    capture request header Referer     len 200
    capture request header X-Request-ID len 36
    capture request header Authorization len 20   # Bearer 토큰 앞부분만

    # 응답 헤더 캡처
    capture response header Content-Type   len 50
    capture response header Content-Length len 10

    # 쿠키 캡처
    capture cookie SESSIONID len 32
    capture cookie csrftoken len 32

    # 캡처된 값은 %[capture.req.hdr(0)], %[capture.req.hdr(1)] 등으로 접근
    # log-format에서 사용 가능
    log-format "%t %ci \"%m %HP\" %ST %B \"%[capture.req.hdr(0)]\" \"%[capture.req.hdr(1)]\""
```

---

## 10. 로그 샘플링

트래픽이 매우 많은 경우 일부만 로그에 기록합니다.

```haproxy
frontend high_traffic
    bind *:80
    mode http

    # 10개 중 1개만 로그
    log global sample 1 period 10

    # 에러는 항상 로그 (샘플링 제외)
    log global
    log-format ...

    default_backend web_backend
```

---

## 11. 로그 분석 명령어

```bash
# 실시간 로그 모니터링
tail -f /var/log/haproxy.log

# 에러만 필터링
grep " 5[0-9][0-9] " /var/log/haproxy.log | tail -20

# 특정 IP 추적
grep "192.168.1.100" /var/log/haproxy.log | tail -20

# 느린 요청 찾기 (1000ms 이상)
awk -F'[/]' '$NF > 1000 {print}' /var/log/haproxy.log

# 상태 코드별 통계
awk '{print $8}' /var/log/haproxy.log | sort | uniq -c | sort -rn

# 분당 요청 수 계산
awk '{print substr($1,1,15)}' /var/log/haproxy.log | sort | uniq -c

# 특정 백엔드 서버 에러
grep "BACKEND_NAME/server1" /var/log/haproxy.log | grep " 5[0-9][0-9] "

# 타임아웃 발생 요청
grep " -1/" /var/log/haproxy.log | tail -20

# 503 에러 분석
grep " 503 " /var/log/haproxy.log | awk '{print $1, $2, $7, $8}'

# 가장 많이 요청된 URL
awk '{print $NF}' /var/log/haproxy.log | sort | uniq -c | sort -rn | head -20

# 평균 응답 시간 계산
awk -F'[/]' '{sum+=$NF; count++} END {print sum/count " ms"}' /var/log/haproxy.log
```

---

## 12. 원격 로그 서버 설정

```haproxy
global
    # UDP syslog (기본, 패킷 손실 가능)
    log 192.168.1.100:514 local0 info

    # TCP syslog (신뢰성 있음, HAProxy 2.0+)
    # log tcp@192.168.1.100:514 local0 info
    # log tcp@192.168.1.100:6514 local0 info ssl  # TLS (HAProxy 2.3+)

    # 여러 로그 서버
    log 192.168.1.100:514 local0 info    # 메인 로그 서버
    log 192.168.1.101:514 local0 err     # 에러 전용 (err 이상만)

    # 로그 버퍼 크기
    log-send-hostname                    # 호스트명 포함
    log-tag "haproxy"                    # 로그 태그 설정
```

---

## 13. Elasticsearch/Filebeat 연동

### Filebeat 설정 (/etc/filebeat/filebeat.yml)
```yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/haproxy.log
    tags: ["haproxy"]
    json.keys_under_root: true    # JSON 로그 포맷 사용 시
    json.add_error_key: true

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "haproxy-logs-%{+yyyy.MM.dd}"

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
```

### JSON 로그 파싱 설정 (HAProxy 측)
```haproxy
defaults
    log-format '{"@timestamp":"%t","log":{"level":"info"},"haproxy":{"frontend":"%f","backend":"%b","server":"%s","client":{"ip":"%ci","port":%cp},"server_addr":{"ip":"%si","port":%sp},"http":{"method":"%m","url":"%HU","version":"%HV","status":%ST},"bytes":{"out":%B,"in":%U},"timers":{"total":%Ta,"queue":%Tw,"connect":%Tc,"response":%Tr},"retries":%rc,"termination_state":"%tsc"}}'
```

---

## 14. 구조화 로그 (log-format-sd)

RFC 5424 구조화 데이터 형식 지원:

```haproxy
defaults
    # Structured Data 포맷 (RFC 5424)
    log-format-sd '[haproxy@47450 src="%ci" dst="%si" method="%m" path="%HP" status="%ST" duration="%Ta"]'
```

---

## 15. 로그 레벨 설정

```
emerg   - 시스템 사용 불가
alert   - 즉각 조치 필요
crit    - 심각한 상태
err     - 에러 조건
warning - 경고 조건
notice  - 정상이지만 주목할 상황
info    - 정보성 메시지 (일반 접근 로그)
debug   - 디버그 메시지 (매우 상세)
```

```haproxy
global
    log 127.0.0.1 local0 info     # info 이상만 기록
    log 127.0.0.1 local1 warning  # warning 이상만 기록 (에러 전용)
```

---

## 16. 프론트엔드별 다른 로그 서버

```haproxy
frontend public_api
    bind *:80
    mode http

    # 이 프론트엔드는 별도 로그 서버로
    log 192.168.1.200:514 local2 info
    option httplog

    default_backend api_backend

frontend admin
    bind *:8080
    mode http

    # 관리자 트래픽은 별도 로그 (보안 감사)
    log 192.168.1.201:514 local3 info
    option httplog

    default_backend admin_backend
```
