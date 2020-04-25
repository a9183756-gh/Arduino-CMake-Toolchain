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
if ("${ARDUINO_PLATFORM_DIR}" STREQUAL "")
	list(APPEND _missing_vars ARDUINO_PLATFORM_DIR)
endif()
if (NOT DEFINED ARDUINO_BOARDS_LIST)
	list(APPEND _missing_vars ARDUINO_BOARDS_LIST)
endif()

if (_missing_vars)

	string(REPLACE ";" "\n" _missing_vars "${_missing_vars}")
	message(FATAL_ERROR "The following variables should be defined\n"
		"${_missing_vars}"
	)

endif()

include("${ARDUINO_TOOLCHAIN_DIR}/Arduino/Utilities/CommonUtils.cmake")

# Escape the string for making it suitable as part of markdown string
function(string_escape_markdown return_value)
	string(REGEX REPLACE "([][(){}_`+*.|\\\\<>!])" "\\\\\\1" _value ${ARGN})
	set("${return_value}" "${_value}" PARENT_SCOPE)
endfunction()

# Escape the string for making it suitable for HTML
function(string_escape_html return_value)
	string(REPLACE "&" "&#38;" _value ${ARGN})
	string(REPLACE "\"" "&#34;" _value "${_value}")
	string(REPLACE "/" "&#47;" _value "${_value}")
	string(REPLACE "<" "&#60;" _value "${_value}")
	string(REPLACE ">" "&#62;" _value "${_value}")
	set("${return_value}" "${_value}" PARENT_SCOPE)
endfunction()

function(string_escape_output return_value)
	if (_fmt_ext STREQUAL "md.in")
		string_escape_markdown(_return_value ${ARGN})
	else()
		string_escape_html(_return_value ${ARGN})
	endif()
	set("${return_value}" "${_return_value}" PARENT_SCOPE)
endfunction()

