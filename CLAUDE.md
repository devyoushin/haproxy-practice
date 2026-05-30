# HAProxy Deep Dive 학습 프로젝트

Amazon Linux 2023 환경 기준의 HAProxy 완전 분석 문서 모음입니다.

## 프로젝트 구조

```
.
├── README.md          # 프로젝트 소개 및 문서 목록
├── CLAUDE.md          # 이 파일
├── docs/
│   └── guides/        # 학습 문서 (01~21번)
└── ops/
    ├── memory/        # AI 작업용 프로젝트 메모리
    └── tools/         # 실습용 설정 예시와 보조 자료
```

## 문서 규칙

- 문서 파일명은 `{번호}_{주제}.md` 형식을 유지한다.
- 모든 학습 문서는 `docs/guides/` 디렉토리에 위치한다.
- 한국어로 작성한다.
- AL2023 환경에서 HAProxy를 설치하고 운영한다는 전제를 유지한다.
- 새 문서를 추가할 때는 `README.md` 문서 목록과 `ops/memory/project_haproxy_study.md`를 함께 갱신한다.

## AI 작업 지침

- 먼저 `README.md`와 `ops/memory/project_haproxy_study.md`를 읽고 현재 범위를 파악한다.
- 기존 문서의 톤처럼 실무 운영 관점의 설명, 설정 예시, 검증 명령을 함께 제공한다.
- HAProxy 설정 예시는 문법 검증 가능한 형태를 우선한다.
- 최신 버전, 보안 권고, 패키지 저장소 상태처럼 바뀔 수 있는 정보는 작업 시점에 공식 문서를 확인한다.
