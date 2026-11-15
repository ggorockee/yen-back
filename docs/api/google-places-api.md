# Google Places API (근처 지점 검색) 명세와 비용

매장을 추가할 때 "돈키호테 도톤보리점 · 140m"처럼 가까운 지점을 보여주는 기능의 외부 API 명세, 비용, 약관 제약을 정리한 문서입니다.

- 결정일: 2026-11-15 (A안: Google만 사용, 비용 상한으로 무료 범위 유지)
- 서비스 적용 코드: server/internal/places/places.go, mobile/lib/ui/shops/shop_form_dialog.dart

> [!CAUTION]
> **결과(지점명·주소)를 저장하거나 캐시하면 안 됩니다.**
> Google Maps Platform 약관상 Places 결과는 place_id(무기한)와 좌표(최대 30일)만 캐시할 수 있고, 이름·주소 등 나머지 내용은 저장할 수 없습니다. reviewmaps의 네이버 검색처럼 DB 캐시 테이블에 쌓아 두는 방식은 쓸 수 없습니다. 그래서 서버는 결과를 캐시하지 않고 응답에 `Cache-Control: no-store`를 붙입니다.
> (약관 원문 일부와 제3자 정리로 확인. Places API Policies 원문은 확인 필요)

> [!WARNING]
> **상한을 올리면 바로 과금됩니다.**
> 하루 상한 160회는 월 무료 5,000회 안에 머물기 위한 값입니다. 올릴 때는 아래 비용표를 보고 결정하고, 서버 PLACES_DAILY_LIMIT와 GCP 쿼터를 함께 바꿔야 합니다.

> [!IMPORTANT]
> **무료 5,000회는 결제 계정 전체 합산입니다.**
> 같은 결제 계정에 연결된 다른 프로젝트가 Text Search Pro를 쓰면 무료 한도를 나눠 씁니다.

## 1. 비용 (Google 공식 가격표, 2026-11-15 확인)

우리가 요청하는 필드(id, displayName, shortFormattedAddress, location)는 Text Search Pro로 과금됩니다. 통화는 USD이며, 원화는 2026-11-13 수출입은행 매매기준율(1달러 = 1,332.4원)로 환산했습니다.

| 월 사용량 | 1,000회당 | 원화 환산 |
|---|---|---|
| 0 ~ 5,000회 | 무료 | 0원 |
| 5,001 ~ 100,000회 | $32.00 | 약 42,600원 |
| 100,001 ~ 500,000회 | $25.60 | 약 34,100원 |
| 500,001 ~ 1,000,000회 | $19.20 | 약 25,600원 |

예전의 월 $200 크레딧은 2025년 3월에 폐지됐습니다.

### 예상 비용 (여행 1건당 매장 8곳 추가 = 호출 8회 가정, 추측)

| 월 일본 여행 사용자 | 월 호출 | 상한 없을 때 | 현재 설정 (하루 160회) |
|---|---|---|---|
| 500명 | 4,000 | 0원 | 0원, 제한 없음 |
| 1,000명 | 8,000 | $96 (약 12.8만 원) | 0원, 붐비는 날 일부 시간 지점 목록 꺼짐 |
| 3,000명 | 24,000 | $608 (약 81만 원) | 0원, 지점 목록이 자주 꺼짐 |
| 10,000명 | 80,000 | $2,400 (약 320만 원) | 0원, 오전 중 소진 |

## 2. 비용을 0원으로 막는 장치

| 장치 | 위치 | 값 | 동작 |
|---|---|---|---|
| 서버 일일 상한 | PLACES_DAILY_LIMIT (infra values) | 160회 / KST 하루 | 넘으면 429 응답, 앱은 지점 목록만 숨김 |
| GCP 쿼터 | places.googleapis.com SearchTextRequest per day | 160회 / 하루 (태평양 시간 자정 초기화) | 서버에 버그가 있어도 Google이 161번째부터 거절 |
| 일본 밖 차단 | 서버 InJapan (지역 박스 5개) | 한국·대만·러시아 등 제외 | 여행 전 한국에서는 호출 0회 |
| 호출 시점 | 앱 | 체인 선택 시 1회, 직접 입력은 버튼을 누를 때 1회 | 타이핑 중에는 호출하지 않음 (테스트로 검증) |
| API 키 제한 | GCP API 키 | places.googleapis.com 전용 | 키가 유출돼도 다른 API에 못 씀 |

