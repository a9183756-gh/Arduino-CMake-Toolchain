# Copyright (c) 2020 Arduino CMake Toolchain
# Copyright (c) 2018 Arduino CMake

# Note: Some code copied from Arduino-CMake-NG project and re-written
# Thanks to the contributers of the project

# No need to include this recursively
if(_PROPERTIES_READER_INCLUDED)
	return()
endif()
set(_PROPERTIES_READER_INCLUDED TRUE)

function(properties_read properties_file namespace)

	file(STRINGS ${properties_file} _content)
	# message("\n${_content}")
	_properties_parse(_content "${namespace}")
	set("${namespace}/list" "${${namespace}/list}" PARENT_SCOPE)
endfunction()

function(properties_get_value namespace property_name return_value)
	cmake_parse_arguments(parsed_args "QUIET" "DEFAULT" "" ${ARGN})
	if (NOT DEFINED "${namespace}.${property_name}")
		# message("parsed_args:${parsed_args_QUIET}:${parsed_args_DEFAULT}")
		if (NOT parsed_args_QUIET AND "${parsed_args_DEFAULT}" STREQUAL "")
			message(FATAL_ERROR "Property '${property_name}' in '${namespace}' invalid!!!")
		else()
			set("${return_value}" "${parsed_args_DEFAULT}" PARENT_SCOPE)
		endif()
	else()
		set("${return_value}" "${${namespace}.${property_name}}" PARENT_SCOPE)
	endif()
	
endfunction()

function(properties_set_value namespace prop value)
	LIST(FIND "${namespace}/list" "${prop}" _idx)
	if (${_idx} EQUAL -1)
		LIST(APPEND "${namespace}/list" "${prop}")
		set("${namespace}/list" "${${namespace}/list}" PARENT_SCOPE)
	endif()
	# message("${namespace}:${prop}:${value}")
	set("${namespace}.${prop}" "${value}")
	set("${namespace}.${prop}" "${value}" PARENT_SCOPE)
endfunction()

function(properties_get_list namespace pattern return_list)
	set(_prop_list "${${namespace}/list}")
	list_filter_include_regex(_prop_list "${pattern}")
	set("${return_list}" "${_prop_list}" PARENT_SCOPE)
endfunction()

function(properties_resolve_value value return_value namespace)

	set(_expanded_list)
	_properties_expand_value("${value}" _result_value "${namespace}"
			_expanded_list)
	set("${return_value}" "${_result_value}" PARENT_SCOPE)

endfunction()

function(properties_resolve_all_values namespace)
	set(_prop_list "${${namespace}/list}")
	set(_expanded_list)
	foreach(_prop IN LISTS _prop_list)
		list(APPEND _expanded_list ${_prop})
		_properties_expand_value("${${namespace}.${_prop}}" _resolved_value "${namespace}"
			_expanded_list)
		# message("Resolve *** ${_prop} ***:${${namespace}.${_prop}}\n${_resolved_value}")
		# message("Expanded: ${_expanded_list}")
		set("${namespace}.${_prop}" "${_resolved_value}")
		set("${namespace}.${_prop}" "${_resolved_value}" PARENT_SCOPE)
	endforeach()
endfunction()

function(properties_print_all namespace)
	set(_prop_list "${${namespace}/list}")
	foreach(_prop IN LISTS _prop_list)
		message("${_prop}=${${namespace}.${_prop}}")
	endforeach()
endfunction()

macro(properties_set_parent_scope namespace)
	set(_prop_list "${${namespace}/list}")
	foreach(_prop IN LISTS _prop_list)
		set("${namespace}.${_prop}" "${${namespace}.${_prop}}" PARENT_SCOPE)
	endforeach()
	set("${namespace}/list" "${${namespace}/list}" PARENT_SCOPE)
endmacro()

macro(_properties_parse content namespace)

	set(_last_property)
	foreach (_property IN LISTS "${content}")

		string(REGEX MATCH "^([^#=]+)=([^#]*)" match "${_property}")
		if (NOT match)
			# May be part of last string (Because CMake omits binary and splits
			# as list element
			string(REGEX MATCH "^([^#]+)" match "${_property}")
			if ("${match}" STREQUAL "")
				continue()
			endif()

			string(STRIP "${CMAKE_MATCH_1}" _last_part)
			set(_last_property "${_last_property}${_last_part}" )
			string(REGEX MATCH "^([^#=]+)=([^#]*)" match "${_last_property}")
			if (NOT match)
				continue()
			endif()
			set(_property "${_last_property}" )
		endif()

		set(_property_name "${CMAKE_MATCH_1}")
		set(_property_value "${CMAKE_MATCH_2}")

		LIST(APPEND "${namespace}/list" "${_property_name}")
		set("${namespace}.${_property_name}" "${_property_value}")
		set("${namespace}.${_property_name}" "${_property_value}" PARENT_SCOPE)

		set(_last_property "${_property}")
	endforeach()

endmacro()

function(_properties_expand_value value return_value namespace
		expanded_list)

	set(_value "${value}")

	# Don't resolve empty values - There's nothing to resolve
	if ("${_value}" STREQUAL "")
		set("${return_value}" "" PARENT_SCOPE)
		return()
	endif ()

	set(_result_value "")
	while(TRUE)
		string(FIND "${_value}" "{" var_start_pos)
		string(SUBSTRING "${_value}" 0 ${var_start_pos} val_prefix)
		string_append(_result_value "${val_prefix}")
		if (var_start_pos EQUAL -1)
			break()
		ENDIF()
		math(EXPR var_start_pos  "${var_start_pos} + 1")
		string(SUBSTRING "${_value}" ${var_start_pos} -1 val_suffix)
		string(FIND "${val_suffix}" "}" var_end_pos)
		if (var_end_pos EQUAL -1)
			string_append(_result_value "{${val_suffix}")
			break()
		ENDIF()
		string(SUBSTRING "${val_suffix}" 0 ${var_end_pos} var_name)
		if (DEFINED "${namespace}.${var_name}")
			list(FIND "${expanded_list}" "${var_name}" _found_idx)
			if ("${_found_idx}" EQUAL -1)
				list(APPEND "${expanded_list}" "${var_name}")
				_properties_expand_value("${${namespace}.${var_name}}"
					_var_value "${namespace}" expanded_list)
				set("${expanded_list}" "${${expanded_list}}"
					PARENT_SCOPE)
				string_append(_result_value "${_var_value}")
			else()
				string_append(_result_value "${${namespace}.${var_name}}")
			endif()
		else()
			string_append(_result_value "{${var_name}}")
		endif()
		math(EXPR var_end_pos  "${var_end_pos} + 1")
		string(SUBSTRING "${val_suffix}" ${var_end_pos} -1 _value)
	endwhile()

	set("${return_value}" "${_result_value}" PARENT_SCOPE)

endfunction()

