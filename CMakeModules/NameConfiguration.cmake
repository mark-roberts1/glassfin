set(MAIN_TARGET Glassfin)

# Output binary name
set(MAIN_NAME glassfin)

# Data directory name - also used for QCoreApplication::applicationName
# which determines QStandardPaths (cache, config, data dirs)
set(DATA_NAME glassfin)

if(APPLE)
  set(MAIN_NAME "Glassfin")
  set(DATA_NAME "Glassfin")
elseif(WIN32)
  set(MAIN_NAME "Glassfin")
  set(DATA_NAME "Glassfin")
endif()

configure_file(src/shared/Names.cpp.in src/shared/Names.cpp @ONLY)
