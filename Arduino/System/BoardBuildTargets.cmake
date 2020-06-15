# Copyright (c) 2020 Arduino CMake Toolchain

if (_BOARD_BUILD_TARGETS_INCLUDED)
	return()
endif()

set(_BOARD_BUILD_TARGETS_INCLUDED TRUE)

include(CMakeParseArguments)
INCLUDE(Arduino/Utilities/CommonUtils)
INCLUDE(Arduino/Utilities/SourceLocator)
include(Arduino/Utilities/SourceDependency)
include(Arduino/System/BoardToolchain)
include(Arduino/System/LibraryIndex)

# Define ARDUINO_LIB property on the target, to identify Arduino Library
# targets.
define_property(TARGET
                PROPERTY ARDUINO_LIB
                FULL_DOCS "If the target builds an Arduino library, then "
                          "this property holds the name of the library"
                BRIEF_DOCS "Arduino library name")

#******************************************************************************
# Interface functions for building the Arduino platform code and libraries,
# and link it with any target in the cmake project.
#

#==============================================================================
# target_link_arduino_libraries(<target>
#           [<PRIVATE|PUBLIC|INTERFACE> <lib>...] ...
#           [<AUTO_PRIVATE|AUTO_PUBLIC|AUTO_INTERFACE> [<src>...]] ...
#           [IGNORE <lib>...]
#           [OVERRIDE <ard_lib_tgt>...])
#
# Link the given arduino libraries to the given target
#
# Arguments:
#
# <target> [IN]: The target to which the arduino libraries are to be linked
#
# <lib> [IN]: Case-sensitive name of the arduino library (NOT target name).
# This is either native, user-installed or project specific Arduino
# library present in Arduino installation paths and project folders (i.e. 
# within the folders with name libraries or dependencies). A special
# name 'core' implies the Arduino core library (Base platform code).
#
# <src> [IN]: Source files used for the automatic detection of the library
# dependencies. If none provided, the list of sources are taken from the
# target SOURCES property. Typically a single interface header file as
# given in one of the below examples should be sufficient.
#
# <ard_lib_tgt> [IN]: Target added using `add_custom_arduino_library` or
# `add_custom_arduino_core`, used as override for any correspondingly 
# automatically detected Arduino library. See detailed documentation.
#
# The keywords AUTO* enables automatic finding of the dependent Arduino
# libraries included from the source files using regular expressions. 
#
# e.g.
#     # Automatically link with Arduino libraries included in my_lib sources.
#     # All those detected libraries are linked as PUBLIC (AUTO_PUBLIC)
#     target_link_arduino_libraries(my_lib AUTO_PUBLIC)
#
#     # Link explicitly with core, Wire and IRremote libraries
#     target_link_arduino_libraries(my_app PRIVATE core Wire IRremote)
#
#     # Automatically link with Arduino libraries included in my_lib.h as
#     # public, and also libraries detected from SOURCES as private
#     target_link_arduino_libraries(my_lib AUTO_PUBLIC my_lib.h AUTO_PRIVATE)
#
# In the above examples, the <lib> parameters (core, Wire, IRremote etc.)
# are Arduino library names and not CMake targets. An internal CMake target
# may be maintened by the toolchain corresponding to each of these Arduino
# libraries (Such an internal target is not accessible outside the toolchain.
# See add_custom_arduino_core/add_custom_arduino_library for advanced usage
# only).
#
# When using automatic detection, in some unlikely cases there may be 
# false positives (e.g. Arduino libraries under a not-defined preprocessor
# flag), which can be ignored using the IGNORE list. Also if there are any
# false negatives (due to not including the correct library header or due
# to obfuscated code?), those needs to be explicitly linked.
#
# e.g.
#     # Ignore certain automatically detected false positives
#     if (ARDUINO_ARCH_AVR)
#     target_link_arduino_libraries(my_app AUTO_PUBLIC IGNORE Wifi)
#     endif()
#
#     # Explicitly link arduino libraries which was not detected
#     target_link_arduino_libraries(my_app PUBLIC Wifi AUTO_PUBLIC)
#
# When automatic detection of libraries is used, then the target is linked
# with the internally maintained CMake target corresponding to the 
# automatically detected libraries. There can be a potential conflict in
# case if an Arduino library is cutomized and linked with the target (See 
# add_custom_arduino_library/add_custom_arduino_core). To avoid this 
# conflict, automatic linking looks for customized versions of the 
# libraries in INTERACE_LINK_LIBRARIES and LINK_LIBRARIES properties
# of the target (if any), as well as in the OVERRIDE list provided to
# this function and uses them instead.
#
# e.g.
#     # See also add_custom_arduino_library to understand the below example
#     find_arduino_library(Wire lib_path)
#     add_custom_arduino_library(my_arduino_wire Wire "${lib_path}")
#     target_link_libraries(my_app PRIVATE my_arduino_wire)
#     # Assuming that my_app sources use some Arduino library 'X' which
#     # in turn uses 'Wire', then the below OVERRIDE ensures that the 
#     # automatically detected 'X' uses 'my_arduino_wire' instead.
#     target_link_arduino_libraries(my_app AUTO_PRIVATE
#                                   OVERRIDE my_arduino_wire)
#     # The OVERRIDE list above is redundant here because we already
#     # linked with my_arduino_wire and so can be found in LINK_LIBRARIES
#
function (target_link_arduino_libraries target_name)

	# message("target_link_arduino_libraries ${target_name} ${ARGN}")

	cmake_policy(PUSH)

	# Need to link with libraries created in any folder and not just
	# in the current folder
	if (NOT CMAKE_VERSION VERSION_LESS 3.13)
		cmake_policy(SET CMP0079 NEW)
	endif()

	set(keywords
		PRIVATE        # Private-linked Arduino Libraries
		PUBLIC         # Public-linked Arduino Libraries
		INTERFACE      # Interface-linked Arduino Libraries
		AUTO           # Default-linked auto detected Arduino libraries
		AUTO_PRIVATE   # Private-linked auto detected Arduino libraries
		AUTO_PUBLIC    # Public-linked auto detected Arduino libraries
		AUTO_INTERFACE # Interface-linked auto detected Arduino libraries
		IGNORE         # Auto detected library names to be ignored
		OVERRIDE       # Customized targets that overrides auto detection
	)

	# Initialize the lists that collect the arguments
	set(_list_DEFAULT)
	foreach(_keyword IN LISTS keywords)
		set(_list_${_keyword}_present FALSE)
		set(_list_${_keyword})
	endforeach()

	# Parse the arguments into lists 
	set(_list_type "DEFAULT")
	foreach(_arg IN LISTS ARGN)
		list(FIND keywords "${_arg}" _idx)
		if (_idx GREATER_EQUAL 0)
			set(_list_type "${_arg}")
			set(_list_${_list_type}_present TRUE)
		else()
			list(APPEND _list_${_list_type} "${_arg}")
		endif()
	endforeach()

	# Index any local libraries (present within the local libraries folder),
	# so that they are included in any libraries search.
	# message("target_link_libraries indexing ${CMAKE_CURRENT_SOURCE_DIR}")
	_index_local_libraries(_local_namespace _is_indexed)
	if (_is_indexed)
		# Cache the search in the parent scope as well
		libraries_set_parent_scope("${_local_namespace}")
	endif()

	# If target_name itself is an internally maintained arduino library,
	# use that instead (Undocumented feature, should not be used)
	if (NOT TARGET "${target_name}")
		_map_libs_to_lib_names(target_name)
		string(MAKE_C_IDENTIFIER "${target_name}" _target_id)
		target_get_arduino_lib("_arduino_lib_${_target_id}" _ard_lib_name)
		if (_ard_lib_name)
			set(target_name "_arduino_lib_${_target_id}")
		else()
			message(FATAL_ERROR "${target_name} is not a CMake target")
		endif()
	endif()

	# Link with the explicitly provided libraries (without
	# PRIVATE/PUBLIC/INTERFACE keywords
	if (_list_DEFAULT)
		set(empty_list)
		_map_libs_to_lib_names(_list_DEFAULT)
		_link_ard_lib_list("${target_name}" _list_DEFAULT ""
			empty_list empty_list)
	endif()

	# Link with the explicitly provided libraries (with
	# PRIVATE/PUBLIC/INTERFACE keywords
	foreach(_link_type IN ITEMS PRIVATE PUBLIC INTERFACE)
		if (_list_${_link_type})
			set(empty_list)
			_map_libs_to_lib_names(_list_${_link_type})
			_link_ard_lib_list("${target_name}" _list_${_link_type}
				"${_link_type}" empty_list empty_list)
		endif()
	endforeach()

	# Include the LINK_LIBS and INTERFACE_LINK_LIBS in override list
	_find_linked_arduino_libs("${target_name}" _override_list)
	list(APPEND _list_OVERRIDE ${_override_list})
	if (_list_OVERRIDE)
		list(REMOVE_DUPLICATES _list_OVERRIDE)
	endif()

	# Link with automatically detectected libraries (with AUTO
	# keyword i.e. default linking without PRIVATE/PUBLIC/INTERFACE)
	if (_list_AUTO_present)
		_get_auto_link_libs("${target_name}" _list_AUTO _list_IGNORE
			 _list_OVERRIDE _link_libs)
		# message("_link_libs:${_link_libs}")
		_link_ard_lib_list("${target_name}" _link_libs ""
			_list_IGNORE _list_OVERRIDE)
	endif()

	# Link with automatically detectected libraries (with AUTO_*
	# keywords i.e. linking with PRIVATE/PUBLIC/INTERFACE)
	foreach(_link_type IN ITEMS PRIVATE PUBLIC INTERFACE)
		if (_list_AUTO_${_link_type}_present)
			_get_auto_link_libs("${target_name}" _list_AUTO_${_link_type}
				 _list_IGNORE _list_OVERRIDE _link_libs)
			# message("_link_libs:${_link_type}:${_link_libs}")
			_link_ard_lib_list("${target_name}" _link_libs "${_link_type}"
				_list_IGNORE _list_OVERRIDE)
		endif()
	endforeach()

	cmake_policy(POP)

