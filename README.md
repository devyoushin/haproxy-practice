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

## 문서 목록

| 파일 | 내용 |
|------|------|
| [01_installation_AL2023.md](docs/01_installation_AL2023.md) | AL2023 HAProxy RPM 설치 가이드 |
| [02_config_structure.md](docs/02_config_structure.md) | 설정 파일 구조, 섹션 구성, 검증 방법 |
| [03_global_section.md](docs/03_global_section.md) | global 섹션 핵심 지시어 |
| [04_defaults_section.md](docs/04_defaults_section.md) | defaults 섹션 공통 정책 |
| [05_frontend_section.md](docs/05_frontend_section.md) | frontend 섹션, bind, ACL 연결 |
| [06_backend_section.md](docs/06_backend_section.md) | backend 섹션, server, option 구성 |
| [07_listen_section.md](docs/07_listen_section.md) | listen 섹션 사용 방식 |
| [08_load_balancing_algorithms.md](docs/08_load_balancing_algorithms.md) | 로드밸런싱 알고리즘 |
| [09_health_checks.md](docs/09_health_checks.md) | 헬스체크 설정과 운영 패턴 |
| [10_ACL.md](docs/10_ACL.md) | ACL 조건식과 라우팅 |
| [11_SSL_TLS.md](docs/11_SSL_TLS.md) | SSL/TLS 종료, 인증서, 보안 설정 |
| [12_logging.md](docs/12_logging.md) | 로깅 형식과 분석 |
| [13_stats_monitoring.md](docs/13_stats_monitoring.md) | 통계 페이지와 모니터링 |
| [14_stick_tables_sessions.md](docs/14_stick_tables_sessions.md) | Stick Table과 세션 지속성 |
| [15_security.md](docs/15_security.md) | 보안 설정과 방어 패턴 |
| [16_performance_tuning.md](docs/16_performance_tuning.md) | 성능 튜닝 |
| [17_high_availability.md](docs/17_high_availability.md) | 고가용성 구성 |
| [18_lua_scripting.md](docs/18_lua_scripting.md) | Lua 스크립팅 |
| [19_runtime_api.md](docs/19_runtime_api.md) | Runtime API와 소켓 운영 |
| [20_practical_examples.md](docs/20_practical_examples.md) | 실전 예제 |
| [21_troubleshooting.md](docs/21_troubleshooting.md) | 트러블슈팅 |

## 파일 구조

```
haproxy-practice/
├── README.md              # 프로젝트 소개 및 문서 인덱스
├── CLAUDE.md              # AI 작업 지침
├── docs/                  # 학습 문서
│   ├── 01_installation_AL2023.md
│   ├── 02_config_structure.md
│   ├── ...
│   └── 21_troubleshooting.md
├── memory/                # AI가 참고할 프로젝트 메모리
│   ├── MEMORY.md
│   └── project_haproxy_study.md
└── tools/                 # 실습용 설정 예시와 보조 자료
    └── sample_haproxy.cfg
```
