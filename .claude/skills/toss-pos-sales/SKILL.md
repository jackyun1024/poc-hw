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

## 주의사항

- `toss-vision tap`이 실패하면 (`found: false`) 화면 상태 재확인
- PIN 좌표는 하드코딩됨 — 윈도우 이동 시 `toss-vision`으로 재확인
- 파일 생성에 최대 30초 소요 — 충분히 대기
- "받기" 클릭 후 macOS 저장 다이얼로그 → Enter로 기본 위치 저장
- 다운로드 파일 위치: `~/Downloads/매출리포트-*.xlsx`

## $ARGUMENTS 파싱

인자가 주어지면 기간으로 해석:
- "6개월" → 최근 6개월 (오늘 기준)
- "1년" → 최근 1년 (6개월씩 2분할)
- "2025.01~2025.06" → 해당 기간
- 인자 없으면 → 사용자에게 기간 질문