endfunction()

#==============================================================================
# This function is to be called for any executable target built in the project
# (Of course, only if the build uses this toolchain i.e. if ARDUINO flag is
# defined).
#
# This function ensures that a binary image is generated that can be readily
# uploaded to the board using the '<make> SERIAL_PORT=<port> upload-<target>'.
# Please note that 'add_executable' typically generates ELF file, which cannot
# be directly uploaded to the board.
#
# This function currently also ensures to setup any other pre/post build 
# actions necessary for building the Arduino image and also printing the
# program/data size of the generated image. 
#
# For example,
#     add_executable(my_app ${MY_APP_SOURCES})
#     if (ARDUINO)
#         target_enable_arduino_upload(my_app)
#     endif()
#
# In the above example, it may also be required to link 'my_app' against the 
# Ardunio 'core' i.e. 'target_link_arduino_libraries(my_app PRIVATE core)'.
# However it is OK if 'core' gets transitively linked indirectly i.e. 
# 'target_link_libraries(my_app PRIVATE my_lib)' where 'my_lib' links with
# 'core' and thus 'my_app' indirectly links with 'core'.
#
function(target_enable_arduino_upload target)

	# TODO check if already set?
	# Also validate if EXE target

	# Directory containing the generated scripts, target binary, sources
	set(_scripts_dir "${ARDUINO_GENERATE_DIR}/.scripts")
	set(_app_targets_dir "${CMAKE_BINARY_DIR}/.app_targets")
	set(_bin_dir "$<TARGET_PROPERTY:${target},BINARY_DIR>")
	set(_src_dir "$<TARGET_PROPERTY:${target},SOURCE_DIR>")

	# Generate content that will be used later by link/tool scripts
	set(_app_info
		"set(ARDUINO_BUILD_SOURCE_PATH \"${_src_dir}\")\n")
	set(_app_info
		"${_app_info}set(ARDUINO_BUILD_PATH \"${_bin_dir}\")\n")
	set(_app_info
		"${_app_info}set(ARDUINO_BUILD_PROJECT_NAME \"${target}\")\n")
	file(GENERATE OUTPUT "${_app_targets_dir}/${target}.cmake" CONTENT
		"${_app_info}")

	# Some platforms generate source files that needs to be linked with the
	# application target. Currently we do it here, but may later be moved
	# to target_link_arduino_libraries(core)
	find_source_files("${ARDUINO_GENERATE_DIR}/sketch" app_sources RECURSE)
	if (NOT "${app_sources}" EQUAL "")
		target_sources("${target}" PRIVATE "${app_sources}")
		target_link_arduino_libraries("${target}" AUTO_PRIVATE "${app_sources}")
	endif()

	# Add build rules: pre-build, pre-link, post-build, objcopy, size etc.
	set(_build_rule_list
		"PreBuildScript.cmake" PRE_BUILD
			"Executing PRE_LINK hooks for '${target}'"
		"PreLinkScript.cmake" PRE_LINK
			"Executing PRE_LINK hooks for '${target}'"
		"PostBuildScript.cmake" POST_BUILD
			"Executing POST_BUILD hooks for '${target}'"
		"ObjCopyScript.cmake" POST_BUILD
			"Generating upload image for '${target}'"
		"SizeScript.cmake" POST_BUILD
			"Calculating '${target}' size")
	list(LENGTH _build_rule_list _num_rules)
	set(_idx 0)
	while(_idx LESS _num_rules)
		list(GET _build_rule_list "${_idx}" _script)
		math(EXPR _idx "${_idx}+1")
		list(GET _build_rule_list "${_idx}" _type)
		math(EXPR _idx "${_idx}+1")
		list(GET _build_rule_list "${_idx}" _comment)
		math(EXPR _idx "${_idx}+1")
		if (EXISTS "${_scripts_dir}/${_script}")
			add_custom_command(TARGET "${target}" ${_type}
				COMMAND ${CMAKE_COMMAND} ARGS
					-D "ARDUINO_BUILD_PATH=${_bin_dir}"
					-D "ARDUINO_BUILD_SOURCE_PATH=${_src_dir}"
					-D "ARDUINO_BUILD_PROJECT_NAME=${target}"
				-P "${_scripts_dir}/${_script}"
				COMMENT "${_comment}"
				VERBATIM)
		endif()
	endwhile()

	# Add tool commands: upload, upload-network, program, erase-flash,
	# burn-bootloader, debug etc.
	set(_tool_script_list
		"upload" "Uploading" TRUE
		"upload-network" "Remote provisioning" TRUE
		"program" "Programming" TRUE
		"erase-flash" "Erasing flash" FALSE
		"burn-bootloader" "Burning bootloader" FALSE
		"debug" "Debugging" TRUE)
	list(LENGTH _tool_script_list _num_tools)
	set(_idx 0)
	while(_idx LESS _num_tools)
		list(GET _tool_script_list "${_idx}" _tool_target)
		math(EXPR _idx "${_idx}+1")
		set(_script "${_tool_target}.cmake")
		list(GET _tool_script_list "${_idx}" _comment)
		math(EXPR _idx "${_idx}+1")
		list(GET _tool_script_list "${_idx}" _is_target_specific)
		math(EXPR _idx "${_idx}+1")
		if (EXISTS "${_scripts_dir}/${_script}")
			if (NOT TARGET ${_tool_target})
				add_custom_target("${_tool_target}"
					${CMAKE_COMMAND} ARGS
						-D "ARDUINO_BINARY_DIR=${CMAKE_BINARY_DIR}"
						-D "MAKE_TARGET=${_tool_target}"
						-P "${_scripts_dir}/${_script}"
					COMMENT "${_comment}"
					WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
					VERBATIM)
			endif()
			if (NOT _is_target_specific)
				continue()
			endif()
			if (NOT "${ARDUINO_LEGACY_TOOL_TARGETS}")
				continue()
			endif()
			add_custom_target("${_tool_target}-${target}"
				${CMAKE_COMMAND} ARGS
					-D "ARDUINO_BUILD_PATH=${_bin_dir}"
					-D "ARDUINO_BUILD_SOURCE_PATH=${_src_dir}"
					-D "ARDUINO_BUILD_PROJECT_NAME=${target}"
					-D "MAKE_TARGET=${_tool_target}"
					-P "${_scripts_dir}/${_script}"
				COMMENT "${_comment} ${target}"
				VERBATIM)
		endif()
	endwhile()
