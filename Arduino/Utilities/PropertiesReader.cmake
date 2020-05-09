# Copyright (c) 2020 Arduino CMake Toolchain
# Copyright (c) 2018 Arduino CMake

# Note: Some code copied from Arduino-CMake-NG project and re-written
# Thanks to the contributers of the project

# No need to include this recursively
if(_PROPERTIES_READER_INCLUDED)
	return()
endif()
set(_PROPERTIES_READER_INCLUDED TRUE)

include(CMakeParseArguments)
include(Arduino/Utilities/CommonUtils)

#==============================================================================
# Properties reader interface function
#

# Read properties from a file and save it in the given namespace
function(properties_read properties_file namespace)

	file(STRINGS ${properties_file} _content)
	# message("\n${_content}")
	_properties_parse(_content "${namespace}")
	set("${namespace}/list" "${${namespace}/list}" PARENT_SCOPE)

endfunction()

# Get a value of the given property from the given namespace
function(properties_get_value namespace property_name return_value)

	cmake_parse_arguments(parsed_args "QUIET" "DEFAULT" "" ${ARGN})
	if (NOT DEFINED "${namespace}.${property_name}")
		# message("parsed_args:${parsed_args_QUIET}:${parsed_args_DEFAULT}")
		if (NOT parsed_args_QUIET AND "${parsed_args_DEFAULT}" STREQUAL "")
			error_exit("Property '${property_name}' in '${namespace}' invalid!!!")
		else()
			set("${return_value}" "${parsed_args_DEFAULT}" PARENT_SCOPE)
		endif()
	else()
		set("${return_value}" "${${namespace}.${property_name}}" PARENT_SCOPE)
	endif()
	
endfunction()

# Set a given property value in the given namespace
function(properties_set_value namespace prop value)
	if (NOT DEFINED "${namespace}.${prop}")
		LIST(APPEND "${namespace}/list" "${prop}")
		set("${namespace}/list" "${${namespace}/list}" PARENT_SCOPE)
	endif()
	# message("${namespace}:${prop}:${value}")
	set("${namespace}.${prop}" "${value}" PARENT_SCOPE)
endfunction()

# Get the list of properties of the given namespace
function(properties_get_list namespace pattern return_list)
	set(_prop_list "${${namespace}/list}")
	list_filter_include_regex(_prop_list "${pattern}")
	set("${return_list}" "${_prop_list}" PARENT_SCOPE)
endfunction()

# Remove all the properties and reset the given namespace
function(properties_reset namespace)
	set(_prop_list "${${namespace}/list}")
	foreach(_prop IN LISTS _prop_list)
		unset("${namespace}.${_prop}" PARENT_SCOPE)
	endforeach()
	set("${namespace}/list" "" PARENT_SCOPE)
endfunction()

# Resolve the given value i.e. expand the embedded variables to their
# values from the namespace
function(properties_resolve_value value return_value namespace)

	cmake_parse_arguments(parsed_args "" "UNRESOLVED_LIST" "" ${ARGN})

	properties_reset("/prop_int_resolved")
	properties_reset("/prop_int_unresolved")
	_properties_expand_value("${value}" _result_value "${namespace}")
	set("${return_value}" "${_result_value}" PARENT_SCOPE)
	if (DEFINED parsed_args_UNRESOLVED_LIST)
		set("${parsed_args_UNRESOLVED_LIST}" "${/prop_int_unresolved/list}"
			PARENT_SCOPE)
	endif()

endfunction()

# Resolve all the values of the given namespace
function(properties_resolve_all_values namespace)

	cmake_parse_arguments(parsed_args "" "UNRESOLVED_LIST" "" ${ARGN})

	set(_prop_list "${${namespace}/list}")
	properties_reset("/prop_int_resolved")
	properties_reset("/prop_int_unresolved")
	foreach(_prop IN LISTS _prop_list)
		# Temporarily resolve it to the same variable to handle recursive
		# references
		properties_set_value("/prop_int_resolved" "${_prop}"
			"{${_prop}}")
		# message("Resolve *** ${_prop} *** : ${${namespace}.${_prop}}")
		_properties_expand_value("${${namespace}.${_prop}}" _resolved_value
			"${namespace}")
		properties_set_value("/prop_int_resolved" "${_prop}"
			"${_resolved_value}")
		# message("EXPANDED ${_prop}: ${_resolved_value}")
	endforeach()
	foreach(_prop IN LISTS "/prop_int_resolved/list")
		set("${namespace}.${_prop}" "${/prop_int_resolved.${_prop}}"
			PARENT_SCOPE)
	endforeach()
	if (DEFINED parsed_args_UNRESOLVED_LIST)
		set("${parsed_args_UNRESOLVED_LIST}" "${/prop_int_unresolved/list}"
			PARENT_SCOPE)
	endif()

