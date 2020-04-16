# Copyright (c) 2020 Arduino CMake Toolchain

# No need to include this recursively
if(_TOOLCHAIN_COMMON_UTILS_INCLUDED)
	return()
endif()
set(_TOOLCHAIN_COMMON_UTILS_INCLUDED TRUE)

# List filter is not available in older versions of cmake
# Providing equivalent versions for the same
function(list_filter_include_regex _list_var _regex)

	if (CMAKE_VERSION VERSION_LESS 3.6.3)
		set(_result)
		foreach(_elem IN LISTS "${_list_var}")
			string(REGEX MATCH "${_regex}" _match "${_elem}")
			if (_match)
				list(APPEND _result "${_elem}")
			endif()
		endforeach()
		set("${_list_var}" "${_result}" PARENT_SCOPE)
	else()
		list(FILTER "${_list_var}" INCLUDE REGEX  "${_regex}")
		set("${_list_var}" "${${_list_var}}" PARENT_SCOPE)
	endif()

endfunction()

# List filter is not available in older versions of cmake
# Providing equivalent versions for the same
function(list_filter_exclude_regex _list_var _regex)

	if (CMAKE_VERSION VERSION_LESS 3.6.3)
		set(_result)
		foreach(_elem IN LISTS "${_list_var}")
			string(REGEX MATCH "${_regex}" _match "${_elem}")
			if (NOT _match)
				list(APPEND _result "${_elem}")
			endif()
		endforeach()
		set("${_list_var}" "${_result}" PARENT_SCOPE)
	else()
		list(FILTER "${_list_var}" EXCLUDE REGEX  "${_regex}")
		set("${_list_var}" "${${_list_var}}" PARENT_SCOPE)
	endif()

endfunction()

# List TRANSFORM is not available in older versions of cmake
# Providing equivalent versions for the same
function(list_transform_replace _list_var _regex _replace)
	if (CMAKE_VERSION VERSION_LESS 3.12.4)
		set(_result)
		foreach (_elem IN LISTS "${_list_var}")
			string(REGEX REPLACE "${_regex}" "${_replace}" _new_elem "${_elem}")
			list(APPEND _result "${_new_elem}")
		endforeach()
		set("${_list_var}" "${_result}" PARENT_SCOPE)
	else()
		list(TRANSFORM "${_list_var}" REPLACE "${_regex}" "${_replace}")
		set("${_list_var}" "${${_list_var}}" PARENT_SCOPE)
	endif()
endfunction()

# List join is not available in older versions of cmake
# Providing equivalent versions for the same
function(list_join list_var join_str return_str)
	if (CMAKE_VERSION VERSION_LESS 3.12.4)
		set(_result)
		set(_join_str "")
		set(_return_str "")
		foreach (_elem IN LISTS "${list_var}")
			set(_return_str "${_return_str}${_join_str}${_elem}")
			set(_join_str "${join_str}")
		endforeach()
		set("${return_str}" "${_return_str}" PARENT_SCOPE)
	else()
		list(JOIN "${list_var}" "${join_str}" _return_str)
		set("${return_str}" "${_return_str}" PARENT_SCOPE)
	endif()
endfunction()

# String APPEND is not available in older versions of cmake
# Providing equivalent versions for the same
function(string_append _string_var)
	if (CMAKE_VERSION VERSION_LESS 3.4.3)
		foreach(_arg IN LISTS ARGN)
			set("${_string_var}" "${${_string_var}}${_arg}" PARENT_SCOPE)
		endforeach()
	else()
		string(APPEND "${_string_var}" ${ARGN})
		set("${_string_var}" "${${_string_var}}" PARENT_SCOPE)
	endif()
endfunction()

# Make a string ready for quoting
function(string_escape_quoting _string_var)
	string(REPLACE "\\" "\\\\" _escaped_str "${${_string_var}}")
	string(REPLACE "\"" "\\\"" _escaped_str "${_escaped_str}")
	set("${_string_var}" "${_escaped_str}" PARENT_SCOPE)
endfunction()

