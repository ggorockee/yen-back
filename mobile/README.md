# 돌려받엔 mobile (Flutter)

일본 쇼핑 가격 계산, 매장별 면세 기준(5,000엔) 추적, 영수증 보관, 출국 알림, 한국 면세한도 경고 앱입니다.

## 구조

| 경로 | 내용 |
|---|---|
| lib/core | 순수 로직: 세금 계산, 매장·여행 합계, 제도 상수, 포맷 |
| lib/data | sqflite 로컬 DB, 서버 저장소(오프라인 캐시), 영수증 파일 |
| lib/services | 로컬 알림, AdMob, 인앱결제, 활동 이벤트 전송, Firebase Remote Config |
| lib/state | Riverpod 프로바이더 |
| lib/ui | 화면 (계산기, 매장, 영수증, 내 여행, 체크리스트, 설정, 온보딩) |
| test | 단위·DB·위젯 흐름 테스트 |

## 빌드 설정 (--dart-define)

| 이름 | 기본값 | 설명 |
|---|---|---|
| API_BASE_URL | 릴리스: https://yen-back.woohalabs.com, 디버그: http://10.0.2.2:8080 | 서버 주소 |
| ADMOB_BANNER_ANDROID / ADMOB_BANNER_IOS | 릴리스: 실제 ID, 그 외: Google 테스트 ID | 배너 광고 단위 |
| ADMOB_INTERSTITIAL_ANDROID / ADMOB_INTERSTITIAL_IOS | 릴리스: 실제 ID, 그 외: Google 테스트 ID | 전면 광고 단위 |

AdMob 앱 ID는 Android는 android/gradle.properties의 admobAppId, iOS는 ios/Flutter/AdMob.xcconfig의 ADMOB_APP_ID입니다. 광고 단위 ID는 릴리스 빌드에서 실제 ID, 그 외에는 Google 테스트 ID가 기본값입니다. 광고 제거 상품 ID는 remove_ads (비소모성)이며 두 스토어에 같은 ID로 등록해야 합니다.

## Firebase

프로젝트는 yen-back(woohalabs 계정)입니다. 리포가 공개라 설정 파일은 커밋하지 않습니다. 새 개발 환경에서는 Firebase 콘솔 또는 CLI(firebase apps:sdkconfig)로 받아 아래 위치에 둡니다.

| 플랫폼 | 파일 | 상태 |
|---|---|---|
| iOS | ios/Runner/GoogleService-Info.plist | 등록됨. 파일이 없으면 iOS 빌드가 실패함 |
| Android | android/app/google-services.json | 앱 미등록. Firebase 없이 앱 기본값으로 동작 |

Remote Config 값은 ../firebase/remoteconfig.template.json에서 관리하고 firebase 디렉터리에서 firebase deploy --only remoteconfig --project yen-back 으로 배포합니다. 키와 앱 기본값은 lib/services/remote_settings.dart에 있습니다.

| 구분 | 키 | 동작 |
|---|---|---|
| 광고 | show_banner_ad, show_interstitial_ad | 광고 종류별 on/off |
| 광고 | interstitial_max_per_session, interstitial_min_gap_minutes | 전면 광고 빈도 |
| 버전 | ios_min_version, android_min_version | 이보다 낮으면 강제 업데이트 (닫을 수 없음) |
| 버전 | ios_latest_version, android_latest_version | 이보다 낮으면 선택 업데이트 (버전당 1회) |
| 버전 | ios_store_url, android_store_url | 비어 있으면 업데이트 안내를 하지 않음 |
| 버전 | update_message | 안내 문구 (비우면 기본 문구) |

Analytics 수집은 기본으로 꺼져 있고, UMP가 동의가 필요 없는 지역(EEA, 영국, 스위스 밖)이라고 판단하면 켜집니다. 유럽에서도 측정하려면 AdMob 동의 모드를 켠 뒤 lib/services/install_measurement.dart를 바꿔야 합니다.

새 버전 배포 순서: 스토어 공개 확인 → latest 올림 → 필요할 때만 min 올림. 강제·선택 업데이트 노출과 반응은 서버 활동 이벤트(update_prompt_shown, force_update_shown, update_accepted, update_dismissed)로 집계됩니다.

## 업데이트 안내 카드 (1.1.1부터 적용)

2026-11-27 결정: 앞으로 업데이트는 화면 대부분을 덮는 넘김 카드로 알립니다. 세 앱 공통 표준은 infra 저장소 `claudedocs/app-update-card.md`, 기준 구현은 reviewmaps `mobile/`(2.2.3)입니다. 아직 적용 전이며 지금은 `lib/ui/update_gate.dart`의 작은 팝업을 씁니다.

| 순서 | 1.1.1에서 할 일 |
|---|---|
| 1 | `release_note` 모델·서비스·카드 화면 이식. 신규 설치는 `onboarding.done` 값이 없는 것으로 구분하고, 온보딩이 이 값을 저장하기 전에 기록 |
| 2 | `assets/release_notes.json` 추가(1~3장), pubspec 등록, 버전 일치 테스트 |
| 3 | `UpdateGate`가 팝업 대신 카드를 띄우게 변경. 강제·선택 규칙(버전당 1회)은 유지 |
| 4 | `firebase/remoteconfig.template.json`과 `remote_settings.dart`에 `release_note` 키 추가 |
| 5 | 이벤트(카드 표시, 선택, 본 장)를 앱과 서버 허용 목록에 함께 추가 |
| 6 | 이전 버전 위에 덮어 설치해 카드 1회 표시, 새 설치에는 없는지 확인 |

적용한 뒤에는 릴리스마다 `release_notes.json`을 갱신합니다.

## 개인정보

- 매장, 상품, 영수증 사진, 출국일은 기기에만 저장됩니다 (영수증 사진은 앱 전용 문서 폴더).
- 서버로는 환율·제도 조회와 활동 이벤트 횟수(이벤트 이름과 개수, 플랫폼·앱 버전 헤더)만 전송됩니다. 자체 서버로는 사용자·기기 식별자를 보내지 않습니다.
- Firebase(Analytics, Remote Config)가 앱 인스턴스 ID, 자동 수집 이벤트, 기기·지역 정보를 Google로 보냅니다. 여행·구매 데이터는 보내지 않습니다.

## 개발

| 작업 | 명령 |
|---|---|
| 의존성 | flutter pub get |
| 분석 | flutter analyze |
| 테스트 | flutter test |
| 포맷 | dart format -l 120 lib test |
| 실행 (로컬 서버) | flutter run (서버를 8080으로 띄운 상태) |
| 릴리스 빌드 | flutter build appbundle / flutter build ipa |