set(_templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Tests/Templates")
set(_pl_build_dir "${ARDUINO_BUILD_ROOT_DIR}")
set(_pl_sys_dir "${ARDUINO_SYSTEM_ROOT_DIR}")
set(_pl_result_dir "${ARDUINO_RESULT_ROOT_DIR}")

# Evaluate the results
set(_brd_tbl_content_str "")
set(num_boards 0)
set(fail_cnt 0)
set(skip_cnt 0)
set(boards_list "")
set(upload_list "")
set(upload-network_list "")
set(program_list "")
set(debug_list "")
if (EXISTS "${_templates_dir}/SupportedBoards/SuppBoardItem.md.in")
	set(_fmt_ext "md.in")
else()
	set(_fmt_ext "html.in")
endif()
macro(_load_template _fname)
	file(READ "${_templates_dir}/SupportedBoards/${_fname}.${_fmt_ext}"
		${_fname}_fmt)
	if (_fmt_ext STREQUAL "md.in")
		string(STRIP "${${_fname}_fmt}" ${_fname}_fmt)
	endif()
endmacro()
foreach(_infile IN ITEMS SuppBoardItem FailBoardItem SkipBoardItem
	SuppToolItem FailToolItem SkipToolItem UnexpectedOptions)
	_load_template(${_infile})
endforeach()
_load_template("UnsuppTool")
include("${_pl_sys_dir}/PlatformInfo.cmake")

# Initialize tools list
foreach(_tool_tgt IN ITEMS upload upload-network program debug)
	set("${_tool_tgt}_list" "")
	set("${_tool_tgt}_tool_id_list" "")
	set("${_tool_tgt}_pass_id_list" "")
	set("${_tool_tgt}_failed_vars" "")
endforeach()

# Evaluate result
foreach(_board_id IN LISTS ARDUINO_BOARDS_LIST)

	set(_board_result_dir "${_pl_result_dir}/${_board_id}")

	if (NOT EXISTS "${_board_result_dir}/result.txt")
		continue()
	endif()

	include("${_board_result_dir}/BoardInfo.cmake")
	string_escape_output(_ARDUINO_BOARD_NAME "${ARDUINO_BOARD_NAME}")
	string_escape_output(_ARDUINO_BOARD_DISTINCT_ID
		"${ARDUINO_BOARD_DISTINCT_ID}")
	file(READ "${_board_result_dir}/result.txt" _result)
	if (_result MATCHES "Skipped")
		math(EXPR skip_cnt "${skip_cnt} + 1")
		string(CONFIGURE "${SkipBoardItem_fmt}" _brd_item_str @ONLY)
	elseif (_result MATCHES "FAIL")
		math(EXPR fail_cnt "${fail_cnt} + 1")
		string(CONFIGURE "${FailBoardItem_fmt}" _brd_item_str @ONLY)
	else()
		string(CONFIGURE "${SuppBoardItem_fmt}" _brd_item_str @ONLY)
	endif()
	math(EXPR num_boards "${num_boards} + 1")
	file(REMOVE "${_board_result_dir}/result.txt")

	file(READ "${_board_result_dir}/BoardsTblEntry.txt" _content)
	set(_brd_tbl_content_str "${_brd_tbl_content_str}${_content}")
	file(REMOVE "${_board_result_dir}/BoardsTblEntry.txt")

	# Supported boards list	
	set(boards_list "${boards_list}${_brd_item_str}")

	# Find supported or failed tool list
	foreach(_tool_tgt IN ITEMS upload upload-network program debug)
		foreach(tool_id IN LISTS "ARDUINO_${_tool_tgt}_TOOL_ID_LIST")
			list(FIND "ARDUINO_${_tool_tgt}_TOOL_ID_LIST" "${tool_id}"
				_tool_idx)
			list(GET "ARDUINO_${_tool_tgt}_TOOL_NAMES" "${_tool_idx}"
				tool_name)
			list(FIND "${_tool_tgt}_tool_id_list" "${tool_id}" _idx)
			if (_idx LESS 0)
				list(APPEND ${_tool_tgt}_tool_id_list "${tool_id}")
				list(APPEND ${_tool_tgt}_tool_names "${tool_name}")
			endif()
			list(FIND "ARDUINO_${_tool_tgt}_TOOLS" "${tool_id}" _idx)
			if (NOT _idx LESS 0)
				list(FIND "ARDUINO_${_tool_tgt}_pass_id_list" "${tool_id}"
					_idx)
				if (_idx LESS 0)
					list(APPEND "${_tool_tgt}_pass_id_list" "${tool_id}")
				endif()
			else() # Failed
				list(APPEND "${_tool_tgt}_failed_vars"
					"${ARDUINO_${_tool_tgt}_FAILED_VARS}")
			endif()
		endforeach()
	endforeach()

endforeach()

# Generate the tool list
foreach(_tool_tgt IN ITEMS upload upload-network program debug)
	set(_tool_idx 0)
	foreach(tool_id IN LISTS "${_tool_tgt}_tool_id_list")
		list(GET "${_tool_tgt}_tool_names" "${_tool_idx}"
			tool_name)
		math(EXPR _tool_idx "${_tool_idx} + 1")
		string_escape_output(_tool_name "${tool_name}")
		list(FIND "${_tool_tgt}_pass_id_list" "${tool_id}" _idx)
		if (_idx LESS 0) # Failed tool
			string(CONFIGURE "${FailToolItem_fmt}" _tool_item_str @ONLY)
		else()
			string(CONFIGURE "${SuppToolItem_fmt}" _tool_item_str @ONLY)
		endif()
		set("${_tool_tgt}_list" "${${_tool_tgt}_list}${_tool_item_str}")
	endforeach()
	if (${_tool_tgt}_list STREQUAL "")
		string(CONFIGURE "${UnsuppTool_fmt}" _unsupp_tool_str @ONLY)
		set(${_tool_tgt}_list "${_unsupp_tool_str}")
	elseif (NOT ${_tool_tgt}_failed_vars STREQUAL "")
		LIST(REMOVE_DUPLICATES "${_tool_tgt}_failed_vars")
		string(REPLACE ";" "\n" _failed_vars "${${_tool_tgt}_failed_vars}")
		file(WRITE "${_pl_result_dir}/${_tool_tgt}_vars.txt" "${_failed_vars}")
		string(CONFIGURE "${UnexpectedOptions_fmt}" _unexp_opt_str @ONLY)
		set("${_tool_tgt}_list" "${${_tool_tgt}_list}${_unexp_opt_str}")
	endif()
endforeach()

math(EXPR eval_board_cnt "${num_boards} - ${skip_cnt}")
if (skip_cnt EQUAL num_boards)
	set(test_result "Skipped (${num_boards} boards)")
	message(WARNING "Skipped known issues!")
elseif (fail_cnt EQUAL 0)
	set(test_result "PASS (${eval_board_cnt} boards)")
elseif(fail_cnt EQUAL eval_board_cnt)
	set(test_result "**FAIL (${eval_board_cnt} boards)**")
else()
	set(test_result
		"**${fail_cnt} of ${num_boards}** boards failed")
endif()

# Copy files to results
set(_files_to_copy
	"${ARDUINO_PLATFORM_DIR}/platform.txt"
	"${ARDUINO_PLATFORM_DIR}/boards.txt")
foreach(_file_path IN ITEMS ${_files_to_copy})
	if (EXISTS "${_file_path}")
		file(COPY "${_file_path}" DESTINATION "${_pl_result_dir}")
	endif()
endforeach()

# Write test results in BoardResults.md
file(READ "${_templates_dir}/TestResults/BoardsTblHdr.md.in"
	_brd_tbl_hdr_fmt)
string(CONFIGURE "${_brd_tbl_hdr_fmt}" _brd_tbl_hdr_str @ONLY)
file(WRITE "${_pl_result_dir}/BoardResults.md"
	"${_brd_tbl_hdr_str}${_brd_tbl_content_str}")

# Write the overall result for the platform
file(WRITE "${_pl_result_dir}/result.txt" "${test_result}")
file(READ "${_templates_dir}/TestResults/PlatformTblEntry.md.in"
	_pl_tbl_entry_fmt)
string(CONFIGURE "${_pl_tbl_entry_fmt}" _pl_tbl_entry_str @ONLY)
file(WRITE "${_pl_result_dir}/PlatformTblEntry.txt"
	"${_pl_tbl_entry_str}")

# Suuported boards tables
if(test_result MATCHES "Skipped")
	file(READ "${_templates_dir}/SupportedBoards/SkipPlEntry.${_fmt_ext}"
		_tbl_entry_fmt)
elseif (test_result MATCHES "FAIL")
	file(READ "${_templates_dir}/SupportedBoards/FailPlEntry.${_fmt_ext}"
		_tbl_entry_fmt)
else()
	file(READ "${_templates_dir}/SupportedBoards/SuppPlEntry.${_fmt_ext}"
		_tbl_entry_fmt)
endif()
string_escape_output(_pl_name "${pl_name}")
string_escape_output(_pkg_maint "${pkg_maint}")
string_escape_output(_pl_id "${pl_id}")
string(CONFIGURE "${_tbl_entry_fmt}" _tbl_entry_str @ONLY)
file(WRITE "${_pl_result_dir}/SupportedTblEntry.txt"
	"${_tbl_entry_str}")
