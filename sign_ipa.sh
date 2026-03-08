#!/bin/bash
# sign_ipa.sh — uYouEnhanced 로컬 서명 스크립트
# 빌드 후 생성된 unsigned IPA를 각 타겟의 전용 프로비저닝 프로파일로 서명합니다.
#
# 사용법:
#   ./sign_ipa.sh <unsigned.ipa>
#   ./sign_ipa.sh              (packages/ 폴더에서 최신 IPA 자동 사용)

set -e

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
KEYS_DIR="/Users/skyprawngo/Documents/keys"

BUNDLE_ID="com.skyprawngo.uYouEnhanced"
TEAM_ID="5SB7JJYS4S"
CERT="Apple Development: skyprawngo@gmail.com (Z5BPV67Q38)"

PP_MAIN="$KEYS_DIR/uYouEnhanced_Dev.mobileprovision"
PP_SHARE="$KEYS_DIR/uYouEnhanced_Share_Extension_Dev.mobileprovision"
PP_OPENYOUTUBE="$KEYS_DIR/uYouEnhanced_OpenYoutube_Extension_Dev.mobileprovision"

# ── IPA 입력 결정 ──────────────────────────────────────────────
if [[ -n "$1" ]]; then
    INPUT_IPA="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
else
    INPUT_IPA=$(ls -t "$PROJ_DIR/packages/"*.ipa 2>/dev/null | head -1)
    if [[ -z "$INPUT_IPA" ]]; then
        echo "❌  packages/ 폴더에 IPA가 없습니다. 경로를 인수로 전달하세요."
        exit 1
    fi
fi
echo "📦  입력 IPA: $INPUT_IPA"

# ── 작업 디렉토리 설정 ─────────────────────────────────────────
WORK_DIR="$PROJ_DIR/.sign_work"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cp "$INPUT_IPA" "$WORK_DIR/app.ipa"
cd "$WORK_DIR"
unzip -q app.ipa
APP="Payload/YouTube.app"

# ── 번들 ID 업데이트 ──────────────────────────────────────────
echo "🔧  번들 ID 업데이트 중..."
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"

SHARE_APPEX="$APP/PlugIns/ShareServiceExtension.appex"
OPENYOUTUBE_APPEX="$APP/PlugIns/OpenYoutubeSafariExtension.appex"

if [[ -d "$SHARE_APPEX" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.ShareExtension" "$SHARE_APPEX/Info.plist"
fi
if [[ -d "$OPENYOUTUBE_APPEX" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.OpenYoutube.Extension" "$OPENYOUTUBE_APPEX/Info.plist"
fi

# ── 프로비저닝 프로파일에서 엔타이틀먼트 추출 ──────────────────
extract_entitlements() {
    local pp="$1"
    local out="$2"
    security cms -D -i "$pp" > /tmp/_pp_decoded.plist
    /usr/libexec/PlistBuddy -x -c "Print :Entitlements" /tmp/_pp_decoded.plist > "$out"
}

echo "🔑  엔타이틀먼트 추출 중..."
extract_entitlements "$PP_MAIN"        "$WORK_DIR/ent_main.plist"
extract_entitlements "$PP_SHARE"       "$WORK_DIR/ent_share.plist"
extract_entitlements "$PP_OPENYOUTUBE" "$WORK_DIR/ent_openyoutube.plist"

# ── 프로비저닝 프로파일 복사 ──────────────────────────────────
cp "$PP_MAIN"        "$APP/embedded.mobileprovision"
[[ -d "$SHARE_APPEX" ]]       && cp "$PP_SHARE"       "$SHARE_APPEX/embedded.mobileprovision"
[[ -d "$OPENYOUTUBE_APPEX" ]] && cp "$PP_OPENYOUTUBE" "$OPENYOUTUBE_APPEX/embedded.mobileprovision"

# ── Frameworks / dylib 서명 (안쪽부터) ───────────────────────
echo "✍️   Frameworks 서명 중..."
find "$APP/Frameworks" \( -name "*.dylib" -o -name "*.framework" \) 2>/dev/null | sort -r | while read -r f; do
    codesign -f -s "$CERT" "$f" 2>/dev/null && echo "    ✓ $(basename "$f")"
done

# ── Extensions 서명 ───────────────────────────────────────────
echo "✍️   Extensions 서명 중..."
if [[ -d "$SHARE_APPEX" ]]; then
    codesign -f -s "$CERT" --entitlements "$WORK_DIR/ent_share.plist" "$SHARE_APPEX"
    echo "    ✓ ShareServiceExtension"
fi
if [[ -d "$OPENYOUTUBE_APPEX" ]]; then
    codesign -f -s "$CERT" --entitlements "$WORK_DIR/ent_openyoutube.plist" "$OPENYOUTUBE_APPEX"
    echo "    ✓ OpenYoutubeSafariExtension"
fi

# ── 그 외 PlugIns 서명 (YouTube 원본 extensions) ─────────────
find "$APP/PlugIns" -name "*.appex" \
    ! -path "*ShareServiceExtension*" \
    ! -path "*OpenYoutubeSafariExtension*" 2>/dev/null | while read -r appex; do
    codesign -f -s "$CERT" "$appex" 2>/dev/null && echo "    ✓ $(basename "$appex")"
done

# ── 메인 앱 서명 ──────────────────────────────────────────────
echo "✍️   메인 앱 서명 중..."
codesign -f -s "$CERT" --entitlements "$WORK_DIR/ent_main.plist" "$APP"
echo "    ✓ YouTube.app"

# ── IPA 재패키징 ──────────────────────────────────────────────
YOUTUBE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist" 2>/dev/null || echo "unknown")
OUTPUT_NAME="uYouEnhanced_${YOUTUBE_VERSION}_signed.ipa"
OUTPUT_IPA="$PROJ_DIR/packages/$OUTPUT_NAME"
mkdir -p "$PROJ_DIR/packages"

rm app.ipa
zip -qr "$OUTPUT_IPA" Payload/

echo ""
echo "✅  서명 완료!"
echo "   출력: $OUTPUT_IPA"
echo "   SHASUM256: $(shasum -a 256 "$OUTPUT_IPA" | cut -d' ' -f1)"
echo ""
echo "👉  AltStore / Sideloadly 등으로 설치하세요."

# 정리
cd "$PROJ_DIR"
rm -rf "$WORK_DIR"
