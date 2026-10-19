#!/bin/zsh
# 시험 레이더 빌드: swiftc로 컴파일하고 ~/Applications/시험 레이더.app 번들을 만든다
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/시험 레이더.app"
mkdir -p build
[ -f build/AppIcon.icns ] || python3 make_icon.py build
python3 tools/check_questions.py "$( [ -f Resources/questions.json ] && echo Resources/questions.json || echo Resources/questions.sample.json )"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 Sources/*.swift -o build/ExamRadar
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/ExamRadar "$APP/Contents/MacOS/"
# 내 문제은행(questions.json)이 없으면 예시 문제로 빌드한다
Q=Resources/questions.json; [ -f "$Q" ] || Q=Resources/questions.sample.json
cp "$Q" "$APP/Contents/Resources/questions.json"
cp build/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>시험 레이더</string>
  <key>CFBundleDisplayName</key><string>시험 레이더</string>
  <key>CFBundleExecutable</key><string>ExamRadar</string>
  <key>CFBundleIdentifier</key><string>com.deventory.examradar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>캘린더의 시험·마감 일정을 카운트다운하고 달력으로 보여주기 위해 읽어요. 일정을 바꾸지는 않아요.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "빌드 완료: $APP"
