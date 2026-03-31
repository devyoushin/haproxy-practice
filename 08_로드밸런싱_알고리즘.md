# HAProxy 로드밸런싱 알고리즘 완전 가이드

HAProxy는 다양한 로드밸런싱 알고리즘을 제공합니다. 서비스 특성에 맞는 알고리즘 선택이 성능과 안정성에 큰 영향을 줍니다.

---

## 알고리즘 비교 요약

| 알고리즘 | 동적 | 가중치 실시간 반영 | 서버 수 제한 | 세션 유지 | 적합한 서비스 |
|---------|------|-----------------|------------|---------|-------------|
| roundrobin | 예 | 즉시 | 4128 | 없음 | 일반 HTTP |
| static-rr | 아니오 | 리로드 필요 | 없음 | 없음 | 안정적 처리량 |
| leastconn | 예 | 즉시 | 없음 | 없음 | DB, LDAP, 긴 연결 |
| first | 아니오 | 리로드 필요 | 없음 | 없음 | 서버 절약, 배치 |
| source | 예 | 즉시 | 없음 | IP 기반 | NAT 환경 |
| uri | 예 | 즉시 | 없음 | URI 기반 | 캐시 서버 |
| url_param | 예 | 즉시 | 없음 | 파라미터 기반 | API, 특정 파라미터 |
| hdr | 예 | 즉시 | 없음 | 헤더 기반 | 사용자 기반 분산 |
| rdp-cookie | 예 | 즉시 | 없음 | RDP 쿠키 | RDP 게이트웨이 |
| random | 예 | 즉시 | 없음 | 없음 | 서버 동적 변경 |

---

## 1. roundrobin (라운드로빈)

### 동작 방식
가중치(weight)에 비례하여 순서대로 각 서버에 요청을 분배합니다.
동적 알고리즘이므로 가중치 변경이 즉시 반영됩니다.

```
요청 순서 (web1:100, web2:200, web3:100 가중치):
web1 → web2 → web2 → web3 → web1 → web2 → web2 → web3 → ...
(web2가 2배 더 많은 요청 처리)
```

### 특징
- **동적(Dynamic)**: 가중치 변경이 즉시 반영됨
- **서버 제한**: 최대 4128개 서버 (HAProxy 내부 제한)
- **가중치 범위**: 1~256 (0은 서버 비활성화)
- **기본 알고리즘**: balance를 명시하지 않으면 roundrobin

### 설정 예시
```haproxy
backend web_rr
    balance roundrobin

    # 균등 분배
    server web1 192.168.1.10:80 check weight 100
    server web2 192.168.1.11:80 check weight 100
    server web3 192.168.1.12:80 check weight 100

# 가중치 차등 분배 (고성능 서버에 더 많은 트래픽)
backend web_weighted
    balance roundrobin

    server high_spec 192.168.1.10:80 check weight 300   # 60% 트래픽
    server mid_spec  192.168.1.11:80 check weight 150   # 30% 트래픽
    server low_spec  192.168.1.12:80 check weight 50    # 10% 트래픽
```

### 주의사항
- 서버가 4128개를 초과하면 `static-rr`로 자동 전환됨
- 연결 시간이 다양한 경우 (짧은 연결 + 긴 연결 혼합) 서버 부하 불균형 발생 가능
- 세션 상태를 유지하는 서비스에는 stick-table 또는 cookie와 함께 사용해야 함

### 적합한 시나리오
- 무상태(stateless) HTTP API 서비스
- 짧은 응답 시간의 서비스
- 서버 사양이 유사한 경우

---

## 2. static-rr (정적 라운드로빈)

### 동작 방식
`roundrobin`과 동일하게 순서대로 분배하지만, **정적(Static)** 방식으로 동작합니다.
가중치 변경이 즉시 반영되지 않고, 설정 리로드 후에 적용됩니다.

### 특징
- **정적(Static)**: 가중치 변경이 즉시 반영되지 않음 (리로드 필요)
- **서버 수 제한 없음**: 4128개 초과 서버에서도 사용 가능
- 서버가 많은 대규모 환경에서 `roundrobin` 대신 사용