endfunction()

#==============================================================================
# find_arduino_library(<lib> <return_lib_path> 
#                      [HINTS path1 [path2 ...]]
#                      [PATH_SUFFIXES suffix1 [suffix2 ...]]
#                      [NO_DEFAULT_PATH]
#                      [QUIET]
#                      [EXCLUDE_LIB_NAMES] [EXCLUDE_INCLUDE_NAMES]
#                      [LIBNAME_RESULT <var>])
#
# Search for the given arduino library in the standard and/or hinted paths.
# This function is required only if there is better control needed in searching
# and adding an arduino library explicitly (See 'add_custom_arduino_library').
# Otherwise 'target_link_arduino_libraries'is sufficient for simple usage.
#
# This function returns the path containing the arduino library found and it is
# ensured that the returned library is compatible with the arduino board being 
# built for.
#
# Arguments:
# <lib> [IN]: Name of the arduino library to search. This can be either the
# library name or the include name.
# <return_lib_path> [OUT]: The path containing the library is returned in this 
# variable
#
# Options:
# HINTS: Specify directories to search in addition to the default locations.
# PATH_SUFFIXES: Specify additional subdirectories to check below each
# directory
# location otherwise considered.
# NO_DEFAULT_PATH: If specified, no default locations are added to the search
# QUIET: If specified, an error will not be generated if the library is not
# found
# EXCLUDE_LIB_NAMES: Given library name should not be matched with the name
# of the library found in library.properties
# EXCLUDE_INCLUDE_NAMES: Given library name should not be matched with the
# include file names of the library
# LIBNAME_RESULT: Return the actual name of the library in this variable if
# <lib> is an include name
#
# e.g. find_arduino_library(Wire lib_path)
#
# In the above example, on return of the function, "${lib_path}" contains the
# path containing the 'Wire' library, which can be used to add this library 
# using the 'add_custom_arduino_library' function.
function(find_arduino_library lib return_lib_path)

	set(_flag_options
		NO_DEFAULT_PATH
		QUIET
		EXCLUDE_LIB_NAMES
		EXCLUDE_INCLUDE_NAMES)

	set(_one_arg_options
		LIBNAME_RESULT)

	set(_multi_arg_options
		HINTS
		PATHS)

	cmake_parse_arguments(parsed_args "${_flag_options}" "${_one_arg_options}"
		"${_multi_arg_options}" ${ARGN})

	# List indexed library namespaces which will be used for the search
	set(ard_libs_ns_list)

	# Index libraries from the hinted paths
	set(_hint_paths
		${parsed_args_HINTS}
		${parsed_args_PATHS}
	)
	if (NOT "${_hint_paths}" STREQUAL "")
		IndexArduinoLibraries(ards_libs_custom ${_hint_paths}
			${parsed_args_UNPARSED_ARGUMENTS}
			COMMENT "Indexing Arduino libraries for ${_hint_paths}")
		list(APPEND ard_libs_ns_list ards_libs_custom)
	endif()

	# Add namespaces that contain libraries indexed from default paths
	if (NOT parsed_args_NO_DEFAULT_PATH)

		# Index local libraries if not already done within the scope
		# and add it to the list of library namespaces
		_index_local_libraries(_local_namespace _ign)
		if (NOT _local_namespace STREQUAL "")
			list(APPEND ard_libs_ns_list "${_local_namespace}")
		endif()

		# Add globally indexed libraries namespace
		list(APPEND ard_libs_ns_list ards_libs_global)

	endif()

	# message("Search namespaces: ${ard_libs_ns_list}")

	set(_lib_name)
	if (DEFINED ARDUINO_LIB_${lib}_LIBNAME)
		set(_lib_name "${ARDUINO_LIB_${lib}_LIBNAME}")
	elseif(DEFINED ARDUINO_LIB_${lib}_PATH)
		set(_lib_name "${lib}")
	else()
		_library_search_process("${ard_libs_ns_list}" "${lib}"
			_lib_path _lib_name "${parsed_args_EXCLUDE_LIB_NAMES}"
			"${parsed_args_EXCLUDE_INCLUDE_NAMES}")
		if (_lib_path)
			if (NOT DEFINED ARDUINO_LIB_${_lib_name}_PATH)
				message(STATUS "Found Arduino Library ${_lib_name}: "
					"${_lib_path}")
				set(ARDUINO_LIB_${_lib_name}_PATH "${_lib_path}" CACHE STRING
					"Path found containing the arduino library ${_lib_name}")
			endif()
			if (NOT _lib_name STREQUAL lib)
				set(ARDUINO_LIB_${lib}_LIBNAME "${_lib_name}" CACHE INTERNAL
					"Actual library name of ${lib}")
			endif()
		endif()
	endif()

	# Error message if not found
	if (NOT _lib_name)
		if (NOT ARDUINO_LIB_${_lib_name}_PATH)
			if (NOT parsed_args_QUIET)
				message(SEND_ERROR "Arduino library ${lib} could not be found in "
						"${search_paths}")
			endif()
			set("${return_lib_path}" "${lib}-NOTFOUND" PARENT_SCOPE)
			return()
		endif()
	endif()

	# message("find_arduino_library(\"${lib}\":${ARDUINO_LIB_${lib}_PATH})")
	if (NOT "${parsed_args_LIBNAME_RESULT}" STREQUAL "")
		set("${parsed_args_LIBNAME_RESULT}" "${_lib_name}" PARENT_SCOPE)
	endif()
	set("${return_lib_path}" "${ARDUINO_LIB_${_lib_name}_PATH}" PARENT_SCOPE)

