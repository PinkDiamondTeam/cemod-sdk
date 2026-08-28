include_guard(GLOBAL)

include(CMakeParseArguments)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# Package an existing payload target as a deterministic .cemod archive.
#
# cemod_package(
#   TARGET example_mod
#   MANIFEST /path/to/manifest.json
#   UI_DIR /path/to/ui-root
#   [PAYLOAD_FORMAT wups|cemod_elf]
#   [OUTPUT /path/to/example.cemod]
#   [PRIVATE_KEY /path/to/key.pem]
# )
function(cemod_package)
  set(one_value_args TARGET MANIFEST UI_DIR PAYLOAD_FORMAT OUTPUT PRIVATE_KEY)
  cmake_parse_arguments(CEMOD "" "${one_value_args}" "" ${ARGN})
  if(CEMOD_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "cemod_package received unknown arguments: ${CEMOD_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT CEMOD_TARGET OR NOT TARGET "${CEMOD_TARGET}")
    message(FATAL_ERROR "cemod_package TARGET must name an existing CMake target")
  endif()
  if(NOT CEMOD_MANIFEST)
    message(FATAL_ERROR "cemod_package requires MANIFEST")
  endif()
  if(NOT CEMOD_PAYLOAD_FORMAT)
    set(CEMOD_PAYLOAD_FORMAT wups)
  endif()
  if(NOT CEMOD_PAYLOAD_FORMAT MATCHES "^(wups|cemod_elf)$")
    message(FATAL_ERROR "cemod_package PAYLOAD_FORMAT must be wups or cemod_elf")
  endif()
  if(NOT CEMOD_OUTPUT)
    set(CEMOD_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${CEMOD_TARGET}.cemod")
  endif()

  set(package_command
    "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../tools/package_cemod.py"
    --manifest "${CEMOD_MANIFEST}"
    --payload "$<TARGET_FILE:${CEMOD_TARGET}>"
    --payload-format "${CEMOD_PAYLOAD_FORMAT}"
    --output "${CEMOD_OUTPUT}")
  set(package_dependencies "${CEMOD_TARGET}" "${CEMOD_MANIFEST}")
  if(CEMOD_UI_DIR)
    file(GLOB_RECURSE ui_files CONFIGURE_DEPENDS LIST_DIRECTORIES false "${CEMOD_UI_DIR}/*")
    list(APPEND package_command --ui-dir "${CEMOD_UI_DIR}")
    list(APPEND package_dependencies ${ui_files})
  endif()
  if(CEMOD_PRIVATE_KEY)
    list(APPEND package_command --private-key "${CEMOD_PRIVATE_KEY}")
    list(APPEND package_dependencies "${CEMOD_PRIVATE_KEY}")
  endif()

  add_custom_command(
    OUTPUT "${CEMOD_OUTPUT}"
    COMMAND ${package_command}
    DEPENDS ${package_dependencies}
    VERBATIM
    COMMENT "Packaging ${CEMOD_OUTPUT}")
  add_custom_target("${CEMOD_TARGET}_cemod" ALL DEPENDS "${CEMOD_OUTPUT}")
endfunction()