### 설정 예시
```haproxy
backend large_cluster
    balance static-rr

    # 4128개 이상의 서버를 사용하는 경우
    server node001 10.0.0.1:80 check weight 1
    server node002 10.0.0.2:80 check weight 1
    # ... 수천 개의 서버
```

### roundrobin과 차이점

| 항목 | roundrobin | static-rr |
|------|-----------|-----------|
| 가중치 즉시 반영 | 예 | 아니오 (리로드 필요) |
| 서버 수 제한 | 4128 | 없음 |
| 메모리 사용 | 더 많음 | 더 적음 |
| CPU 오버헤드 | 약간 더 많음 | 적음 |

---

## 3. leastconn (최소 연결)

### 동작 방식
현재 활성 연결 수가 가장 적은 서버를 선택합니다.
연결 수가 동일한 서버가 여러 개인 경우, roundrobin 방식으로 선택합니다.

```
현재 상태:
web1: 10개 연결
web2: 5개 연결  ← 선택
web3: 8개 연결

다음 요청 후:
web1: 10개 연결
web2: 6개 연결
web3: 8개 연결
```

### 특징
- **동적(Dynamic)**: 가중치 변경 즉시 반영
- 연결 수를 실시간으로 추적
- 서버가 느려지거나 지연이 발생하면 자동으로 해당 서버로의 새 연결을 줄임
- 긴 연결 시간의 서비스에 매우 적합

### 설정 예시
```haproxy
backend db_servers
    balance leastconn

    # 데이터베이스 클러스터
    default-server inter 3s fall 3 rise 2 maxconn 50

    server db1 10.0.0.10:5432 check
    server db2 10.0.0.11:5432 check
    server db3 10.0.0.12:5432 check

backend ldap_servers
    balance leastconn

    # LDAP 서버 (연결 시간이 긴 경우)
    server ldap1 10.0.0.20:389 check
    server ldap2 10.0.0.21:389 check
```

### 적합한 시나리오
- **데이터베이스**: MySQL, PostgreSQL, MongoDB 등
- **LDAP/AD 서버**: 인증 서버
- **WebSocket**: 긴 시간 연결을 유지하는 서비스
- **파일 업로드/다운로드**: 전송 시간이 다양한 서비스
- 요청 처리 시간이 크게 다른 서비스 (예: 빠른 쿼리 vs 느린 쿼리)

---

## 4. first (첫 번째 서버 우선)

### 동작 방식
서버 목록의 첫 번째 서버가 `maxconn`에 도달할 때까지 모든 요청을 해당 서버로 보냅니다.
첫 번째 서버가 가득 차면 두 번째 서버로, 두 번째도 가득 차면 세 번째 서버 순으로 진행합니다.

```
서버 상태 (maxconn=10):
web1: 10/10 (가득 참) → web2 사용 시작
web2: 7/10             ← 현재 여기로 요청
web3: 0/10             (아직 미사용)
```

### 특징
- **정적(Static)**: 가중치 변경 즉시 반영 안 됨
- 서버를 절약하는 데 효과적 (클라우드 비용 최소화)
- `maxconn`을 설정해야 의미 있음
- weight는 서버 순서에 영향을 주지 않음 (순서대로 사용)

### 설정 예시
```haproxy
backend batch_servers
    balance first

    # 클라우드 자동 확장 시나리오
    # 처음에는 server1만 사용, 부하 증가 시 server2, server3 순으로 사용
    server server1 10.0.0.10:8080 check maxconn 100
    server server2 10.0.0.11:8080 check maxconn 100
    server server3 10.0.0.12:8080 check maxconn 100
```

### 적합한 시나리오
- 클라우드 환경에서 서버 인스턴스 비용 최소화
- 배치 처리 작업 (나머지 서버를 대기 상태로 유지)
- 서버 리소스를 최대한 활용하고 싶은 경우

---

## 5. source (소스 IP 해시)

### 동작 방식
클라이언트 소스 IP 주소를 해시하여 항상 같은 서버로 라우팅합니다.
서버 추가/제거 시 해시 결과가 변경되어 기존 세션이 다른 서버로 이동할 수 있습니다.

```
클라이언트 IP → 해시 → 서버 선택
192.168.1.1   → 해시값 → web1 (항상)
192.168.1.2   → 해시값 → web3 (항상)
192.168.1.3   → 해시값 → web2 (항상)
```

