cmake_policy(VERSION 3.2)

set(_missing_vars "")
if (NOT DEFINED CMAKE_GENERATOR)
	list(APPEND _missing_vars CMAKE_GENERATOR)
endif()
if (NOT DEFINED ARDUINO_BOARD_MANAGER_URL)
	list(APPEND _missing_vars ARDUINO_BOARD_MANAGER_URL)
endif()
if (NOT DEFINED ARDUINO_BOARD_MANAGER_REF_URL)
	list(APPEND _missing_vars ARDUINO_BOARD_MANAGER_REF_URL)
endif()
if ("${ARDUINO_TOOLCHAIN_DIR}" STREQUAL "")
	list(APPEND _missing_vars ARDUINO_TOOLCHAIN_DIR)
endif()
if ("${ARDUINO_BUILD_ROOT_DIR}" STREQUAL "")
	list(APPEND _missing_vars ARDUINO_BUILD_ROOT_DIR)
endif()
if ("${ARDUINO_SYSTEM_ROOT_DIR}" STREQUAL "")
	list(APPEND _missing_vars ARDUINO_SYSTEM_ROOT_DIR)
endif()
if ("${ARDUINO_RESULT_ROOT_DIR}" STREQUAL "")
	list(APPEND _missing_vars ARDUINO_RESULT_ROOT_DIR)
endif()
if (NOT DEFINED ARDUINO_PLATFORM)
	list(APPEND _missing_vars ARDUINO_PLATFORM)
endif()

if (_missing_vars)

	string(REPLACE ";" "\n" _missing_vars "${_missing_vars}")
	message(FATAL_ERROR "The following variables should be defined\n"
		"${_missing_vars}"
	)

endif()

set(_templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Tests/Templates")
set(_pl_build_dir "${ARDUINO_BUILD_ROOT_DIR}")
set(_pl_sys_dir "${ARDUINO_SYSTEM_ROOT_DIR}")
set(_pl_result_dir "${ARDUINO_RESULT_ROOT_DIR}")

# Prepare build directory
function(_remove_build_directory _build_dir)
	if (NOT IS_DIRECTORY "${_build_dir}")
		file(MAKE_DIRECTORY "${_build_dir}")
	endif()
	
	file(GLOB _files_list "${_build_dir}/*")
	list(LENGTH _files_list _num_files)
	if (_num_files GREATER 0)
		if (NOT IS_DIRECTORY "${_build_dir}/CMakeFiles")
			message(FATAL_ERROR "Is ${_build_dir} a CMake build dir?")
		endif()
	
		foreach(_file IN LISTS _files_list)
			# Cleanup
			file(REMOVE_RECURSE "${_file}")
		endforeach()
	endif()
endfunction()
_remove_build_directory("${_pl_build_dir}")

# Prepare results directory
file(REMOVE_RECURSE "${_pl_result_dir}")
file(MAKE_DIRECTORY "${_pl_result_dir}")

execute_process(
	COMMAND "${CMAKE_COMMAND}"
		-G "${CMAKE_GENERATOR}"
		-D "ARDUINO_BOARD_OPTIONS_FILE=${ARDUINO_BOARD_OPTIONS_FILE}"
		-D "ARDUINO_BOARD_MANAGER_URL=${ARDUINO_BOARD_MANAGER_URL}"
		-D "ARDUINO_BOARD_MANAGER_REF_URL=${ARDUINO_BOARD_MANAGER_REF_URL}"
		-D "ARDUINO_BOARD=${ARDUINO_BOARD}"
		-D "ARDUINO_PLATFORM=${ARDUINO_PLATFORM}"
		-D "ARDUINO_BUILD_ROOT_DIR=${_pl_build_dir}"
		-D "ARDUINO_RESULT_ROOT_DIR=${_pl_result_dir}"
		-D "ARDUINO_SYSTEM_ROOT_DIR=${_pl_sys_dir}"
		-D "ARDUINO_PKG_MGR_DL_CACHE=${ARDUINO_PKG_MGR_DL_CACHE}"
		-D "ARDUINO_MAX_BOARDS_PER_PLATFORM=${ARDUINO_MAX_BOARDS_PER_PLATFORM}"
		-D "ARDUINO_NO_INSTALLED_REFERENCES=${ARDUINO_NO_INSTALLED_REFERENCES}"
		"${ARDUINO_TOOLCHAIN_DIR}/Tests"
	WORKING_DIRECTORY "${_pl_build_dir}"
	RESULT_VARIABLE _result
)

if (NOT _result EQUAL 0)
	_remove_build_directory("${_pl_build_dir}")
	message(FATAL_ERROR "Setup tests failed!!!")
endif()

execute_process(
	COMMAND "${CMAKE_CTEST_COMMAND}" --verbose
	WORKING_DIRECTORY "${_pl_build_dir}"
	RESULT_VARIABLE _result
)

_remove_build_directory("${_pl_build_dir}")
if (NOT _result EQUAL 0)
    message(FATAL_ERROR "Running package tests failed!!!")
endif()