# String REGEX REPLACE ignores ^ and incorrectly replaces intermediate matches
# as well. This is an alternate solution.
function(string_regex_replace_start regex replace return_value)
	set(_input "")
	foreach(_arg IN LISTS ARGN)
		string_append(_input "${_arg}")
	endforeach()
	string(REGEX MATCH "^${regex}" _match "${_input}")
	string(LENGTH "${_match}" _match_len)
	string(SUBSTRING "${_input}" "${_match_len}" -1 _value)
	set("${return_value}" "${_value}" PARENT_SCOPE)
	foreach(_idx RANGE 0 9)
		if (DEFINED CMAKE_MATCH_${_idx})
			set(CMAKE_MATCH_${_idx} "${CMAKE_MATCH_${_idx}}" PARENT_SCOPE)
		endif()
	endforeach()
endfunction()

# Escape the string for making it suitable as part of a regular expression
function(string_escape_regex return_value)
	string(REGEX REPLACE "([][()+*.|^$\\\\<>])" "\\\\\\1" _value ${ARGN})
	set("${return_value}" "${_value}" PARENT_SCOPE)
endfunction()

# Escape the string for making it suitable as part of markdown string
function(string_escape_markdown return_value)
	string(REGEX REPLACE "([][(){}_`+*.|\\\\<>!])" "\\\\\\1" _value ${ARGN})
	set("${return_value}" "${_value}" PARENT_SCOPE)
endfunction()

# Check if two files are the same
function(check_same_file file1 file2 _ret_var)
	get_filename_component(x "${file1}" ABSOLUTE)
	get_filename_component(y "${file2}" ABSOLUTE)
	if (x STREQUAL y)
		set("${_ret_var}" TRUE PARENT_SCOPE)
	else()
		set("${_ret_var}" FALSE PARENT_SCOPE)
	endif()
endfunction()

# Add file(s) as configure dependency so that CMake re-runs when
# those files change
function(add_configure_dependency file)
	foreach(item IN LISTS ARGN ITEMS "${file}")
		# message("Configure dependency: ${item}")
		set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
			"${item}")
	endforeach()
endfunction()

# List sublist is not available in older versions of cmake
# Providing equivalent versions for the same
function(list_sublist list_var begin length return_list_var)

	if (CMAKE_VERSION VERSION_LESS 3.12.4)
		set(_result)
		list(LENGTH "${list_var}" _list_len)
		if (length LESS 0)
			set(length "${_list_len}")
		endif()
		math(EXPR _end  "${begin} + ${length}")
		if (_end GREATER _list_len)
			set(_end ${_list_len})
		endif()
		set(_idx "${begin}")
		while(_idx LESS _end)
			list(GET "${list_var}" "${_idx}" _elem)
			list(APPEND _result "${_elem}")
			math(EXPR _idx "${_idx}+1")
		endwhile()
		set("${return_list_var}" "${_result}" PARENT_SCOPE)
	else()
		list(SUBLIST "${list_var}" "${begin}" "${length}" _result)
		set("${return_list_var}" "${_result}" PARENT_SCOPE)
	endif()

endfunction()

# Exit with error
function(error_exit)
	# Ensure that the board option is included next time
	unset(_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE_TS CACHE)
	message(FATAL_ERROR ${ARGN})
endfunction()

# Graceful error macro. Must be called only from functions
# which parsed the REQUIRED/QUIET/RESULT_VARIABLE arguments
# with prefix in parsed_args
macro(report_error _err_code)

	cmake_parse_arguments(_err_args "NO_RETURN" "" "" ${ARGN})

	# Report error, set result and return from the current function
	if (parsed_args_REQUIRED)
		error_exit(${_err_args_UNPARSED_ARGUMENTS})
	elseif(NOT parsed_args_QUIET)
		message(WARNING ${_err_args_UNPARSED_ARGUMENTS})
	endif()

	if (parsed_args_RESULT_VARIABLE)
		set("${parsed_args_RESULT_VARIABLE}" "${_err_code}" PARENT_SCOPE)
	endif()
	if (NOT _err_args_NO_RETURN)
		return()
	endif()
endmacro()

function(print_vars_with_prefix prefix)
    get_cmake_property(_variableNames VARIABLES)
	string(REGEX REPLACE "\\." "\\\\." prefix_regex "${prefix}")
    list_filter_include_regex(_variableNames "^${prefix_regex}")
    foreach (_variableName ${_variableNames})
        message("${_variableName}=${${_variableName}}")
    endforeach()
endfunction()