### 특징
- 같은 IP의 클라이언트는 항상 같은 서버로 라우팅
- 서버 수가 변경되면 일부 클라이언트가 다른 서버로 이동 (해시 재계산)
- NAT 환경에서 여러 사용자가 같은 IP를 사용하면 부하 불균형 발생 가능

### 파라미터
```haproxy
backend web
    balance source

    # IPv4/IPv6 해시 테이블 크기 조정
    hash-type consistent    # 일관성 해시 (서버 변경 시 영향 최소화)
    # hash-type map-based   # 기본값 (단순 해시)
```

### 설정 예시
```haproxy
backend sticky_web
    balance source

    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
    server web3 192.168.1.12:80 check

# 일관성 해시 사용 (서버 변경 시 영향 최소화)
backend consistent_hash_web
    balance source
    hash-type consistent

    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
    server web3 192.168.1.12:80 check
```

### 주의사항
- 기업 네트워크에서 NAT로 인해 수천 명이 같은 IP를 사용할 수 있음
- 이 경우 특정 서버에 과부하 발생
- `consistent` 해시 타입 사용 시 서버 추가/제거 시 영향 최소화

### 적합한 시나리오
- 같은 클라이언트가 같은 서버를 사용해야 하는 경우 (세션 없는 간단한 상태 유지)
- Memcached 클러스터 (캐시 지역성 향상)
- 인터넷 → HAProxy 사이에 NAT가 없는 환경

---

## 6. uri (URI 해시)

### 동작 방식
요청 URI를 해시하여 서버를 선택합니다. 같은 URI는 항상 같은 서버로 라우팅됩니다.
캐시 서버 클러스터에서 캐시 히트율을 극대화하는 데 유용합니다.

```
URI → 해시 → 서버 선택
/images/logo.png   → hash → cache1 (항상)
/css/style.css     → hash → cache2 (항상)
/js/app.js         → hash → cache1 (항상)
```

### 파라미터
```haproxy
balance uri [len <n>] [depth <n>] [whole]
```

| 파라미터 | 설명 | 예시 |
|---------|------|------|
| `len <n>` | URI의 처음 n바이트만 해시에 사용 | `balance uri len 20` |
| `depth <n>` | URI의 처음 n개 디렉토리만 사용 | `balance uri depth 3` |
| `whole` | 쿼리 문자열 포함 전체 URI 사용 | `balance uri whole` |

### 설정 예시
```haproxy
# 캐시 서버 클러스터
backend cache_servers
    balance uri

    server cache1 10.0.0.10:80 check
    server cache2 10.0.0.11:80 check
    server cache3 10.0.0.12:80 check

# 디렉토리 깊이 3까지만 해시 (하위 파일들이 같은 서버로)
backend cdn_backend
    balance uri depth 3

    server cdn1 10.0.0.20:80 check
    server cdn2 10.0.0.21:80 check

# 쿼리 문자열까지 포함
backend api_cache
    balance uri whole

    server api1 10.0.0.30:80 check
    server api2 10.0.0.31:80 check
```

### 적합한 시나리오
- **HTTP 캐시 서버 클러스터**: 같은 콘텐츠가 항상 같은 서버 캐시에 저장
- **CDN 오리진 서버**: 콘텐츠 지역성 향상
- **이미지/정적 파일 서버**: 캐시 히트율 최대화

---

## 7. url_param (URL 파라미터 해시)

### 동작 방식
URL의 특정 파라미터 값을 해시하여 서버를 선택합니다.
파라미터가 없는 요청은 roundrobin으로 처리됩니다.

### 파라미터
```haproxy
balance url_param <param_name> [check_post [<max_wait>]]
```

| 파라미터 | 설명 |
|---------|------|
| `<param_name>` | 해시에 사용할 URL 파라미터 이름 |
| `check_post` | POST 요청 body에서도 파라미터 검색 |
| `<max_wait>` | POST body 대기 최대 바이트 수 (기본값: 64) |

