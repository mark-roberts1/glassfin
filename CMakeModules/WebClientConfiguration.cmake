# Glassfin's front end.
#
# Upstream Jellyfin Media Player has no web client of its own: it ships a
# server-picker page and then navigates the webview at whatever Jellyfin
# server you name, loading that server's copy of jellyfin-web. Glassfin
# replaces the interface, so the interface has to come from somewhere else —
# here. `web/` is a Vite application; it is built during the CMake build and
# baked into the binary as Qt resources under `/glassfin`, then served on its
# own URL scheme (see src/ui/GlassfinScheme.h).
#
# Two knobs:
#
#   -DBUILD_WEB_CLIENT=OFF     don't run npm; requires WEB_CLIENT_DIST
#   -DWEB_CLIENT_DIST=<path>   use an already-built dist, for build hosts with
#                              no Node and for reproducible packaging
#
# There is deliberately no third option that produces a binary with no front
# end in it. That binary would start, show nothing, and take an afternoon to
# diagnose.

option(BUILD_WEB_CLIENT "Build web/ with npm as part of the build" ON)
set(WEB_CLIENT_DIST "" CACHE PATH "Path to an already-built web/dist, instead of running npm")

set(WEB_CLIENT_SOURCE_DIR ${CMAKE_SOURCE_DIR}/web)

if(WEB_CLIENT_DIST)
  if(NOT EXISTS "${WEB_CLIENT_DIST}/index.html")
    message(FATAL_ERROR "WEB_CLIENT_DIST is set to ${WEB_CLIENT_DIST} but there is no index.html in it.")
  endif()
  set(WEB_CLIENT_DIR ${WEB_CLIENT_DIST})
  add_custom_target(web_client)
  message(STATUS "Web client: prebuilt, from ${WEB_CLIENT_DIST}")

elseif(BUILD_WEB_CLIENT)
  # npm.cmd first: find_program only appends .exe and .com on Windows, so
  # plain `npm` matches the extension-less shell script next to it, which
  # Windows cannot execute. On Linux there is no npm.cmd and this falls
  # straight through.
  find_program(NPM_EXECUTABLE NAMES npm.cmd npm)
  if(NOT NPM_EXECUTABLE)
    message(FATAL_ERROR
      "npm was not found, and it is needed to build the Glassfin front end.\n"
      "Install Node.js, or build web/ elsewhere and configure with "
      "-DBUILD_WEB_CLIENT=OFF -DWEB_CLIENT_DIST=/path/to/web/dist")
  endif()

  set(WEB_CLIENT_DIR ${WEB_CLIENT_SOURCE_DIR}/dist)

  # `npm ci` writes this, so it is a real timestamp for "the lockfile has been
  # installed" — the install re-runs when the lockfile changes and not on every
  # build, which it would if the target had no output to compare.
  set(WEB_CLIENT_STAMP ${WEB_CLIENT_SOURCE_DIR}/node_modules/.package-lock.json)

  add_custom_command(
    OUTPUT ${WEB_CLIENT_STAMP}
    COMMAND ${NPM_EXECUTABLE} ci --no-audit --no-fund
    WORKING_DIRECTORY ${WEB_CLIENT_SOURCE_DIR}
    DEPENDS ${WEB_CLIENT_SOURCE_DIR}/package-lock.json
    COMMENT "Installing front-end dependencies"
    VERBATIM
  )

  file(GLOB_RECURSE WEB_CLIENT_SOURCES CONFIGURE_DEPENDS
    ${WEB_CLIENT_SOURCE_DIR}/src/*
    ${WEB_CLIENT_SOURCE_DIR}/public/*
  )
  list(APPEND WEB_CLIENT_SOURCES
    ${WEB_CLIENT_SOURCE_DIR}/index.html
    ${WEB_CLIENT_SOURCE_DIR}/vite.config.ts
    ${WEB_CLIENT_SOURCE_DIR}/tsconfig.json
    ${WEB_CLIENT_SOURCE_DIR}/package.json
  )

  add_custom_command(
    OUTPUT ${WEB_CLIENT_DIR}/index.html
    COMMAND ${NPM_EXECUTABLE} run build
    WORKING_DIRECTORY ${WEB_CLIENT_SOURCE_DIR}
    DEPENDS ${WEB_CLIENT_SOURCES} ${WEB_CLIENT_STAMP}
    COMMENT "Building the Glassfin front end"
    VERBATIM
  )

  add_custom_target(web_client DEPENDS ${WEB_CLIENT_DIR}/index.html)
  message(STATUS "Web client: built from ${WEB_CLIENT_SOURCE_DIR} with ${NPM_EXECUTABLE}")

else()
  message(FATAL_ERROR
    "BUILD_WEB_CLIENT is OFF and WEB_CLIENT_DIST is not set, so the binary "
    "would have no interface in it. Set one of them.")
endif()