160 x 31일 = 4,960회로 월 무료 5,000회 안에 들어갑니다. GCP 쿼터는 태평양 시간 자정(한국 16~17시)에 초기화되므로, KST 기준 서버 상한과 초기화 시각이 다르지만 둘 다 하루 160회를 넘지 않습니다.

## 3. 요청과 응답

| 항목 | 값 |
|---|---|
| 엔드포인트 | POST https://places.googleapis.com/v1/places:searchText |
| 인증 | 헤더 X-Goog-Api-Key (서버만 보유, 앱에는 없음) |
| 필드 마스크 | places.id, places.displayName, places.shortFormattedAddress, places.location |
| 언어·지역 | languageCode=ko, regionCode=JP |
| 범위 | 사용자 위치 중심 반경 3km 우선(locationBias), 거리순(rankPreference=DISTANCE), 최대 10개 |

> [!NOTE]
> 필드 마스크에 평점·영업시간 등을 추가하면 더 비싼 등급(Enterprise, 1,000회당 $35, 무료 1,000회)으로 바뀝니다. 필드를 늘리기 전에 가격표를 확인하세요.

우리 서버 API: `GET /v1/places/search?q=돈키호테&lat=34.6687&lng=135.5013`

```json
{
  "places": [
    { "id": "ChIJ...", "name": "돈키호테 도톤보리점", "address": "7-13 Souemonchō, Chuo Ward, Osaka", "lat": 34.6693, "lng": 135.5026, "distance_m": 140 }
  ]
}
```

| 상태 코드 | 의미 | 앱 표시 |
|---|---|---|
| 200 | 성공 (일본 밖이면 빈 목록) | 지점 목록 또는 "근처에서 찾지 못했어요" |
| 400 | 검색어(1~40자)나 좌표 오류 | 오류 안내 |
| 429 | 오늘 상한 도달 | 오류 안내, 이름 직접 입력은 가능 |
| 502 | Google 호출 실패 | 오류 안내 |
| 503 | 키 미설정 | 오류 안내 |

## 4. 개인정보

- 위치는 매장 추가 화면을 열 때만, 사용 중 권한으로 요청합니다.
- 위치는 검색 요청에만 쓰고 서버에 저장하거나 로그에 남기지 않습니다 (접근 로그에는 경로만 기록).
- 같은 위치가 Google에도 전달되므로 앱 설정 화면의 개인정보 안내에 명시했습니다.

## 5. 모니터링

| 지표·알림 | 의미 |
|---|---|
| yenback_places_daily_calls / yenback_places_daily_limit | 오늘 과금 호출 수와 상한 |
| yenback_places_requests_total{result} | ok, limited, out_of_area, invalid, error, disabled |
| yenback_places_upstream_calls_total{result} | Google 호출 성공·실패 (과금 대상) |
| YenBackPlacesLimitReached | 상한 도달. 상한을 올릴지(과금) B안을 도입할지 결정 시점 |
| YenBackPlacesErrors | 키·결제·API 활성화 문제 |

## 6. 상한을 올릴 때 체크리스트

- [ ] 최근 한 달 yenback_places_daily_calls 추이와 상한 도달 빈도 확인
- [ ] 위 비용표로 예상 월 비용 계산
- [ ] GCP 결제 예산 알림 설정 (Billing > Budgets & alerts)
- [ ] infra charts/helm/prod/yen-back/values.yaml의 PLACES_DAILY_LIMIT 변경
- [ ] GCP 쿼터 SearchTextRequest per day 변경 (Service Usage API 또는 콘솔 > Places API > 할당량)
- [ ] 이 문서의 결정 내용 갱신

## 7. 나중에 검토할 대안 (B안)

OpenStreetMap 데이터(ODbL, 출처 표시 조건으로 저장 허용)를 서버 Postgres에 지점 DB로 쌓고, 지점명이 없을 때만 Google로 보완하는 방식입니다. 2026-11-15 도톤보리 반경 1.5km 조사에서 체인 매장 30곳 위치는 모두 있었지만 지점명은 약 1/3만 있었습니다. 상한 도달이 잦아지면 도입을 검토합니다.

## 참고

- [Google Maps Platform 가격표](https://developers.google.com/maps/billing-and-pricing/pricing)
- [2025년 3월 가격 체계 변경](https://developers.google.com/maps/billing-and-pricing/march-2025)
- [Google Maps Platform 서비스별 약관](https://cloud.google.com/maps-platform/terms/maps-service-terms/index-20240422)
- [Places API (New) Text Search](https://developers.google.com/maps/documentation/places/web-service/text-search)
