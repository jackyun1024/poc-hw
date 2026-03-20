#!/bin/bash
# 토스 포스 매출 엑셀 내보내기 — OCR 확인 후 행동 패턴
# Usage: export-sales.sh <시작일YYYYMMDD> <종료일YYYYMMDD>
set -euo pipefail

START_DATE="${1:?Usage: export-sales.sh <시작일YYYYMMDD> <종료일YYYYMMDD>}"
END_DATE="${2:?Usage: export-sales.sh <시작일YYYYMMDD> <종료일YYYYMMDD>}"
TV="/Users/jack/.local/bin/toss-vision"
CC="/opt/homebrew/bin/cliclick"

log() { echo "▶ $1"; }
fail() { echo "✗ $1" >&2; exit 1; }
ocr_check() { $TV list 2>&1; }

# 포맷된 날짜: 20250320 → 2025.03.20
FMT_START="${START_DATE:0:4}.${START_DATE:4:2}.${START_DATE:6:2}"
FMT_END="${END_DATE:0:4}.${END_DATE:4:2}.${END_DATE:6:2}"

# OCR에서 특정 텍스트의 좌표 추출 (JSON → x y)
get_xy() {
    local json=$($TV find "$1" ${2:-} 2>/dev/null)
    local found=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['found'])")
    if [ "$found" != "True" ]; then
        echo "0 0"
        return 1
    fi
    echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['x'], d['y'])"
}