endfunction()

#==============================================================================
# add_custom_arduino_library(<target_name> <lib> [PATH lib_path])
#
# Add a target that builds the arduino library present in the given directory. Adding a
# library using this function is typically not needed. It is sufficient to use 
# target_link_arduino_libraries. However this function may provide better control.
# For example, if it is required to add 2 versions of the same library with different
# compile options, then this function can be handy. A target added using this function
# is linked with other targets using the standard 'target_link_libraries' and not
# target_link_arduino_libraries.
#
# Arguments:
# <target_name> [IN]: Name of the new target to be added
# <lib> [IN]: Name of the arduino library
# [lib_path] [IN]: Optional root directory containing the Arduino library.
# This can be obtained using 'find_arduino_library' or any other means.
#
# e.g. Equivalent of target_link_arduino_libraries(my_app PRIVATE Wire) is as follows:
#     add_custom_arduino_library(my_arduino_wire Wire)
#     target_link_libraries(my_app PRIVATE my_arduino_wire)
#
# In the above example, due to the availability of target name for the added library 
# (my_arduino_wire), user has better control of the library target.
function(add_custom_arduino_library target lib)

	_add_internal_arduino_library("${target}" "${lib}" ${ARGN})

endfunction()

#==============================================================================
# add_custom_arduino_core(<target_name>)
#
# Add a target that builds the arduino core for the arduino board being built for. 
# Adding the core library using this function is typically not needed. It is sufficient
# to use target_link_arduino_libraries to link with 'core' library. However this function
# may provide better control. For example, if it is required to add 2 versions of the 
# core with different compile options, then this function can be handy. A target added
# using this function is linked with other targets using the standard function 
# 'target_link_libraries' which takes target names and not using the function
# 'target_link_arduino_libraries' which takes library names.
#
# Arguments:
# <target_name> [IN]: Name of the new target to be added
#
# e.g. Equivalent of target_link_arduino_libraries(my_app PRIVATE core) is as follows:
#     add_custom_arduino_core(my_arduino_core)
#     target_link_libraries(my_app PRIVATE my_arduino_core)
#
# In the above example, due to the availability of target name for the core library
# (my_arduino_core), user has better control of the target.
function(add_custom_arduino_core target)

	_add_internal_arduino_core("${target}")

