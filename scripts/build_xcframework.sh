#!/bin/zsh
# Builds a distributable static Swift XCFramework from the local Swift package.
# Output: PLzmaSDK.xcframework at the repository root.

set -euo pipefail

readonly ROOT_DIR="${0:A:h:h}"
readonly SCHEME="PLzmaSDK-Static"
readonly CONFIGURATION="Release"
readonly OUTPUT_PATH="${ROOT_DIR}/PLzmaSDK.xcframework"
readonly BUILD_DIR="${ROOT_DIR}/.build/xcframework"

archive_product() {
  local identifier="$1"
  local destination="$2"
  local architectures="$3"
  local archive_path="${BUILD_DIR}/${identifier}.xcarchive"
  local derived_data_path="${BUILD_DIR}/DerivedData/${identifier}"

  xcodebuild archive \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "${destination}" \
    -archivePath "${archive_path}" \
    -derivedDataPath "${derived_data_path}" \
    ARCHS="${architectures}" \
    ONLY_ACTIVE_ARCH=NO \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    CODE_SIGNING_ALLOWED=NO
}

create_framework() {
  local identifier="$1"
  local architectures="$2"
  local framework_path="${BUILD_DIR}/Frameworks/${identifier}/PLzmaSDK.framework"
  local archive_path="${BUILD_DIR}/${identifier}.xcarchive"
  local derived_data_path="${BUILD_DIR}/DerivedData/${identifier}"
  local product_objects_path="${archive_path}/Products/Users/${USER}/Objects"
  local module_path

  module_path="$(find "${derived_data_path}" -type f -path '*/Objects-normal/*/PLzmaSDK.swiftmodule' -print -quit)"
  if [[ -z "${module_path}" ]]; then
    print -u2 "error: PLzmaSDK.swiftmodule was not found for ${identifier}"
    exit 1
  fi

  mkdir -p "${framework_path}/Modules/PLzmaSDK.swiftmodule" "${framework_path}/Headers"
  libtool -static \
    -o "${framework_path}/PLzmaSDK" \
    "${product_objects_path}/PLzmaSDK.o" \
    "${product_objects_path}/libplzma.o"

  local platform_suffix
  case "${identifier}" in
    ios-arm64) platform_suffix="apple-ios" ;;
    *simulator) platform_suffix="apple-ios-simulator" ;;
    macos-*) platform_suffix="apple-macos" ;;
    *) print -u2 "error: unknown platform for ${identifier}"; exit 1 ;;
  esac

  local architecture
  for architecture in ${=architectures}; do
    local architecture_module_path
    architecture_module_path="$(find "${derived_data_path}" -type f -path "*/Objects-normal/${architecture}/PLzmaSDK.swiftmodule" -print -quit)"
    local architecture_interface_path="${architecture_module_path%.swiftmodule}.swiftinterface"
    local target_module_name="${architecture}-${platform_suffix}"
    cp "${architecture_module_path}" "${framework_path}/Modules/PLzmaSDK.swiftmodule/${target_module_name}.swiftmodule"
    cp "${architecture_interface_path}" "${framework_path}/Modules/PLzmaSDK.swiftmodule/${target_module_name}.swiftinterface"
  done

  cp "${ROOT_DIR}/libplzma.h" "${framework_path}/Headers/libplzma.h"
  cat > "${framework_path}/Headers/PLzmaSDK.h" <<'EOF'
#import <Foundation/Foundation.h>
#import "libplzma.h"
EOF
  cat > "${framework_path}/Modules/module.modulemap" <<'EOF'
framework module PLzmaSDK {
  umbrella header "PLzmaSDK.h"
  export *
  module * { export * }
}

module libplzma {
  header "../Headers/libplzma.h"
  export *
}
EOF
  plutil -create xml1 "${framework_path}/Info.plist"
  plutil -replace CFBundleIdentifier -string "com.plzmasdk.PLzmaSDK" "${framework_path}/Info.plist"
  plutil -replace CFBundleName -string "PLzmaSDK" "${framework_path}/Info.plist"
  plutil -replace CFBundlePackageType -string "FMWK" "${framework_path}/Info.plist"
  plutil -replace CFBundleVersion -string "1" "${framework_path}/Info.plist"
  plutil -replace CFBundleShortVersionString -string "1.6.1" "${framework_path}/Info.plist"
}

rm -rf "${BUILD_DIR}" "${OUTPUT_PATH}"
mkdir -p "${BUILD_DIR}/Frameworks"

archive_product "ios-arm64" "generic/platform=iOS" "arm64"
archive_product "ios-arm64_x86_64-simulator" "generic/platform=iOS Simulator" "arm64 x86_64"
archive_product "macos-arm64_x86_64" "generic/platform=macOS" "arm64 x86_64"

create_framework "ios-arm64" "arm64"
create_framework "ios-arm64_x86_64-simulator" "arm64 x86_64"
create_framework "macos-arm64_x86_64" "arm64 x86_64"

xcodebuild -create-xcframework \
  -framework "${BUILD_DIR}/Frameworks/ios-arm64/PLzmaSDK.framework" \
  -framework "${BUILD_DIR}/Frameworks/ios-arm64_x86_64-simulator/PLzmaSDK.framework" \
  -framework "${BUILD_DIR}/Frameworks/macos-arm64_x86_64/PLzmaSDK.framework" \
  -output "${OUTPUT_PATH}"

for identifier in ios-arm64 ios-arm64_x86_64-simulator macos-arm64_x86_64; do
  cp "${BUILD_DIR}/Frameworks/${identifier}/PLzmaSDK.framework/Modules/PLzmaSDK.swiftmodule/"*.swiftmodule \
    "${OUTPUT_PATH}/${identifier}/PLzmaSDK.framework/Modules/PLzmaSDK.swiftmodule/"
done

if [[ "${KEEP_XCFRAMEWORK_ARCHIVES:-0}" != "1" ]]; then
  rm -rf "${BUILD_DIR}"
fi

print "Created ${OUTPUT_PATH}"
