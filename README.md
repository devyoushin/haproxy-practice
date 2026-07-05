# haproxy-practice

HAProxy를 설치하고 운영하기 위한 개인 학습 공간입니다.

## 어디서 시작할까

- 문서 지도: `docs/README.md`
- 첫 문서: `docs/01-installation/01_installation_AL2023.md`
- 운영 보조 자료: `ops/README.md`
- AI 작업 지침: `CLAUDE.md`

## 구조

| 경로 | 내용 |
|------|------|
| `docs/` | 설치, 설정, 라우팅, 로드밸런싱, 보안, 성능, 운영 문서 |
| `ops/` | 설정 예시, 프로젝트 메모리 |
| `CLAUDE.md` | 이 레포에서 Claude가 참고할 작업 지침 |

## 빠른 명령

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl reload haproxy
systemctl restart haproxy
```