endfunction()

#==============================================================================
# Return the Arduino library corresponding to the given target
function(target_get_arduino_lib target ret_var)
	if (NOT TARGET "${target}")
		set("${ret_var}" "" PARENT_SCOPE)
		return()
	endif()
	get_target_property(_lib_type "${target}" TYPE)
	if ("${_lib_type}" STREQUAL "INTERFACE_LIBRARY")
		set("${ret_var}" "" PARENT_SCOPE)
		return()
	endif()
	get_target_property(_ard_lib_name "${target}" ARDUINO_LIB)
	if (NOT _ard_lib_name)
		set("${ret_var}" "" PARENT_SCOPE)
		return()
	endif()
	set("${ret_var}" "${_ard_lib_name}" PARENT_SCOPE)
endfunction()

#==============================================================================
# Implementation functions (Subject to change. DO NOT USE)
#

# Get the arduino libraries that are included by the given target
# or source list
function(_get_auto_link_libs target_name src_list_var ignore_list_var
	override_list_var ret_list_var)

	set(_ret_list)

	target_get_arduino_lib("${target_name}" _target_ard_lib_name)

	set(override_names)
	foreach(override IN LISTS ${override_list_var})
		target_get_arduino_lib("${override}" _ard_lib_name)
		list(APPEND override_names ${_ard_lib_name})
	endforeach()

	if (NOT "${${src_list_var}}" STREQUAL "")
		set(_target_sources "${${src_list_var}}")
	else()
		get_target_property(_lib_type "${target_name}" TYPE)
		if ("${_lib_type}" STREQUAL "INTERFACE_LIBRARY")
			set(_target_sources "")
		else()
			get_target_property(_target_sources "${target_name}" SOURCES)
		endif()
	endif()

	get_target_property(target_source_dir "${target_name}" SOURCE_DIR)

	set(_all_includes)
	foreach(file IN LISTS _target_sources)
		get_filename_component(_file_path "${file}" ABSOLUTE
			BASE_DIR "${target_source_dir}")
		get_source_file_included_headers("${_file_path}" _includes)
		add_configure_dependency("${_file_path}")
		list(APPEND _all_includes ${_includes})
	endforeach()

	if (NOT "${_all_includes}" STREQUAL "")
		list(REMOVE_DUPLICATES _all_includes)
	endif()
	# message("get_source_file_included_headers(${_all_includes}:)")
	foreach(inc IN LISTS _all_includes ITEMS "Arduino")
		list(FIND ${ignore_list_var} "${inc}" _idx)
		# Check if to be ignored
		if (_idx LESS 0)
			if (inc STREQUAL "Arduino")
				set(_lib "core")
			else()
				_map_libs_to_lib_names(inc EXCLUDE_LIB_NAMES QUIET)
				set(_lib "${inc}")
			endif()
			if (_lib STREQUAL "")
				continue()
			endif()
			if ("${_target_ard_lib_name}" STREQUAL "${_lib}")
				# No linking with self
				continue()
			endif()
			list(FIND override_names "${_lib}" _idx)
			if (_idx GREATER_EQUAL 0)
				list(GET ${override_list_var} ${_idx} _cust_lib)
				list(APPEND _ret_list "${_cust_lib}")
			else()
				list(APPEND _ret_list "${_lib}")
			endif()
		endif()
	endforeach()

	if (NOT "${_ret_list}" STREQUAL "")
		list(REMOVE_DUPLICATES _ret_list)
	endif()
	set("${ret_list_var}" "${_ret_list}" PARENT_SCOPE)
endfunction()

# Link the given target with the given list of libraries, creating
# internal targets for the linked libraries as necessary.
function(_link_ard_lib_list target_name lib_list_var link_type
	ignore_list_var override_list_var)

	#message("_link_ard_lib_list \"${target_name}\" \"${${lib_list_var}}\"")

	set(_link_targets)
	foreach(_lib IN LISTS ${lib_list_var})

		# Get a suitable name for the target correspoinding to lib
		string(MAKE_C_IDENTIFIER "${_lib}" _lib_id)

		# If the library name is already a target building an arduino
		# library, use that. Typically used for convenience or for
		# overridden libraries
		target_get_arduino_lib("${_lib}" _ard_lib_name)
		if (_ard_lib_name)
			set(_link_target "${_lib}")
		elseif (TARGET "_arduino_lib_${_lib_id}")
			# Already having the internal library
			set(_link_target "_arduino_lib_${_lib_id}")
		elseif ("${_lib}" STREQUAL "core")
			# library is core, add a library with core sources
			_add_internal_arduino_core(_arduino_lib_core)
			set(_link_target "_arduino_lib_core")
		else()
			# add the library with its sources
			_add_internal_arduino_library("_arduino_lib_${_lib_id}"
				"${_lib}")
			if (NOT TARGET "_arduino_lib_${_lib_id}")
				return()
			endif()
			target_link_arduino_libraries("_arduino_lib_${_lib_id}"
				AUTO_PUBLIC
				IGNORE ${${ignore_list_var}}
				OVERRIDE ${${override_list_var}})
			set(_link_target "_arduino_lib_${_lib_id}")
		endif()

		if (NOT "${_link_target}" STREQUAL "${target_name}")
			list(APPEND _link_targets "${_link_target}")
		endif()
	endforeach()

	# Finally link the target with all the libraries
	# message("target_link_libraries(\"${target_name}\" ${link_type} ${_link_targets})")
	if (_link_targets)
		target_link_libraries("${target_name}" ${link_type}
			${_link_targets})
	endif()

