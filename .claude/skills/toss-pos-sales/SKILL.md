---
name: toss-pos-sales
description: 토스 포스에서 매출 데이터 엑셀 추출. 다음 요청 시 트리거 - "토스 매출 뽑아줘", "매출 데이터 추출", "토스 포스 엑셀", "매출 리포트 다운로드", "POS 매출", "매출 내보내기"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write, Glob, Grep
argument-hint: [기간: 예) 6개월, 1년, 2025.01~2025.06]
---

# 토스 포스 매출 데이터 추출

토스 포스 맥앱에서 매출 리포트를 엑셀로 추출하는 자동화 스킬.

## 필수 도구

- `toss-vision` (Apple Vision OCR 헬퍼): `${CLAUDE_SKILL_DIR}/scripts/toss-vision` 또는 `/Users/jack/.local/bin/toss-vision`
- `cliclick` (좌표 클릭): `/opt/homebrew/bin/cliclick`
- `openpyxl`, `msoffcrypto-tool` (엑셀 검증용 Python 패키지)
- 검증 스크립트: `${CLAUDE_SKILL_DIR}/scripts/verify-sales-data.py`

### toss-vision 빌드 (바이너리가 없을 때)
```bash
cd ${CLAUDE_SKILL_DIR}/toss-vision
swift build -c release
cp .build/release/toss-vision ../scripts/toss-vision
```

### 셋업 alias (선택)
```bash
TV="${CLAUDE_SKILL_DIR}/scripts/toss-vision"
```

## 핵심 규칙

### 좌표 체계
- `toss-vision`의 좌표 = `cliclick`의 좌표 = macOS 글로벌 좌표 (1:1 매핑)
- 항상 `toss-vision list`로 화면 상태를 확인한 후 행동할 것
- 스크린샷 추정 금지 — OCR 결과만 신뢰

### 날짜 입력 패턴 (WebView 입력란)
```bash
# 1. 시작일 입력란 클릭
toss-vision tap "년.월.일"

# 2. 전체선택 → 삭제 → 타이핑 → Enter로 확정
osascript -e 'tell application "System Events" to keystroke "a" using command down'
osascript -e 'tell application "System Events" to key code 51'  # Delete
cliclick t:20250320
osascript -e 'tell application "System Events" to key code 36'  # Enter (필수!)

# 3. 종료일로 이동: 시작일 "일" 부분 더블클릭 → Tab
cliclick dc:{시작일_x+26},{시작일_y}
osascript -e 'tell application "System Events" to key code 48'  # Tab

# 4. 종료일 입력 → Enter
osascript -e 'tell application "System Events" to keystroke "a" using command down'
osascript -e 'tell application "System Events" to key code 51'
cliclick t:20250919
osascript -e 'tell application "System Events" to key code 36'  # Enter (필수!)
```

**핵심**: 날짜 입력 후 반드시 **Enter**를 쳐야 값이 확정되고 "파일 만들기" 버튼이 활성화됨!

### PIN 입력
- PIN 패드의 0 버튼 좌표: **(780, 580)** (윈도우 위치 135,25 기준)
- 기본 PIN: `0000` (4번 클릭)
- PIN 좌표는 윈도우 위치에 따라 달라지므로, 윈도우 위치 변경 시 재계산 필요

### 6개월 제한
- 토스 포스 엑셀 내보내기는 **최대 6개월** 단위
- 6개월 초과 요청 시 자동으로 분할:
  - 1년 → 2분할 (전반기/후반기)
  - 2년 → 4분할

### 파일 암호화
- 다운로드된 xlsx는 **CDFV2 Encrypted** (PIN으로 암호화)
- 복호화: `msoffcrypto-tool`로 해독 가능
- 파일 내 시트: `데이터 기준`, `결제 합계`, `상품 주문 합계`, `결제 상세내역`, `상품 주문 상세내역`

## 실행 플로우

