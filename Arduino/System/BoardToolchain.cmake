# Copyright (c) 2020 Arduino CMake Toolchain

#******************************************************************************
# Setup the compiler toolchain for the selected arduino board (This file has
# a dependency of indexing arduino boards and selecting one of them, see
# BoardsIndex.cmake for details).

# Do not include this recursively
if(_BOARD_TOOLCHAIN_INCLUDED)
	return()
endif()
set(_BOARD_TOOLCHAIN_INCLUDED TRUE)

include(Arduino/Utilities/CommonUtils)
include(Arduino/Utilities/PropertiesReader)
include(Arduino/System/BoardsIndex)

#==============================================================================
# Setup the toolchain for the Arduino board provided in board_id. This function
# is called after calling IndexArduinoBoards() and then passing one of the
# indexed board ID to set up the toolchain. Any system configuration and
# scripts required for the board are generated in the given directory that
# gets used later while setting up target commands and build rules.
#
function (SetupBoardToolchain boards_namespace board_id generate_dir)

	# Allow report_error function to be used
	cmake_parse_arguments(parsed_args "QUIET;REQUIRED"
		"RESULT_VARIABLE" "" ${ARGN})

	if (parsed_args_QUIET)
		list(APPEND _args "QUIET")
	endif()

	if (parsed_args_REQUIRED)
		list(APPEND _args "REQUIRED")
	endif()

	if (DEFINED parsed_args_RESULT_VARIABLE)
		set("${parsed_args_RESULT_VARIABLE}" 0 PARENT_SCOPE)
	endif()

	# Set some initial find root paths
	if (ARDUINO_SKETCHBOOK_PATH)
		list(APPEND ARDUINO_FIND_ROOT_PATH "${ARDUINO_SKETCHBOOK_PATH}")
	endif()

	# Get Platform name, board name, architecture and platform path
	_board_get_platform_property("name" pl_name)
	_board_get_property("name" board_name)
	_board_get_platform_property("architecture" pl_arch)
	string(TOUPPER "${pl_arch}" ARDUINO_BOARD_BUILD_ARCH)
	_board_get_platform_property("/pl_path" ARDUINO_BOARD_RUNTIME_PLATFORM_PATH)

	# Inherit the platform.txt from the referenced platform. This gets
	# overriden later, if the platform provides its own platform.txt.
	_board_get_property("build.core" _prop_value  QUIET)
	_board_get_ref_platform("${_prop_value}" _core_pkg_name _build_core)
	if (_core_pkg_name)
		# Read platform.txt and platform.local.txt of referenced platform into
		# the ard_global namespace. Anything read here could be overridden
		# later while transfering properties from board.txt
		_board_find_ref_platform("${_core_pkg_name}" "${pl_arch}" _ref_pl)
		_board_load_ref_platform_prop(ard_global "${_ref_pl}")
		_board_load_ref_programmers_prop(ard_programmers "${_ref_pl}")
		packages_get_platform_property("${_ref_pl}" "/pl_path"
			ARDUINO_CORE_SPECIFIC_PLATFORM_PATH)
		set(_core_pl_path "${ARDUINO_CORE_SPECIFIC_PLATFORM_PATH}")
		set(platform_txt_optional 1)
	else()
		set(ARDUINO_CORE_SPECIFIC_PLATFORM_PATH)
		set(_core_pl_path "${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}")
		set(platform_txt_optional 0)
	endif()

	# Read platform.txt and platform.local.txt into the ard_global namespace
	# Anything read here could be overridden later while transfering properties
	# from board.txt
	if (EXISTS "${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}/platform.txt" OR
		NOT platform_txt_optional)
		properties_read("${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}/platform.txt"
			ard_global)
	endif()
	if (EXISTS "${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}/platform.local.txt")
		properties_read(
			"${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}/platform.local.txt"
			ard_global)
	endif()
	_board_get_platform_property("/local_path" _local_path)
	if (EXISTS "${_local_path}/platform.local.txt")
		properties_read("${_local_path}/platform.local.txt" ard_global)
	endif()
	if (EXISTS "${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}/programmers.txt")
		properties_read("${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}/programmers.txt"
            ard_programmers)
	endif()

	# Set build.arch
	properties_set_value("ard_global" "build.arch" "${ARDUINO_BOARD_BUILD_ARCH}")

	list(APPEND ARDUINO_FIND_ROOT_PATH "${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}")
	if (ARDUINO_CORE_SPECIFIC_PLATFORM_PATH)
		list(APPEND ARDUINO_FIND_ROOT_PATH "${_core_pl_path}")
	endif()

	# Set runtime.platform.path
	properties_set_value("ard_global" "runtime.platform.path"
		"${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}")

	# Set runtime.hardware.path
	_board_get_platform_property("/hw_path" _prop_value)
	properties_set_value("ard_global" "runtime.hardware.path" "${_prop_value}")

	# Set runtime.ide.path, runtime.ide.version, ide_version and software
	if (ARDUINO_INSTALL_PATH AND
		EXISTS "${ARDUINO_INSTALL_PATH}/lib/version.txt")
		set(_path "${ARDUINO_INSTALL_PATH}")
		file(READ "${ARDUINO_INSTALL_PATH}/lib/version.txt" _version)
                string(STRIP "${_version}" _version)
	else()
		set(_path "${ARDUINO_TOOLCHAIN_DIR}")
		set(_version "${ARDUINO_TOOLCHAIN_VERSION}.0")
	endif()
	string(REPLACE "." ";" _version_comp "${_version}")
	set(_version "")
	set(_b_first TRUE)
	foreach(_comp IN LISTS _version_comp)
		string(LENGTH "${_comp}" _len)
		if(NOT _b_first AND _len EQUAL 1)
			set(_comp "0${_comp}")
		endif()
		set(_version "${_version}${_comp}")
		set(_b_first FALSE)
	endforeach()

	properties_set_value("ard_global" "software" "ARDUINO")
	properties_set_value("ard_global" "runtime.ide.path" "${_path}")
	properties_set_value("ard_global" "runtime.ide.version" "${_version}")
	properties_set_value("ard_global" "ide_version" "${_version}")

	# Set build.core.path and ARDUINO_BOARD_BUILD_CORE_PATH
	set(ARDUINO_BOARD_BUILD_CORE_PATH "${_core_pl_path}/cores/${_build_core}")

	properties_set_value("ard_global" "build.core.path"
		"${ARDUINO_BOARD_BUILD_CORE_PATH}")
	string_escape_quoting(ARDUINO_BOARD_BUILD_CORE_PATH)

	# Set build.variant.path and ARDUINO_BOARD_BUILD_VARIANT_PATH
	_board_get_property("build.variant" _prop_value QUIET DEFAULT "")
	if (_prop_value)
		_board_get_ref_platform("${_prop_value}" _variant_pkg_name _build_variant)
		if (_variant_pkg_name)
			_board_find_ref_platform("${_variant_pkg_name}" "${pl_arch}" _ref_pl)
			packages_get_platform_property("${_ref_pl}" "/pl_path"
				_variant_pl_path)
		else()
			set(_variant_pl_path "${ARDUINO_BOARD_RUNTIME_PLATFORM_PATH}")
		endif()
		set(ARDUINO_BOARD_BUILD_VARIANT_PATH
			"${_variant_pl_path}/variants/${_build_variant}")
	else()
		set(ARDUINO_BOARD_BUILD_VARIANT_PATH)
	endif()

	properties_set_value("ard_global" "build.variant.path"
		"${ARDUINO_BOARD_BUILD_VARIANT_PATH}")
	string_escape_quoting(ARDUINO_BOARD_BUILD_VARIANT_PATH)

	# Set build.system.path
	properties_set_value("ard_global" "build.system.path"
		"${_core_pl_path}/system")

	# Set runtime.os and ARDUINO_BOARD_HOST_NAME
	if (${CMAKE_HOST_APPLE})
		set(ARDUINO_BOARD_HOST_NAME "macosx")
	elseif (${CMAKE_HOST_UNIX})
		set(ARDUINO_BOARD_HOST_NAME "linux")
	elseif (${CMAKE_HOST_WIN32})
		set(ARDUINO_BOARD_HOST_NAME "windows")
	endif()
	properties_set_value("ard_global" "runtime.os" "${ARDUINO_BOARD_HOST_NAME}")

	# Packager of the selected board
	_board_get_platform_property("/pkg_id" pkg_id)
	_board_get_platform_property("/json_idx" json_idx)
	packages_get_property("${pkg_id}" "${json_idx}" "/packager" pkg_name)

	# Find if the tools used are in a referenced platform. If so, load the
	# properties of the referenced platform and transfer the tool's
	# properties from there
	set(_tool_prop_list "upload.tool" "program.tool" "bootloader.tool")
	set(_tool_recipe_regex_list "upload\\.pattern|upload\\.network_pattern"
		"program\\.pattern|erase\\.pattern" "bootloader\\.pattern")
	list(LENGTH _tool_prop_list _tool_prop_len)
	set(last_tool_pkg_name)
	set(_tool_prop_idx 0)
	while(_tool_prop_idx LESS ${_tool_prop_len})
		list(GET _tool_prop_list ${_tool_prop_idx} _tool_prop)
		string(REGEX MATCH "^[^.]+" _action "${_tool_prop}")
		list(GET _tool_recipe_regex_list ${_tool_prop_idx} _tool_recipe_regex)
		math(EXPR _tool_prop_idx "${_tool_prop_idx}+1")
		_board_get_property("${_tool_prop}" _tool_name QUIET DEFAULT "")
		if (NOT _tool_name)
			continue()
		endif()
		string(MAKE_C_IDENTIFIER "${_tool_prop}" _c_tool_prop)
		string(TOUPPER "${_c_tool_prop}" _c_tool_prop)
		_board_get_ref_platform("${_tool_name}" _ref_tool_pkg_name _tool_name)
		set(ARDUINO_BOARD_${_c_tool_prop} "${_tool_name}")
		if (_ref_tool_pkg_name AND
			# If same as _core_pkg_name or pkg_name, no need to trasnfer
			# tool properties, because all their platform properties got
			# transferred already.
			NOT "${_ref_tool_pkg_name}" STREQUAL "${_core_pkg_name}" AND
			NOT "${_ref_tool_pkg_name}" STREQUAL "${pkg_name}")

			if (NOT _ref_tool_pkg_name STREQUAL last_tool_pkg_name)
				_board_find_ref_platform("${_ref_tool_pkg_name}" "${pl_arch}"
					_ref_pl)
				properties_reset(ard_tool_local)
				_board_load_ref_platform_prop(ard_tool_local "${_ref_pl}")
				set(last_tool_pkg_name "${_ref_tool_pkg_name}")
			endif()
			# Transfer the tool properties from the referenced package
			properties_get_list(ard_tool_local
				"^tools\\.${_tool_name}\\.${_action}\\." _prop_name_list)
			foreach(_prop_name IN LISTS _prop_name_list)
				properties_get_value(ard_tool_local "${_prop_name}" _value)
				properties_resolve_value("${_value}" _value ard_tool_local)
				properties_set_value(ard_global "${_prop_name}" "${_value}")
			endforeach()

			# Save to load the tool paths later
			list(APPEND _ref_tool_pkgs "${_ref_tool_pkg_name}")
		endif()
	endwhile()

	# Set the tool paths (runtime.tools.<name>.path) of all the tool
	# dependencies of the current platform as well as the referred platforms
	if (_ref_tool_pkgs)
		list(REMOVE_DUPLICATES _ref_tool_pkgs)
	endif()
	if (_core_pkg_name)
		list(APPEND _ref_tool_pkgs "${_core_pkg_name}")
	endif()
	# To support old platforms, without references, always add arduino tools
	packages_find_platforms(_old_ref_pl PACKAGER "arduino"
		ARCHITECTURE "${pl_arch}" INSTALL_PREFERRED)
	if (_old_ref_pl)
		_board_get_ref_tools_list("arduino")
		_board_set_tool_path_properties()
	endif()
	# message("Finding tools of current packager ${pkg_name}")
	_board_get_tools_list()
	_board_set_tool_path_properties()
	foreach(_packager IN LISTS _ref_tool_pkgs)
		# message("Finding tools of packager ${_packager}")
		_board_get_ref_tools_list("${_packager}")
		_board_set_tool_path_properties()
	endforeach()

	# Transfer properties of the selected board to overwrite any platform
	# properties
	_board_get_property_list(".*" _board_options)
	# message("_board_options:${_board_options}")
	foreach(_option IN LISTS _board_options)
		string(REGEX MATCH "^menu\\.(.*)" match "${_option}")
		if (match)
			# ignore menu properties which is already transferred
			# while indexing the boards
			continue()
		endif()

		# property of the selected board
		_board_get_property("${_option}" _prop_value)
		properties_set_value("ard_global" "${_option}" "${_prop_value}")
	endforeach()

	# before resolving the values, overwrite the host specific properties
	properties_get_list(ard_global ".*\\.${ARDUINO_BOARD_HOST_NAME}$"
		_host_prop_list)
	foreach(_host_prop IN LISTS _host_prop_list)
		properties_get_value(ard_global "${_host_prop}" _prop_value)
		string(REGEX REPLACE "\\.${ARDUINO_BOARD_HOST_NAME}$" "" _prop
			"${_host_prop}")
		properties_set_value(ard_global "${_prop}" "${_prop_value}")
	endforeach()

	# Arduino build has an assumption that there is only a single sketchbook
	# (a single executable) and a single build path. However in CMake, various
	# components (e.g. various libraries and executables) can be built in 
	# different directories, and hence any of the generated files referred in
	# these build patterns can come from different directories in case of
	# CMake build. To arbitrate this, we identify the list of generated
	# files based on the sequence of the execution of these patterns, and
	# set a consistent directory for each of these generated files.

	# First find the generated files from prebuild patterns. These will
	# be used to resolve these files for build patterns later below.
	# Also generate a prebuild script for executing these prebuild commands.
	set(_gen_file_list)
	set(_prebuild_pattern_list
		"recipe\\.hooks\\.prebuild\\.[0-9]+\\.pattern$"
		"recipe\\.hooks\\.sketch\\.prebuild\\.[0-9]+\\.pattern$"
		"recipe\\.hooks\\.libraries\\.prebuild\\.[0-9]+\\.pattern$"
		"recipe\\.hooks\\.core\\.prebuild\\.[0-9]+\\.pattern$")
	_board_find_gen_file_list("" _gen_file_list ${_prebuild_pattern_list})

	# Resolve generated files for build patterns. These will use the generated
	# files from fixed {build.path}, which is generate_dir. This is because
	# these patterns have no idea of the executable target to which they will 
	# be linked with, and most likely there won't be an issue in using the
	# common generated files for them.
	set(_common_replace_list)
	foreach(_gen_file IN LISTS _gen_file_list)
		string(REPLACE "{build.path}" "${generate_dir}" _replace_file
			"${_gen_file}")
		string(REPLACE "{build.project_name}" "${CMAKE_PROJECT_NAME}"
			_replace_file "${_replace_file}")
		string(REPLACE "{build.source.path}" "${CMAKE_SOURCE_DIR}"
			_replace_file "${_replace_file}")
		list(APPEND _common_replace_list "${_replace_file}")
	endforeach()
	_board_replace_gen_file_list("${_gen_file_list}" "${_common_replace_list}"
		"^recipe\\.c\\.o\\.pattern$" "^recipe\\.cpp\\.o\\.pattern$"
		"^recipe\\.S\\.o\\.pattern$" "^recipe\\.ar\\.pattern$")

	# Find additional generated files during link time?. This will be used
	# to preferentially use the generated files either from the app's build
	# directory or the common build directory. Not needed?
	set(_prelink_pattern_list
		"^recipe\\.hooks\\.core\\.postbuild\\.[0-9]+\\.pattern$"
		"^recipe\\.hooks\\.libraries\\.postbuild\\.[0-9]+\\.pattern$"
		"^recipe\\.hooks\\.sketch\\.postbuild\\.[0-9]+\\.pattern$"
		"^recipe\\.hooks\\.postbuild\\.[0-9]+\\.pattern$"
		"^recipe\\.hooks\\.linking\\.prelink\\.[0-9]+\\.pattern$")
	set(_link_pattern "^recipe\\.c\\.combine\\.pattern$")
	set(_postbuild_pattern_list
		"^recipe\\.hooks\\.linking\\.postlink\\.[0-9]+\\.pattern$")
	set(_objcopy_pattern_list
		"^recipe\\.hooks\\.objcopy\\.preobjcopy\\.[0-9]+\\.pattern$"
		"^recipe\\.objcopy\\..*\\.pattern$"
		"^recipe\\.hooks\\.objcopy\\.postobjcopy\\.[0-9]+\\.pattern$")
	#_board_find_gen_file_list("${_gen_file_list}" _gen_file_list
	#	${_prelink_pattern_list} ${_link_pattern} ${_postbuild_pattern_list}
	#	${_objcopy_pattern_list})

	# Find the generated core archive file name
	_board_find_gen_file_list("" _core_gen_list "recipe\\.ar\\.pattern")
	list(LENGTH _core_gen_list _num_core_gen_files)
	set(_search_pattern "${_core_gen_list}")
	if (_num_core_gen_files GREATER 1)
		set(_search_pattern "")
		foreach(_core_gen_file IN LISTS _core_gen_list)
			if (_core_gen_file MATCHES "\\.a$")
				set(_search_pattern "${_core_gen_file}")
			endif()
		endforeach()
	endif()
	_board_replace_gen_file_list("${_search_pattern}" "{archive_file_path}"
		"recipe\\.ar\\.pattern"
		${_prelink_pattern_list} ${_link_pattern} ${_postbuild_pattern_list})

	# Find the core generated object files
	_board_find_core_obj_list(_core_obj_files)

	# message("\n\nAll properties in global before resolve")
	# properties_print_all(ard_global)
	# Resolve all the known variables so far. Remaining will be resolved later
	properties_resolve_all_values(ard_global)

	# message("\n\nAll properties in global")
	# properties_print_all(ard_global)

	# Add definitions for menu options
	set(ARDUINO_SEL_MENU_SET_LIST)
	foreach(_menu_opt_id IN LISTS ARDUINO_SEL_MENU_OPT_ID_LIST)
		string_append(ARDUINO_SEL_MENU_SET_LIST
			"set(${_menu_opt_id} TRUE)\nadd_definitions(-D${_menu_opt_id})\n"
		)
	endforeach()

	# CMAKE_C_COMPILER
	_board_resolve_build_rule("recipe.c.o.pattern" _build_cmd
		_build_string)
	set(CMAKE_C_COMPILER "${_build_cmd}")
	set(CMAKE_C_COMPILE_OBJECT "<CMAKE_C_COMPILER> ${_build_string}")
	string_escape_quoting(CMAKE_C_COMPILER)
	string_escape_quoting(CMAKE_C_COMPILE_OBJECT)

	# CMAKE_CXX_COMPILER
	_board_resolve_build_rule("recipe.cpp.o.pattern" _build_cmd
		_build_string)
	set(CMAKE_CXX_COMPILER "${_build_cmd}")
	set(CMAKE_CXX_COMPILE_OBJECT "<CMAKE_CXX_COMPILER> ${_build_string}")
	string_escape_quoting(CMAKE_CXX_COMPILER)
	string_escape_quoting(CMAKE_CXX_COMPILE_OBJECT)

	# CMAKE_ASM_COMPILER
	_board_resolve_build_rule("recipe.S.o.pattern" _build_cmd
		_build_string)
	if (_build_cmd) # ASM pattern may not be there?
		set(CMAKE_ASM_COMPILER "${_build_cmd}")
		set(CMAKE_ASM_COMPILE_OBJECT "<CMAKE_ASM_COMPILER> ${_build_string}")
		string_escape_quoting(CMAKE_ASM_COMPILER)
		string_escape_quoting(CMAKE_ASM_COMPILE_OBJECT)
	endif()

	# CMAKE_C_LINK_EXECUTABLE and CMAKE_CXX_LINK_EXECUTABLE
	_board_resolve_build_rule("recipe.c.combine.pattern" _link_cmd
		_link_pattern)
	if (CMAKE_HOST_WIN32)
		set(_c "\"")
	else()
		set(_c "'")
	endif()
	set(_scripts_dir "${generate_dir}/.scripts")
	foreach(lang IN ITEMS C CXX)
		set(CMAKE_${lang}_LINK_EXECUTABLE "<CMAKE_COMMAND>")
		string_append(CMAKE_${lang}_LINK_EXECUTABLE
			" -D ARDUINO_LINK_COMMAND=\"${_link_cmd}\""
			" -D ARG_TARGET_NAME=<TARGET_NAME>"
			" -D ARG_TARGET=<TARGET> "
			" -D ${_c}ARG_LINK_FLAGS=<FLAGS> <CMAKE_${lang}_LINK_FLAGS> "
				"<LINK_FLAGS>${_c}"
			" -D ${_c}ARG_OBJECTS=<OBJECTS>${_c}"
			" -D ${_c}ARG_LINK_LIBRARIES=<LINK_LIBRARIES>${_c}")
		string_escape_quoting(CMAKE_${lang}_LINK_EXECUTABLE)
	endforeach()

	# CMAKE_C_CREATE_STATIC_LIBRARY
	_board_resolve_build_rule("recipe.ar.pattern" _build_cmd
		_build_string)
	set(CMAKE_AR "${_build_cmd}")
	set(CMAKE_C_CREATE_STATIC_LIBRARY "<CMAKE_AR> ${_build_string}")
	string_escape_quoting(CMAKE_AR)
	string_escape_quoting(CMAKE_C_CREATE_STATIC_LIBRARY)

	# CMAKE_CXX_CREATE_STATIC_LIBRARY
	set(CMAKE_CXX_CREATE_STATIC_LIBRARY "<CMAKE_AR> ${_build_string}")
	string_escape_quoting(CMAKE_CXX_CREATE_STATIC_LIBRARY)

	if (ARDUINO_INSTALL_PATH)
		list(APPEND ARDUINO_FIND_ROOT_PATH "${ARDUINO_INSTALL_PATH}")
	endif()

	_board_find_system_program_path()
	list(APPEND ARDUINO_SYSTEM_PROGRAM_PATH "/bin")
	list(REMOVE_DUPLICATES ARDUINO_SYSTEM_PROGRAM_PATH)

	string(TOUPPER "${_version}" CMAKE_SYSTEM_VERSION)

	_board_get_property("/short_id" _short_id)
	string(TOUPPER "${_short_id}" _default_build_board)
	properties_get_value(ard_global "build.board" ARDUINO_BOARD
		DEFAULT "${_default_build_board}")

	# Generate scripts for pre-link, link, post-build and objcopy
	_board_gen_target_recipe_script("${_scripts_dir}/PreBuildScript.cmake"
		${_prebuild_pattern_list})
	_board_gen_target_recipe_script("${_scripts_dir}/PreLinkScript.cmake"
		${_prelink_pattern_list})
	_board_gen_target_recipe_script("${_scripts_dir}/PostBuildScript.cmake"
		${_postbuild_pattern_list})
	_board_gen_target_recipe_script("${_scripts_dir}/ObjCopyScript.cmake"
		${_objcopy_pattern_list})
	_board_gen_target_link_script("${_scripts_dir}/LinkScript.cmake"
		"${_gen_file_list}" "${_core_obj_files}" "${_link_cmd}"
		"${_link_pattern}")

	# Generate cmake scripts for size calculation
	_board_gen_target_size_script("${_scripts_dir}/SizeScript.cmake")

	# Replace {serial.port} in upload.network_pattern with {network.ip}
	# to fix the semantics of the upload.network_pattern
	_board_fix_nw_pattern_semantics(ard_global)

	# Generate cmake scripts for upload, upload-network, program, erase,
	# burn-bootloader, debug etc.
	set(_tool_script_list
		"upload.tool" "upload.pattern" upload.cmake TRUE
		"upload.tool" "upload.network_pattern" upload-network.cmake TRUE
		"program.tool" "program.pattern" program.cmake TRUE
		"program.tool" "erase.pattern" erase-flash.cmake FALSE
		"bootloader.tool" "bootloader.pattern" burn-bootloader.cmake FALSE
		"debug.tool" "debug.pattern" debug.cmake TRUE)
	list(LENGTH _tool_script_list _num_tools)
	set(_idx 0)
	while(_idx LESS _num_tools)
		list(GET _tool_script_list "${_idx}" _tool_var)
		math(EXPR _idx "${_idx}+1")
		list(GET _tool_script_list "${_idx}" _pattern_name)
		math(EXPR _idx "${_idx}+1")
		list(GET _tool_script_list "${_idx}" _script)
		math(EXPR _idx "${_idx}+1")
		list(GET _tool_script_list "${_idx}" _is_target_specific)
		math(EXPR _idx "${_idx}+1")
		_board_gen_target_tool_script(ard_global "${_tool_var}"
			"${_scripts_dir}/${_script}" ${_pattern_name})
	endwhile()

	# Execute the prebuild script for the project directory, so that the
	# try_compile can depend on the generataed files from these
	if (EXISTS "${_scripts_dir}/PreBuildScript.cmake")
		execute_process(COMMAND ${CMAKE_COMMAND}
			-D "ARDUINO_BUILD_PATH=${generate_dir}"
			-D "ARDUINO_BUILD_PROJECT_NAME=${CMAKE_PROJECT_NAME}"
			-D "ARDUINO_BUILD_SOURCE_PATH=${CMAKE_SOURCE_DIR}"
			-P "${_scripts_dir}/PreBuildScript.cmake")
	endif()

	# Set some more standard and useful CMake toolchain variables that are not set
	# in SetupBoardToolchain
	set(CMAKE_SYSTEM_PROCESSOR "${ARDUINO_BOARD_BUILD_ARCH}")
	set(ARDUINO "${CMAKE_SYSTEM_VERSION}")
	set("ARDUINO_ARCH_${CMAKE_SYSTEM_PROCESSOR}" TRUE)
	SET("ARDUINO_${ARDUINO_BOARD}" TRUE)
	string_escape_quoting(ARDUINO_BOARD_RUNTIME_PLATFORM_PATH)

	# Set ARDUINO_BOARD_IDENTIFIER
	set(ARDUINO_BOARD_IDENTIFIER "${_short_id}")
	set(ARDUINO_BOARD_NAME "${board_name}")
	set(ARDUINO_GENERATE_DIR "${generate_dir}")

	set(templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Arduino/Templates")
	configure_file(
		"${templates_dir}/ArduinoSystem.cmake.in"
		"${generate_dir}/ArduinoSystem.cmake" @ONLY
	)

endfunction()

#==============================================================================
# Implementation functions (Subject to change. DO NOT USE)
#

# Return property of the currently selected board
function (_board_get_property prop return_value)
	boards_get_property("${boards_namespace}" "${board_id}"
		${prop} _return_value ${ARGN})
	set("${return_value}" "${_return_value}" PARENT_SCOPE)
endfunction()

# Return property of the platform of the currently selected board
function (_board_get_platform_property prop return_value)
	boards_get_platform_property("${boards_namespace}"
		"${board_id}" ${prop} _return_value ${ARGN})
	set("${return_value}" "${_return_value}" PARENT_SCOPE)
endfunction()

# Return property list of the currently selected board
function (_board_get_property_list pattern return_list)
	boards_get_property_list("${boards_namespace}"
		"${board_id}" ${pattern} _return_list)
	set("${return_list}" "${_return_list}" PARENT_SCOPE)
endfunction()

# Return property of the platform of the currently selected board
function (_board_get_packager_property prop return_value)
	boards_get_packager_property("${boards_namespace}"
		"${board_id}" ${prop} _return_value ${ARGN})
	set("${return_value}" "${_return_value}" PARENT_SCOPE)
endfunction()

# Used by _board_gen_target_tool_script to expand some tool related variables
function(_board_resolve_tool_properties namespace tool tool_string return_string)

	properties_get_list("${namespace}" "^tools\\.${tool}\\." _tool_properties)
	properties_reset(ard_local)
	foreach(_prop IN LISTS _tool_properties)
		properties_get_value("${namespace}" "${_prop}" _value)
		string_regex_replace_start("tools\\.${tool}\\." "" _local_prop
			"${_prop}")
		if ("${_local_prop}" MATCHES "^([^.]+)\\.verbose" OR
			"${_local_prop}" MATCHES "^([^.]+)\\.verify")
			# These will be resolved later hrough user provided values
			continue()
		endif()
		properties_set_value(ard_local "${_local_prop}" "${_value}")
	endforeach()

	properties_resolve_value("${tool_string}" _value "ard_local")
	set("${return_string}" "${_value}" PARENT_SCOPE)

endfunction()

# Used by _board_gen_target_tool_script to expand some tool related variables
function(_board_resolve_programmer_properties prog_prefix string return_string)

	properties_get_list(ard_programmers "^${prog_prefix}\\."
		_prog_properties)
	properties_reset(ard_local)
	foreach(_prop IN LISTS _prog_properties)
		properties_get_value(ard_programmers "${_prop}" _value)
		string_regex_replace_start("${prog_prefix}\\." "" _local_prop
			"${_prop}")
		if ("${_local_prop}" MATCHES "^([^.]+)\\.verbose" OR
			"${_local_prop}" MATCHES "^([^.]+)\\.verify")
			# These will be resolved later hrough user provided values
			continue()
		endif()
		properties_set_value(ard_local "${_local_prop}" "${_value}")
	endforeach()

	properties_resolve_value("${string}" _value "ard_local")
	set("${return_string}" "${_value}" PARENT_SCOPE)

endfunction()

# Used by SetupBoardToolchain to expand the command line for the compilers
# (build rules)
function(_board_resolve_build_rule rule return_cmd return_string)

	properties_get_value(ard_global "${rule}" rule_string QUIET)
	if (NOT rule_string)
		set("${return_cmd}" "" PARENT_SCOPE)
		set("${return_string}" "" PARENT_SCOPE)
		return()
	endif()
	string_regex_replace_start("(\"[^\"]+\"|[^ ]+)" "" _rule_string
		"${rule_string}")
	set(_rule_cmd "${CMAKE_MATCH_1}")
	string(REGEX REPLACE "^\"([^\"]+)\"$" "\\1" _rule_cmd "${_rule_cmd}")
	get_filename_component(_path "${_rule_cmd}" DIRECTORY)
	get_filename_component(_name "${_rule_cmd}" NAME)
	find_program(_resolve_program "${_name}" PATHS "${_path}" NO_DEFAULT_PATH
		NO_CMAKE_FIND_ROOT_PATH)
	if (_resolve_program)
		set(_rule_cmd "${_resolve_program}")
	endif()
	unset(_resolve_program CACHE)

	# message("_rule_cmd:${_rule_cmd}")
	# message("_rule_string:${_rule_string}")

	# Various known archive file pattern
	set(archive_file_patterns
		"{archive_file_path}"
		"{build\\.path}/{archive_file}"
		"{build\\.path}/arduino\\.ar"
		"{build\\.path}/libcore\\.a")

	if (rule STREQUAL "recipe.c.o.pattern" OR
		rule STREQUAL "recipe.cpp.o.pattern" OR
		rule STREQUAL "recipe.S.o.pattern")

		# {includes}
		if (CMAKE_VERSION VERSION_LESS 3.4.0)
			string(REPLACE "{includes}" "<DEFINES> <FLAGS>"
				_rule_string "${_rule_string}")
		else()
			string(REPLACE "{includes}" "<DEFINES> <INCLUDES> <FLAGS>"
				_rule_string "${_rule_string}")
		endif()

		# {source_file}
		string(REGEX REPLACE "\"{source_file}\"|{source_file}" "<SOURCE>" 
			_rule_string "${_rule_string}")
	
		# {object_file}
		string(REGEX REPLACE "\"{object_file}\"|{object_file}" "<OBJECT>"
			_rule_string "${_rule_string}")

	elseif(rule STREQUAL "recipe.ar.pattern")

		# {object_file}
		string(REGEX REPLACE "\"{object_file}\"|{object_file}"
			"<LINK_FLAGS> <OBJECTS>" _rule_string "${_rule_string}")

		# {archive_file_path}
		foreach(ar_pattern IN LISTS archive_file_patterns)
			string(REGEX REPLACE "\"${ar_pattern}\"|${ar_pattern}" "<TARGET>"
				_rule_string "${_rule_string}")
		endforeach()	

	else() # combine pattern

		# <TARGET>
		STRING(REGEX REPLACE "\"{build.path}/{build.project_name}\\.elf\""
			"<TARGET>" _rule_string "${_rule_string}")
		STRING(REGEX REPLACE "{build.path}/{build.project_name}\\.elf"
			"<TARGET>" _rule_string "${_rule_string}")

		# {object_files}
		string(REPLACE "{object_files}" "<OBJECTS> <LINK_LIBRARIES>"
			_rule_string "${_rule_string}")
	endif()

	# {archive_file_path}
	foreach(ar_pattern IN LISTS archive_file_patterns)
		string(REGEX REPLACE "\"${ar_pattern}\"|${ar_pattern}"
			"{archive_file_path}" _rule_string "${_rule_string}")
	endforeach()

	# {build.path}
	if (NOT rule STREQUAL "recipe.c.combine.pattern")
		string(REPLACE "{build.source.path}" "${CMAKE_SOURCE_DIR}"
			_rule_string "${_rule_string}")
		string(REPLACE "{build.path}" "${generate_dir}"
			_rule_string "${_rule_string}")
		string(REPLACE "{build.project_name}" "${CMAKE_PROJECT_NAME}"
			_rule_string "${_rule_string}")
	endif()

	# message("Resolved _rule_string:${_rule_string}")

	# message("Before excaping _rule_string: ${_rule_string}")
	_board_resolve_arduino_quoting("${_rule_string}" _rule_string)
	# message("After excaping _rule_string: ${_rule_string}")

	# message("Final _rule_string:${_rule_string}")

	set("${return_cmd}" "${_rule_cmd}" PARENT_SCOPE)
	set("${return_string}" "${_rule_string}" PARENT_SCOPE)

endfunction()

# Escape certain quotes for the CMake to function correctly in the
# presence of those quote characters
function(_board_resolve_arduino_quoting str return_str)

	string(LENGTH "${str}" _str_len)
	if (${_str_len} EQUAL 0)
		set("${return_str}" "" PARENT_SCOPE)
		return()
	endif()

	set(_state " ")
	set(_result_str "")
	set(_curr_arg "")
	set(_quote_needed 0)
	set(_space_chars "[ \t\r\n]")

	set(_idx 0)
	string(SUBSTRING "${str}" ${_idx} 1 _str_chr)

	while(TRUE)
		math(EXPR _idx "${_idx} + 1")
		string(SUBSTRING "${str}" ${_idx} 1 _nxt_chr)

		if ("${_state}" STREQUAL "\"") # Explicit quoted
			if ((_str_chr STREQUAL "\"" OR
				_str_chr STREQUAL "'") AND
				(_nxt_chr MATCHES "${_space_chars}" OR _nxt_chr STREQUAL ""))
				set(_state " ")
				if(_quote_needed)
					string_append(_result_str "\"${_curr_arg}\"")
				else()
					string_append(_result_str "${_curr_arg}")
				endif()
				set(_curr_arg)
				set(_quote_needed 0)
			elseif(_str_chr STREQUAL "\"")
				string_append(_curr_arg "\\\"")
				set(_quote_needed 1)
			elseif(_str_chr STREQUAL "\\")
				string_append(_curr_arg "\\\\")
				set(_quote_needed 1)
			elseif(_str_chr MATCHES "${_space_chars}")
				string_append(_curr_arg "${_str_chr}")
				set(_quote_needed 1)
			elseif(_str_chr MATCHES "[][()'`|;*?&{}]")
				string_append(_curr_arg "${_str_chr}")
				set(_quote_needed 1)
			else()
				string_append(_curr_arg "${_str_chr}")
			endif()
		elseif("${_state}" STREQUAL " ") # State after space
			if(_str_chr STREQUAL "\"" OR
				_str_chr STREQUAL "'")
				set(_state "\"")
			elseif(_str_chr MATCHES "${_space_chars}")
				string_append(_result_str "${_str_chr}")
			else()
				set(_state "")
				string_append(_curr_arg "${_str_chr}")
			endif()
		else() # Unquoted argument
			if(_str_chr STREQUAL "\"")
				string_append(_curr_arg "\\\"")
				set(_quote_needed 1)
			elseif(_str_chr STREQUAL "\\")
				string_append(_curr_arg "\\\\")
				set(_quote_needed 1)
			elseif(_str_chr STREQUAL "'")
				string_append(_curr_arg "${_str_chr}")
                set(_quote_needed 1)
			elseif(_str_chr MATCHES "${_space_chars}")
				set(_state " ")
				if(_quote_needed)
					string_append(_result_str "\"${_curr_arg}\"")
				else()
					string_append(_result_str "${_curr_arg}")
				endif()
				set(_curr_arg)
				set(_quote_needed 0)
				string_append(_result_str "${_str_chr}")
			elseif(_str_chr MATCHES "[][()'`|;*?&]")
				string_append(_curr_arg "${_str_chr}")
				set(_quote_needed 1)
			else()
				string_append(_curr_arg "${_str_chr}")
			endif()
		endif()

		if (NOT _idx LESS _str_len)
			if (_curr_arg)
				if(_quote_needed)
					string_append(_result_str "\"${_curr_arg}\"")
				else()
					string_append(_result_str "${_curr_arg}")
				endif()
			endif()
			break()
		endif()

		set(_str_chr "${_nxt_chr}")
	endwhile()

	set("${return_str}" "${_result_str}" PARENT_SCOPE)

endfunction()

# Function to find all the system program paths
function (_board_find_system_program_path)

	set(_rule_name_regex_list "^recipe\\..*\\.pattern$"
		"^tools\\..*\\.network_pattern$" "^tools\\..*\\.pattern$")
	set(ARDUINO_SYSTEM_PROGRAM_PATH)
	foreach(_rule_name_regex IN LISTS _rule_name_regex_list)
		properties_get_list(ard_global "${_rule_name_regex}"
			_rule_name_list)
		foreach (_rule_name IN LISTS _rule_name_list)
			properties_get_value(ard_global "${_rule_name}"
				_rule_string)
			if (NOT _rule_string)
				continue()
			endif()

			string_regex_replace_start("(\"[^\"]+\"|[^ ]+)" "" _match
				"${_rule_string}")
			set(_rule_cmd "${CMAKE_MATCH_1}")
			string(REGEX REPLACE "^\"([^\"]+)\"$" "\\1" _rule_cmd
				"${_rule_cmd}")
			get_filename_component(_rule_cmd_path "${_rule_cmd}" DIRECTORY)
			# message("_rule_cmd_path(${_rule_name}):${_rule_cmd_path}")
			if (NOT _rule_cmd_path)
				continue()
			endif()

			# Check if this command is in one of the find root paths, based on
			# which set the system program path (suffixes used by find_program)
			string(SUBSTRING "${_rule_cmd_path}" 0 1 _first_rule_char)
			foreach(_root_path IN LISTS ARDUINO_FIND_ROOT_PATH)
				string(SUBSTRING "${_root_path}" 0 1 _first_rp_char)
				if(NOT _first_rule_char STREQUAL _first_rp_char)
					continue()
				endif()
				file(RELATIVE_PATH _rel_path "${_root_path}" "${_rule_cmd_path}")
				string(REGEX MATCH "^\\.\\.\\/" _match "${_rel_path}")
				if (NOT _match)
					# message("_rel_path:${_rel_path}")
					list(APPEND ARDUINO_SYSTEM_PROGRAM_PATH "/${_rel_path}")
					break()
				endif()
			endforeach()

		endforeach()
	endforeach()

	set(ARDUINO_SYSTEM_PROGRAM_PATH "${ARDUINO_SYSTEM_PROGRAM_PATH}"
		PARENT_SCOPE)

endfunction()

# Function to generate a cmake script that calculates the size of the compiled
# arduino binary
function (_board_gen_target_size_script out_file)

	properties_get_value(ard_global "recipe.size.pattern"
		RECIPE_SIZE_PATTERN QUIET DEFAULT "")
	if (NOT RECIPE_SIZE_PATTERN)
		return()
	endif()
	string_escape_quoting(RECIPE_SIZE_PATTERN)

	properties_get_list(ard_global "^recipe\\.size\\.regex" _size_regex_name_list)
	list(LENGTH _size_regex_name_list SIZE_REGEX_COUNT)

	foreach (size_regex_name IN LISTS _size_regex_name_list)

		properties_get_value(ard_global "${size_regex_name}" _size_regex)
		if (NOT _size_regex)
			continue()
		endif()
		string(REGEX MATCH "^recipe\\.size\\.regex\\.?(.*)" _match
			"${size_regex_name}")
		set(_size_name "${CMAKE_MATCH_1}")

		if(_size_name STREQUAL "")
			set(_size_name "program")
			properties_get_value(ard_global "upload.maximum_size" _maximum_size
				DEFAULT 0)
		else()
			properties_get_value(ard_global "upload.maximum_${_size_name}_size"
				_maximum_size DEFAULT 0)
		endif()

		# Filter out non-captured expression from regex which is not supported
		# Instead of that calculate the sub expression match index
		string(REGEX MATCHALL "\\\\.|\\(.." _match_list "${_size_regex}")
		set(_size_match_index 1)
		set(_idx 1)
		foreach(_match IN LISTS _match_list)
			if (_match MATCHES "^\\\\.$")
				continue()
			endif()

			if (NOT _match STREQUAL "^(?:$")
				set(_size_match_index ${_idx})
			endif()

			math(EXPR _idx "${_idx} + 1")
		endforeach()
		string(REGEX REPLACE "\\(\\?:" "(" _size_regex "${_size_regex}")
		string(REGEX REPLACE "\\|\\)" ")" _size_regex "${_size_regex}")

		# Excape certain characters suitable for cmake script generation
		# message("_size_regex:${_size_regex}")
		string(REGEX REPLACE "\\\\s" "[ \t]" _size_regex "${_size_regex}")
		# message("_size_regex:${_size_regex}")

		string(REGEX REPLACE "\\\\|\\\$|\"" "\\\\\\0" _size_regex
			"${_size_regex}")

		list(APPEND SIZE_REGEX_LIST "${_size_regex}")
		list(APPEND SIZE_NAME_LIST "${_size_name}")
		list(APPEND MAXIMUM_SIZE_LIST "${_maximum_size}")
		list(APPEND SIZE_MATCH_IDX_LIST "${_size_match_index}")

	endforeach()

	if (${SIZE_REGEX_COUNT} GREATER 0)
		set(templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Arduino/Templates")
		configure_file("${templates_dir}/Scripts/SizeScript.cmake.in"
			"${out_file}"
			@ONLY)
	endif()

endfunction()

# Generate the script for one or more build hooks and other build rules that
# can be executed (using cmake), by providing target specific options like the
# ARDUINO_BUILD_PATH, ARDUINO_BUILD_PROJECT_NAME and ARDUINO_BUILD_SOURCE_PATH
function(_board_gen_target_recipe_script out_file)

	set(ARDUINO_PATTERN_NAMES)
	set(ARDUINO_PATTERN_CMDLINE_LIST)
	foreach(_pattern_name_regex IN LISTS ARGN)
		properties_get_list(ard_global "${_pattern_name_regex}"
			_pattern_name_list)
		foreach(_pattern_name IN LISTS _pattern_name_list)
			properties_get_value(ard_global "${_pattern_name}" _pattern)
			if ("${_pattern}" STREQUAL "")
				continue()
			endif()
			_board_resolve_arduino_quoting("${_pattern}" _pattern)
			string_escape_quoting(_pattern)
			set(_pattern_name_str "${_pattern_name}")
			string(REGEX MATCH "^recipe\\.(.+)\\.pattern$" _match
				"${_pattern_name_str}")
			if (_match)
				set(_pattern_name_str "${CMAKE_MATCH_1}")
			endif()
			string_escape_quoting(_pattern_name_str)
			string_append(ARDUINO_PATTERN_NAMES "\t\"${_pattern_name_str}\"\n")
			string_append(ARDUINO_PATTERN_CMDLINE_LIST "\t\"${_pattern}\"\n")
		endforeach()
	endforeach()
	if (NOT "${ARDUINO_PATTERN_NAMES}" STREQUAL "")
		set(templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Arduino/Templates")
		configure_file("${templates_dir}/Scripts/BuildRuleScript.cmake.in"
			"${out_file}" @ONLY)
	endif()

endfunction()

# Function to generate a cmake script for linking the executable target. This
# script can be executed by providing target link arguments like 
# ARDUINO_LINK_COMMAND, ARG_TARGET, ARG_TARGET_BASE, ARG_OBJECTS,
# ARG_LINK_LIBRARIES and ARG_LINK_FLAGS
function (_board_gen_target_link_script out_file gen_files core_obj_files
	link_cmd link_pattern)

	string_escape_quoting(gen_files)
	string_escape_quoting(core_obj_files)
	string_escape_quoting(link_cmd)
	string_escape_quoting(link_pattern)

	set(templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Arduino/Templates")
	configure_file("${templates_dir}/Scripts/LinkScript.cmake.in"
		"${out_file}" @ONLY)

endfunction()

# Generate the CMake script for one or more tools that provide a specific
# action like upload. Target specific options like ARDUINO_BUILD_PATH,
# ARDUINO_BUILD_PROJECT_NAME and ARDUINO_BUILD_SOURCE_PATH need to be provided
# to the script. If the tool requires more options, then they are provided
# either through ARDUINO_[<tool>_]<action>_<option> cache variable or through
# the environment variable <option>, when invoking the script.
function(_board_gen_target_tool_script namespace tool_var out_file
	_pattern_name)

	# Get the tool(s) used for the function
	set(_tool_list)
	set(_tool_prog_list)
	set(_def_tool "")
	string(REGEX MATCH "^([^.]+)" _match "${_pattern_name}")
	set(_action "${CMAKE_MATCH_1}")
	string(TOUPPER "${_action}" _action_var)

	# Set the default programmer
	if (DEFINED "ARDUINO_${_action_var}_PROGRAMMER")
		set(ARDUINO_${_action_var}_PROGRAMMER
			"${ARDUINO_${_action_var}_PROGRAMMER}" CACHE
			STRING "Default programmer for ${_action}")
	endif()

	if (DEFINED "ARDUINO_PROGRAMMER")
		set(ARDUINO_PROGRAMMER "${ARDUINO_PROGRAMMER}" CACHE STRING
			"Default programmer")
	endif()

	properties_get_value(ard_global "${tool_var}" _tool QUIET DEFAULT "")
	if (_tool)
		_board_get_ref_platform("${_tool}" _ref_tool_pkg_name _tool)
		list(APPEND _tool_list "${_tool}")
		list(APPEND _tool_prog_list ".")
		set(_def_tool "${_tool}")
	endif()

	properties_get_list(ard_programmers "^[^.]+\\.name$" _prog_name_prop_list)
	foreach(_prog_name_prop IN LISTS _prog_name_prop_list)
		string(REGEX MATCH "^([^.]+)\\.name$" _match "${_prog_name_prop}")
		set(_prog_prefix "${CMAKE_MATCH_1}")
		properties_get_value(ard_programmers "${_prog_prefix}.${tool_var}"
			_prog_tool QUIET DEFAULT "${_tool}")
		if (_prog_tool)
			list(APPEND _tool_list "${_prog_tool}")
			list(APPEND _tool_prog_list "${_prog_prefix}")
		endif()
	endforeach()	

	set(ARDUINO_TOOL_NAMES)
	set(ARDUINO_TOOL_CMDLINE_LIST)
	set(ARDUINO_TOOL_ALTARGS "\t\".\"\n")
	set(_used_tool_names)
	set(_prog_idx 0)
	set(_default_tool)
	foreach(_tool IN LISTS _tool_list)
		list(GET _tool_prog_list "${_prog_idx}" _tool_prog)
		math(EXPR _prog_idx "${_prog_idx}+1")
		properties_get_value(${namespace} "tools.${_tool}.${_pattern_name}"
			_pattern QUIET)
		if ("${_pattern}" STREQUAL "")
			continue()
		endif()

		# Transfer tools properties
		_board_resolve_tool_properties(${namespace} "${_tool}"
			"${_pattern}" _pattern)

		# Transfer programmer properties
		set(_is_default_tool FALSE)
		if (NOT _tool_prog STREQUAL ".")
			set(_old_pattern "${_pattern}")
			_board_resolve_programmer_properties("${_tool_prog}"
				"${_pattern}" _pattern)
			if ("${_tool}" STREQUAL "${_def_tool}" AND
				_old_pattern STREQUAL _pattern)
				# Programmer did not make any difference in command line.
				# i.e. no programmer dependency. Just ignore this.
				continue()
			endif()
			set(_tool_name_prefix "${_tool_prog}")
			if ("${ARDUINO_${_action_var}_PROGRAMMER}" STREQUAL
				"${_tool_prog}")
				set(_is_default_tool TRUE)
			elseif(NOT DEFINED "ARDUINO_${_action_var}_PROGRAMMER" AND
				"${ARDUINO_PROGRAMMER}" STREQUAL "${_tool_prog}")
				set(_is_default_tool TRUE)
			endif()

			# Set the tool description
			properties_get_value(ard_programmers "${_tool_prog}.name"
				_tool_desc QUIET DEFAULT "${_tool_prog}")
		else()
			set(_tool_name_prefix "${_tool}")
			set(_tool_desc "${_tool}")
			set(_is_default_tool TRUE)
		endif()

		# Avoid duplicate names for the _tool_name
		set(_cnt 1)
		set(_tool_name "${_tool_name_prefix}")
		while(TRUE)
			list(FIND _used_tool_names "${_tool_name}" _idx)
			if (_idx LESS 0)
				break()
			endif()
			math(EXPR _cnt "${_cnt}+1")
			set(_tool_name "${_tool_name_prefix}.${_cnt}")
		endwhile()
		list(APPEND _used_tool_names "${_tool_name}")

		# Set default tool name
		if (_is_default_tool)
			set(_default_tool "${_tool_name}")
		endif()
		set(_only_tool "${_tool_name}")

		# Find all the unresolved variables
		string(REGEX MATCHALL "{[^{}/]+}" _unresolved_list "${_pattern}")
		if (NOT "${_unresolved_list}" STREQUAL "")
			list(REMOVE_DUPLICATES _unresolved_list)
		endif()

		# Target specific variables variables will be resolved when
		# executing the script
		list(REMOVE_ITEM _unresolved_list "{build.path}"
			"{build.project_name}" "{build.source.path}")

		# {<action>.verbose} and {<action>.verify}
		set(ARDUINO_TOOL_CURR_ALTARGS "")
		_board_find_add_alt_arg("verbose" "quiet" TRUE)
		_board_find_add_alt_arg("verify" "noverify" TRUE)
		string_escape_quoting(ARDUINO_TOOL_CURR_ALTARGS)
		string_append(ARDUINO_TOOL_ALTARGS
			"\t\"${ARDUINO_TOOL_CURR_ALTARGS}\"\n")

		# Create default value for the variables in cache
		foreach(_unresolved IN LISTS _unresolved_list)
			string(REGEX MATCH "^{(${_action}\\.)?(.*)}$"
				_match "${_unresolved}")
			set(_var "${CMAKE_MATCH_2}")
			set(_var_name "${_action}.${_var}")
			string(MAKE_C_IDENTIFIER "${_var_name}" _var_name)
			string(TOUPPER "${_var_name}" _var_name)
			if (DEFINED "ARDUINO_${_var_name}")
				set(ARDUINO_${_var_name} "${ARDUINO_${_var_name}}"
					CACHE STRING
					"Default value for '{${_var}}' for '${_action}'")
			endif()
			# Enhanced description of the tool
			if (_tool_prog STREQUAL ".")
				if (_var STREQUAL "serial.port" OR
					_var STREQUAL "serial.port.file")
					string_append(_tool_desc " (Serial Port)")
				elseif(_var STREQUAL "network.ip")
					string_append(_tool_desc " (Network)")
				endif()
			endif()
		endforeach()

		_board_resolve_arduino_quoting("${_pattern}" _pattern)
		string_escape_quoting(_tool_name)
		string_append(ARDUINO_TOOL_NAMES "\t\"${_tool_name}\"\n")
		string_escape_quoting(_pattern)
		string_append(ARDUINO_TOOL_CMDLINE_LIST "\t\"${_pattern}\"\n")
		string_escape_quoting(_tool_desc)
		string_append(ARDUINO_TOOL_DESCRIPTIONS "\t\"${_tool_desc}\"\n")
	endforeach()

	if (NOT "${ARDUINO_TOOL_NAMES}" STREQUAL "")

		# Select the only tool as the default tool
		list(LENGTH ARDUINO_TOOL_NAMES _num_tools)
		if (_num_tools EQUAL 1)
			set(_default_tool "${_only_tool}")
		endif()

		set(templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Arduino/Templates")
		configure_file("${templates_dir}/Scripts/ToolScript.cmake.in"
			"${out_file}" @ONLY)
	endif()

endfunction()

# Get referenced platform from the string
function(_board_get_ref_platform str return_pkg_name return_str)
	string(REPLACE ":" ";" str_list "${str}")
	list(LENGTH str_list _len)
	if (_len EQUAL 2)
		list(GET str_list 0 _return_pkg_name)
		list(GET str_list 1 _return_str)
		set("${return_pkg_name}" "${_return_pkg_name}" PARENT_SCOPE)
		set("${return_str}" "${_return_str}" PARENT_SCOPE)
	else()
		set("${return_pkg_name}" "" PARENT_SCOPE)
		set("${return_str}" "${str}" PARENT_SCOPE)
	endif()
endfunction()

macro(_board_find_ref_platform _ref_pkg_name _ref_pl_arch _return_ref_pl)

	packages_find_platforms(_found_ref_pl
		PACKAGER "${_ref_pkg_name}"
		ARCHITECTURE "${_ref_pl_arch}"
		INSTALL_PREFERRED)
	if (NOT _found_ref_pl)
		if (CMAKE_VERBOSE_MAKEFILE)
			message(STATUS "Platform dependency ${pl_name} => "
				"'${_ref_pl_arch}' from '${_ref_pkg_name}'")
		endif()
		report_error(200 "Platform '${_ref_pl_arch}' from '${_ref_pkg_name}' "
			"not found! Installation required. If you know the URL, "
			"try with the option -D ARDUINO_BOARD_MANAGER_REF_URL=<url>")
	endif()

	# Display the platform dependency
	packages_get_platform_property("${_found_ref_pl}" "/pkg_id" ref_pkg_id)
	packages_get_platform_property("${_found_ref_pl}" "/json_idx" ref_json_idx)
	packages_get_property("${ref_pkg_id}" "${ref_json_idx}" "maintainer"
		ref_pkg_maint DEFAULT "${_ref_pkg_name}")
	packages_get_platform_property("${_found_ref_pl}" "name" ref_pl_name)
	if (CMAKE_VERBOSE_MAKEFILE)
		message(STATUS "Platform dependency ${pl_name} => "
			"'${ref_pl_name}' from '${ref_pkg_maint}'")
	endif()

	# Check if installed. Install if package management enabled
	packages_get_platform_property("${_found_ref_pl}" "/installed" b_installed)
	if (NOT b_installed)
		if ("${ARDUINO_ENABLE_PACKAGE_MANAGER}")
			BoardManager_InstallPlatform("${_found_ref_pl}" ${_args}
				RESULT_VARIABLE _result)
			if (NOT _result EQUAL 0)
				report_error(${_result} "Installing platform '${ref_pl_name}'"
					" from '${ref_pkg_maint}' failed!!!")
			endif()
		else()
			report_error(201 "Platform '${ref_pl_name}' from "
				"'${ref_pkg_maint}' not found! Installation required. "
				"Try the option -D ARDUINO_ENABLE_PACKAGE_MANAGER=1")
		endif()
	endif()

	set("${_return_ref_pl}" "${_found_ref_pl}")

endmacro()

macro(_board_find_ref_tool _ref_tool_name _ref_tool_version _ref_tool_packager
	_ref_pl_arch _return_ref_tool b_exact)

	if (${b_exact})
		set(_version_arg VERSION_EQUAL)
	else()
		set(_version_arg VERSION_GREATER_EQUAL)
	endif()

	packages_find_tools("${_ref_pl_arch}" _found_ref_tool
		PACKAGER "${_ref_tool_packager}"
		NAME "${_ref_tool_name}"
		${_version_arg} "${_ref_tool_version}"
		INSTALL_PREFERRED)

	if (NOT _found_ref_tool)
		if (CMAKE_VERBOSE_MAKEFILE)
			message(STATUS "Tool dependency '${pl_name}' => "
				"'${_ref_tool_name} (${_ref_tool_version})' "
				"from '${_ref_tool_packager}'")
		endif()
		report_error(202 "Tool '${_ref_tool_name} (${_ref_tool_version})' "
			"from '${_ref_tool_packager}' not found! If you know the URL, "
			"try with the option -D ARDUINO_BOARD_MANAGER_REF_URL=<url>")
	endif()

	packages_get_tool_property("${_found_ref_tool}" "/pkg_id" ref_pkg_id)
	packages_get_tool_property("${_found_ref_tool}" "/json_idx" ref_json_idx)
	packages_get_property("${ref_pkg_id}" "${ref_json_idx}" "maintainer"
		ref_pkg_maint DEFAULT "${_ref_tool_packager}")
	if (CMAKE_VERBOSE_MAKEFILE)
		message(STATUS "Tool dependency ${pl_name} => "
			"'${_ref_tool_name} (${_ref_tool_version})' "
			"from '${ref_pkg_maint}'")
	endif()

	# Check if installed. Install if package management enabled
	# However no need to install if not exact version requested
	packages_get_tool_property("${_found_ref_tool}" "/installed" b_installed)
	if (NOT b_installed AND NOT ${b_exact})
		if ("${ARDUINO_ENABLE_PACKAGE_MANAGER}")
			BoardManager_InstallTool("${_found_ref_tool}" ${_args}
				RESULT_VARIABLE _result)
			if (NOT _result EQUAL 0)
				report_error("${_result}" "Installing tool '${_ref_tool_name} "
					"(${_ref_tool_version})' failed!!!")
			endif()
		else()
			report_error(203 "Tool '${_ref_tool_name} (${_ref_tool_version})' "
				"from '${ref_pkg_maint}' not found! Try the option "
				"-D ARDUINO_ENABLE_PACKAGE_MANAGER=1")
		endif()
	endif()

	set("${_return_ref_tool}" "${_found_ref_tool}")

endmacro()

macro(_board_load_ref_platform_prop load_namespace ref_pl_id)

	packages_get_platform_property("${ref_pl_id}" "/pl_path" _pl_path)

	# Read platform.txt and platform.local.txt of the given platform into
	# the given namespace.
	properties_read("${_pl_path}/platform.txt" "${load_namespace}" ${ARGN})
	if (EXISTS "${_pl_path}/platform.local.txt")
		properties_read("${_pl_path}/platform.local.txt" "${load_namespace}")
	endif()
	packages_get_platform_property("${ref_pl_id}" "/local_path" _local_path)
	if (EXISTS "${_local_path}/platform.local.txt")
		properties_read("${_local_path}/platform.local.txt"
			"${load_namespace}")
	endif()

endmacro()

macro(_board_load_ref_programmers_prop load_namespace ref_pl_id)

	packages_get_platform_property("${ref_pl_id}" "/pl_path" _pl_path)

	# Read programmers.txt of the given platform into the given namespace.
	if (EXISTS "${_pl_path}/programmers.txt")
		properties_read("${_pl_path}/programmers.txt" "${load_namespace}"
			${ARGN})
	endif()

endmacro()

# Get the tools dependencies of the selected board
macro(_board_get_tools_list)

	set(_tool_name_list)
	set(_tool_version_list)
	set(_tool_packager_list)

	_board_get_platform_property("toolsDependencies.N" _num_tools QUIET)
	if (_num_tools STREQUAL "")
		# Some platform had non standard JSON, which is handled here!!!
		_board_get_packager_property("toolsDependencies.N" _num_tools QUIET)
		if (_num_tools GREATER 0)
			foreach (_tool_idx RANGE 1 "${_num_tools}")
				_board_get_packager_property(
					"toolsDependencies.${_tool_idx}.name" _tool_name)
				list(APPEND _tool_name_list "${_tool_name}")
				_board_get_packager_property(
					"toolsDependencies.${_tool_idx}.version" _tool_version)
				list(APPEND _tool_version_list "${_tool_version}")
				_board_get_packager_property(
					"toolsDependencies.${_tool_idx}.packager" _tool_packager)
				list(APPEND _tool_packager_list "${_tool_packager}")
			endforeach()
		endif()
	elseif(_num_tools GREATER 0)
		# Standard JSON format
		foreach (_tool_idx RANGE 1 "${_num_tools}")
			_board_get_platform_property(
				"toolsDependencies.${_tool_idx}.name" _tool_name)
			list(APPEND _tool_name_list "${_tool_name}")
			_board_get_platform_property(
				"toolsDependencies.${_tool_idx}.version" _tool_version)
			list(APPEND _tool_version_list "${_tool_version}")
			_board_get_platform_property(
				"toolsDependencies.${_tool_idx}.packager" _tool_packager)
			list(APPEND _tool_packager_list "${_tool_packager}")
		endforeach()
	endif()

endmacro()

# Get the tools dependencies of the referenced packager
macro(_board_get_ref_tools_list ref_packager)

	set(_tool_name_list)
	set(_tool_version_list)
	set(_tool_packager_list)

	packages_find_platforms(_ref_pl PACKAGER "${ref_packager}"
		ARCHITECTURE "${pl_arch}" INSTALLED_PREFERRED)
	if (NOT _ref_pl)
		report_error(204
			"Tool referenced platform '${ref_packager}.${pl_arch}' not found! "
			"If you know the URL, try with the option "
			"-D ARDUINO_BOARD_MANAGER_REF_URL=<url>")
	endif()

	packages_get_platform_property("${_ref_pl}" "toolsDependencies.N"
		_num_tools QUIET)
	if (_num_tools GREATER 0)
		foreach (_tool_idx RANGE 1 "${_num_tools}")
			packages_get_platform_property("${_ref_pl}"
				"toolsDependencies.${_tool_idx}.name" _tool_name)
			list(APPEND _tool_name_list "${_tool_name}")
			packages_get_platform_property("${_ref_pl}"
				"toolsDependencies.${_tool_idx}.version" _tool_version)
			list(APPEND _tool_version_list "${_tool_version}")
			packages_get_platform_property("${_ref_pl}"
				"toolsDependencies.${_tool_idx}.packager" _tool_packager)
			list(APPEND _tool_packager_list "${_tool_packager}")
		endforeach()
	endif()

endmacro()

# Set the tools path propertied
macro(_board_set_tool_path_properties)

	set(_tool_root_path)

	list(LENGTH _tool_name_list _num_tools)
	set(_tool_idx 0)
	while(_tool_idx LESS _num_tools)

		list(GET _tool_name_list ${_tool_idx} _tool_name)
		list(GET _tool_version_list ${_tool_idx} _tool_version)
		list(GET _tool_packager_list ${_tool_idx} _tool_packager)
		math(EXPR _tool_idx "${_tool_idx} + 1")

		set(_ref_tool "")
		# _board_find_ref_tool("${_tool_name}" "${_tool_version}" "${_tool_packager}"
		#	"${pl_arch}" _ref_tool FALSE)
		if (_ref_tool)
			packages_get_tool_property("${_ref_tool}" "/tl_path"
				_tool_path)
			#message("_tool_path:${_tool_path}")
		endif()
		_board_find_ref_tool("${_tool_name}" "${_tool_version}" "${_tool_packager}"
			"${pl_arch}" _exact_ref_tool TRUE)
		packages_get_tool_property("${_exact_ref_tool}" "/tl_path"
			_exact_tool_path)
		#message("_exact_tool_path:${_exact_tool_path}")
		if (NOT _ref_tool)
			set(_tool_path "${_exact_tool_path}")
		endif()
		properties_set_value("ard_global"
			"runtime.tools.${_tool_name}.path" "${_tool_path}")
		properties_set_value("ard_global"
			"runtime.tools.${_tool_name}-${_tool_version}.path"
			"${_exact_tool_path}")
		list(APPEND _tool_root_path ${_tool_path} ${_exact_tool_path})

	endwhile()

	if (NOT "${_tool_root_path}" STREQUAL "")
		list(REMOVE_DUPLICATES _tool_root_path)
	endif()
	list(APPEND ARDUINO_FIND_ROOT_PATH ${_tool_root_path})

endmacro()

function(_board_find_gen_file_list gen_file_list return_file_list)

	foreach(_pattern_name_regex IN LISTS ARGN)

		properties_get_list(ard_global "${_pattern_name_regex}"
			_pattern_name_list)
		foreach(_pattern_name IN LISTS _pattern_name_list)
			properties_get_value(ard_global "${_pattern_name}" _pattern)
			# message("${_pattern_name}:${_pattern}")
			foreach(_gen_file IN LISTS gen_file_list)
				string(REPLACE "${_gen_file}" "" _pattern
					"${_pattern}")
			endforeach()
			string(REPLACE "[" "<SQRBRKTO>" _pattern "${_pattern}")
			string(REPLACE "]" "<SQRBRKTC>" _pattern "${_pattern}")
			separate_arguments(_pattern UNIX_COMMAND "${_pattern}")
			foreach(_pattern_comp IN LISTS _pattern)
				string(REGEX MATCH "{build\\.path}/[^ ]+" _new_gen_file
					"${_pattern_comp}")
				if (NOT "${_new_gen_file}" STREQUAL "")
					list(APPEND gen_file_list "${_new_gen_file}")
				endif()
			endforeach()
		endforeach()
	endforeach()

	set("${return_file_list}" "${gen_file_list}" PARENT_SCOPE)
endfunction()

macro(_board_replace_gen_file_list gen_file_list replace_file_list)

	foreach(_pattern_name_regex IN LISTS ARGN)

		properties_get_list(ard_global "${_pattern_name_regex}"
			_pattern_name_list)
		foreach(_pattern_name IN LISTS _pattern_name_list)

			properties_get_value(ard_global "${_pattern_name}" _pattern)
			list(LENGTH gen_file_list _num_files)
			set(_file_idx 0)
			while (_file_idx LEXX _num_files)
				list(GET gen_file_list ${_file_idx} _gen_file)
				list(GET replace_file_list ${_file_idx} _replace_file)
				math(EXPR _file_idx "${_file_idx}+1")
				string(REPLACE "${_gen_file}" "${_replace_file}" _pattern
					"${_pattern}")
			endwhile()
			properties_set_value(ard_global "${_pattern_name}" "${_pattern}")
		endforeach()
	endforeach()

endmacro()

function(_board_find_core_obj_list ret_core_obj_files)

	# Find core object files
	include (Arduino/Utilities/SourceLocator)
	set(_core_obj_files)
	find_source_files("${ARDUINO_BOARD_BUILD_CORE_PATH}" core_sources RECURSE
		NO_ENABLE_LANGUAGE)
	foreach(source IN LISTS core_sources)
		file(RELATIVE_PATH _source_rel_path "${ARDUINO_BOARD_BUILD_CORE_PATH}"
			"${source}")
		list(APPEND _core_obj_files "core/${_source_rel_path}.o")
	endforeach()
	if (ARDUINO_BOARD_BUILD_VARIANT_PATH)
		find_source_files("${ARDUINO_BOARD_BUILD_VARIANT_PATH}" variant_sources
			RECURSE NO_ENABLE_LANGUAGE)
		foreach(source IN LISTS variant_sources)
			file(RELATIVE_PATH _source_rel_path "${ARDUINO_BOARD_BUILD_CORE_PATH}"
				"${source}")
			list(APPEND _core_obj_files "variant/${_source_rel_path}.o")
		endforeach()
	endif()

	set("${ret_core_obj_files}" "${_core_obj_files}" PARENT_SCOPE)

endfunction()

macro(_board_find_add_alt_arg targ farg def_val)
	list(FIND _unresolved_list "{${_action}.${targ}}" _list_idx)
	if (NOT _list_idx LESS 0)
		properties_get_value(ard_global
			"tools.${_tool}.${_action}.${targ}" _def_args QUIET)
		string_append(ARDUINO_TOOL_CURR_ALTARGS " \"${targ}\"")
		properties_get_value(ard_global
			"tools.${_tool}.${_action}.params.${targ}"
			_true_args QUIET DEFAULT "${_def_args}")
		string_append(ARDUINO_TOOL_CURR_ALTARGS " \"${_true_args}\"")
		properties_get_value(ard_global
			"tools.${_tool}.${_action}.params.${farg}"
			_false_args QUIET DEFAULT "${_def_args}")
		string_append(ARDUINO_TOOL_CURR_ALTARGS " \"${_false_args}\"")
		list(REMOVE_ITEM _unresolved_list "{${_action}.${targ}}")
		string(TOUPPER "${_action}.${targ}" _var)
		string(MAKE_C_IDENTIFIER "${_var}" _var)
		set(ARDUINO_${_var} "${def_val}" CACHE BOOL
			"Default value for '${targ}' for '${_action}'")
	endif()
endmacro()

macro(_board_fix_nw_pattern_semantics namespace)

	properties_get_list("${namespace}" "tools\\.[^.]+\\.upload.network_pattern"
		_nw_pattern_list)
	foreach(_pattern_name IN LISTS _nw_pattern_list)
		properties_get_value("${namespace}" "${_pattern_name}" _nw_pattern
			QUIET)
		string(REPLACE "{serial.port}" "{network.ip}"
			_nw_pattern "${_nw_pattern}")
		string(REPLACE "{upload.serial.port}" "{network.ip}"
			_nw_pattern "${_nw_pattern}")
		properties_set_value(ard_global "${_pattern_name}" "${_nw_pattern}")
	endforeach()

	if (NOT DEFINED ARDUINO_UPLOAD_NETWORK_PORT)
		set(ARDUINO_UPLOAD_NETWORK_PORT 0)
	endif()

endmacro()

macro(_board_platform_rewrite_keys)

	set(_patch_dir "${ARDUINO_TOOLCHAIN_DIR}/Arduino/Patches")
	properties_read("${ARDUINO_TOOLCHAIN_DIR}/Arduino/Patches/platform.keys.rewrite.txt")
	properties_get_list()

endmacro()