endfunction()

# Used to add internal arduino library
function(_add_internal_arduino_library target lib)

	cmake_parse_arguments(parsed_args "" "PATH" "" ${ARGN})

	set(_lib_path "${parsed_args_PATH}")
	if (NOT _lib_path)
		find_arduino_library("${lib}" _lib_path LIBNAME_RESULT lib)
		if (NOT _lib_path)
			return()
		endif()
	else()
		# TODO Parse the library name from library.properties in the path?
	endif()

	# Index the source files
	find_library_source_files("${_lib_path}" lib_sources)
	find_library_header_files("${_lib_path}" lib_headers)
	get_headers_parent_directories("${lib_headers}" include_dirs)

	# TODO Exclude files that do not belong to the board architecture

	# Add the library and set the include directories
	# message("${target}:${lib_sources}:\n${lib_headers}")
	if (NOT lib_sources)
		# Could have added INTERFACE library, but due to CMake limitation
		# of not able to set a property to INTERFACE targets, we have the
		# following workaround of adding a dummy source file
		configure_file(
			${ARDUINO_TOOLCHAIN_DIR}/Arduino/Templates/DummySource.cpp.in
			${CMAKE_CURRENT_BINARY_DIR}/${target}_dummy.cpp
		)
		set(lib_sources "${CMAKE_CURRENT_BINARY_DIR}/${target}_dummy.cpp")
	endif()

	add_library("${target}" STATIC ${lib_headers} ${lib_sources})
	# message("\"${include_dirs}\"")
	target_include_directories(${target} PUBLIC ${include_dirs})

	# Add ARDUINO_LIB property
	set_target_properties("${target}" PROPERTIES ARDUINO_LIB "${lib}")

endfunction()

