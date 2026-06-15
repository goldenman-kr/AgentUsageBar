# Claude 사용량 위젯 (macOS)

Claude 구독 사용량 — **현재 세션**과 **주간 한도** — 을 macOS **메뉴바 앱**과 **WidgetKit 위젯**(알림 센터 / 바탕화면)으로 보여줍니다. 데스크톱 앱 설정의 "사용량" 페이지와 동일한 수치를 표시합니다.

> ⚠️ **비공식 도구 · 본인 책임 사용(use at your own risk).** 이 프로젝트는 Anthropic의 **문서화되지 않은 내부 엔드포인트**를 호출하고, **Claude Code가 macOS Keychain에 저장한 OAuth 토큰**을 재사용합니다. Anthropic이 만들거나 승인·보증한 것이 **아닙니다**. 사용에 따른 약관 위반·계정 제재·예고 없는 동작 중단의 가능성이 있습니다. 자세한 내용은 아래 [면책 조항](#면책-조항-disclaimer)을 반드시 확인하세요.

```
메뉴바:   ◔ 12% · 12%          ← 현재 세션 % · 주간 %

팝오버 / 위젯:
┌──────────────────────────────┐
│ Claude 사용량        Max (20x)│
│ 현재 세션                 12% │
│ ▓▓░░░░░░░░░░  3시간 45분 후   │
│ 주간 · 모든 모델          12% │
│ ▓▓░░░░░░░░░░  수 오후 7:59… │
│ Sonnet 전용                0% │
│ 마지막 업데이트: 방금         │
└──────────────────────────────┘
```

## 데이터 출처 (어떻게 동작하나)

별도 로그인이 없습니다. **Claude Code CLI/데스크톱 앱이 macOS Keychain에 저장한 OAuth 액세스 토큰을 재사용**해, Claude 데스크톱 앱이 "사용량" 페이지에 쓰는 것과 동일한 사용량 엔드포인트를 호출합니다. 화면에 표시되는 항목:

- **현재 세션**(5시간 창) · **주간 한도**(모든 모델 / Sonnet 전용 / Opus 전용)
- **추가 사용 크레딧**, **플랜 라벨**(예: Max (20x))

> 정확한 엔드포인트·요청 헤더·Keychain 항목·응답 필드 매핑 등 구현 세부는 소스 코드를 참고하세요 — `Packages/ClaudeUsageCore/Sources/ClaudeUsageCore/`의 `Constants.swift`, `KeychainTokenStore.swift`, `UsageAPIClient.swift`, `Models.swift`. (이 도구의 약관상 유의사항은 아래 [면책 조항](#면책-조항-disclaimer) 참고.)

> **토큰은 읽기 전용입니다.** 위젯은 토큰을 갱신·회전하지 않습니다(그러면 Claude Code의 refresh 토큰이 무효화될 수 있음). 토큰이 만료되면 마지막 수치를 유지한 채 안내를 표시하고, Claude Code/데스크톱 앱이 토큰을 갱신하면 다음 새로고침에서 자동으로 따라잡습니다.

## 아키텍처

```
Packages/ClaudeUsageCore/        SwiftPM 공유 패키지
  ├─ ClaudeUsageCore  (라이브러리) 모델·Keychain·API 클라이언트·포매터·App Group 코덱
  ├─ ClaudeUsageUI    (라이브러리) 공유 SwiftUI 컴포넌트(MeterBar, MetricRow)
  └─ usage-probe      (실행파일)   라이브 API 검증용 CLI

App/ClaudeUsageBar/              메뉴바 앱 (비샌드박스)  ← 데이터 소유자
  토큰 읽기 → 60초마다 fetch → App Group에 스냅샷 기록 → 위젯 reload

Widget/ClaudeUsageWidget/        WidgetKit 확장 (샌드박스)  ← 데이터 소비자
  App Group 스냅샷만 읽어 렌더 (네트워크·Keychain 불필요)
```

메뉴바 앱이 네트워크를 전담하고, 위젯은 App Group에 저장된 스냅샷만 읽습니다. 덕분에 위젯은 WidgetKit의 갱신 예산을 I/O에 낭비하지 않고, Keychain 접근 제약도 우회합니다.

## 빌드 & 실행

요구사항: macOS 14+, Xcode 16+(여기선 26.5), `xcodegen`(`brew install xcodegen`).

### 1) 데이터 파이프라인 검증 (팀 불필요)
```bash
./scripts/verify.sh      # 단위 테스트 + 실제 API 라이브 프로브
```

### 2) 메뉴바 앱만 빠르게 시험 (팀 불필요, ad-hoc)
```bash
./scripts/run-local.sh   # ad-hoc 서명 → 메뉴바 앱 실행
```
이 모드에선 App Group이 없어 **위젯에는 데이터가 전달되지 않습니다**(메뉴바 앱은 완전 동작).

### 3) 전체(앱 + 위젯) 서명 빌드
```bash
DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build.sh
# 팀 ID 확인:  security find-identity -v -p codesigning
```
또는 Xcode에서 직접:
```bash
xcodegen generate && open ClaudeUsage.xcodeproj
```
1. `ClaudeUsageBar` · `ClaudeUsageWidget` 두 타깃의 **Signing & Capabilities**에서 본인 **Team** 선택.
2. App Group ID는 entitlements·Info.plist에서 `group.$(DEVELOPMENT_TEAM).com.hubinsoft.claudeusage` 로 정의되어, 선택한 팀 ID가 빌드 시 자동 치환됩니다(런타임엔 Info.plist에서 읽음). **macOS는 App Group ID에 Team ID prefix가 필수**라 이렇게 구성했습니다 — 별도 수정 불필요. (reverse-DNS 부분을 바꾸려면 두 entitlements·`project.yml`의 `AppGroupIdentifier`를 함께 수정.)
3. `ClaudeUsageBar` 스킴 **Run**.

### 위젯 추가
앱을 한 번 실행해 두면(스냅샷이 기록됨) → 알림 센터 열기 → **위젯 편집** → "Claude 사용량" 추가. 바탕화면에 두려면 바탕화면 우클릭 → **위젯 편집**.

### 로그인 시 자동 실행
팝오버의 "로그인 시 자동 실행" 체크박스 (`SMAppService`). `/Applications`에 설치 후 사용 권장.

## 첫 실행 시 Keychain 권한
서명된 앱이 `Claude Code-credentials` 항목을 처음 읽을 때 macOS가 접근 허용을 물을 수 있습니다 → **항상 허용**을 선택하세요.

## 개인정보
- 토큰과 사용량은 **로컬에서만** 처리되어 `api.anthropic.com`(데스크톱 앱과 동일)에만 전송됩니다. 외부 서버로 보내지 않습니다.
- 토큰 값은 로그에 남기지 않습니다(진단 로그는 % 수치·플랜 라벨만).

## 한계 / 메모
- 비공식 엔드포인트를 사용합니다(데스크톱 앱이 쓰는 것과 동일). Anthropic이 변경하면 깨질 수 있습니다.
- 폴링 간격은 **5분**(`UsageViewModel.refreshInterval`)이고, 팝오버 열기/절전 복귀로 인한 자동 호출은 45초 디바운스됩니다. HTTP 429를 받으면 `Retry-After`를 존중해(없으면 2분) 자동 백오프합니다. 더 자주 보려면 `refreshInterval`을 줄이되 rate limit에 유의하세요.
- WidgetKit 위젯은 시스템 갱신 예산을 따릅니다. 정확한 즉시 갱신은 메뉴바 앱이 `reloadAllTimelines()`로 밀어줍니다.
- 번들 ID는 `com.hubinsoft.*` 기준이고, App Group ID는 `group.<TeamID>.com.hubinsoft.claudeusage`(Team ID 자동 치환)입니다. macOS App Group은 Team ID prefix가 필수이므로 이 형식을 사용합니다.

## 면책 조항 (Disclaimer)

**이 프로젝트는 Anthropic이 만들거나 후원·보증·승인한 것이 아니며, Anthropic과 아무런 제휴 관계가 없습니다.** "Claude"와 "Anthropic"은 Anthropic PBC의 상표입니다. 식별 목적으로만 사용했습니다.

이 도구는 다음에 의존합니다:
- Anthropic의 **문서화되지 않은 내부 사용량 엔드포인트** 호출 (데스크톱 앱이 쓰는 것과 동일)
- **Claude Code가 macOS Keychain에 저장한 OAuth 액세스 토큰** 재사용 (API 키가 아님)

### Anthropic 이용약관과의 충돌 가능성

[Anthropic Consumer Terms of Service](https://www.anthropic.com/legal/consumer-terms)(Claude.ai·Claude 앱·Pro/Max 구독에 적용)의 다음 조항과 **충돌할 소지가 있습니다.** 직접 확인하고 판단하세요:

- **§3 (Use of our Services)** — *"Anthropic API Key로 접근하거나 별도로 명시적으로 허용된 경우를 제외하고, 봇·스크립트 등 **자동화된/비인간적 수단으로 Services에 접근**하는 것"* 을 금지. 이 위젯은 **API 키가 아닌 구독 OAuth 토큰으로 스크립트(앱)가 자동 접근**하므로 이 예외(API 키)에 해당하지 않습니다.
- **§3** — *"Services를 **리버스 엔지니어링**·디컴파일·디스어셈블하는 것"* 을 금지. 엔드포인트를 클라이언트 분석으로 알아낸 방식이 이 조항과 긴장 관계에 있습니다.
- **§2 (Account creation and access)** — *"계정 로그인 정보·API 키·자격증명을 **타인과 공유**하지 말 것."* 이 도구는 토큰을 외부로 전송하지 않고 같은 사용자의 기기에서만 쓰므로 "타인 공유"에 직접 해당하진 않지만, **README가 토큰 추출 방법을 공개**한다는 점은 인지하세요.

> ⚠️ 위는 법률 자문이 아닙니다. 약관 해석·적용은 변경될 수 있으며 최종 판단·책임은 사용자에게 있습니다. **계정 조치(경고·정지) 또는 예고 없는 동작 중단**의 위험을 감수하고 사용하세요. 우려되면 **개인 로컬 용도로만** 사용하고 광범위한 배포는 자제하는 것을 권장합니다.

### 보증·책임의 부인

이 소프트웨어는 명시적·묵시적 보증 없이 "있는 그대로(AS IS)" 제공됩니다. 사용으로 인한 어떠한 손해·계정 문제에 대해서도 작성자는 책임지지 않습니다.
