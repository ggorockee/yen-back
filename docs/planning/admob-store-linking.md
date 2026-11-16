# AdMob 스토어 연결 체크리스트 (출시 후)

AdMob 콘솔(woohalabs@gmail.com)에서 돌려받엔 앱 두 개가 "검토 필요 / 광고 게재가 제한됨 - 스토어를 추가하여 한도 해제" 상태다. 앱이 스토어에 **정식 공개된 뒤에만** 스토어 연결이 가능하므로, 각 플랫폼 출시 직후 아래 순서로 진행한다.

작성일: 2026-11-16

## 현재 상태

| 항목 | Android | iOS |
|---|---|---|
| AdMob 앱 이름 | 돌려받엔 Android | 돌려받엔 iOS |
| AdMob 앱 ID | ca-app-pub-8516861197467665~8757073285 | ca-app-pub-8516861197467665~1203171840 |
| 코드의 앱 ID | android/gradle.properties의 admobAppId (일치) | ios/Flutter/AdMob.xcconfig (일치) |
| 광고 단위 | 배너, 전면 2개 | 배너, 전면 2개 |
| 스토어 상태 | Play 공개 테스트(Alpha)만 진행, 프로덕션 미출시 | 1.0 심사 대기 중 |
| 스토어 식별자 | com.woohalabs.yenback | App Store 앱 ID 6835096650 |
| app-ads.txt | https://yen-back.woohalabs.com/app-ads.txt (PR #7) | 같음 |

## 1. 사전 확인 (출시 전에 끝내기)

- [x] 서버에 /app-ads.txt 추가 (PR #7 머지)
- [ ] https://yen-back.woohalabs.com/app-ads.txt 가 200으로 응답하고 내용이 "google.com, pub-8516861197467665, DIRECT, f08c47fec0942fa0" 인지 확인
- [ ] Play Console 스토어 설정의 웹사이트가 https://yen-back.woohalabs.com 인지 확인
- [ ] App Store Connect 앱 정보의 마케팅 URL(개발자 웹사이트)이 https://yen-back.woohalabs.com 인지 확인

## 2. Android 출시 후 (Play 프로덕션 공개 직후)

- [ ] Play 스토어에서 "돌려받엔" 또는 com.woohalabs.yenback 검색 시 앱이 보이는지 확인 (공개 후 수 시간 걸릴 수 있음)
- [ ] AdMob → 앱 → 돌려받엔 Android → "스토어 추가"
- [ ] Google Play 검색창에 com.woohalabs.yenback 입력 → 검색 결과에서 돌려받엔 선택 → 계속
- [ ] 패키지 이름 확인 단계에서 com.woohalabs.yenback 일치 확인 → 완료
- [ ] AdMob 앱 목록에서 스토어 열이 "Google Play"로 바뀌었는지 확인
- [ ] 승인 상태가 "검토 필요" → "준비됨"으로 바뀌는지 확인 (AdMob 검토는 보통 수일 소요)

## 3. iOS 출시 후 (App Store 공개 직후)

- [ ] App Store에서 앱이 검색되는지 확인 (공개 후 수 시간 걸릴 수 있음)
- [ ] AdMob → 앱 → 돌려받엔 iOS → "스토어 추가"
- [ ] App Store 검색창에 6835096650 또는 앱 이름 입력 → 돌려받엔 선택 → 계속
- [ ] AdMob 앱 목록에서 스토어 열이 "App Store"로 바뀌었는지 확인
- [ ] 승인 상태가 "준비됨"으로 바뀌는지 확인

참고: EU DSA를 "EU 배포 안 함"으로 신고해서 iOS 앱은 EU 27개국 App Store에 노출되지 않는다. AdMob 연결에는 영향 없음.

## 4. app-ads.txt 확인 (스토어 연결 후 1~7일)

- [ ] AdMob → 앱 → app-ads.txt 화면에 yen-back.woohalabs.com/app-ads.txt 행이 돌려받엔(Android, iOS)으로 표시되는지 확인
- [ ] 상태가 "app-ads.txt 파일을 찾아서 확인했습니다"인지 확인
- [ ] 7일이 지나도 안 보이면 스토어의 개발자 웹사이트 URL이 정확한지 다시 확인

## 5. 광고 게재 확인

- [ ] AdMob 앱 목록에서 "광고 게재가 제한됨" 문구가 사라졌는지 확인
- [ ] 보고서에서 돌려받엔 Android, iOS의 노출수가 집계되는지 확인
- [ ] 릴리스 빌드에서 배너(계산기, 매장, 내 여행 탭)와 전면 광고(매장, 영수증 저장 후)가 실제 광고로 나오는지 실기기 확인

## 문제 해결

| 증상 | 원인 | 조치 |
|---|---|---|
| 스토어 추가 검색에 앱이 안 나옴 | 공개 직후 색인 지연, 또는 테스트 트랙만 공개 | 프로덕션 공개 여부 확인 후 수 시간 뒤 재시도 |
| app-ads.txt 행이 계속 안 보임 | 개발자 웹사이트 도메인 불일치, 서버 미배포 | 스토어 웹사이트 URL과 /app-ads.txt 응답 확인 |
| 승인 상태가 계속 "검토 필요" | AdMob 앱 검토 진행 중 | 수일 대기, 정책 센터에서 위반 사항 확인 |
| EU 사용자에게 광고가 거의 안 나옴 | 동의 거부 또는 UMP 미적용 버전 | PR #8(UMP 동의) 포함 버전인지 확인 |