# Used to add internal arduino core library
function(_add_internal_arduino_core target)

	## Index the source files
	find_source_files("${ARDUINO_BOARD_BUILD_CORE_PATH}" core_sources RECURSE)
	if (ARDUINO_BOARD_BUILD_VARIANT_PATH)
		find_source_files("${ARDUINO_BOARD_BUILD_VARIANT_PATH}" variant_sources RECURSE)
	else()
		set(variant_sources)
	endif()
	# find_header_files("${ARDUINO_BOARD_BUILD_CORE_PATH}" core_headers)
	# find_header_files("${ARDUINO_BOARD_BUILD_VARIANT_PATH}" variant_headers)

	# On some platforms, files ending with small case .s and .cxx are not taken
	# and cause issues filter this out
	list_filter_exclude_regex(core_sources "(.s|.[cC][xX][xX])$")

	# Add the library and set the include directories
	# message("${target}:${lib_sources}:\n${lib_headers}")
	if ("${core_sources}" STREQUAL "")
		# Could have added INTERFACE library, but due to CMake limitation
		# of not able to set a property to INTERFACE targets, we have the
		# following workaround of adding a dummy source file
		configure_file(
			${ARDUINO_TOOLCHAIN_DIR}/Arduino/Templates/DummySource.cpp.in
			${CMAKE_CURRENT_BINARY_DIR}/${target}_dummy.cpp
		)
		set(core_sources "${CMAKE_CURRENT_BINARY_DIR}/${target}_dummy.cpp")
	endif()

	# Add core sources as an object library
	add_library("${target}_cobjects_" OBJECT
		${core_headers}
		${core_sources})
	target_include_directories("${target}_cobjects_" PRIVATE
		"${ARDUINO_BOARD_BUILD_CORE_PATH}"
		"${ARDUINO_BOARD_BUILD_VARIANT_PATH}")
	_arduino_get_objects("${target}_cobjects_" "${core_sources}" _cobjects_)

	set(_vobjects_)
	if (NOT "${variant_sources}" STREQUAL "")
		add_library("${target}_vobjects_" OBJECT
			${variant_headers}
			${variant_sources})
		target_include_directories("${target}_vobjects_" PRIVATE
			"${ARDUINO_BOARD_BUILD_CORE_PATH}"
			"${ARDUINO_BOARD_BUILD_VARIANT_PATH}")
		_arduino_get_objects("${target}_vobjects_" "${variant_sources}"
			_vobjects_)
	endif()

	add_library("${target}" 
		$<TARGET_OBJECTS:${target}_cobjects_>)
	if (NOT "${_vobjects_}" STREQUAL "")
		add_dependencies("${target}" "${target}_vobjects_")
	endif()
	
	target_include_directories("${target}" INTERFACE
		"${ARDUINO_BOARD_BUILD_CORE_PATH}"
		"${ARDUINO_BOARD_BUILD_VARIANT_PATH}")

	set(_gen_content "
		set(ARDUINO_CORE_OBJECTS \"${_cobjects_}\")
		set(ARDUINO_VARIANT_OBJECTS \"${_vobjects_}\")")
	file(GENERATE OUTPUT "$<TARGET_FILE:${target}>.ard_core_info"
		CONTENT "${_gen_content}")

	# Add ARDUINO_LIB property
	set_target_properties("${target}" PROPERTIES ARDUINO_LIB "core")

endfunction()

# Find the arduino libraries that have been linked with the given
# target
function(_find_linked_arduino_libs target_name ret_list_var)
	get_target_property(_lib_type "${target_name}" TYPE)
	if ("${_lib_type}" STREQUAL "INTERFACE_LIBRARY")
		set(_link_libs)
	else()
		get_target_property(_link_libs "${target_name}" LINK_LIBRARIES)
		if (NOT _link_libs)
			set(_link_libs)
		endif()
	endif()

	get_target_property(_intf_link_libs "${target_name}"
		INTERFACE_LINK_LIBRARIES)
	if (_intf_link_libs)
		list(APPEND _link_libs ${_intf_link_libs})
	endif()

	foreach(_link_lib IN LISTS _link_libs)
		target_get_arduino_lib("${_link_lib}" _ard_lib_name)
		if (_ard_lib_name)
			if (NOT "${_link_lib}" MATCHES "^_arduino_lib_" AND
				NOT "${_link_lib}" STREQUAL "core")
				list(APPEND _ret_list "${_link_lib}")
			endif()
		endif()
	endforeach()

	set("${ret_list_var}" "${_ret_list}" PARENT_SCOPE)
endfunction()

# Search algorithm for Arduino libraries
function(_library_search_process ns_list lib return_path return_lib_name
	is_excl_lib_name is_excl_inc_name)

	# message("Searching for ${lib}...")

	# convert lib to a string that can be used in regular expression match
	string_escape_regex(lib_regex "${lib}")

	# message("lib_regex:${lib_regex}")
	set(matched_lib_priority 3) # Initialize to the lowest lib priority
	set(matched_folder_priority 7) # Initialize to the lowest folder priority
	set(matched_arch_priority 3) # Initialize to the lowest arch priority
	set(matched_lib_path "") # The matched library path
	set(matched_lib_name "") # The matched library name

	foreach(_ns IN LISTS ns_list)
		libraries_get_list("${_ns}" _lib_list)

		foreach(_lib_id IN LISTS _lib_list)

			libraries_get_property("${_ns}" "${_lib_id}" "/name" _lib_name)
			libraries_get_property("${_ns}" "${_lib_id}" "/path" _lib_path)
			libraries_get_property("${_ns}" "${_lib_id}" "/architectures"
				_lib_arch_list)
			libraries_get_property("${_ns}" "${_lib_id}" "/exp_includes"
				_lib_exp_inc_list)
			libraries_get_property("${_ns}" "${_lib_id}" "/imp_includes"
				_lib_imp_inc_list)

			# Check for library name match
			set(lib_priority 0)
			set(_imp_inc_match FALSE)
			if ("${lib}" STREQUAL "${_lib_name}" AND NOT is_excl_lib_name)
				# 'lib' is a library name and not include name
				set(lib_priority 1)
			elseif(NOT is_excl_inc_name)
				# Check for match with the include names
				_find_match_lib_inc_name("${lib}" _lib_exp_inc_list _found)
				if (NOT _found)
					set(_imp_inc_match TRUE)
					_find_match_lib_inc_name("${lib}" _lib_imp_inc_list _found)
				endif()
				if (_found)
					set(lib_priority 2)
				endif()
			endif()

			# message("Match1 ${lib}:${_lib_path}:${lib_priority}:${_imp_inc_match}")
			# Library is not matching with any library or include name
			if (lib_priority EQUAL 0)
				continue()
			endif()

			# Check for folder name match
			get_filename_component(folder_name "${_lib_path}" NAME)
			if ("${folder_name}" STREQUAL "${lib}")
				set(folder_name_priority 1)
			elseif ("${folder_name}" STREQUAL "${lib}-master")
				set(folder_name_priority 2)
			elseif("${folder_name}" MATCHES "^${lib_regex}.*")
				set(folder_name_priority 3)
			elseif("${folder_name}" MATCHES ".*${lib_regex}$")
				set(folder_name_priority 4)
			elseif("${folder_name}" MATCHES ".*${lib_regex}.*")
				set(folder_name_priority 5)
			elseif(_imp_inc_match)
				# For implicit include match, folder should match in order to
				# avoid unnecessary linking during auto linking
				continue()
			else()
				set(folder_name_priority 6)
			endif()

			# message("Match2 ${lib}:${_lib_path}:${folder_name_priority}")

			# Check for architecture match
			string(TOUPPER "${ARDUINO_BOARD_BUILD_ARCH}" board_arch)
			if (NOT "${_lib_arch_list}" STREQUAL "")
				set(arch_match_priority 0) # Match should happen in the loop
				foreach(arch IN LISTS _lib_arch_list)
					string(STRIP "${arch}" arch)
					string(TOUPPER "${arch}" arch)
					if ("${arch}" STREQUAL "${board_arch}")
						set(arch_match_priority 1)
						break()
					elseif("${arch}" STREQUAL "*")
						set(arch_match_priority 2)
					endif()
				endforeach()
				if (arch_match_priority EQUAL 0)
					continue()
				endif()
			else()
				set(arch_match_priority 2) # unspecified arch assumed to match
			endif()

			# message("Folder/Arch match ${lib}:${_lib_path}:"
			#	"${lib_priority}/${matched_lib_priority}:"
			#	"${folder_name_priority}/${matched_folder_priority}:"
			#	"${arch_match_priority}/${matched_arch_priority}")

			# Check for better lib priority
			if (${lib_priority} LESS ${matched_lib_priority})
				set(matched_lib_path "${_lib_path}")
				set(matched_lib_name "${_lib_name}")
				set(matched_lib_priority "${lib_priority}")
				set(matched_folder_priority "${folder_name_priority}")
				set(matched_arch_priority "${arch_match_priority}")
				continue()
			elseif (NOT ${lib_priority} EQUAL ${matched_lib_priority})
				continue()
			endif()

			# Check for better folder name priority
			if (${folder_name_priority} LESS ${matched_folder_priority})
				set(matched_lib_path "${_lib_path}")
				set(matched_lib_name "${_lib_name}")
				set(matched_folder_priority "${folder_name_priority}")
				set(matched_arch_priority "${arch_match_priority}")
				continue()
			elseif (NOT ${folder_name_priority} EQUAL
				${matched_folder_priority})
				continue()
			endif()

			# Check for optimized architecture
			if (${arch_match_priority} LESS ${matched_arch_priority})
				set(matched_lib_path "${_lib_path}")
				set(matched_lib_name "${_lib_name}")
				set(matched_arch_priority "${arch_match_priority}")
				continue()
			elseif (NOT ${arch_match_priority} EQUAL ${matched_arch_priority})
				continue()
			endif()

		endforeach()
	endforeach()

	if (NOT matched_lib_path)
		# message("${lib} Not found!!!")
		set ("${return_path}" "${lib}-NOTFOUND" PARENT_SCOPE)
		return()
	endif()

	# message("${lib} found!!!")
	set ("${return_path}" "${matched_lib_path}" PARENT_SCOPE)
	set ("${return_lib_name}" "${matched_lib_name}" PARENT_SCOPE)

endfunction()

# Index any libraries within the current directory
function(_index_local_libraries return_namespace return_is_indexed)

	set(_local_lib_paths)
	if (EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/libraries" OR
		EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/dependencies")
		list(APPEND _local_lib_paths "${CMAKE_CURRENT_SOURCE_DIR}")
	endif()
	list(APPEND _local_lib_paths ${ARDUINO_LIBRARIES_SEARCH_PATHS_EXTRA})
	properties_get_value(ards_libs_global "lib_search_root_list"
		_global_indexed_paths QUIET) # TODO
	foreach(_path IN LISTS _global_indexed_paths)
		if (NOT "${_local_lib_paths}" STREQUAL "")
			list(REMOVE_ITEM _local_lib_paths "${_path}")
		endif()
	endforeach()
	set("${return_is_indexed}" FALSE PARENT_SCOPE)
	if (NOT "${_local_lib_paths}" STREQUAL "")
		properties_get_value(ards_libs_local "lib_search_root_list"
			_local_indexed_paths QUIET) # TODO
		# message("_local_lib_paths:${_local_lib_paths}")
		# message("_local_indexed_paths:${_local_indexed_paths}")
		if (NOT "${_local_lib_paths}" STREQUAL "${_local_indexed_paths}")
			IndexArduinoLibraries(ards_libs_local ${_local_lib_paths}
				COMMENT "Indexing local Arduino libraries for "
				"${CMAKE_CURRENT_SOURCE_DIR}")
			libraries_set_parent_scope(ards_libs_local)
			set("${return_is_indexed}" TRUE PARENT_SCOPE)
		endif()
		set("${return_namespace}" ards_libs_local PARENT_SCOPE)
	else()
		set("${return_namespace}" "" PARENT_SCOPE)
	endif()
endfunction()

# Find a matching include name for the given lib
function(_find_match_lib_inc_name lib_name inc_list_var return_flag)
	set(_found FALSE)
	foreach(_lib_inc IN LISTS ${inc_list_var})
		string(REGEX MATCH "^(.+)\\.[^.]+$" _match "${_lib_inc}")
		if (NOT "${_match}" STREQUAL "")
			set(_lib_inc "${CMAKE_MATCH_1}")
		endif()
		if ("${lib_name}" STREQUAL "${_lib_inc}")
			set(_found TRUE)
			break()
		endif()
	endforeach()
	set("${return_flag}" "${_found}" PARENT_SCOPE)
endfunction()

# target_link_arduino_libraries API takes library names as well. Here we
# convert the given names in the API to library names using 
# find_arduino_library. This is to ensure that we use the same target name
# for a library regardless of whether it is linked with target name or 
# include name.
function(_map_libs_to_lib_names libs_list_var)
	set(_lib_names_list)
	foreach(_lib IN LISTS "${libs_list_var}")
		if ("${_lib}" STREQUAL "core")
			list(APPEND _lib_names_list "${_lib}")
			continue()
		endif()
		target_get_arduino_lib("${_lib}" _ard_lib_name)
		if (_ard_lib_name)
			list(APPEND _lib_names_list "${_lib}")
		else()
			find_arduino_library("${_lib}" _lib_path
				LIBNAME_RESULT _lib_name ${ARGN})
			if (_lib_path)
				list(APPEND _lib_names_list "${_lib_name}")
			endif()
		endif()
	endforeach()
	set("${libs_list_var}" "${_lib_names_list}" PARENT_SCOPE)
endfunction()

# For CMake versions below 3.9.0, predict the objects path
function(_arduino_get_objects target sources return_objects)
	if (NOT CMAKE_VERSION VERSION_LESS "3.9.0")
		set(_objects "$<TARGET_OBJECTS:${target}>")
	else()
		set(_objects)
		# TODO Assumption
		set(_obj_dir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${target}.dir")
		foreach(_source IN LISTS sources)
			if (NOT "${_source}" MATCHES "\\.[sS]$")
				set(_obj_file "${_obj_dir}/${_source}.o")
			else()
				set(_obj_file "${_obj_dir}/${_source}.obj")
			endif()
			string(REGEX REPLACE "[ ]" "_" _obj_file "${_obj_file}")
			list(APPEND _objects "${_obj_file}")
		endforeach()
	endif()
	set("${return_objects}" "${_objects}" PARENT_SCOPE)
endfunction()
