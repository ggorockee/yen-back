# yen-back server

돌려받엔 앱용 Go(Fiber) API 서버입니다. 한국수출입은행 환율을 수집·캐시하고, 일본 면세 제도 상수와 앱 활동 지표를 제공합니다.

## 엔드포인트

| 포트 | 메서드 | 경로 | 설명 |
|---|---|---|---|
| 8080 | GET | /healthz | liveness |
| 8080 | GET | /readyz | readiness (저장소 연결 확인) |
| 8080 | GET | /v1/rates/latest | 최신 영업일 환율 (JPY, USD). 저장소가 비어 있으면 즉시 수집 시도 (5분에 1회로 제한) |
| 8080 | GET | /v1/rules | 면세 제도 상수 (5,000엔, 90일, 세율, 800달러, 출처) |
| 8080 | POST | /v1/events | 앱 활동 이벤트 집계 (이름·횟수만, 허용 목록 기반) |
| 8080 | POST | /internal/collect | 수동 수집. X-Internal-Token 헤더 필요, INTERNAL_TOKEN 미설정 시 404 |
| 9090 | GET | /metrics | Prometheus 지표. 외부 라우팅 없음 (ServiceMonitor 전용) |

/v1/rates/latest 응답 예시

```json
{
  "base_date": "2026-11-13",
  "fetched_at": "2026-11-13T02:12:00Z",
  "source": "koreaexim",
  "stale": false,
  "rates": {
    "JPY": { "krw_per_unit": 9.2135, "raw": "921.35", "unit": 100 },
    "USD": { "krw_per_unit": 1388.5, "raw": "1,388.5", "unit": 1 }
  }
}
```

POST /v1/events 요청 예시 (X-App-Platform, X-App-Version 헤더 함께 전송)

```json
{ "events": [ { "name": "item_added", "count": 3 }, { "name": "app_open", "count": 1 } ] }
```

## 환경 변수

| 이름 | 기본값 | 설명 |
|---|---|---|
| PORT | 8080 | API 포트 |
| METRICS_PORT | 9090 | /metrics 포트 (PORT와 달라야 함) |
| KOREAEXIM_API_KEY | (없음) | 수출입은행 Open API 인증키. 없으면 수집 실패 |
| KOREAEXIM_URL | oapi.koreaexim.go.kr 엔드포인트 | 테스트용 재정의 |
| DATABASE_URL | (없음) | Postgres DSN. 비우면 메모리 저장소 |
| COLLECT_INTERVAL | (없음) | 앱 내 수집 주기 (예: 30m). 비우면 외부 스케줄러가 /internal/collect 호출 |
| INTERNAL_TOKEN | (없음) | /internal/* 보호 토큰 |
| LOG_LEVEL | info | debug, info, warn, error |

## 수집 동작

외부 API 명세와 인증키 만료(2년) 등 주의사항은 docs/api/koreaexim-exchange-api.md를 참고하세요.

- 오늘(KST)부터 하루씩 거슬러 올라가며 조회하고, 이미 저장된 날짜에 닿으면 멈춥니다. 주말·공휴일·11시 이전에도 호출은 몇 번뿐입니다 (30분 주기 기준 하루 최대 약 48회, 한도 1,000회).
- 빈 응답(비영업일)은 오류가 아니라 empty로 기록됩니다. 기준일이 4일을 넘으면 stale=true로 응답합니다.
- 엔화는 100엔 단위(JPY(100))로 고시되므로 1엔 단위로 바꿔 저장합니다.
- 인증키는 개인정보 보유기간(2년)이 지나 재동의하지 않으면 파기되어 result=3이 반환됩니다. 재동의 안내 메일을 놓치지 말고, 파기됐다면 재발급 후 GCP 시크릿 prod-yen-back-credentials에 새 버전을 추가합니다. (키 발급일: 2026-11-15)

## 모니터링 (infra 연동)

kube-prometheus-stack이 ServiceMonitor로 9090/metrics를 30초마다 수집합니다. 대시보드는 Grafana "돌려받엔 (yen-back)" (uid yen-back), 알림 규칙은 yen-back-server 그룹입니다. 모든 라벨 값은 개수가 제한됩니다 (라우트 패턴, 플랫폼·이벤트 허용 목록, semver 형식 버전만 사용).

| 지표 | 종류 | 라벨 | 의미 |
|---|---|---|---|
| yenback_build_info | gauge | version, commit | 배포 버전 |
| yenback_http_requests_total | counter | method, route, status | 요청 수 |
| yenback_http_request_duration_seconds | histogram | method, route | 응답 시간 |
| yenback_http_requests_in_flight | gauge | | 처리 중 요청 |
| yenback_app_requests_total | counter | platform, app_version | 앱 요청 (헤더 기준) |
| yenback_app_events_total | counter | event, platform | 앱 활동 이벤트 |
| yenback_app_events_rejected_total | counter | reason | 거부된 이벤트 |
| yenback_collector_runs_total | counter | status (ok, empty, error) | 수집 실행 결과 |
| yenback_collector_upstream_calls_total | counter | result (ok, empty, error) | 수출입은행 호출 |
| yenback_collector_run_duration_seconds | histogram | | 수집 소요 시간 |
| yenback_collector_last_run_timestamp_seconds | gauge | | 마지막 실행 시각 |
| yenback_collector_last_success_timestamp_seconds | gauge | | 마지막 성공 시각 |
| yenback_exchange_rate_krw | gauge | currency | 최신 환율 (1단위당 원) |
| yenback_rate_base_date_timestamp_seconds | gauge | | 최신 기준일 |
| yenback_rate_age_days | gauge | | 기준일 경과일 (-1 = 없음) |
| go_*, process_* | | | Go 런타임 |

## 개발

| 작업 | 명령 |
|---|---|
| 테스트 | go test -race ./... |
| 정적 분석 | go vet ./... 와 staticcheck ./... |
| 로컬 실행 | KOREAEXIM_API_KEY=키 COLLECT_INTERVAL=30m go run ./cmd/api |
| 이미지 태그 갱신 (CI용) | go run ./cmd/bumpimage -file values.yaml -key image.tag -value 태그 |

배포는 GitOps입니다. main에 머지되면 GitHub Actions가 Docker Hub(ggorockee/yen-back-server)에 이미지를 올리고, infra 레포의 charts/helm/prod/yen-back/values.yaml 태그를 갱신하는 PR을 만들어 자동 머지합니다. ArgoCD가 이를 반영합니다.
