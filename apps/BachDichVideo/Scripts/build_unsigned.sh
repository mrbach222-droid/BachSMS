#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo 'Cần chạy trên macOS có Xcode. Không thể tạo IPA iOS trên Linux/Windows.' >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null; then
  echo 'Cài XcodeGen trước: brew install xcodegen' >&2
  exit 1
fi
xcodegen generate
swift test
xcodebuild -project BachDichVideo.xcodeproj -scheme BachDichVideo \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/BachDichVideo.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
python3 Scripts/package_ipa.py
