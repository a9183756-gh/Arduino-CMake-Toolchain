# Copyright (c) 2020 Arduino CMake Toolchain

# No need to include this recursively
if(_LIBRARY_INDEX_INCLUDED)
	return()
endif()
set(_LIBRARY_INDEX_INCLUDED TRUE)

# Cache variable for setting any additional root folders that contain the
# Arduino libraries. 'libraries' or 'dependencies' suffix shall not be 
# added in this list of paths.
set(ARDUINO_LIBRARIES_SEARCH_PATHS_EXTRA "" CACHE PATH
	"Paths to search for Arduino libraries in addition to standard paths"
)

#******************************************************************************
# Indexing of Arduino Libraries. Keeps a list of installed libraries to be
# used during the library search.

include(CMakeParseArguments)
include(Arduino/Utilities/CommonUtils)
include(Arduino/Utilities/PropertiesReader)

#==============================================================================
# Glob the libraries folder for installed libraries and parse the library
# properties from library.properties file.
#
# After calling this function, libraries_get_list returns a list of libraries,
# whose properties can be queried using libraries_get_property.
#
function(IndexArduinoLibraries namespace)

	cmake_parse_arguments(parsed_args "" "" "COMMENT;PATH_SUFFIXES" ${ARGN})

	properties_reset("${namespace}")

	set(search_paths "${parsed_args_UNPARSED_ARGUMENTS}")
	if (search_paths STREQUAL "")
		set(search_paths
			${CMAKE_SOURCE_DIR}
			$CACHE{ARDUINO_LIBRARIES_SEARCH_PATHS_EXTRA}
			${ARDUINO_PACKAGE_MANAGER_PATH}
			${ARDUINO_SKETCHBOOK_PATH}
			${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}
			${ARDUINO_CORE_SPECIFIC_PLATFORM_PATH}
			${ARDUINO_INSTALL_PATH})
	endif()

	# Glob the list of all the libraries to search for in the priority order
	set(_cached_search_root_list "${_ARDUINO_LIB_SEARCH_ROOT_LIST}")
	set(_search_root_list)
	set(_lib_count 0)
	set(_lib_list)
	foreach(_root_path IN LISTS search_paths)

		list(FIND _cached_search_root_list "${_root_path}" _path_idx)
		if (_path_idx LESS 0)
			# This root path is still not scanned
			list(LENGTH _cached_search_root_list _path_idx)
			list(APPEND _cached_search_root_list "${_root_path}")
		endif()

		set(glob_expressions)
		foreach(suffix IN LISTS parsed_args_PATH_SUFFIXES ITEMS "libraries"
			"dependencies")
			list(APPEND glob_expressions "${_root_path}/${suffix}/*")
		endforeach()

		if (CMAKE_VERSION VERSION_LESS 3.12.0)
			file(GLOB _path_list ${glob_expressions})
		else()
			file(GLOB _path_list CONFIGURE_DEPENDS ${glob_expressions})
		endif()
		list(SORT _path_list)

		# Reindex the libraries only if there is a change?
		if (NOT DEFINED _LAST_ARDUINO_LIB_SEARCH_PATHS.${_path_idx} OR NOT
			_path_list STREQUAL _LAST_ARDUINO_LIB_SEARCH_PATHS.${_path_idx})
			if (NOT "${parsed_args_COMMENT}" STREQUAL "")
				string(REPLACE ";" "" parsed_args_COMMENT
					"${parsed_args_COMMENT}")
				message(STATUS "${parsed_args_COMMENT}")
				set(parsed_args_COMMENT) # No more messages in the loop
			endif()
			_libraries_scan("${_path_idx}" "${_root_path}" "${_path_list}")
			set(_LAST_ARDUINO_LIB_SEARCH_PATHS.${_path_idx} "${_path_list}"
				CACHE INTERNAL "")
		endif()

		set(_idx 1)
		list(LENGTH _ARDUINO_LIB_NAMES_LIST.${_path_idx} _num_libs)
		while(_idx LESS _num_libs)
			list(GET _ARDUINO_LIB_NAMES_LIST.${_path_idx} ${_idx} _lib_name)
			list(GET _ARDUINO_LIB_PATH_LIST.${_path_idx} ${_idx} _rel_path)
			list(GET _ARDUINO_LIB_ARCH_LIST.${_path_idx} ${_idx} _lib_arch_str)
			list(GET _ARDUINO_LIB_EXP_INC_LIST.${_path_idx} ${_idx}
				_lib_exp_inc_str)
			list(GET _ARDUINO_LIB_IMP_INC_LIST.${_path_idx} ${_idx}
				_lib_imp_inc_str)
			math(EXPR _idx "${_idx} + 1")

			math(EXPR _lib_count "${_lib_count} + 1")
			set(_lib_id "lib.${_lib_count}")

			properties_set_value("${namespace}" "${_lib_id}/name"
				"${_lib_name}")
			properties_set_value("${namespace}" "${_lib_id}/path"
				"${_root_path}/${_rel_path}")
			string(REGEX REPLACE " *, *" ";" _lib_arch_list "${_lib_arch_str}")
			properties_set_value("${namespace}" "${_lib_id}/architectures"
				"${_lib_arch_list}")
			string(REGEX REPLACE " *, *" ";" _lib_exp_inc_list
				"${_lib_exp_inc_str}")
			properties_set_value("${namespace}" "${_lib_id}/exp_includes"
				"${_lib_exp_inc_list}")
			string(REGEX REPLACE " *, *" ";" _lib_imp_inc_list
				"${_lib_imp_inc_str}")
			properties_set_value("${namespace}" "${_lib_id}/imp_includes"
				"${_lib_imp_inc_list}")
			list(APPEND _lib_list "${_lib_id}")
		endwhile()

	endforeach()

	set(_ARDUINO_LIB_SEARCH_ROOT_LIST "${_cached_search_root_list}"
		CACHE INTERNAL "")

	# Create property entries from the cached list of libraries
	properties_set_value("${namespace}" "lib_list" "${_lib_list}")
	properties_set_value("${namespace}" "lib_search_root_list"
		"${search_paths}")
	properties_set_parent_scope("${namespace}")

	# libraries_print_properties("${namespace}")

