#!/bin/bash
set -e

echo "=== toss-pos-sales 셋업 ==="

# 1. toss-vision 빌드
echo "1. toss-vision 빌드 중..."
cd .claude/skills/toss-pos-sales/toss-vision
swift build -c release 2>&1 | tail -1
cp .build/release/toss-vision ../scripts/toss-vision
cd ../../../..
echo "   ✅ toss-vision 빌드 완료"

# 2. cliclick 확인
if command -v cliclick &>/dev/null; then
    echo "2. ✅ cliclick 설치됨"
else
    echo "2. cliclick 설치 중..."
    brew install cliclick
    echo "   ✅ cliclick 설치 완료"
fi

# 3. Python 패키지
echo "3. Python 패키지 설치 중..."
pip3 install openpyxl msoffcrypto-tool -q
echo "   ✅ Python 패키지 설치 완료"

# 4. PATH에 추가 (선택)
mkdir -p ~/.local/bin
cp .claude/skills/toss-pos-sales/scripts/toss-vision ~/.local/bin/toss-vision
echo "4. ✅ toss-vision → ~/.local/bin/"

echo ""
echo "=== 셋업 완료! ==="
echo "Claude Code에서 '/toss-pos-sales 6개월' 로 사용하세요"
