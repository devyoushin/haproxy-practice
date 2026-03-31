# HAProxy 완전 학습 가이드

이 디렉토리는 HAProxy에 대한 심층적인 학습 자료를 담고 있습니다.
Amazon Linux 2023 환경 기준으로 작성되었습니다.

## HAProxy란?

HAProxy(High Availability Proxy)는 TCP 및 HTTP 기반 애플리케이션을 위한
고성능 오픈소스 로드밸런서 및 프록시 서버입니다.
C로 작성되어 있으며, 단일 프로세스에서 수만 개의 동시 연결을 처리할 수 있습니다.

### 주요 특징
- **고성능**: 단일 코어에서 수만 TPS 처리 가능
- **L4/L7 로드밸런싱** 지원 (TCP 및 HTTP 레벨)
- **SSL/TLS 종단점(termination)** 및 브리지 지원
- **강력한 헬스체크** 기능 (TCP, HTTP, 에이전트 기반)
- **풍부한 ACL(접근 제어 목록)** 시스템
- **Stick Table**을 이용한 세션 지속성
- **Lua 스크립팅** 지원으로 확장 가능
- **Runtime API**를 통한 무중단 설정 변경
- **Prometheus, 자체 통계 페이지** 지원

### HAProxy가 적합한 경우
- 대규모 트래픽을 여러 서버에 분산해야 할 때
- SSL/TLS 오프로딩이 필요할 때
- 세밀한 트래픽 제어 및 라우팅이 필요할 때
- 고가용성(HA) 인프라를 구성할 때
- 마이크로서비스 아키텍처에서 API 게이트웨이 역할이 필요할 때

## 버전 정보

| 버전 | 지원 유형 | 상태 | 설명 |
|------|----------|------|------|
| 2.6 | LTS | EOL 예정 | 구버전 장기 지원 |
| 2.8 | LTS | 활성 지원 | **프로덕션 권장** |
| 3.0 | LTS | 활성 지원 | 최신 장기 지원 버전 |
| 3.1 | Stable | 활성 지원 | 최신 안정 버전 |

> **권장**: 새로운 프로덕션 환경에는 HAProxy 2.8 LTS 또는 3.0 LTS를 사용하세요.

## 디렉토리 구조

```
haproxy-practice/
├── README.md                    # 이 파일 (인덱스)
├── 01_설치가이드_AL2023.md      # Amazon Linux 2023 설치
├── 02_설정파일_구조.md          # 설정 파일 전체 구조
├── 03_global_섹션.md            # global 섹션 딥다이브
├── 04_defaults_섹션.md          # defaults 섹션 딥다이브
├── 05_frontend_섹션.md          # frontend 섹션 딥다이브
├── 06_backend_섹션.md           # backend 섹션 딥다이브
├── 07_listen_섹션.md            # listen 섹션 딥다이브
├── 08_로드밸런싱_알고리즘.md    # 모든 LB 알고리즘
├── 09_헬스체크.md               # 헬스체크 완전 가이드
├── 10_ACL.md                    # ACL 완전 가이드
├── 11_SSL_TLS.md                # SSL/TLS 완전 가이드
├── 12_로깅.md                   # 로깅 완전 가이드
├── 13_통계_모니터링.md          # 통계 및 모니터링
├── 14_스틱테이블_세션.md        # Stick Tables & 세션 지속성
├── 15_보안설정.md               # 보안 설정 가이드
├── 16_성능튜닝.md               # 성능 최적화 가이드
├── 17_고가용성_HA.md            # 고가용성 구성
├── 18_Lua_스크립팅.md           # Lua 스크립팅 가이드
├── 19_런타임API.md              # Runtime API 가이드
├── 20_실전예제.md               # 실전 설정 예제 모음
└── 21_트러블슈팅.md             # 문제 해결 가이드
```

## 학습 순서

### 초급 (기본 개념 및 설치)
1. [AL2023 설치 가이드](01_설치가이드_AL2023.md) - RPM 설치, 소스 빌드
2. [설정 파일 구조](02_설정파일_구조.md) - 섹션 이해, 문법 규칙
3. [global 섹션](03_global_섹션.md) - 전역 설정
4. [defaults 섹션](04_defaults_섹션.md) - 기본값 설정
5. [frontend 섹션](05_frontend_섹션.md) - 요청 수신부
6. [backend 섹션](06_backend_섹션.md) - 서버 풀 설정
7. [listen 섹션](07_listen_섹션.md) - 간단한 프록시

### 중급 (핵심 기능)
8. [로드밸런싱 알고리즘](08_로드밸런싱_알고리즘.md) - roundrobin, leastconn 등
9. [헬스체크](09_헬스체크.md) - TCP, HTTP, 에이전트 체크
10. [ACL (접근 제어 목록)](10_ACL.md) - 조건부 라우팅
11. [SSL/TLS 설정](11_SSL_TLS.md) - 인증서, mTLS
12. [로깅](12_로깅.md) - 로그 설정 및 분석
13. [통계 및 모니터링](13_통계_모니터링.md) - 대시보드, Prometheus

### 고급 (심화 기능)
14. [Stick Tables & 세션 지속성](14_스틱테이블_세션.md) - 세션 고정
15. [보안 설정](15_보안설정.md) - DDoS 방어, 보안 헤더
16. [성능 튜닝](16_성능튜닝.md) - 멀티스레딩, 버퍼 최적화
17. [고가용성 (HA)](17_고가용성_HA.md) - keepalived, peers
18. [Lua 스크립팅](18_Lua_스크립팅.md) - 동적 처리
19. [Runtime API](19_런타임API.md) - 무중단 설정 변경
20. [실전 예제](20_실전예제.md) - 웹, DB, gRPC, 블루-그린
21. [트러블슈팅](21_트러블슈팅.md) - 문제 해결

## 빠른 시작 예제

최소한의 HAProxy 설정으로 로드밸런서 구성:

```haproxy
global
    maxconn 4096
    log /dev/log local0

defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    option httplog

frontend web
    bind *:80
    default_backend webservers

backend webservers
    balance roundrobin
    option httpchk GET /health
    server web1 192.168.1.10:8080 check
    server web2 192.168.1.11:8080 check
    server web3 192.168.1.12:8080 check
```

## 참고 자료

- [공식 문서](https://www.haproxy.org/download/2.8/doc/configuration.txt)
- [HAProxy GitHub](https://github.com/haproxy/haproxy)
- [HAProxy Blog](https://www.haproxy.com/blog/)
- [커뮤니티 Wiki](https://www.haproxy.org/#docs)
