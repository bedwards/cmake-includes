# Builds the Vite/React UI bundle in /ui and wraps the resulting dist/ files
# as a JUCE binary-data target (WebUIAssets) the plugin can serve via
# WebBrowserComponent's ResourceProvider.
#
# Configure-time flow:
#   1. npm install (idempotent; skipped if node_modules is up to date)
#   2. npm run build with VITE_MODULUS_VERSION + VITE_UI_VERSION injected so
#      the footer shows the real plugin/UI versions.
#   3. Glob ui/dist/* into a juce_add_binary_data target named WebUIAssets,
#      using a dedicated WebUIData namespace + WebUIData.h header so its
#      symbols don't collide with the generic Assets BinaryData target.
#
# Vite emits hashed asset filenames (e.g. index-DhXUedl4.css), so re-running
# `cmake --build` alone after editing UI sources won't pick up new files. To
# refresh during dev: `cmake -B build && cmake --build build`.

set(MODULUS_UI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ui")
set(MODULUS_UI_DIST "${MODULUS_UI_DIR}/dist")

# Read the UI bundle version from ui/package.json.
file(READ "${MODULUS_UI_DIR}/package.json" _modulus_ui_pkg_json)
string(REGEX MATCH "\"version\"[ \t\r\n]*:[ \t\r\n]*\"([^\"]+)\"" _ "${_modulus_ui_pkg_json}")
set(MODULUS_UI_VERSION "${CMAKE_MATCH_1}")
if(NOT MODULUS_UI_VERSION)
    message(FATAL_ERROR "WebUI: failed to read version from ${MODULUS_UI_DIR}/package.json")
endif()
message(STATUS "WebUI: plugin=${CURRENT_VERSION} ui=${MODULUS_UI_VERSION}")

find_program(NPM_EXECUTABLE npm)
if(NOT NPM_EXECUTABLE)
    message(FATAL_ERROR "WebUI: npm not found on PATH. Install Node.js to build the UI bundle.")
endif()

# Install dependencies if node_modules is missing or older than package.json.
# Skipped on every reconfigure when up to date so this is cheap.
set(_modulus_ui_node_modules "${MODULUS_UI_DIR}/node_modules")
set(_modulus_ui_pkg_lock "${MODULUS_UI_DIR}/package-lock.json")
set(_need_install FALSE)
if(NOT EXISTS "${_modulus_ui_node_modules}")
    set(_need_install TRUE)
elseif(EXISTS "${_modulus_ui_pkg_lock}" AND "${_modulus_ui_pkg_lock}" IS_NEWER_THAN "${_modulus_ui_node_modules}")
    set(_need_install TRUE)
endif()
if(_need_install)
    message(STATUS "WebUI: running npm install in ${MODULUS_UI_DIR}")
    execute_process(
        COMMAND "${NPM_EXECUTABLE}" install --no-audit --no-fund
        WORKING_DIRECTORY "${MODULUS_UI_DIR}"
        RESULT_VARIABLE _npm_install_result
    )
    if(NOT _npm_install_result EQUAL 0)
        message(FATAL_ERROR "WebUI: npm install failed (exit ${_npm_install_result})")
    endif()
endif()

# Run a production build at configure time so ui/dist/ exists for the
# binary-data glob below.
message(STATUS "WebUI: running npm run build")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
            "VITE_MODULUS_VERSION=${CURRENT_VERSION}"
            "VITE_UI_VERSION=${MODULUS_UI_VERSION}"
            "${NPM_EXECUTABLE}" run build
    WORKING_DIRECTORY "${MODULUS_UI_DIR}"
    RESULT_VARIABLE _npm_build_result
)
if(NOT _npm_build_result EQUAL 0)
    message(FATAL_ERROR "WebUI: npm run build failed (exit ${_npm_build_result})")
endif()

# Collect freshly built dist/ files for the binary-data target.
file(GLOB_RECURSE WebUIAssetFiles CONFIGURE_DEPENDS "${MODULUS_UI_DIST}/*")
list(FILTER WebUIAssetFiles EXCLUDE REGEX "/\\.DS_Store$")
list(FILTER WebUIAssetFiles EXCLUDE REGEX "\\.map$")
if(NOT WebUIAssetFiles)
    message(FATAL_ERROR "WebUI: ui/dist is empty after build; expected at least index.html")
endif()

juce_add_binary_data(WebUIAssets
    NAMESPACE WebUIData
    HEADER_NAME WebUIData.h
    SOURCES ${WebUIAssetFiles})

# Required for Linux happiness. Mirrors cmake/Assets.cmake.
set_target_properties(WebUIAssets PROPERTIES POSITION_INDEPENDENT_CODE TRUE)

# Note: Vite emits hashed asset filenames (e.g. index-DhXUedl4.css). Those
# names change every build, so re-running an incremental build alone wouldn't
# pick up new files via this target's GLOB. Instead the UI build is run at
# CMake configure time above. To pick up UI source changes during dev:
#     cmake -B build && cmake --build build
# A single `cmake --build` re-uses the previously built ui/dist/.