### 설정 예시
```haproxy
# 사용자 ID로 라우팅 (같은 사용자는 같은 서버)
backend user_services
    balance url_param user_id

    server svc1 10.0.0.10:8080 check
    server svc2 10.0.0.11:8080 check
    server svc3 10.0.0.12:8080 check

# 예시 요청:
# GET /api/profile?user_id=1001 → svc2 (항상)
# GET /api/profile?user_id=1002 → svc1 (항상)

# POST body에서도 파라미터 확인
backend payment_services
    balance url_param session_id check_post 1024

    server pay1 10.0.0.20:8080 check
    server pay2 10.0.0.21:8080 check
```

### 적합한 시나리오
- 사용자 ID, 세션 ID, 주문 ID 등을 파라미터로 전달하는 API
- 같은 엔티티에 대한 요청을 같은 서버로 보내야 하는 경우 (로컬 캐시 활용)

---

## 8. hdr (HTTP 헤더 해시)

### 동작 방식
지정한 HTTP 헤더의 값을 해시하여 서버를 선택합니다.
헤더가 없는 요청은 roundrobin으로 처리됩니다.

### 파라미터
```haproxy
balance hdr(<header_name>) [use_domain_only]
```

| 파라미터 | 설명 |
|---------|------|
| `<header_name>` | 해시에 사용할 HTTP 헤더 이름 |
| `use_domain_only` | Host 헤더에서 도메인 부분만 사용 (서브도메인 무시) |

### 설정 예시
```haproxy
# 사용자 ID 헤더로 라우팅
backend user_api
    balance hdr(X-User-Id)

    server api1 10.0.0.10:8080 check
    server api2 10.0.0.11:8080 check
    server api3 10.0.0.12:8080 check

# Host 헤더의 도메인 부분으로 라우팅 (가상 호스팅)
backend vhost
    balance hdr(host) use_domain_only

    server web1 10.0.0.20:80 check
    server web2 10.0.0.21:80 check

# API 키로 라우팅
backend keyed_api
    balance hdr(X-API-Key)

    server backend1 10.0.0.30:8080 check
    server backend2 10.0.0.31:8080 check
```

### 적합한 시나리오
- 사용자 식별 헤더 (X-User-Id, X-Tenant-Id 등)를 기반으로 라우팅
- API 키 기반 라우팅
- 멀티테넌시 애플리케이션 (테넌트별 서버 할당)

---

## 9. rdp-cookie (RDP 쿠키 해시)

### 동작 방식
Microsoft RDP(Remote Desktop Protocol)의 쿠키를 해시하여 서버를 선택합니다.
RDP 게이트웨이 또는 터미널 서비스 팜에서 사용합니다.

### 설정 예시
```haproxy
listen rdp_farm
    bind *:3389
    mode tcp
    balance rdp-cookie(mstshash)

    # 기본 RDP 쿠키 이름: mstshash
    server rdp1 10.0.0.10:3389 check
    server rdp2 10.0.0.11:3389 check
    server rdp3 10.0.0.12:3389 check
```

### 적합한 시나리오
- Windows 터미널 서비스(RDS) 팜
- 가상 데스크톱 인프라(VDI) 로드밸런서

---

## 10. random (무작위)

### 동작 방식
랜덤하게 서버를 선택합니다. 기본적으로 2개의 서버를 무작위로 선택한 후,
그 중 활성 연결 수가 적은 서버로 요청을 보냅니다 (Power of Two Random Choices).

### 파라미터
```haproxy
balance random [<draws>]
```

- `draws`: 후보 서버 수 (기본값: 2)
- draws가 클수록 leastconn에 가까워지지만 CPU 사용량 증가

### 특징
- 서버 추가/제거 시 다른 알고리즘보다 영향 최소화
- 분산 환경에서 여러 HAProxy 인스턴스가 있을 때 효과적
- 동적 알고리즘 (가중치 즉시 반영)

### 설정 예시
```haproxy
# 기본 random (2개 중 leastconn)
backend dynamic_cluster
    balance random

    server node1 10.0.0.10:8080 check
    server node2 10.0.0.11:8080 check
    server node3 10.0.0.12:8080 check
    server node4 10.0.0.13:8080 check

# 3개 후보 중 leastconn (더 나은 분산)
backend better_random
    balance random(3)

    server node1 10.0.0.10:8080 check weight 100
    server node2 10.0.0.11:8080 check weight 100
    server node3 10.0.0.12:8080 check weight 200  # 2배 가중치
```

