#!/bin/sh
# Builds a release at build/release: Toolbelt signed with Developer ID and
# notarized, in a signed and notarized DMG (make-dmg.sh), and the Sparkle appcast
# that offers it to installed copies. Needs a Developer ID Application certificate,
# a notarytool profile, NOTARY_PROFILE (toolbelt by default), and the Sparkle
# signing key in Keychain (scripts/sparkle.sh generate_keys).
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
project=$root/Toolbelt.xcodeproj
scheme=Toolbelt
out=$root/build/release
packages=$root/build/SourcePackages
profile=${NOTARY_PROFILE:-toolbelt}
repository=https://github.com/artdima/Toolbelt

# A DMG that no commit matches could not be tagged.
if [ -n "$(git -C "$root" status --porcelain)" ]; then
    echo "error: uncommitted changes; a release is built from a commit" >&2
    exit 1
fi

settings=$(xcodebuild -project "$project" -scheme "$scheme" -configuration Release -showBuildSettings 2>/dev/null)
team=$(printf '%s\n' "$settings" | awk '$1 == "DEVELOPMENT_TEAM" { print $3; exit }')
version=$(printf '%s\n' "$settings" |
    awk '/^Build settings for / { target = $NF } target == "Toolbelt:" && $1 == "MARKETING_VERSION" { print $3; exit }')
identity=$(security find-identity -v -p codesigning |
    awk -v team="($team)\"" '/"Developer ID Application: / && index($0, team) { print $2; exit }')
if [ -z "$identity" ]; then
    echo "error: no Developer ID Application certificate for team $team;" \
        "create one in Xcode → Settings → Accounts → Manage Certificates" >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "error: no notary profile $profile; run" \
        "xcrun notarytool store-credentials $profile --apple-id <Apple ID> --team-id $team" >&2
    exit 1
fi

# The CHANGELOG section of a version with every paragraph and list item on one
# line, so that a hard wrap does not become a line break in Sparkle's Markdown.
changelog_notes() {
    awk -v heading="## $1" '
        /^## / { p = ($0 == heading); next }
        !p { next }
        /^$/ { if (line != "") print line; line = ""; print; next }
        /^- / { if (line != "") print line; line = $0; next }
        { sub(/^ +/, ""); line = (line == "") ? $0 : line " " $0 }
        END { if (line != "") print line }
    ' "$root/CHANGELOG.md"
}

notes=$(changelog_notes "$version")
if [ -z "$(printf '%s' "$notes" | tr -d '[:space:]')" ]; then
    echo "error: CHANGELOG.md has no ## $version section; the appcast takes its notes from it" >&2
    exit 1
fi

# An update signed with any other key is refused by every copy that has this one built in.
embedded_key=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$root/Toolbelt-Info.plist" 2>/dev/null || true)
if ! signing_key=$("$root/scripts/sparkle.sh" generate_keys -p); then
    echo "error: no Sparkle signing key in Keychain; run scripts/sparkle.sh generate_keys," \
        "or import a backup with scripts/sparkle.sh generate_keys -f <file>" >&2
    exit 1
fi
if [ "$embedded_key" != "$signing_key" ]; then
    echo "error: SUPublicEDKey in Toolbelt-Info.plist is not the Sparkle key in Keychain; run" \
        "plutil -replace SUPublicEDKey -string \"\$(scripts/sparkle.sh generate_keys -p)\" Toolbelt-Info.plist" \
        "and commit" >&2
    exit 1
fi

notarize() {
    log=$out/notary-$(basename "$1").log
    xcrun notarytool submit "$1" --keychain-profile "$profile" --wait | tee "$log"
    if ! grep -q '^ *status: Accepted' "$log"; then
        id=$(awk '$1 == "id:" { print $2; exit }' "$log")
        if [ -n "$id" ]; then
            xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true
        fi
        echo "error: Apple did not notarize $(basename "$1")" >&2
        exit 1
    fi
}

(cd "$root" && swift test --quiet)

rm -rf "$out"
mkdir -p "$out"

xcodebuild archive -quiet -project "$project" -scheme "$scheme" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$out/Toolbelt.xcarchive" -allowProvisioningUpdates \
    -clonedSourcePackagesDirPath "$packages"

cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$team</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -quiet -archivePath "$out/Toolbelt.xcarchive" -exportPath "$out/export" \
    -exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates

app=$out/export/Toolbelt.app
dmg=$out/Toolbelt-$version.dmg

# The app is notarized on its own first, so that it opens offline once copied out of the DMG.
ditto -c -k --keepParent "$app" "$out/Toolbelt.zip"
notarize "$out/Toolbelt.zip"
xcrun stapler staple "$app"

"$root/scripts/make-dmg.sh" "$app" "$dmg"
codesign --sign "$identity" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"

spctl --assess --type execute -v "$app"
spctl --assess --type open --context context:primary-signature -v "$dmg"

# Signed last: stapling changes the DMG.
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$app/Contents/Info.plist")
minimum_system=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$app/Contents/Info.plist")
signature=$("$root/scripts/sparkle.sh" sign_update -p "$dmg")
length=$(stat -f %z "$dmg")
published=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')
cat > "$out/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Toolbelt</title>
        <link>$repository</link>
        <item>
            <title>Toolbelt $version</title>
            <pubDate>$published</pubDate>
            <sparkle:version>$build</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$minimum_system</sparkle:minimumSystemVersion>
            <description sparkle:format="markdown"><![CDATA[
$notes
]]></description>
            <enclosure url="$repository/releases/download/v$version/Toolbelt-$version.dmg"
                length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
        </item>
    </channel>
</rss>
EOF
xmllint --noout "$out/appcast.xml"

echo
echo "Toolbelt $version from $(git -C "$root" rev-parse --short HEAD): $dmg"
shasum -a 256 "$dmg"
echo "Appcast: $out/appcast.xml"
