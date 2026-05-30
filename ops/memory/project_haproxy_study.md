---
name: haproxy-practice project
description: AL2023 환경에서 HAProxy를 공부하는 학습 프로젝트. RPM 설치부터 핵심 섹션, 운영 기능, 트러블슈팅까지 deep-dive 문서 포함.
type: project
---

HAProxy 전체 학습 문서 프로젝트. /Users/sunny/Desktop/haproxy-practice/ 에 위치.

**Why:** AL2023 환경에서 HAProxy 설치, 설정 구조, 로드밸런싱, 헬스체크, ACL, SSL/TLS, 모니터링, 고가용성, Runtime API까지 실무 운영 수준으로 학습하기 위한 목적.

**How to apply:** 이 프로젝트에서 작업할 때 AL2023 환경과 HAProxy 운영 학습 목적을 전제로 설명하고, 새 내용 추가 시 기존 `docs/guides/` 문서 구조와 한국어 deep-dive 톤을 유지한다.

생성된 문서 목록 (01~21번):
01_installation_AL2023.md, 02_config_structure.md, 03_global_section.md,
04_defaults_section.md, 05_frontend_section.md, 06_backend_section.md,
07_listen_section.md, 08_load_balancing_algorithms.md, 09_health_checks.md,
10_ACL.md, 11_SSL_TLS.md, 12_logging.md, 13_stats_monitoring.md,
14_stick_tables_sessions.md, 15_security.md, 16_performance_tuning.md,
17_high_availability.md, 18_lua_scripting.md, 19_runtime_api.md,
20_practical_examples.md, 21_troubleshooting.md