endfunction()

#==============================================================================
# As explained in 'IndexArduinoLibraries', this function returns all the
# indexed arduino libraries. Must be called after a call to 
# 'IndexArduinoLibraries'.
#
# Arguments:
# <return_list> [OUT]: The list of libraries
#
function(libraries_get_list namespace return_list)

	properties_get_value("${namespace}" "lib_list" _lib_list)
	set("${return_list}" "${_lib_list}" PARENT_SCOPE)

endfunction()

#==============================================================================
# As explained in 'IndexArduinoLibraries', this function returns the property
# of the specified library.
#
# Arguments:
# <lib_id> [IN]: library identifier (one of the entries in the list
# returned by 'libraries_get_list'
# <prop_name> [IN]: Property name (rooted at the library.properties entry)
# or one of "/*" properties
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(libraries_get_property namespace lib_id prop_name return_value)

	# TODO check the validity of the namespace?

	# If the property starts with '/' it implies local property
	string(SUBSTRING "${prop_name}" 0 1 first_letter)
	if ("${first_letter}" STREQUAL "/")
		properties_get_value("${namespace}" "${lib_id}${prop_name}"
			_prop_value ${ARGN})
		set("${return_value}" "${_prop_value}" PARENT_SCOPE)
	else()
		properties_get_value("${namespace}" "${lib_id}.${prop_name}"
			_prop_value ${ARGN})
		set("${return_value}" "${_prop_value}" PARENT_SCOPE)
	endif()

endfunction()

#==============================================================================
# Print all the properties of all the indexed libraries (for debugging)
#
function(libraries_print_properties namespace)

	properties_print_all("${namespace}")

endfunction()

#==============================================================================
# The caller of 'IndexArduinoLibraries' can use this function to set the scope
# of the indexed libraries to its parent context (similar to PARENT_SCOPE of
# 'set' function)
#
macro(libraries_set_parent_scope namespace)

	properties_set_parent_scope("${namespace}")

endmacro()

#==============================================================================
# Implementation functions (Subject to change. DO NOT USE)
#

# Scan the given paths for the Arduino libraries
function(_libraries_scan scan_idx scan_root_path scan_path_list)

	# Capture all the library information in a list.
	# Here, initial dummy non-empty ":" allows later empty fields in the list.
	set(_lib_names_list ":")
	set(_lib_path_list ":")
	set(_lib_arch_list ":")
	set(_lib_exp_inc_list ":")
	set(_lib_imp_inc_list ":")

	foreach(_lib_path IN LISTS scan_path_list)

		# The folder must contain library.properties
		if (NOT IS_DIRECTORY "${_lib_path}" OR
			NOT EXISTS "${_lib_path}/library.properties")
			continue()
		endif()

		# Read the properties of the library
		get_filename_component(_lib_path_name "${_lib_path}" NAME)
		# message("Read ${_lib_path}/library.properties")
		properties_read("${_lib_path}/library.properties" lib_prop)
		properties_get_value(lib_prop "name" _lib_name
			DEFAULT "${_lib_path_name}")
		properties_get_value(lib_prop "architectures" _lib_arch_str QUIET)
		properties_get_value(lib_prop "includes" _lib_exp_inc_str QUIET)
		properties_reset(lib_prop)

		# If no explicit includes list provides, glob for the implicit includes
		set(_lib_imp_inc_str "")
		if ("${_lib_exp_inc_str}" STREQUAL "")
			find_library_header_files("${_lib_path}" _lib_includes NO_RECURSE)
			set(_lib_inc_name_list)
			foreach(_include IN LISTS _lib_includes)
				get_filename_component(_include_name "${_include}" NAME)
				list(APPEND _lib_inc_name_list "${_include_name}")
			endforeach()
			string(REPLACE ";" "," _lib_imp_inc_str "${_lib_inc_name_list}")
		endif()

		list(APPEND _lib_names_list "${_lib_name}")
		file(RELATIVE_PATH _rel_path "${scan_root_path}" "${_lib_path}")
		list(APPEND _lib_path_list "${_rel_path}")
		list(APPEND _lib_arch_list "${_lib_arch_str}")
		list(APPEND _lib_exp_inc_list "${_lib_exp_inc_str}")
		list(APPEND _lib_imp_inc_list "${_lib_imp_inc_str}")

	endforeach()

	# Cache the information for use during the library search
	set(_ARDUINO_LIB_NAMES_LIST.${scan_idx} "${_lib_names_list}"
		CACHE INTERNAL "")
	set(_ARDUINO_LIB_PATH_LIST.${scan_idx} "${_lib_path_list}"
		CACHE INTERNAL "")
	set(_ARDUINO_LIB_ARCH_LIST.${scan_idx} "${_lib_arch_list}"
		CACHE INTERNAL "")
	set(_ARDUINO_LIB_EXP_INC_LIST.${scan_idx} "${_lib_exp_inc_list}"
		CACHE INTERNAL "")
	set(_ARDUINO_LIB_IMP_INC_LIST.${scan_idx} "${_lib_imp_inc_list}"
		CACHE INTERNAL "")

endfunction()

