# 돌려받엔 mobile (Flutter)

일본 쇼핑 가격 계산, 매장별 면세 기준(5,000엔) 추적, 영수증 보관, 출국 알림, 한국 면세한도 경고 앱입니다.

## 구조

| 경로 | 내용 |
|---|---|
| lib/core | 순수 로직: 세금 계산, 매장·여행 합계, 제도 상수, 포맷 |
| lib/data | sqflite 로컬 DB, 서버 저장소(오프라인 캐시), 영수증 파일 |
| lib/services | 로컬 알림, AdMob, 인앱결제, 활동 이벤트 전송 |
| lib/state | Riverpod 프로바이더 |
| lib/ui | 화면 (계산기, 매장, 영수증, 내 여행, 체크리스트, 설정, 온보딩) |
| test | 단위·DB·위젯 흐름 테스트 |

## 빌드 설정 (--dart-define)

| 이름 | 기본값 | 설명 |
|---|---|---|
| API_BASE_URL | 릴리스: https://yen-back.woohalabs.com, 디버그: http://10.0.2.2:8080 | 서버 주소 |
| ADMOB_BANNER_ANDROID / ADMOB_BANNER_IOS | Google 테스트 ID | 배너 광고 단위 |
| ADMOB_INTERSTITIAL_ANDROID / ADMOB_INTERSTITIAL_IOS | Google 테스트 ID | 전면 광고 단위 |

AdMob 앱 ID는 Android는 Gradle 속성 admobAppId, iOS는 ios/Flutter/AdMob.xcconfig의 ADMOB_APP_ID로 바꿉니다. 기본값은 Google 샘플 ID입니다. 광고 제거 상품 ID는 remove_ads (비소모성)이며 두 스토어에 같은 ID로 등록해야 합니다.

## 개인정보

- 매장, 상품, 영수증 사진, 출국일은 기기에만 저장됩니다 (영수증 사진은 앱 전용 문서 폴더).
- 서버로는 환율·제도 조회와 활동 이벤트 횟수(이벤트 이름과 개수, 플랫폼·앱 버전 헤더)만 전송됩니다. 사용자·기기 식별자는 보내지 않습니다.

## 개발

| 작업 | 명령 |
|---|---|
| 의존성 | flutter pub get |
| 분석 | flutter analyze |
| 테스트 | flutter test |
| 포맷 | dart format -l 120 lib test |
| 실행 (로컬 서버) | flutter run (서버를 8080으로 띄운 상태) |
| 릴리스 빌드 | flutter build appbundle --dart-define=ADMOB_BANNER_ANDROID=실제ID ... |