# OCR에서 bbox의 왼쪽 끝 x 좌표 추출
get_left_x() {
    $TV ocr 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for el in data:
    if '$1' in el['text']:
        print(el['x'] - el['w'] // 2)
        break
else:
    print(0)
"
}

##############################
# 1. 앱 활성화 + OCR 확인
##############################
log "1. 앱 활성화"
osascript -e 'tell application "Toss POS" to activate'
sleep 0.5
log "   OCR 상태 확인..."
$TV has "토스 포스" 2>/dev/null || fail "토스 포스 앱이 안 보임"

##############################
# 2. 엑셀 기간선택 화면 확인
##############################
log "2. 엑셀 기간선택 화면 확인"
if $TV has "액셀 기간선택" 2>/dev/null; then
    log "   이미 열려있음 ✓"
else
    log "   엑셀 내보내기 열기..."
    $TV tap "엑셀 내보내기" --retry 3 2>/dev/null
    sleep 1
    $TV has "액셀 기간선택" 2>/dev/null || fail "엑셀 기간선택 화면 못 열음"
    log "   열림 ✓"
fi

##############################
# 3. 시작일 입력란 찾기 (큰 거 → 세부)
##############################
log "3. 시작일 입력란 찾기"

# OCR로 "년.월.일" 두 개를 구분: x가 작은 게 시작일, 큰 게 종료일
START_FIELD=$($TV ocr 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
# '년' 또는 '월' 또는 '일'이 포함된 날짜 입력란 후보
candidates = [el for el in data if '년' in el['text'] and '일' in el['text'] and el['y'] > 550]
if not candidates:
    print('0 0 0')
else:
    # x가 가장 작은 것 = 시작일 (왼쪽)
    start = min(candidates, key=lambda e: e['x'])
    left_x = start['x'] - start['w'] // 2
    # 년 서브필드 = 왼쪽 끝 + bbox 높이만큼 (폰트 크기 비례 오프셋)
    offset = max(start['h'], 8)
    print(f\"{left_x + offset} {start['y']} {start['x']} {start['w']}\")
")
SF_YEAR_X=$(echo $START_FIELD | cut -d' ' -f1)
SF_Y=$(echo $START_FIELD | cut -d' ' -f2)
SF_CENTER_X=$(echo $START_FIELD | cut -d' ' -f3)
SF_WIDTH=$(echo $START_FIELD | cut -d' ' -f4)

[ "$SF_YEAR_X" != "0" ] || fail "시작일 입력란 못 찾음"
log "   시작일 '년' 클릭 위치: ($SF_YEAR_X, $SF_Y) (center: $SF_CENTER_X, w: $SF_WIDTH)"

##############################
# 4. 시작일 입력
##############################
log "4. 시작일 입력: $FMT_START"
$CC c:$SF_YEAR_X,$SF_Y
sleep 0.3
osascript -e 'tell application "System Events" to keystroke "a" using command down'
sleep 0.1
osascript -e 'tell application "System Events" to key code 51'
sleep 0.2
$CC t:$START_DATE
sleep 0.3
osascript -e 'tell application "System Events" to key code 36'  # Enter
sleep 0.5

# OCR로 입력 확인
log "   OCR 검증..."
$TV has "$FMT_START" 2>/dev/null || fail "시작일 입력 실패 — OCR에서 $FMT_START 안 보임"
log "   시작일 확인 ✓"

##############################
# 5. 종료일로 이동 (더블클릭 → Tab)
##############################
log "5. 종료일로 이동"

# 입력된 시작일 좌표 찾기
read SX SY <<< $(get_xy "$FMT_START")
[ "$SX" != "0" ] || fail "입력된 시작일 좌표 못 찾음"
log "   시작일 위치: ($SX, $SY)"

# "일" 부분 더블클릭 — 입력된 시작일 bbox 오른쪽 끝 근처
# SF_WIDTH = OCR bbox 너비, 오른쪽 끝 = center + width/2 - 5
DC_X=$((SX + SF_WIDTH / 2 - 5))
log "   더블클릭: ($DC_X, $SY) → Tab"
$CC dc:$DC_X,$SY
sleep 0.2
osascript -e 'tell application "System Events" to key code 48'  # Tab
sleep 0.3

##############################
# 6. 종료일 입력
##############################
log "6. 종료일 입력: $FMT_END"
# ⚠️ Cmd+A/Delete 하지 않음! Tab 직후 빈 필드에 바로 타이핑
# Cmd+A하면 시작일이 선택되어 덮어써짐
$CC t:$END_DATE
sleep 0.3
osascript -e 'tell application "System Events" to key code 36'  # Enter
sleep 0.5

# OCR 검증
log "   OCR 검증..."
$TV has "$FMT_END" 2>/dev/null || fail "종료일 입력 실패 — OCR에서 $FMT_END 안 보임"
log "   종료일 확인 ✓"

# 양쪽 다 있는지 최종 확인
log "   양쪽 날짜 최종 확인..."
$TV has "$FMT_START" 2>/dev/null || fail "시작일이 사라짐"
log "   $FMT_START ~ $FMT_END ✓✓"

##############################
# 7. 파일 만들기
##############################
log "7. 파일 만들기"
# 파일 만들기 버튼 찾고 클릭
read FX FY <<< $(get_xy "파일 만들기")
[ "$FX" != "0" ] || fail "파일 만들기 버튼 못 찾음"
$CC c:$FX,$FY
sleep 3

# PIN 화면 확인
log "   PIN 화면 확인..."
$TV has "비밀번호 확인" 2>/dev/null || {
    log "   PIN 안 뜸 — 한번 더 클릭"
    $CC c:$FX,$FY
    sleep 3
    $TV has "비밀번호 확인" 2>/dev/null || fail "PIN 화면 안 뜸"
}
log "   PIN 화면 ✓"

##############################
# 8. PIN 0000
##############################
log "8. PIN 0000 입력"

# PIN 패드에서 0 위치를 OCR로 찾기
# "비밀번호 확인" 텍스트의 x 근처 + 아래쪽에서 찾기
PW_JSON=$($TV find "비밀번호 확인" 2>/dev/null)
PW_X=$(echo "$PW_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['x'])")
ZERO_POS=$($TV ocr 2>/dev/null | python3 -c "
import sys, json
pw_x = $PW_X
data = json.load(sys.stdin)
# PIN 패드 0: '비밀번호 확인'과 x가 비슷하고(+-200), y가 더 아래(+200~+400)
zeros = [el for el in data if el['text'].strip() == '0' and abs(el['x'] - pw_x) < 200 and el['y'] > 500]
if zeros:
    z = max(zeros, key=lambda e: e['y'])
    print(f\"{z['x']} {z['y']}\")
else:
    print('0 0')  # 못 찾으면 실패 처리
")
ZX=$(echo $ZERO_POS | cut -d' ' -f1)
ZY=$(echo $ZERO_POS | cut -d' ' -f2)
[ "$ZX" != "0" ] || fail "PIN 패드에서 0 버튼 못 찾음"
log "   0 버튼 위치: ($ZX, $ZY)"

$CC c:$ZX,$ZY && sleep 0.3
$CC c:$ZX,$ZY && sleep 0.3
$CC c:$ZX,$ZY && sleep 0.3
$CC c:$ZX,$ZY
sleep 3

##############################
# 9. 파일 생성 대기
##############################
log "9. 파일 생성 대기..."
WAIT_JSON=$($TV wait "받기" --timeout 30 2>/dev/null)
FOUND=$(echo "$WAIT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['found'])")
[ "$FOUND" = "True" ] || fail "파일 생성 타임아웃 (30초)"
log "   파일 생성 완료 ✓"

##############################
# 10. 다운로드
##############################
log "10. 다운로드"

# "받기" 위치를 OCR로 찾기 — 여러 "받기"가 있으면 첫 번째 (가장 위)
read RX RY <<< $(get_xy "받기")
[ "$RX" != "0" ] || fail "받기 버튼 못 찾음"
log "   받기 위치: ($RX, $RY)"

$CC c:$RX,$RY
sleep 3
osascript -e 'tell application "System Events" to key code 36'  # Enter = 저장
sleep 2

LATEST=$(ls -t ~/Downloads/매출리포트-*.xlsx 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
    log "다운로드 완료: $LATEST"
    echo "$LATEST"
else
    fail "다운로드 파일 못 찾음"
fi