### roundrobin vs leastconn vs random 비교

| 상황 | roundrobin | leastconn | random |
|------|-----------|-----------|--------|
| 균일한 짧은 요청 | 최적 | 좋음 | 좋음 |
| 다양한 처리 시간 | 나쁨 | 최적 | 좋음 |
| 서버 동적 추가/제거 | 영향 있음 | 영향 있음 | 영향 최소 |
| 분산 HAProxy 환경 | 조정 필요 | 조정 필요 | 자연스러움 |

### 적합한 시나리오
- 서버가 자주 추가/제거되는 동적 클러스터
- 마이크로서비스 환경 (서비스 인스턴스 빈번한 변경)
- 여러 HAProxy 인스턴스가 동시에 운영되는 경우

---

## 11. 해시 타입 (hash-type)

`source`, `uri`, `url_param`, `hdr`, `rdp-cookie` 알고리즘과 함께 사용 가능합니다.

```haproxy
backend web
    balance uri
    hash-type map-based    # 기본값: 단순 모듈로 해시
    # hash-type consistent  # 일관성 해시 (서버 변경 시 영향 최소화)
```

### map-based vs consistent

| 항목 | map-based | consistent |
|------|-----------|------------|
| 서버 추가 시 재배치 | 많음 (대부분 변경) | 적음 (~1/N 변경) |
| 분산 균등성 | 더 균등 | 약간 불균등 |
| 메모리 | 적음 | 더 많음 |
| 캐시 히트율 | 서버 변경 시 하락 | 서버 변경 시 유지 |

```haproxy
# 캐시 서버에서 서버 변경 시 영향 최소화
backend cache_cluster
    balance uri
    hash-type consistent

    server cache1 10.0.0.10:80 check
    server cache2 10.0.0.11:80 check
    server cache3 10.0.0.12:80 check
```

---

## 12. 알고리즘 선택 가이드

### 서비스 유형별 권장 알고리즘

```
HTTP API (무상태, 짧은 요청)
    → roundrobin (기본)
    → 서버 동적 변경 많으면: random

HTTP API (특정 사용자 → 같은 서버)
    → hdr(X-User-Id) 또는 url_param user_id
    → 서버 변경이 많으면: consistent hash 추가

데이터베이스 (MySQL, PostgreSQL)
    → leastconn

WebSocket / 긴 연결
    → leastconn

캐시 서버 (Memcached, Varnish)
    → uri (캐시 히트율 최대화)
    → source (클라이언트별 지역성)

RDP / 터미널 서비스
    → rdp-cookie

대규모 클러스터 (4128개 이상)
    → static-rr

서버 절약 (클라우드 비용 최소화)
    → first (maxconn 설정 필수)
```

### 실전 멀티 백엔드 예시

```haproxy
# API 서버: 무상태 HTTP, 균등 분산
backend api_servers
    balance roundrobin
    option httpchk GET /health
    default-server inter 3s fall 3 rise 2
    server api1 10.0.1.10:8080 check
    server api2 10.0.1.11:8080 check
    server api3 10.0.1.12:8080 check

# 데이터베이스: 최소 연결 우선
backend db_servers
    balance leastconn
    option tcp-check
    default-server inter 5s fall 3 rise 2 maxconn 50
    server db1 10.0.2.10:5432 check
    server db2 10.0.2.11:5432 check

# 캐시 서버: URI 기반 (캐시 히트율 최대화)
backend cache_servers
    balance uri
    hash-type consistent
    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG
    server cache1 10.0.3.10:6379 check
    server cache2 10.0.3.11:6379 check
    server cache3 10.0.3.12:6379 check

# WebSocket: 최소 연결 + 터널 타임아웃
backend websocket_servers
    balance leastconn
    timeout tunnel 3600s
    option http-server-close
    server ws1 10.0.4.10:8080 check
    server ws2 10.0.4.11:8080 check

# 사용자별 API: 헤더 해시 (같은 사용자 → 같은 서버)
backend user_api_servers
    balance hdr(X-User-Id)
    hash-type consistent
    server user_api1 10.0.5.10:8080 check
    server user_api2 10.0.5.11:8080 check
    server user_api3 10.0.5.12:8080 check
```