```
1. 토스 포스 활성화
2. 햄버거 메뉴 → 매출 리포트 (이미 매출 리포트 화면이면 스킵)
3. "엑셀 내보내기" 탭
4. 기간 입력 (6개월 단위로 분할)
5. "파일 만들기" 클릭
6. PIN 0000 입력
7. 파일 생성 대기 (15~30초)
8. "받기" 클릭 → Enter로 저장
9. 다음 기간 반복
10. 전체 파일 검증 (날짜 커버리지, 빠진 날짜)
```

### 상세 단계

#### Step 1: 앱 활성화 및 상태 확인
```bash
osascript -e 'tell application "Toss POS" to activate'
sleep 0.5
toss-vision list
```

#### Step 2: 매출 리포트 화면으로 이동
`toss-vision list` 결과에 "매출 리포트"가 보이면 이미 해당 화면.
아니면:
```bash
toss-vision tap "≡"  # 또는 햄버거 아이콘 좌표
toss-vision tap "매출 리포트"
```

#### Step 3: 엑셀 내보내기
```bash
toss-vision tap "엑셀 내보내기"
```

#### Step 4: 날짜 입력
위의 "날짜 입력 패턴" 참조. 항상 `toss-vision list`로 결과 확인.

#### Step 5: 파일 만들기 + PIN
```bash
cliclick c:{파일만들기_x},{파일만들기_y}
sleep 3
# PIN 0000
cliclick c:780,580 && sleep 0.3
cliclick c:780,580 && sleep 0.3
cliclick c:780,580 && sleep 0.3
cliclick c:780,580
```

#### Step 6: 대기 및 다운로드
```bash
sleep 15
toss-vision list  # "받기" 버튼 확인
toss-vision tap "받기"
sleep 3
osascript -e 'tell application "System Events" to key code 36'  # Enter로 저장
```

#### Step 7: 검증
```python
import msoffcrypto, openpyxl, io
# 파일 복호화 후 날짜 커버리지 검증
# 시트: "결제 상세내역" → "결제기준일자" 컬럼
# 시트: "상품 주문 상세내역" → "주문기준일자" 컬럼
```

## 삽질 기록 & 트러블슈팅

### 1. WebView 앱이라 AppleScript UI 요소 접근 불가
**증상**: `entire contents of window 1`로 버튼을 찾으려 하면 닫기/최소화/전체화면 3개만 나옴
**원인**: 토스 포스 내부가 WebView(웹 렌더링)라서 네이티브 UI 요소로 노출 안 됨
**해결**: `toss-vision` (Apple Vision OCR)로 화면 텍스트를 읽고 좌표를 얻어서 `cliclick`으로 클릭

### 2. 스크린샷에서 좌표 추정하면 빗나감
**증상**: 전체 스크린샷을 AI가 보고 추정한 좌표가 수십 px 빗나감 (3~5번 반복 실패)
**원인**: 전체 화면 이미지에서 작은 텍스트 위치를 정확히 추정하기 어려움
**해결**: `toss-vision`이 OCR bounding box에서 정확한 좌표를 반환 → 스크린샷 추정 자체를 하지 말 것

### 3. 날짜 입력이 안 됨 — keystroke가 WebView에 전달 안 됨
**증상**: `keystroke "2025.09.20"`이 입력란에 안 들어감
**원인**: WebView 내부의 input 필드는 macOS keystroke 이벤트를 직접 받지 못함
**해결**: `cliclick t:20250920` 사용 → cliclick의 타이핑은 저수준 키 이벤트라 WebView에도 전달됨
**주의**: 날짜 구분자(`.`)는 입력하지 않음! `20250920`처럼 숫자만 입력하면 앱이 자동으로 `2025.09.20`으로 포맷

### 4. 날짜 입력 후 "파일 만들기" 버튼이 반응 없음 ⚠️ 가장 큰 삽질
**증상**: 날짜를 정확히 입력했는데 "파일 만들기" 클릭해도 아무 반응 없음 (PIN 화면 안 뜸)
**원인**: 날짜 입력 후 **Enter를 안 쳐서** 값이 확정되지 않은 상태. WebView 입력란은 Enter를 쳐야 onChange 이벤트가 발생하고 값이 실제로 반영됨
**해결**: 날짜 타이핑 후 반드시 Enter:
```bash
cliclick t:20250920
osascript -e 'tell application "System Events" to key code 36'  # Enter 필수!!!
```