endfunction()

# Print all the properties of the namespace (for debugging)
function(properties_print_all namespace)
	set(_prop_list "${${namespace}/list}")
	foreach(_prop IN LISTS _prop_list)
		message("${_prop}=${${namespace}.${_prop}}")
	endforeach()
endfunction()

# Set the scope of the given namespace to the caller's parent, so that
# the namespace is accessible from the parent scope. Analogous to
# set(... PARENT_SCOPE)
macro(properties_set_parent_scope namespace)
	set(_prop_list "${${namespace}/list}")
	foreach(_prop IN LISTS _prop_list)
		set("${namespace}.${_prop}" "${${namespace}.${_prop}}" PARENT_SCOPE)
	endforeach()
	set("${namespace}/list" "${${namespace}/list}" PARENT_SCOPE)
endmacro()

#==============================================================================
# Implementation functions (Subject to change. DO NOT USE)
#

# Parse the properties
macro(_properties_parse content_var namespace)

	set(_last_property)
	foreach (_property IN LISTS "${content_var}")

		string(STRIP "${_property}" _property)
		if ("${_property}" STREQUAL "")
			continue()
		endif()
		if (_property MATCHES "^[ \t]*#") # Comment
			continue()
		endif()
		string(REGEX MATCH "^([^=]+)=(.*)" match "${_property}")
		if (NOT match)
			# May be part of last string (Because CMake omits binary and splits
			# as list element
			string(REGEX MATCH "^(.+)" match "${_property}")
			if ("${match}" STREQUAL "")
				continue()
			endif()

			string(STRIP "${CMAKE_MATCH_1}" _last_part)
			set(_last_property "${_last_property}${_last_part}" )
			string(REGEX MATCH "^([^=]+)=(.*)" match "${_last_property}")
			if (NOT match)
				continue()
			endif()
			set(_property "${_last_property}" )
		endif()

		set(_property_name "${CMAKE_MATCH_1}")
		string(STRIP "${_property_name}" _property_name)
		set(_property_value "${CMAKE_MATCH_2}")
		string(STRIP "${_property_value}" _property_value)

		if (NOT DEFINED "${namespace}.${_property_name}")
			LIST(APPEND "${namespace}/list" "${_property_name}")
		endif()

		set("${namespace}.${_property_name}" "${_property_value}")
		set("${namespace}.${_property_name}" "${_property_value}" PARENT_SCOPE)

		set(_last_property "${_property}")
	endforeach()

endmacro()

# Utility function to expand the embedded variables
function(_properties_expand_value value return_value namespace)

	set(_value "${value}")

	# Don't resolve empty values - There's nothing to resolve
	if ("${_value}" STREQUAL "")
		set("${return_value}" "" PARENT_SCOPE)
		return()
	endif ()

	# Get the variables list
	string(REGEX MATCHALL "{[^{}/]+}" _var_list "${_value}")
	if (NOT "${_var_list}" STREQUAL "")
		list(REMOVE_DUPLICATES _var_list)
	endif()
	foreach(_var_str IN LISTS _var_list)

		# Get the variable name
		string(REGEX MATCH "^{(.*)}$" _match "${_var_str}")
		set(_var_name "${CMAKE_MATCH_1}")

		# Check if not resolved already
		if (NOT DEFINED "/prop_int_resolved.${_var_name}")
			# If such a variable is not in the namespace, no need to resolve
			if (NOT DEFINED "${namespace}.${_var_name}")
				properties_set_value("/prop_int_unresolved" ${_var_name} "")
				continue()
			endif()

			# Temporarily resolve it to the same variable to handle recursive
			# references
			properties_set_value("/prop_int_resolved" "${_var_name}"
				"{${_var_name}}")

			# message("=> Resolve *** ${_var_name} *** : "
			#	"${${namespace}.${_var_name}}")
			_properties_expand_value("${${namespace}.${_var_name}}"
				_var_value "${namespace}")
			properties_set_value("/prop_int_resolved" "${_var_name}"
				"${_var_value}")
			# message("=> EXPANDED ${_var_name}: ${_var_value}")
		endif()

		string(REPLACE "${_var_str}" "${/prop_int_resolved.${_var_name}}"
			_value "${_value}")

	endforeach()

	properties_set_parent_scope("/prop_int_resolved")
	properties_set_parent_scope("/prop_int_unresolved")
	set("${return_value}" "${_value}" PARENT_SCOPE)

endfunction()

