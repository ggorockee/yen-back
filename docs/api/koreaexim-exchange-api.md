# 한국수출입은행 현재환율 Open API 명세

돌려받엔 서버(yen-back)가 환율을 받아오는 외부 API의 명세와 운영 시 주의사항을 정리한 문서입니다.

- 출처: 한국수출입은행 Open API 개발명세 (명세 수정일 2026-04-28)
- 문서 작성일: 2026-11-15
- 서비스 적용 코드: server/internal/koreaexim/client.go, server/internal/rates/service.go

> [!CAUTION]
> **인증키는 2년 뒤 파기될 수 있습니다.**
> 개인정보 보유기간(2년)이 지나면 신청 때 입력한 개인정보와 API 키가 파기되고, 호출 결과가 `result: 3`(인증코드 오류)으로 바뀝니다. 파기된 키는 다시 쓸 수 없어 새로 발급받아야 합니다.
> 파기 전에 등록 이메일(신청 계정)로 "개인정보 수집 재동의" 메일이 오고, 재동의하면 2년 연장됩니다.
> 현재 키 발급일은 **2026-11-15**이므로 **2028년 11월 전후로 재동의 메일을 반드시 확인**하세요.

> [!WARNING]
> **기존 도메인은 사용할 수 없습니다.**
> 요청 도메인이 `www.koreaexim.go.kr`에서 `oapi.koreaexim.go.kr`로 바뀌었고, 기존 도메인 병행 가동은 2026-04-30에 종료됐습니다. 예전 블로그·예제 코드의 URL을 그대로 쓰면 안 됩니다.

> [!IMPORTANT]
> **일일 호출 한도는 1,000회입니다.**
> 한도를 넘기면 `result: 4`가 반환되고 데이터가 제공되지 않습니다. 앱이 이 API를 직접 호출하면 안 되고, 반드시 서버가 받아 저장한 값을 조회해야 합니다.

> [!NOTE]
> **데이터는 영업일 오전 11시 전후에 하루 한 번 갱신됩니다.**
> 비영업일(주말·공휴일)이나 당일 11시 이전에 그날 날짜로 요청하면 데이터가 없습니다. 이 경우는 오류가 아니므로 직전 영업일 값을 써야 합니다.

## 1. 기본 정보

| 항목 | 내용 |
|---|---|
| 서비스명 | 현재환율 API |
| 제공기관 | 한국수출입은행 정보시스템부 |
| 담당 연락처 | 02-3779-6549 |
| API 유형 | REST (JSON) |
| 일일 제한 | 1,000회 |
| 이용허락조건 | 공공누리 |
| 등록일 / 수정일 | 2015-10-08 / 2026-04-28 |
| 사용하지 않는 API | 대출금리(AP02), 국제금리(AP03): 돌려받엔은 환율만 사용 |

## 2. 요청

요청 URL: `https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON`

| 변수명 | 타입 | 필수 | 설명 | 값 |
|---|---|---|---|---|
| authkey | String | 필수 | 인증키 | Open API 신청 시 발급된 키 |
| searchdate | String | 선택 | 조회 날짜 | 2015-01-01 또는 20150101 형식, 생략 시 현재일 |
| data | String | 필수 | API 종류 | AP01 환율, AP02 대출금리, AP03 국제금리 |

요청 예시: `https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON?authkey=발급키&searchdate=20261113&data=AP01`

> [!WARNING]
> 인증키가 URL 쿼리에 들어갑니다. 요청 URL을 로그에 그대로 남기지 마세요. 키는 GCP Secret Manager `prod-yen-back-credentials`의 `KOREAEXIM_API_KEY`에만 보관합니다.

## 3. 응답

통화별 객체의 배열입니다. 아래는 일부만 발췌한 예시입니다 (값은 명세 예시).

```json
[
  {
    "result": 1,
    "cur_unit": "JPY(100)",
    "ttb": "941.53",
    "tts": "960.56",
    "deal_bas_r": "951.05",
    "bkpr": "951",
    "yy_efee_r": "0.96833",
    "ten_dd_efee_r": "0.0242",
    "kftc_bkpr": "951",
    "kftc_deal_bas_r": "951.05",
    "cur_nm": "일본 옌"
  },
  {
    "result": 1,
    "cur_unit": "USD",
    "ttb": "1,056.23",
    "tts": "1,077.56",
    "deal_bas_r": "1,066.9",
    "bkpr": "1,066",
    "yy_efee_r": "2.69465",
    "ten_dd_efee_r": "0.07485",
    "kftc_bkpr": "1,071",
    "kftc_deal_bas_r": "1,071.4",
    "cur_nm": "미국 달러"
  }
]
```

| 변수명 | 타입 | 설명 | 돌려받엔 사용 |
|---|---|---|---|
| result | Integer | 조회 결과 코드 (아래 표) | 사용 |
| cur_unit | String | 통화코드. 일부는 단위 포함 (예: JPY(100)) | 사용 |
| cur_nm | String | 국가/통화명 | |
| ttb | String | 전신환(송금) 받으실 때 | |
| tts | String | 전신환(송금) 보내실 때 | |
| deal_bas_r | String | 매매기준율 | 사용 |
| bkpr | String | 장부가격 | |
| yy_efee_r | String | 년환가료율 | |
| ten_dd_efee_r | String | 10일환가료율 | |
| kftc_deal_bas_r | String | 서울외국환중개 매매기준율 | |
| kftc_bkpr | String | 서울외국환중개 장부가격 | |

