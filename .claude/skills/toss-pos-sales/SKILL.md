---
name: toss-pos-sales
description: 토스 포스에서 매출 데이터 엑셀 추출. 다음 요청 시 트리거 - "토스 매출 뽑아줘", "매출 데이터 추출", "토스 포스 엑셀", "매출 리포트 다운로드", "POS 매출", "매출 내보내기"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write, Glob, Grep
argument-hint: [기간: 예) 6개월, 1년, 2025.01~2025.06]
---

# 토스 포스 매출 데이터 추출

토스 포스 맥앱에서 매출 리포트를 엑셀로 자동 추출하는 스킬.

## 핵심 원칙

### 1. 보고 → 확인 → 행동
모든 액션 전에 `toss-vision`으로 현재 상태를 OCR 확인한다. 맹목적으로 클릭하지 않는다.

### 2. 큰 거 찾고 → 세부 찾기
"년.월.일"이 2개 있으면 OCR bbox로 왼쪽(시작일)/오른쪽(종료일) 구분.
bbox left_edge + 10px = "년" 서브필드 클릭 위치.

### 3. 스크립트 활용
날짜 입력~다운로드까지 `export-sales.sh`에 들어있다.
**에이전트가 직접 날짜 입력을 시도하지 말 것.** 스크립트를 호출할 것.
스크립트가 매 단계마다 OCR 검증을 한다.

### 한 기간 추출
```bash
${CLAUDE_SKILL_DIR}/scripts/export-sales.sh <시작일YYYYMMDD> <종료일YYYYMMDD>
```
예: `export-sales.sh 20250320 20250919`

### 1년 추출 (6개월 제한 → 2분할)
```bash
# 전반기
${CLAUDE_SKILL_DIR}/scripts/export-sales.sh 20250320 20250919

# 엑셀 기간선택 화면 다시 열기
/Users/jack/.local/bin/toss-vision tap "액셀 기간선택" --retry 3
sleep 1

# 후반기
${CLAUDE_SKILL_DIR}/scripts/export-sales.sh 20250920 20260320
```

### 검증
```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/verify-sales-data.py ~/Downloads/매출리포트-*.xlsx
```

## 제약사항

- 최대 **6개월** 단위 → 초과 시 분할 필수
- 다운로드 파일은 **PIN 0000으로 암호화**됨
- 파일 위치: `~/Downloads/매출리포트-*.xlsx`
- 토스 포스 앱이 켜져있고 로그인된 상태여야 함
- **매출 리포트** 화면에서 실행해야 함 (아니면 먼저 이동)

## 매출 리포트 화면으로 이동

```bash
TV=/Users/jack/.local/bin/toss-vision
osascript -e 'tell application "Toss POS" to activate'
sleep 0.5
# 이미 매출 리포트 화면인지 확인
$TV has "매출 리포트" && echo "OK" || {
    $TV tap "≡"   # 햄버거 메뉴
    sleep 1
    $TV tap "매출 리포트"
    sleep 1
}
```

## 스크립트가 실패하면

스크립트 출력에서 `✗`로 시작하는 줄이 실패 지점. 주요 원인:

| 에러 | 원인 | 해결 |
|------|------|------|
| 시작일 입력 실패 | 엑셀 기간선택 화면이 아님 | 화면 상태 확인 후 재시도 |
| 종료일 입력 실패 | 시작일이 먼저 입력 안 됨 | 스크립트 처음부터 재실행 |
| PIN 화면 안 뜸 | 날짜가 확정 안 됨 (Enter 누락) | 스크립트가 Enter 포함하므로 재실행 |
| 파일 생성 타임아웃 | 서버 느림 | 다운로드 리스트 탭에서 수동 확인 |

## 도구

| 도구 | 경로 | 용도 |
|------|------|------|
| toss-vision | `/Users/jack/.local/bin/toss-vision` | OCR + 클릭 |
| cliclick | `/opt/homebrew/bin/cliclick` | 좌표 클릭/타이핑 |
| export-sales.sh | `${CLAUDE_SKILL_DIR}/scripts/export-sales.sh` | 한 기간 추출 자동화 |
| verify-sales-data.py | `${CLAUDE_SKILL_DIR}/scripts/verify-sales-data.py` | 엑셀 검증 |

## $ARGUMENTS 파싱

- "6개월" → 최근 6개월, export-sales.sh 1회
- "1년" → 최근 1년, export-sales.sh 2회 (6개월씩)
- "2025.01~2025.06" → 해당 기간, export-sales.sh 1회
- 인자 없으면 → 사용자에게 기간 질문
