# toss-pos-sales

토스 포스 맥앱에서 매출 데이터를 자동으로 추출하는 Claude Code 스킬.

## 구조

```
.claude/skills/toss-pos-sales/
├── SKILL.md                        # 스킬 정의 (Claude Code가 읽음)
├── toss-vision/                    # Apple Vision OCR 헬퍼 (Swift)
│   ├── Package.swift
│   └── Sources/main.swift
└── scripts/
    └── verify-sales-data.py        # 엑셀 검증 스크립트
```

## 사전 요구사항

- macOS 14+ (Apple Vision Framework 필요)
- Swift 5.9+
- [cliclick](https://github.com/BlueM/cliclick): `brew install cliclick`
- Python 패키지: `pip3 install openpyxl msoffcrypto-tool`
- 토스 포스 맥앱 설치 및 로그인

## 셋업

```bash
# 1. 레포 클론
git clone https://github.com/jackyun1024/poc-hw.git
cd poc-hw

# 2. toss-vision 빌드
cd .claude/skills/toss-pos-sales/toss-vision
swift build -c release
cp .build/release/toss-vision ../scripts/toss-vision
cd ../../../..

# 3. cliclick 설치 (없으면)
brew install cliclick

# 4. Python 패키지
pip3 install openpyxl msoffcrypto-tool

# 5. (선택) toss-vision을 PATH에 추가
cp .claude/skills/toss-pos-sales/scripts/toss-vision ~/.local/bin/
```

## 사용법

Claude Code에서:

```
/toss-pos-sales 6개월
/toss-pos-sales 1년
/toss-pos-sales 2025.01~2025.06
```

또는 자연어:
```
토스 매출 뽑아줘
매출 데이터 추출해줘
```

## toss-vision 단독 사용

```bash
# 화면의 모든 텍스트 + 좌표
toss-vision list

# 특정 텍스트 찾기
toss-vision find "매출 리포트"

# 찾아서 클릭
toss-vision tap "받기"

# 특정 앱 지정
toss-vision list --app "다른 앱"
```

## 핵심 노하우

- 날짜 입력 후 **Enter 필수** (값 확정)
- 종료일 이동: 시작일 더블클릭 → **Tab**
- 엑셀 최대 **6개월** 단위 → 자동 분할
- 다운로드 파일은 PIN으로 **암호화** (기본 0000)