### 결과 코드

| result | 의미 | 돌려받엔 처리 |
|---|---|---|
| 1 | 성공 | 저장 |
| 2 | DATA 코드 오류 (data 값 잘못됨) | 오류로 기록, 수집 실패 |
| 3 | 인증코드 오류. 2년 만료로 키가 파기됐을 수 있음 | 오류로 기록, 로그에 재발급 안내 |
| 4 | 일일 제한 횟수 마감 | 오류로 기록, 다음 날 자동 복구 |

> [!IMPORTANT]
> **숫자가 문자열이고 쉼표가 들어 있습니다.** 예: `"1,066.9"`. 쉼표를 제거한 뒤 숫자로 바꿔야 합니다.

> [!IMPORTANT]
> **엔화는 100엔 기준입니다.** `cur_unit`이 `JPY(100)`이면 `deal_bas_r`은 100엔당 원화입니다. 1엔당 값은 100으로 나눠야 합니다. IDR(100) 등 다른 통화도 같은 형식입니다.

> [!NOTE]
> **데이터가 없을 때의 응답:** 명세에는 null이 반환된다고 되어 있지만, 2026-11-15(일) 실제 응답은 빈 배열 `[]`이었습니다. 두 경우 모두 "데이터 없음"으로 처리합니다.

> [!NOTE]
> **매매기준율은 실제 결제 환율이 아닙니다.** 카드 결제나 환전에는 수수료와 스프레드가 붙으므로 앱 화면에 "기준 환율" 또는 "참고용"으로 표시합니다.

## 4. 돌려받엔 서버 적용 방식

| 항목 | 내용 |
|---|---|
| 호출 주체 | Go 서버만 호출. 앱은 서버의 GET /v1/rates/latest 조회 |
| 수집 주기 | 서버 안 스케줄러 30분 간격 (COLLECT_INTERVAL=30m) |
| 조회 방식 | 오늘(KST)부터 하루씩 거슬러 조회하고, 이미 저장된 날짜에 닿으면 멈춤 |
| 최대 역조회 | 10일 (설·추석 연휴 대비) |
| 사용 통화 | JPY, USD (USD는 한국 면세한도 800달러 환산용) |
| 저장 단위 | 1단위당 원화로 변환해 저장 (JPY 921.35 → 9.2135원/엔), 원본 문자열도 함께 보관 |
| 호출량 | 실행당 0~3회 수준, 하루 최대 약 48회 (한도의 5% 미만) |
| 오래된 값 표시 | 기준일이 4일보다 오래되면 응답에 stale=true |
| 요청 타임아웃 | 10초 |
| 키 보관 | GCP Secret Manager prod-yen-back-credentials (프로젝트 yanggo-514212) → ExternalSecret → Pod 환경변수 |

실제 동작 확인 (2026-11-15 일요일, 로컬): 11-15, 11-14는 데이터 없음, 11-13(금) 값을 3회 호출로 저장. JPY(100) 833.45원, USD 1,332.4원.

## 5. 모니터링과 알림

| 알림 | 조건 | 의미와 대응 |
|---|---|---|
| YenBackNoRates | 환율이 30분간 한 번도 없음 | 키 미등록, 키 오류, 네트워크 문제. 시크릿과 수집 로그 확인 |
| YenBackCollectorFailing | 3시간 동안 수집이 모두 실패 | result=3이면 키 파기 가능성(재발급), result=4면 호출량 확인 |
| YenBackRatesStale | 기준일이 4일 초과로 1시간 지속 | 연휴에는 정상. 평일이면 API 장애 확인 |

관련 지표: yenback_collector_runs_total, yenback_collector_upstream_calls_total, yenback_rate_age_days, yenback_exchange_rate_krw. Grafana 대시보드 "돌려받엔 (yen-back)"의 "환율 수집" 행에서 확인합니다.

## 6. 인증키 재발급 절차

- [ ] 한국수출입은행 Open API 페이지에서 "현재환율 API" 인증키 신청 (활용용도: 모바일 앱 서비스)
- [ ] 발급된 키로 한 번 호출해 result=1 확인
- [ ] GCP Secret Manager `prod-yen-back-credentials`에 새 버전 추가 (JSON의 KOREAEXIM_API_KEY만 교체, INTERNAL_TOKEN은 유지)
- [ ] 이전 버전 비활성화
- [ ] ExternalSecret 갱신 대기(최대 1시간) 후 yen-back Pod 재시작
- [ ] Grafana에서 수집 결과가 ok로 바뀌었는지 확인
- [ ] 이 문서의 "현재 키 발급일" 갱신

## 7. 변경 이력 (제공기관 공지)

| 적용일 | 내용 |
|---|---|
| 2026-04-30 | 기존 도메인(www.koreaexim.go.kr) 병행 가동 중단 |
| 2025-06-25 | 요청 도메인 변경 (www.koreaexim.go.kr → oapi.koreaexim.go.kr) |
| 2020-07-13 | 일일 호출 한도 1,000회 적용 (초과 시 result=4) |

## 8. 참고: 방화벽 허용이 필요한 경우

GKE에서 외부로 나가는 요청은 현재 막혀 있지 않아 설정이 필요 없습니다. 이그레스 제한을 도입한다면 아래 IP를 허용해야 합니다.

| 용도 | IP |
|---|---|
| 홈페이지 접속 | 39.115.136.135 |
| API 호출 | 39.115.136.167 |