### 5. 종료일 입력란에 포커스가 안 감
**증상**: 시작일 입력 후 종료일 입력란을 클릭해도 시작일에 계속 타이핑됨
**원인**: WebView의 날짜 입력란이 년/월/일 각각 분리된 서브필드로 구성됨. 단순 클릭으로는 종료일 필드로 이동 안 됨
**해결**: 시작일의 "일" 부분을 **더블클릭** → **Tab** 키로 종료일로 이동
```bash
# 시작일 Enter로 확정 먼저!
cliclick c:{시작일_x},{시작일_y}
osascript -e 'tell application "System Events" to key code 36'  # Enter

# 그 다음 더블클릭 → Tab
cliclick dc:{시작일_x+26},{시작일_y}  # "일" 부분 더블클릭
osascript -e 'tell application "System Events" to key code 48'  # Tab → 종료일로 이동
```
**핵심 순서**: 시작일 입력 → **Enter** → 더블클릭 → **Tab** → 종료일 입력 → **Enter**

### 6. `toss-vision tap ">"` 가 엉뚱한 곳을 클릭
**증상**: 달력의 `>` 화살표를 tap하려 했는데 매출현황의 `<>` 텍스트를 잡아버림
**원인**: OCR이 `>` 텍스트를 여러 곳에서 발견하면 첫 번째 매칭을 반환
**해결**: 특수문자나 짧은 텍스트는 `toss-vision tap` 대신 `toss-vision find`로 좌표 확인 후 직접 `cliclick c:x,y` 사용

### 7. PIN 패드 클릭 좌표가 안 맞음
**증상**: PIN 패드의 0을 클릭하려는데 빗나감
**원인**: 외부 모니터 + Retina 듀얼 모니터 환경에서 좌표 체계 혼란
**해결**:
- `screencapture -R x,y,w,h` 좌표 = `cliclick` 좌표 = macOS 글로벌 좌표 (1:1)
- `screencapture -R`로 PIN 패드 영역만 캡처 → 이미지에서 0 위치 확인 → `cliclick좌표 = 캡처시작점 + 이미지내오프셋`
- **하지만 가장 좋은 방법**: `toss-vision`으로 PIN 화면 OCR → 숫자 좌표 직접 얻기 (OCR이 숫자를 잡으면)

### 8. "파일 만들기" 클릭 후 blur 문제
**증상**: 날짜 입력란에 커서가 있는 상태에서 "파일 만들기" 클릭 → 첫 클릭이 blur 이벤트로 소비되어 버튼이 안 눌림
**해결**: Enter로 값 확정하면 이 문제도 해결됨. Enter가 blur + 값 확정을 동시에 처리

### 9. 저장 다이얼로그 처리
**증상**: "받기" 클릭 후 macOS 저장 다이얼로그가 뜨는데 cliclick으로 "저장" 버튼 클릭이 불안정
**해결**: Enter 키가 가장 확실:
```bash
toss-vision tap "받기"
sleep 3  # 저장 다이얼로그 뜨기 대기
osascript -e 'tell application "System Events" to key code 36'  # Enter = 기본 저장
```

### 10. 다운로드 파일이 암호화되어 있음
**증상**: `openpyxl.load_workbook()`이 `BadZipFile: File is not a zip file` 에러
**원인**: 토스 포스가 PIN으로 xlsx를 CDFV2 암호화함
**해결**:
```python
import msoffcrypto, io, openpyxl
with open("매출리포트.xlsx", "rb") as f:
    file = msoffcrypto.OfficeFile(f)
    file.load_key(password="0000")
    buf = io.BytesIO()
    file.decrypt(buf)
    buf.seek(0)
    wb = openpyxl.load_workbook(buf)
```

