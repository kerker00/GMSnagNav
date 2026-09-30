#!/bin/zsh
# Takes the README screenshots of the demo app on macOS and an iPad simulator, in light and dark
# appearance, and copies them to docs/images.
#
# The UI test target needs a development team for macOS: set it in
# Examples/SnagNavDemo/Config/Signing.local.xcconfig. Pass the simulator's name as the first
# argument to use a different iPad. Requires jq and ffmpeg, for example from Homebrew.

set -euo pipefail

cd "$(dirname "$0")/.."
ipad="${1:-iPad Pro 13-inch (M5)}"
output="docs/images"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$output"

# Runs the screenshot tests on a destination and copies their attachments to docs/images.
take_screenshots() {
  local destination="$1" results="$work/$2.xcresult"
  TEST_RUNNER_README_SCREENSHOTS=1 xcodebuild test \
    -project Examples/SnagNavDemo/SnagNavDemo.xcodeproj \
    -scheme SnagNavDemo \
    -destination "$destination" \
    -only-testing SnagNavDemoUITests/ReadmeScreenshots \
    -resultBundlePath "$results" \
    -quiet

  local attachments="$work/$2"
  xcrun xcresulttool export attachments --path "$results" --output-path "$attachments"
  # The manifest maps each exported file to the attachment's name, such as "macos-light".
  jq -r '.[].attachments[] | "\(.exportedFileName)\t\(.suggestedHumanReadableName)"' \
    "$attachments/manifest.json" |
    while IFS=$'\t' read -r file name; do
      cp "$attachments/$file" "$output/${name%%_*}.png"
    done
}

take_screenshots "platform=macOS" macos

take_screenshots "platform=iOS Simulator,name=$ipad" ipad

# Crop the status bar, which shows the simulator's clock and language, off the iPad screenshots.
for image in "$output"/ipad-*.png; do
  ffmpeg -loglevel error -y -i "$image" -vf "crop=iw:ih-50:0:50" "$work/cropped.png"
  mv "$work/cropped.png" "$image"
done

ls -l "$output"
