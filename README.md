# HAProxy 완전 학습 가이드

이 디렉토리는 HAProxy에 대한 심층적인 학습 자료를 담고 있습니다.
Amazon Linux 2023 환경 기준으로 작성되었습니다.

## HAProxy란?

HAProxy(High Availability Proxy)는 TCP 및 HTTP 기반 애플리케이션을 위한
고성능 오픈소스 로드밸런서 및 프록시 서버입니다.
C로 작성되어 있으며, 단일 프로세스에서 수만 개의 동시 연결을 처리할 수 있습니다.

### 주요 특징
- 고성능: 단일 코어에서 수만 TPS 처리 가능
- L4/L7 로드밸런싱 지원
- SSL/TLS 종단점(termination) 및 브리지 지원
- 강력한 헬스체크 기능
- 풍부한 ACL(접근 제어 목록) 시스템
- Stick Table을 이용한 세션 지속성
- Lua 스크립팅 지원
- Runtime API를 통한 무중단 설정 변경
- Prometheus, 자체 통계 페이지 지원

## 버전 정보

| 버전 | 지원 유형 | 설명 |
|------|----------|------|
| 2.8 | LTS | 장기 지원 버전 (프로덕션 권장) |
| 2.9 | Stable | 안정 버전 |
| 3.0 | LTS | 최신 장기 지원 버전 |
| 3.1 | Stable | 최신 안정 버전 |

## 학습 순서

1. [AL2023 설치 가이드](01_installation_AL2023.md)
2. [설정 파일 구조](02_config_structure.md)
3. [global 섹션](03_global_section.md)
4. [defaults 섹션](04_defaults_section.md)
5. [frontend 섹션](05_frontend_section.md)
6. [backend 섹션](06_backend_section.md)
7. [listen 섹션](07_listen_section.md)
8. [로드밸런싱 알고리즘](08_load_balancing_algorithms.md)
9. [헬스체크](09_health_checks.md)
10. [ACL (접근 제어 목록)](10_ACL.md)
11. [SSL/TLS 설정](11_SSL_TLS.md)
12. [로깅](12_logging.md)
13. [통계 및 모니터링](13_stats_monitoring.md)
14. [Stick Tables & 세션 지속성](14_stick_tables_sessions.md)
15. [보안 설정](15_security.md)
16. [성능 튜닝](16_performance_tuning.md)
17. [고가용성 (HA)](17_high_availability.md)
18. [Lua 스크립팅](18_lua_scripting.md)
19. [Runtime API](19_runtime_api.md)
20. [실전 예제](20_practical_examples.md)
21. [트러블슈팅](21_troubleshooting.md)

## 파일 구조

```
haproxy-practice/
├── README.md                        # 이 파일 (인덱스)
├── 01_installation_AL2023.md        # AL2023 RPM 설치 가이드
├── 02_config_structure.md           # 설정 파일 구조
├── 03_global_section.md             # global 섹션
├── 04_defaults_section.md           # defaults 섹션
├── 05_frontend_section.md           # frontend 섹션
├── 06_backend_section.md            # backend 섹션
├── 07_listen_section.md             # listen 섹션
├── 08_load_balancing_algorithms.md  # 로드밸런싱 알고리즘
├── 09_health_checks.md              # 헬스체크
├── 10_ACL.md                        # ACL (접근 제어 목록)
├── 11_SSL_TLS.md                    # SSL/TLS 설정
├── 12_logging.md                    # 로깅
├── 13_stats_monitoring.md           # 통계 및 모니터링
├── 14_stick_tables_sessions.md      # Stick Tables & 세션
├── 15_security.md                   # 보안 설정
├── 16_performance_tuning.md         # 성능 튜닝
├── 17_high_availability.md          # 고가용성 (HA)
├── 18_lua_scripting.md              # Lua 스크립팅
├── 19_runtime_api.md                # Runtime API
├── 20_practical_examples.md         # 실전 예제
└── 21_troubleshooting.md            # 트러블슈팅
```