### 11. 실제 데이터는 첫 번째 시트가 아님
**증상**: 파일 열면 `데이터 기준` 시트만 보여서 데이터가 없는 것처럼 보임
**원인**: 첫 시트는 메타정보, 실제 데이터는 다른 시트에 있음
**해결**: 시트 목록 확인:
- `데이터 기준`: 메타 (시작일, 종료일, 집계 단위)
- `결제 합계`: 일별 결제 요약
- `상품 주문 합계`: 상품별 판매 요약
- **`결제 상세내역`**: 건별 결제 데이터 (날짜 컬럼: `결제기준일자`)
- **`상품 주문 상세내역`**: 건별 주문 데이터 (날짜 컬럼: `주문기준일자`)

## 완전한 날짜 입력 예제 (복붙용)

```bash
TV="toss-vision"  # 또는 ${CLAUDE_SKILL_DIR}/scripts/toss-vision

# 1. 앱 활성화
osascript -e 'tell application "Toss POS" to activate'
sleep 0.5

# 2. 엑셀 내보내기 화면 열기
$TV tap "엑셀 내보내기"
sleep 1

# 3. 시작일 입력
$TV tap "년.월.일"
sleep 0.3
osascript -e 'tell application "System Events" to keystroke "a" using command down'
sleep 0.1
osascript -e 'tell application "System Events" to key code 51'
sleep 0.2
cliclick t:20250320
sleep 0.3
osascript -e 'tell application "System Events" to key code 36'  # ★ Enter 필수
sleep 0.5

# 4. 종료일로 이동 (더블클릭 → Tab)
# 시작일 좌표를 toss-vision으로 확인
START_X=$($TV find "2025.03.20" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['x'])")
START_Y=$($TV find "2025.03.20" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['y'])")
cliclick dc:$((START_X+26)),$START_Y
sleep 0.2
osascript -e 'tell application "System Events" to key code 48'  # Tab
sleep 0.3

# 5. 종료일 입력
osascript -e 'tell application "System Events" to keystroke "a" using command down'
sleep 0.1
osascript -e 'tell application "System Events" to key code 51'
sleep 0.2
cliclick t:20250919
sleep 0.3
osascript -e 'tell application "System Events" to key code 36'  # ★ Enter 필수
sleep 0.5

# 6. 확인
$TV list | grep -E "2025|2026"

# 7. 파일 만들기
$TV tap "파일 만들기"
sleep 3

# 8. PIN 0000 (toss-vision으로 0 위치 찾기)
ZERO_X=$($TV find "0" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['x']) if d['found'] else print(780)")
ZERO_Y=$($TV find "0" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['y']) if d['found'] else print(580)")
cliclick c:$ZERO_X,$ZERO_Y && sleep 0.3
cliclick c:$ZERO_X,$ZERO_Y && sleep 0.3
cliclick c:$ZERO_X,$ZERO_Y && sleep 0.3
cliclick c:$ZERO_X,$ZERO_Y
sleep 15

# 9. 다운로드
$TV tap "받기"
sleep 3
osascript -e 'tell application "System Events" to key code 36'  # Enter로 저장
sleep 2

# 10. 파일 확인
ls -lt ~/Downloads/매출리포트-*.xlsx | head -3
```

## 주의사항

- `toss-vision tap`이 실패하면 (`found: false`) 화면 상태 재확인
- PIN 좌표는 윈도우 위치에 따라 달라짐 — `toss-vision`으로 매번 확인하는 것이 안전
- 파일 생성에 최대 30초 소요 — 충분히 대기
- "받기" 클릭 후 macOS 저장 다이얼로그 → **Enter**로 기본 위치 저장이 가장 확실
- 다운로드 파일 위치: `~/Downloads/매출리포트-*.xlsx`
- 6개월 초과 기간은 반드시 분할할 것 — 안 하면 서버에서 거부될 수 있음

## $ARGUMENTS 파싱

인자가 주어지면 기간으로 해석:
- "6개월" → 최근 6개월 (오늘 기준)
- "1년" → 최근 1년 (6개월씩 2분할)
- "2025.01~2025.06" → 해당 기간
- 인자 없으면 → 사용자에게 기간 질문
