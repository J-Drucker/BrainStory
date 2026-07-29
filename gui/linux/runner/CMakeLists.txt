cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

if(CARGO_EXECUTABLE)
  add_custom_command(
    OUTPUT "${BRAINSTORY_ENGINE_LIBRARY}"
    COMMAND ${CARGO_EXECUTABLE} ${BRAINSTORY_ENGINE_BUILD_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../.."
    DEPENDS
      "${BRAINSTORY_ENGINE_MANIFEST}"
      "${BRAINSTORY_ENGINE_LOCKFILE}"
      ${BRAINSTORY_ENGINE_SOURCES}
    COMMENT "Building brainstory_engine Rust library"
    VERBATIM
  )
  add_custom_target(brainstory_engine_build
    DEPENDS "${BRAINSTORY_ENGINE_LIBRARY}"
  )
  add_dependencies(${BINARY_NAME} brainstory_engine_build)

  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${BRAINSTORY_ENGINE_LIBRARY}"
      "$<TARGET_FILE_DIR:${BINARY_NAME}>/libbrainstory_engine.so"
    VERBATIM
  )
endif()
