set(_missing_vars "")
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
if (NOT DEFINED ARDUINO_PL_TEST_LIST)
	list(APPEND _missing_vars ARDUINO_PL_TEST_LIST)
endif()

if (_missing_vars)

	string(REPLACE ";" "\n" _missing_vars "${_missing_vars}")
	message(FATAL_ERROR "The following variables should be defined\n"
		"${_missing_vars}"
	)

endif()

set(_templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Tests/Templates")

# Evaluate the results
set(_pl_tbl_content_str "")
set(num_tests 0)
set(fail_cnt 0)
foreach(_pl_test_id IN LISTS ARDUINO_PL_TEST_LIST)
	
	set(_pl_result_dir "${ARDUINO_RESULT_ROOT_DIR}/${_pl_test_id}")

	if (NOT EXISTS "${_pl_result_dir}/result.txt")
		continue()
	endif()

	file(READ "${_pl_result_dir}/result.txt" _result)
	if (NOT _result MATCHES "PASS")
		math(EXPR fail_cnt "${fail_cnt} + 1")
	endif()
	math(EXPR num_tests "${num_tests} + 1")
	file(REMOVE "${_pl_result_dir}/result.txt")

	file(READ "${_pl_result_dir}/PlatformTblEntry.txt" _content)
	set(_pl_tbl_content_str "${_pl_tbl_content_str}${_content}")
	file(REMOVE "${_pl_result_dir}/PlatformTblEntry.txt")

	file(READ "${_pl_result_dir}/SupportedTblEntry.txt" _content)
	set(_supp_tbl_content_str "${_supp_tbl_content_str}${_content}")
	file(REMOVE "${_pl_result_dir}/SupportedTblEntry.txt")
endforeach()

set(test_result "**${fail_cnt} of ${num_tests}** platforms failed")

# Write test results in TestResults.md and SupportedBoards.md
file(READ "${_templates_dir}/TestResults/PlatformTblHdr.md.in"
	_pl_tbl_hdr_fmt)
string(CONFIGURE "${_pl_tbl_hdr_fmt}" _pl_tbl_hdr_str @ONLY)
file(WRITE "${ARDUINO_RESULT_ROOT_DIR}/TestResults.md"
	"${_pl_tbl_hdr_str}${_pl_tbl_content_str}")
file(READ "${_templates_dir}/SupportedBoards/TblHdr.md.in"
	_supp_tbl_hdr_fmt)
string(CONFIGURE "${_supp_tbl_hdr_fmt}" _supp_tbl_hdr_str @ONLY)
file(WRITE "${ARDUINO_RESULT_ROOT_DIR}/SupportedBoards.md"
	"${_supp_tbl_hdr_str}${_supp_tbl_content_str}")

# Archive the test results
get_filename_component(_dir_name "${ARDUINO_RESULT_ROOT_DIR}" NAME)
get_filename_component(_dir "${ARDUINO_RESULT_ROOT_DIR}" DIRECTORY)
file(REMOVE "${_dir}/${_dir_name}.tar.gz")
execute_process(
	COMMAND "${CMAKE_COMMAND}" -E tar czf "${_dir_name}.tar.gz" "${_dir_name}"
	WORKING_DIRECTORY "${_dir}")

# Copy the error_log.txt and BoardOptions.cmake relative to
# Tests/Results
file(GLOB_RECURSE _copy_list "${ARDUINO_RESULT_ROOT_DIR}/error_log.txt"
	"${ARDUINO_RESULT_ROOT_DIR}/BoardOptions.cmake"
	"${ARDUINO_RESULT_ROOT_DIR}/*_vars.txt")
message("_copy_list:${_copy_list}")
foreach(_file IN LISTS _copy_list)
	file(RELATIVE_PATH _rel_path "${ARDUINO_RESULT_ROOT_DIR}" "${_file}")
	set(_dest_file "${ARDUINO_RESULT_ROOT_DIR}/Tests/Results/${_rel_path}")
	get_filename_component(_dest_dir "${_dest_file}" DIRECTORY)
	message("${_dest_dir}:${_dest_file}")
	file(MAKE_DIRECTORY "${_dest_dir}")
	file(COPY "${_file}" DESTINATION "${_dest_dir}")
endforeach()

