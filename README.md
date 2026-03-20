# toss-pos-sales

토스 포스 맥앱에서 매출 데이터를 자동으로 추출하는 Claude Code 스킬.

Apple Vision OCR로 화면을 읽고, 자동으로 날짜 입력 → 파일 생성 → PIN 입력 → 다운로드까지 수행합니다.

## 퀵 스타트

```bash
# 1. 클론 & 셋업 (1분)
git clone https://github.com/jackyun1024/poc-hw.git
cd poc-hw
./setup.sh

# 2. 토스 포스 앱 켜기 (로그인된 상태)

# 3. Claude Code에서 이 폴더 열고:
claude

# 4. 매출 뽑기
> 지금 켜져있는 토스 포스에서 1년치 매출 뽑아줘
```

끝. Claude가 알아서 6개월씩 나눠서 추출하고, 빠진 날짜 없는지 검증까지 해줍니다.

## 셋업 상세

### 사전 요구사항
- macOS 14+ (Apple Vision Framework)
- Swift 5.9+ (Xcode 설치되어 있으면 OK)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 설치
- 토스 포스 맥앱 설치 및 로그인

### 자동 셋업
```bash
./setup.sh
```
이 스크립트가 다음을 수행:
1. `toss-vision` Swift 바이너리 빌드
2. `cliclick` 설치 (brew)
3. Python 패키지 설치 (`openpyxl`, `msoffcrypto-tool`)
4. `toss-vision`을 `~/.local/bin/`에 복사

### 수동 셋업 (setup.sh 안 쓸 때)
```bash
# toss-vision 빌드
cd .claude/skills/toss-pos-sales/toss-vision
swift build -c release
cp .build/release/toss-vision ../scripts/toss-vision
cd ../../../..

# 의존성
brew install cliclick
pip3 install openpyxl msoffcrypto-tool
```

## 사용법

### Claude Code 스킬로 사용

```bash
# 이 폴더에서 Claude Code 실행
cd poc-hw
claude
```

그리고 다음 중 아무거나:
```
> /toss-pos-sales 1년
> /toss-pos-sales 6개월
> /toss-pos-sales 2025.01~2025.06
> 토스 매출 뽑아줘
> 매출 데이터 추출해줘
> 토스 포스 엑셀 내보내기
```

### toss-vision 단독 사용

```bash
# 토스 포스 화면의 모든 텍스트 + 좌표
toss-vision list

# 특정 텍스트의 클릭 좌표 찾기
toss-vision find "매출 리포트"
# → {"text": "매출 리포트", "x": 204, "y": 150, "found": true}

# 찾아서 클릭까지 원샷
toss-vision tap "받기"

# 다른 앱에도 사용 가능
toss-vision list --app "카카오톡"
```

### 엑셀 검증

```bash
python3 .claude/skills/toss-pos-sales/scripts/verify-sales-data.py \
  ~/Downloads/매출리포트-*.xlsx --password 0000
```

## 동작 원리

```
1. toss-vision으로 토스 포스 화면 OCR (Apple Vision)
2. 텍스트 좌표 기반으로 메뉴 탐색 (cliclick)
3. 엑셀 내보내기 → 날짜 입력 → Enter로 확정
4. 6개월 초과 시 자동 분할
5. 파일 만들기 → PIN 0000 입력
6. 다운로드 → 암호화된 xlsx 복호화 → 날짜 커버리지 검증
```

## 구조

```
poc-hw/
├── README.md
├── setup.sh                            # 원클릭 셋업
├── .gitignore
└── .claude/skills/toss-pos-sales/
    ├── SKILL.md                        # Claude Code 스킬 정의
    ├── toss-vision/                    # Apple Vision OCR 헬퍼
    │   ├── Package.swift
    │   └── Sources/main.swift
    └── scripts/
        └── verify-sales-data.py        # 엑셀 검증
```

## 핵심 노하우

| 항목 | 설명 |
|------|------|
| 날짜 입력 | 타이핑 후 **Enter 필수** (값 확정 안 하면 버튼 비활성) |
| 종료일 이동 | 시작일 더블클릭 → **Tab** |
| 기간 제한 | 최대 **6개월** → 자동 분할 |
| 파일 암호 | PIN `0000`으로 암호화됨 |
| 좌표 체계 | `toss-vision` 좌표 = `cliclick` 좌표 (1:1) |

## 트러블슈팅

- **toss-vision이 앱을 못 찾음**: 토스 포스 앱이 켜져 있고 화면에 보이는지 확인
- **클릭이 안 먹힘**: 시스템 설정 → 개인정보 보호 → 손쉬운 사용에서 터미널/Claude Code 허용
- **빌드 실패**: `xcode-select --install`로 Command Line Tools 설치
- **파일 만들기 버튼 무반응**: 날짜 입력 후 Enter를 안 친 경우
