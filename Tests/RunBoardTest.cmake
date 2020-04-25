cmake_policy(VERSION 3.2)

set(_missing_vars "")
if (NOT DEFINED CMAKE_GENERATOR)
	list(APPEND _missing_vars CMAKE_GENERATOR)
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
if (NOT DEFINED ARDUINO_BOARD_ID)
	list(APPEND _missing_vars ARDUINO_BOARD_ID)
endif()
if (NOT DEFINED ARDUINO_SKIP_REGULAR_EXPRESSION)
	list(APPEND _missing_vars ARDUINO_SKIP_REGULAR_EXPRESSION)
endif()

if (_missing_vars)

	string(REPLACE ";" "\n" _missing_vars "${_missing_vars}")
	message(FATAL_ERROR "The following variables should be defined\n"
		"${_missing_vars}"
	)

endif()

set(_templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Tests/Templates")
set(_board_build_dir "${ARDUINO_BUILD_ROOT_DIR}/${ARDUINO_BOARD_ID}")
set(_board_sys_dir "${ARDUINO_SYSTEM_ROOT_DIR}/${ARDUINO_BOARD_ID}")
set(_board_result_dir "${ARDUINO_RESULT_ROOT_DIR}/${ARDUINO_BOARD_ID}")
set(_board_sys_file "${_board_sys_dir}/ArduinoSystem.cmake")

# Prepare build directory
function(_remove_build_directory _build_dir)
	if (NOT IS_DIRECTORY "${_build_dir}")
		file(MAKE_DIRECTORY "${_build_dir}")
	endif()

	file(GLOB _files_list "${_build_dir}/*")
	list(LENGTH _files_list _num_files)
	if (_num_files GREATER 0)
		if (NOT IS_DIRECTORY "${_build_dir}/CMakeFiles")
			message(FATAL_ERROR "Is ${_build_dir} a CMake build directory?")
		endif()

		foreach(_file IN LISTS _files_list)
			# Cleanup
			file(REMOVE_RECURSE "${_file}")
		endforeach()
	endif()
endfunction()

macro(_log_and_execute_process)
	#if (DEFINED ENV{VERBOSE} OR "${CMAKE_VERBOSE_MAKEFILE}")
		string(REPLACE ";" " " _log_message "${ARGN}")
		execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${_log_message}")
	#endif()
	execute_process(${ARGN})
endmacro()

_remove_build_directory("${_board_build_dir}")

# Prepare results directory
file(REMOVE_RECURSE "${_board_result_dir}")
file(MAKE_DIRECTORY "${_board_result_dir}")

function(_gen_result_content _test_type _result_code _log_content
	return_code)

	execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${_log_content}")
	# Configure the result content for the board
	# First include board specific variables and initialize paths
	include("${_board_sys_dir}/BoardInfo.cmake")

	# Test result
	file(MAKE_DIRECTORY "${_board_result_dir}")
	set("${return_code}" "${_result_code}" PARENT_SCOPE)
	if (_result_code EQUAL 0)
		set(test_result "PASS")
		set(_files_to_copy
			"${_board_sys_dir}/BoardOptions.cmake")
		set(_files_to_attach
			"${ARDUINO_BOARD_ID}/output_log.txt")
		file(WRITE "${_board_result_dir}/output_log.txt" "${_log_content}")
	elseif(_test_type STREQUAL "Configure")
		set(test_result "**FAIL (Configure)**")
		set(_files_to_copy ${_files_to_attach}
			"${_board_sys_dir}/BoardOptions.cmake"
			"${_board_build_dir}/CMakeFiles/CMakeError.log"
			"${_board_build_dir}/CMakeFiles/CMakeOutput.log"
			"${_board_sys_file}")
		set(_files_to_attach
			"${ARDUINO_BOARD_ID}/error_log.txt"
			"${ARDUINO_BOARD_ID}/CMakeError.log"
			"${ARDUINO_BOARD_ID}/CMakeOutput.log"
			"${ARDUINO_BOARD_ID}/ArduinoSystem.cmake"
			"platform.txt"
			"boards.txt")
		file(WRITE "${_board_result_dir}/error_log.txt" "${_log_content}")
	else()
		set(test_result "**FAIL (${_test_type})**")
		set(_files_to_copy
			"${_board_sys_dir}/BoardOptions.cmake"
			"${_board_sys_file}")
		set(_files_to_attach
			"${ARDUINO_BOARD_ID}/error_log.txt"
			"${ARDUINO_BOARD_ID}/ArduinoSystem.cmake"
			"platform.txt"
			"boards.txt")
		file(WRITE "${_board_result_dir}/error_log.txt" "${_log_content}")
	endif()

	# Copy files
	foreach(_file_path IN ITEMS ${_files_to_copy})
		if (EXISTS "${_file_path}")
			file(COPY "${_file_path}" DESTINATION "${_board_result_dir}")
		endif()
	endforeach()

	# Attach files
	set(test_attach_files "")
	foreach(_file_path IN ITEMS ${_files_to_attach})
		get_filename_component(_file_name "${_file_path}" NAME)
		set(test_attach_files 
			"${test_attach_files}[${_file_name}](${_file_path})<br/>")
	endforeach()

	# Check for skipped tests
	if (NOT "${ARDUINO_SKIP_REGULAR_EXPRESSION}" STREQUAL "" AND
		NOT "${test_result}" STREQUAL "PASS")
		string(REGEX REPLACE "\r?\n" "\n" _log_content "${_log_content}")
		string(REGEX MATCH "${ARDUINO_SKIP_REGULAR_EXPRESSION}" _match
			"${_log_content}")
		if (NOT _match STREQUAL "")
			set(test_result "Skipped")
			set("${return_code}" "SKIP" PARENT_SCOPE)
		endif()
	endif()

	# Finally configure displayed content
	file(WRITE "${_board_result_dir}/result.txt" "${test_result}")
	configure_file("${_templates_dir}/TestResults/BoardsTblEntry.md.in"
		"${_board_result_dir}/BoardsTblEntry.txt" @ONLY)
	configure_file("${_templates_dir}/SupportedBoards/BoardInfo.cmake.in"
		"${_board_result_dir}/BoardInfo.cmake" @ONLY)

	# Remove the build directory
	_remove_build_directory("${_board_build_dir}")

endfunction()

# Configure
if (NOT DEFINED ENV{TEST_TOOLCHAIN_FILE})
	_log_and_execute_process(
		COMMAND "${CMAKE_COMMAND}"
			-G "${CMAKE_GENERATOR}"
			-D "CMAKE_TOOLCHAIN_FILE=${ARDUINO_TOOLCHAIN_DIR}/Arduino-toolchain.cmake"
			-D "ARDUINO_SYSTEM_FILE=${_board_sys_file}"
			-D "CMAKE_VERBOSE_MAKEFILE=TRUE"
			"${ARDUINO_TOOLCHAIN_DIR}/Examples/01_hello_world"
		WORKING_DIRECTORY "${_board_build_dir}"
		OUTPUT_VARIABLE _configure_content
		ERROR_VARIABLE _configure_content
		RESULT_VARIABLE _result
	)
else()
	set(_toolchain_file $ENV{TEST_TOOLCHAIN_FILE})
	get_filename_component(_toolchain_dir "${_toolchain_file}" DIRECTORY)
	message("Cross toolchain ${_toolchain_file}:${ARDUINO_BUILD_ROOT_DIR}/_pkg_mgr")
	_log_and_execute_process(
		COMMAND "${CMAKE_COMMAND}"
			-G "${CMAKE_GENERATOR}"
			-D "CMAKE_TOOLCHAIN_FILE=${_toolchain_file}"
			-D "ARDUINO_BOARD_OPTIONS_FILE=${ARDUINO_BOARD_OPTIONS_FILE}"
			-D "ARDUINO_BOARD=${ARDUINO_BOARD_ID}"
			-D "CMAKE_VERBOSE_MAKEFILE=TRUE"
			-D "ARDUINO_PACKAGE_PATH_EXTRA=${ARDUINO_BUILD_ROOT_DIR}/_pkg_mgr"
			"${_toolchain_dir}/Examples/01_hello_world"
		WORKING_DIRECTORY "${_board_build_dir}"
		OUTPUT_VARIABLE _configure_content
		ERROR_VARIABLE _configure_content
		RESULT_VARIABLE _result
	)
endif()

if (NOT _result EQUAL 0)
	_gen_result_content("Configure" "${_result}"
		"${_configure_content}" _ret_code)
	if (_ret_code STREQUAL "SKIP")
		message(WARNING "Configure failed (skipped known issue)!!!")
		return()
	else()
		message(FATAL_ERROR "Configure failed!!!")
	endif()
endif()

# Build
_log_and_execute_process(
	COMMAND "${CMAKE_COMMAND}" "--build" "." -- VERBOSE=1
	WORKING_DIRECTORY "${_board_build_dir}"
	OUTPUT_VARIABLE _build_content
	ERROR_VARIABLE _build_content
	RESULT_VARIABLE _result
)

set(_build_result_code "${_result}")

## Tools
set(_known_vars_upload
	"TOOL"
	"TARGET"
	"UPLOAD_VERBOSE"
	"VERIFY"
	"SERIAL_PORT"
	"SERIAL_PORT_FILE"
	"EXTRA_FILES"
)
set("_known_vars_upload-network"
	"TOOL"
	"TARGET"
	"UPLOAD_VERBOSE"
	"VERIFY"
	"NETWORK_IP"
	"NETWORK_PORT"
	"NETWORK_PASSWORD"
	"NETWORK_ENDPOINT_UPLOAD"
	"NETWORK_ENDPOINT_SYNC"
	"NETWORK_ENDPOINT_RESET"
	"NETWORK_SYNC_RETURN"
)
set(_known_vars_program
	"TOOL"
	"TARGET"
	"PROGRAM_VERBOSE"
	"VERIFY"
	"SERIAL_PORT"
	"UPLOAD_EXTRA_FILES"
)
set("_known_vars_erase-flash"
	"TOOL"
	"TARGET"
	"ERASE_VERBOSE"
	"VERIFY"
	"SERIAL_PORT"
)
set("_known_vars_burn-bootloader"
	"TOOL"
	"TARGET"
	"BOOTLOADER_VERBOSE"
	"VERIFY"
	"SERIAL_PORT"
)
set(_known_vars_debug
	"TOOL"
	"TARGET"
	"DEBUG_VERBOSE"
	"VERIFY"
)

set(_tool_result_code 0)
set(_tool_content "")
foreach(_tool_tgt IN ITEMS upload upload-network program erase-flash
	burn-bootloader debug)

	set("${_tool_tgt}_tool_id_list" "")
	set("${_tool_tgt}_tool_names" "")

	set(_script "${_board_sys_dir}/.scripts/${_tool_tgt}.cmake")
	if (NOT EXISTS "${_script}")
		continue()
	endif()

	_log_and_execute_process(
		COMMAND "${CMAKE_COMMAND}" -E env "ARDUINO_LIST_OPTION_VALUES=TOOL"
			"${CMAKE_COMMAND}" -P "${_script}"
		WORKING_DIRECTORY "${_board_build_dir}"
		OUTPUT_VARIABLE _tool_id_list_content
		ERROR_VARIABLE _tool_id_list_content
		RESULT_VARIABLE _result
	)

	if (NOT _result EQUAL 0)
		set(_tool_result_code "${_result}")
		set(_tool_content "${_tool_content}${_tool_id_list_content}")
		continue()
	endif()

	_log_and_execute_process(
		COMMAND "${CMAKE_COMMAND}" -E env
			"ARDUINO_LIST_OPTION_VALUES=TOOL_DESCRIPTIONS"
			"${CMAKE_COMMAND}" -P "${_script}"
		WORKING_DIRECTORY "${_board_build_dir}"
		OUTPUT_VARIABLE _tool_desc_content
		ERROR_VARIABLE _tool_desc_content
		RESULT_VARIABLE _result
	)

	if (NOT _result EQUAL 0)
		set(_tool_result_code "${_result}")
		set(_tool_content "${_tool_content}${_tool_desc_content}")
		continue()
	endif()

	string(STRIP "${_tool_id_list_content}" _tool_id_list_content)
	string(STRIP "${_tool_desc_content}" _tool_desc_content)
	string(REGEX REPLACE "\r?\n" ";" ${_tool_tgt}_tool_id_list
		"${_tool_id_list_content}")
	string(REGEX REPLACE "\r?\n" ";" ${_tool_tgt}_tool_names
		"${_tool_desc_content}")
	set(_unknown_vars)
	list(LENGTH ${_tool_tgt}_tool_id_list _num_tools)
	set(_tool_idx 0)
	while(_tool_idx LESS _num_tools)
		list(GET ${_tool_tgt}_tool_id_list ${_tool_idx} _tool_name)
		math(EXPR _tool_idx "${_tool_idx} + 1")

		_log_and_execute_process(
			COMMAND "${CMAKE_COMMAND}" -E env "TOOL=${_tool_name}"
				"ARDUINO_LIST_OPTION_VALUES="
				"${CMAKE_COMMAND}" -P "${_script}"
			WORKING_DIRECTORY "${_board_build_dir}"
			OUTPUT_VARIABLE _options_content
			ERROR_VARIABLE _options_content
			RESULT_VARIABLE _result
		)

		if (NOT _result EQUAL 0)
			set(_tool_result_code "${_result}")
			set(_tool_content "${_tool_content}${_options_content}")
			continue()
		endif()

		string(STRIP "${_options_content}" _options_content)
		string(REGEX REPLACE "\r?\n" ";" _options "${_options_content}")
		set(_curr_unknown_vars "")
		foreach(_option IN LISTS _options)
			list(FIND _known_vars_${_tool_tgt} "${_option}" _idx)
			if (_idx LESS 0)
				list(APPEND _curr_unknown_vars "${_option}")
			endif()
		endforeach()
		if (NOT _curr_unknown_vars STREQUAL "")
			list(APPEND "ARDUINO_${_tool_tgt}_FAILED_TOOLS" "${_tool_name}")
			list(APPEND _unknown_vars ${_curr_unknown_vars})
			list(APPEND "ARDUINO_${_tool_tgt}_FAILED_VARS"
				"${_curr_unknown_vars}")
		else()
			list(APPEND "ARDUINO_${_tool_tgt}_TOOLS" "${_tool_name}")
		endif()
	endwhile()

	if (NOT "${_unknown_vars}" STREQUAL "")
		list(REMOVE_DUPLICATES _unknown_vars)
		string(REPLACE ";" ", " _unknown_vars "${_unknown_vars}")
		set(_msg "${_tool_tgt} has unknown variables: ${_unknown_vars}")
		set(_tool_content "${_tool_content}${_msg}")
	endif()
	
endforeach()

set(_ret_code 0)
if (NOT _build_result_code EQUAL 0)
	_gen_result_content("Build" "${_build_result_code}"
		"${_configure_content}${_build_content}${_tool_content}" _ret_code)
	if (_ret_code STREQUAL "SKIP")
		message(WARNING "Build failed (skipped known issue)!!!")
		return()
	else()
		message(FATAL_ERROR "Build failed!!!")
	endif()
elseif(NOT _tool_result_code EQUAL 0)
	_gen_result_content("${_tool_tgt}" "${_tool_result_code}"
		"${_configure_content}${_build_content}${_tool_content}" _ret_code)
	if (_ret_code STREQUAL "SKIP")
		message(WARNING "Tool '${_tool_tgt}' failed (skipped known issue)!!!")
		return()
	else()
		message(FATAL_ERROR "Tool '${_tool_tgt}' failed!!!")
	endif()
else()
	_gen_result_content("" "0"
		"${_configure_content}${_build_content}${_tool_content}" _ret_code)
endif()
