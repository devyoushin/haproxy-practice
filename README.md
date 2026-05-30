# haproxy-practice

Amazon Linux 2023 기준으로 HAProxy 설치, 섹션별 설정, 로드밸런싱, 헬스체크, TLS, 보안, 성능 튜닝을 정리한 개인 학습 문서입니다.

## 빠른 시작

- 처음 볼 문서: `docs/guides/01_installation_AL2023.md`
- 전체 흐름: 설치 -> 설정 구조 -> frontend/backend/listen -> 로드밸런싱/헬스체크 -> 보안/성능/운영
- AI 작업 지침: `CLAUDE.md`

## 구조

```text
haproxy-practice/
├── README.md
├── CLAUDE.md
├── docs/
│   └── guides/    # 학습 문서
└── ops/
    ├── memory/    # 프로젝트 메모리
    └── tools/     # 설정 예시와 보조 자료
```

## 주요 문서

| 범위 | 문서 |
|------|------|
| 시작 | `docs/guides/01_installation_AL2023.md`, `docs/guides/02_config_structure.md` |
| 기본 섹션 | `docs/guides/03_global_section.md`, `docs/guides/04_defaults_section.md` |
| 트래픽 처리 | `docs/guides/05_frontend_section.md`, `docs/guides/06_backend_section.md`, `docs/guides/07_listen_section.md` |
| 운영 | `docs/guides/09_health_checks.md`, `docs/guides/12_logging.md`, `docs/guides/13_stats_monitoring.md` |
| 고급 | `docs/guides/17_high_availability.md`, `docs/guides/19_runtime_api.md`, `docs/guides/21_troubleshooting.md` |

## 빠른 명령

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl reload haproxy
systemctl restart haproxy
echo "show info" | socat - /var/lib/haproxy/stats
```
