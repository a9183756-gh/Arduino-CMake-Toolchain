# Copyright (c) 2020 Arduino CMake Toolchain

# No need to include this recursively
if(_BOARD_MANAGER_INCLUDED)
	return()
endif()
set(_BOARD_MANAGER_INCLUDED TRUE)

include(CMakeParseArguments)
include(Arduino/Utilities/CommonUtils)
include(Arduino/System/PackageIndex)

#==============================================================================
# Download one or more packages from the given URL list (passed in ARGN).
# The URL is typically the "board manager URL" of an Arduino platform. After
# the download, the Arduino platforms/tools available in the package can be
# indexed and one or more can be installed.
#
# Typical flow is as below:
#
# list(APPEND CMAKE_MODULE_PATH "/path/to/Arduino-CMake-Toolchain")
# include(Arduino/PackageManager/BoardsManager)
# BoardManager_DownloadPackage(
#     "https://dl.espressif.com/dl/package_esp32_index.json"
#     JSON_FILES_LIST esp32_json_file)
# IndexArduinoPackages("${esp32_json_file}")
# packages_find_platforms(platforms_list
#     JSON_FILES "${esp32_json_file}")
# ... # Display/Install etc
#
function(BoardManager_DownloadPackage)

	cmake_parse_arguments(parsed_args "QUIET;REQUIRED"
		"JSON_FILES_LIST" "" ${ARGN})

	if (parsed_args_QUIET)
		list(APPEND _args "QUIET")
	endif()

	if (parsed_args_REQUIRED)
		list(APPEND _args "REQUIRED")
	endif()

	# Download each given URL
	set(_json_files_list)
	foreach(_url IN LISTS parsed_args_UNPARSED_ARGUMENTS)
		string(STRIP "${_url}" _url)
		get_filename_component(_pkg_index_name "${_url}" NAME)
		set(_json_path "${ARDUINO_PACKAGE_MANAGER_PATH}/${_pkg_index_name}")
		set(_result 0)
		if (EXISTS "${ARDUINO_PKG_MGR_DL_CACHE}/${_pkg_index_name}")
			set(_json_path "${ARDUINO_PKG_MGR_DL_CACHE}/${_pkg_index_name}")
		elseif (NOT EXISTS "${_json_path}")
			_board_mgr_download("${_url}" "${_json_path}"
				RESULT_VARIABLE _result ${_args})
		endif()
		if (_result EQUAL 0)
			list(APPEND _json_files_list "${_json_path}")
		endif()
	endforeach()

	# Set the list of successfully downloaded files
	if (DEFINED parsed_args_JSON_FILES_LIST)
		set("${parsed_args_JSON_FILES_LIST}" "${_json_files_list}"
			PARENT_SCOPE)
	endif()

endfunction()

#==============================================================================
# Install the platform specified in pl_id and also the tool dependencies of the
# platform. It is assumed that the pl_id is one in the list returned by
# 'packages_find_platforms'. See an example in BoardManager_DownloadPackage.
#
function(BoardManager_InstallPlatform pl_id)

	cmake_parse_arguments(parsed_args "QUIET;REQUIRED"
		"RESULT_VARIABLE" "" ${ARGN})

	if (parsed_args_QUIET)
		list(APPEND _args "QUIET")
	endif()

	if (parsed_args_REQUIRED)
		list(APPEND _args "REQUIRED")
	endif()

	# Initialize return result
	if (DEFINED parsed_args_RESULT_VARIABLE)
		set(${parsed_args_RESULT_VARIABLE} 0 PARENT_SCOPE)
	endif()

	packages_get_platform_property("${pl_id}" "name" pl_name)
	packages_get_platform_property("${pl_id}" "/pkg_id" pkg_id)
	packages_get_platform_property("${pl_id}" "/json_idx" json_idx)
	packages_get_property("${pkg_id}" "${json_idx}" "maintainer"
			pkg_maint DEFAULT "${pkg_id}")
	packages_get_platform_property("${pl_id}" "architecture" pl_arch)
	packages_get_platform_property("${pl_id}" "/pl_path" pl_path)
	get_filename_component(pl_extract_path "${pl_path}" DIRECTORY)
	set(pl_extract_path "${pl_extract_path}/_tmp_extract_path")

	# Return if already installed
	if (IS_DIRECTORY "${pl_path}")
		return()
	endif()

	message(STATUS "Installing platform '${pl_name}' from '${pkg_maint}'")

	file(REMOVE_RECURSE "${pl_extract_path}")
	packages_get_platform_property("${pl_id}" "url" pl_url)
	get_filename_component(_default_archive_name "${pl_url}" NAME)
	packages_get_platform_property("${pl_id}" "archiveFileName"
		pl_archive_name DEFAULT "${_default_archive_name}")
	packages_get_platform_property("${pl_id}" "checksum" pl_checksum QUIET)
	set(_expected_hash_arg)
	if (NOT pl_checksum STREQUAL "")
		string(REPLACE ":" ";" pl_checksum "${pl_checksum}")
		list(GET pl_checksum 0 _hash_type)
		string(REPLACE "-" "" _hash_type "${_hash_type}")
		list(GET pl_checksum 1 _hash)
		set(_expected_hash_arg "EXPECTED_HASH;${_hash_type}=${_hash}")
	endif()

	_board_mgr_download_extract("${pl_url}" "${pl_extract_path}"
		"${pl_archive_name}" RESULT_VARIABLE _result
		${_expected_hash_arg} ${_args})
		# SHOW_PROGRESS
	if (NOT _result EQUAL 0)
		report_error("${_result}" "Platform ${pl_id} download failed!!!")
	endif()

	file(GLOB _extract_paths "${pl_extract_path}/*")
	set(_sub_dir)
	set(_dir_count 0)
	foreach(_path IN LISTS _extract_paths)
		get_filename_component(f_name "${_path}" NAME)
		if (IS_DIRECTORY "${_path}")
			set(_sub_dir "${_path}")
			math(EXPR _dir_count "${_dir_count} + 1")
		elseif("${f_name}" STREQUAL "boards.txt")
			set(_sub_dir "${pl_extract_path}")
			set(_dir_count "1")
			break()
		endif()
	endforeach()
	# message("_sub_dir:${_sub_dir}:${_dir_count}")
	if(NOT _sub_dir OR _dir_count GREATER 1)
		report_error(100
			"Unexpected directory structure while installing "
			"platform ${pl_id}!!!")
	endif()

	file(RENAME "${_sub_dir}" "${pl_path}")
	file(REMOVE_RECURSE "${pl_extract_path}")

	# Download and extract the tool dependencies
	_board_mgr_get_pl_tools_list()

	list(LENGTH _tool_name_list _num_tools)
	set(_tool_idx 0)
	while(_tool_idx LESS _num_tools)

		list(GET _tool_name_list ${_tool_idx} _tool_name)
		list(GET _tool_version_list ${_tool_idx} _tool_version)
		list(GET _tool_packager_list ${_tool_idx} _tool_packager)
		math(EXPR _tool_idx "${_tool_idx} + 1")

		packages_find_tools("${pl_arch}" _tl_id
			PACKAGER "${_tool_packager}"
			NAME "${_tool_name}"
			VERSION_EQUAL "${_tool_version}"
			INSTALL_PREFERRED)

		# If no such tool can be found, report error
		if (NOT _tl_id)
			report_error(101 NO_RETURN
				"Tool '${_tool_name} (${_tool_version})' from "
				"'${_tool_packager}' required for '${pl_id}' not found! "
				"If you know the URL, try with the option -D "
				"ARDUINO_BOARD_MANAGER_REF_URL=<url>")
			continue()
		endif()

		if (CMAKE_VERBOSE_MAKEFILE)
			message(STATUS "Tool dependency ${pl_name} => "
				"${_tool_name} (${_tool_version})")
		endif()

		BoardManager_InstallTool("${_tl_id}" RESULT_VARIABLE _result ${_args})
		if (NOT _result EQUAL 0)
			report_error("${_result}" NO_RETURN
				"Installting ${_tool_name} (${_tool_version}) for "
				"${pl_id} failed!!!")
			continue()
		endif()

	endwhile()

endfunction()

#==============================================================================
# Install the tool specified in tl_id. It is assumed that the tl_id is one
# in the list returned by 'packages_find_tools'. See an example flow in
# BoardManager_DownloadPackage.
#
function(BoardManager_InstallTool tl_id)

	cmake_parse_arguments(parsed_args "QUIET;REQUIRED"
		"RESULT_VARIABLE" "" ${ARGN})

	if (parsed_args_QUIET)
		list(APPEND _args "QUIET")
	endif()

	if (parsed_args_REQUIRED)
		list(APPEND _args "REQUIRED")
	endif()

	if (DEFINED parsed_args_RESULT_VARIABLE)
		set(${parsed_args_RESULT_VARIABLE} 0 PARENT_SCOPE)
	endif()

	packages_get_tool_property("${tl_id}" "name" tl_name)
	packages_get_tool_property("${tl_id}" "/pkg_id" pkg_id)
	packages_get_tool_property("${tl_id}" "/json_idx" json_idx)
	packages_get_property("${pkg_id}" "${json_idx}" "maintainer"
			pkg_maint DEFAULT "${pkg_id}")
	packages_get_tool_property("${tl_id}" "version" tl_version)
	packages_get_tool_property("${tl_id}" "/tl_path" tl_path)
	get_filename_component(tl_extract_path "${tl_path}" DIRECTORY)
	set(tl_extract_path "${tl_extract_path}/_tmp_extract_path")

	# Return if already installed
	if (IS_DIRECTORY "${tl_path}")
		return()
	endif()

	message(STATUS "Installing tool '${tl_name} (${tl_version})' "
		"from '${pkg_maint}'")

	packages_get_tool_property("${tl_id}" "systems.N" num_sys)
	set(_match_sys)
	set(_match_priority 100)
	if (num_sys EQUAL 0)
		report_error("${_result}"
			"Tool ${tl_id} not available for this system!!!")
	endif()

	foreach (sys_idx RANGE 1 "${num_sys}")
		set(sys "systems.${sys_idx}")
		packages_get_tool_property("${tl_id}" "${sys}.host" tl_host)
		# message("sys:${sys}:${tl_host}")
		_board_mgr_host_match("${tl_host}" _priority)
		if (_priority AND _priority LESS _match_priority)
			set(_match_sys "${sys}")
			set(_match_priority ${_priority})
		endif()
	endforeach()

	if (NOT _match_sys)
		report_error("${_result}"
			"Tool ${tl_id} not available for this system!!!")
	endif()

	set(sys "${_match_sys}")

	# Download and extract the tool
	file(REMOVE_RECURSE "${tl_extract_path}")
	packages_get_tool_property("${tl_id}" "${sys}.url" tl_url)
	get_filename_component(_default_archive_name "${tl_url}" NAME)
	packages_get_tool_property("${tl_id}" "${sys}.archiveFileName"
		tl_archive_name DEFAULT "${_default_archive_name}")
	packages_get_tool_property("${tl_id}" "${sys}.checksum" tl_checksum QUIET)
	set(_expected_hash_arg)
	if (NOT tl_checksum STREQUAL "")
		string(REPLACE ":" ";" tl_checksum "${tl_checksum}")
		list(GET tl_checksum 0 _hash_type)
		string(REPLACE "-" "" _hash_type "${_hash_type}")
		list(GET tl_checksum 1 _hash)
		set(_expected_hash_arg "EXPECTED_HASH;${_hash_type}=${_hash}")
	endif()

	_board_mgr_download_extract("${tl_url}" "${tl_extract_path}"
		"${tl_archive_name}" RESULT_VARIABLE _result
		${_expected_hash_arg} ${_args})
		# SHOW_PROGRESS
	if (NOT _result EQUAL 0)
		report_error("${_result}" "Tool ${tl_id} download failed!!!")
	endif()

	file(GLOB _extract_paths "${tl_extract_path}/*")
	set(_sub_dir)
	set(_dir_count 0)
	foreach(_path IN LISTS _extract_paths)
		if (IS_DIRECTORY "${_path}")
			set(_sub_dir "${_path}")
			math(EXPR _dir_count "${_dir_count} + 1")
		endif()
	endforeach()
	if (_dir_count GREATER 1)
		set(_sub_dir "${tl_extract_path}")
	endif()
	if(NOT _sub_dir)
		report_error(100
			"Unexpected directory structure while installing tool ${tl_id}!!!")
	endif()

	file(RENAME "${_sub_dir}" "${tl_path}")
	file(REMOVE_RECURSE "${tl_extract_path}")

endfunction()

#==============================================================================
# Implementation functions (Subject to change. DO NOT USE)
#

# match the given host id with the running host
# TODO Simplify this?
function(_board_mgr_host_match host _ret_priority)

	# message("Matching ${host} with ${CMAKE_HOST_SYSTEM_PROCESSOR}:${CMAKE_HOST_SYSTEM_NAME}:WIN32-${CMAKE_HOST_WIN32}:CYGWIN-${CYGWIN}:MINGW-${MINGW}:MSYS-${MSYS}:UNIX-${CMAKE_HOST_UNIX}:APPLE-${CMAKE_HOST_APPLE}")
	if (host STREQUAL "all")
		set("${_ret_priority}" 99 PARENT_SCOPE)
		# message("_priority: 99")
		return()
	endif()

	if (CMAKE_HOST_WIN32 OR CYGWIN)

		if ("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "AMD64" OR
			"${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "x86_64")
			set(_processor_list "x86_64;i686;i386")
			set(_os_list "mingw64;mingw32")
		elseif("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "IA64" OR
			"${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "ia64")
			set(_processor_list "ia64;i686;i386") # Check
			set(_os_list "mingw64;mingw32")
		elseif("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "ARM64" OR
			"${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "aarch64")
			set(_processor_list "aarch64;arm") # check
			set(_os_list "mingw64;mingw32")
		elseif("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "X86" OR
			"${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "i686" OR
			"${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "i386")
			set(_processor_list "i686;i386") # Atleast i686 host assumed
			set(_os_list "mingw32")
		else()
			set("${_ret_priority}" 0 PARENT_SCOPE)
			# message("_priority: 0: No Processor match")
			return()
		endif()

	elseif(CMAKE_HOST_UNIX)

		set(_processor_list "${CMAKE_HOST_SYSTEM_PROCESSOR}")
		if ("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "x86_64")
			set(_processor_list "x86_64;i686;i386")
		else()
			string(TOLOWER "${CMAKE_HOST_SYSTEM_PROCESSOR}" _os_list)
		endif()
		if (MSYS OR "${CMAKE_HOST_SYSTEM_NAME}" MATCHES "CYGWIN.*")
			set(_os_list "mingw32")
		else()
			string(TOLOWER "${CMAKE_HOST_SYSTEM_NAME}" _os_list)
		endif()		
	else()

		set("${_ret_priority}" 0 PARENT_SCOPE)
		# message("_priority: 0: No host match")
		return()

	endif()

	set(_result 0)
	string(REPLACE "-" ";" host_parts "${host}")
	list (LENGTH host_parts num_parts)
	# message("list:${_processor_list}:${_os_list}:${host_parts}")

	# Match processor
	list(GET host_parts 0 host_processor)
	set(_priority 0)
	foreach(_processor IN LISTS _processor_list)
		math(EXPR _priority "${_priority} + 1")
		if(_processor STREQUAL host_processor)
			math(EXPR _result "${_priority} * 10")
		endif()
	endforeach()

	if (_result EQUAL 0)
		# message("_priority: 0: No match processor")
		set("${_ret_priority}" 0 PARENT_SCOPE)
		return()
	endif()

	# Match OS
	if (num_parts LESS 2)
		set("${_ret_priority}" ${_result} PARENT_SCOPE)
		# message("_priority: ${_result}: only arch match")
		return()
	endif()

	list(GET host_parts 1 host_os)
	set(_os_prefix_match FALSE)
	set(_priority 0)
	foreach(_os IN LISTS _os_list)
		math(EXPR _priority "${_priority} + 1")
		if(_os STREQUAL host_os)
			math(EXPR _result "${_result} + ${_priority}")
			set("${_ret_priority}" ${_result} PARENT_SCOPE)
			# message("_priority: ${_result}: match")
			return()
		elseif(host_os MATCHES "^${_os}*")
			set(_os_prefix_match TRUE)
		endif()
	endforeach()

	# Try match OS with the third part of the triplet
	if (num_parts GREATER 2)
		list(GET host_parts 2 host_os)
		set(_priority 0)
		foreach(_os IN LISTS _os_list)
			math(EXPR _priority "${_priority} + 1")
			if(_os STREQUAL host_os)
				math(EXPR _result "${_result} + ${_priority}")
				set("${_ret_priority}" ${_result} PARENT_SCOPE)
				# message("_priority: ${_result}: match")
				return()
			elseif(host_os MATCHES "^${_os}*")
				set(_os_prefix_match TRUE)
			endif()
		endforeach()
	endif()

	if (_os_prefix_match)
		math(EXPR _result "${_result} + 9")
		set("${_ret_priority}" ${_result} PARENT_SCOPE)
		# message("_priority: ${_result}: OS prefix match")
		return()
	endif()

	# message("_priority: 0: No match os")
	set("${_ret_priority}" 0 PARENT_SCOPE)

endfunction()

# Download the given URL in the given path
function(_board_mgr_download url _file_path)

	cmake_parse_arguments(parsed_args "QUIET;REQUIRED"
		"RESULT_VARIABLE" "" ${ARGN})

	if (CMAKE_VERBOSE_MAKEFILE)
		message(STATUS "Downloading ${url}...")
	endif()

	file(DOWNLOAD "${url}" "${_file_path}" STATUS _status
		${parsed_args_UNPARSED_ARGUMENTS})
	list(GET _status 0 _result)
	list(GET _status 1 _result_str)
	if (DEFINED parsed_args_RESULT_VARIABLE)
		set(${parsed_args_RESULT_VARIABLE} ${_result} PARENT_SCOPE)
	endif()

	if (NOT _result EQUAL 0)
		if (parsed_args_REQUIRED)
			error_exit("${_result_str}\n"
				"Downloading ${url} failed!!!")
		elseif(NOT parsed_args_QUIET)
			message(WARNING "${_result_str}\n"
				"Downloading ${url} failed!!!")
		endif()
	endif()

endfunction()

# Download the given archive URL and extract the archive
function(_board_mgr_download_extract url dir file_name)

	cmake_parse_arguments(parsed_args "QUIET;REQUIRED"
		"RESULT_VARIABLE" "" ${ARGN})

	set(_download_dir "${ARDUINO_PKG_MGR_DL_CACHE}")
	set(_archive_path "${_download_dir}/${file_name}")
	file(MAKE_DIRECTORY "${_download_dir}")
	file(MAKE_DIRECTORY "${dir}")
	_board_mgr_download("${url}" "${_archive_path}" ${ARGN}
		RESULT_VARIABLE _result)

	if (NOT _result EQUAL 0)
		if (DEFINED parsed_args_RESULT_VARIABLE)
			set(${parsed_args_RESULT_VARIABLE} ${_result} PARENT_SCOPE)
		endif()
		return()
	endif()

	if (CMAKE_VERBOSE_MAKEFILE)
		message(STATUS "Extracting ${_archive_path}...")
	endif()
	execute_process(COMMAND ${CMAKE_COMMAND} -E tar xfz "${_archive_path}"
		WORKING_DIRECTORY "${dir}"
		RESULT_VARIABLE _result)
	if (DEFINED parsed_args_RESULT_VARIABLE)
		set(${parsed_args_RESULT_VARIABLE} ${_result} PARENT_SCOPE)
	endif()
	if (NOT _result EQUAL 0)
		file(REMOVE_RECURSE "${dir}")
		if (parsed_args_REQUIRED)
			error_exit("${_result_str}\n"
				"Extracting ${_archive_path} failed!!!")
		elseif(NOT parsed_args_QUIET)
			message(WARNING "${_result_str}\n"
				"Extracting ${_archive_path} failed!!!")
		endif()
	endif()

endfunction()

# Get the tools dependencies of the selected board
macro(_board_mgr_get_pl_tools_list)

	set(_tool_name_list)
	set(_tool_version_list)
	set(_tool_packager_list)

	packages_get_platform_property("${pl_id}" "toolsDependencies.N"
		_num_tools QUIET)
	if (_num_tools STREQUAL "")
		# Some platform had non standard JSON, which is handled here!!!
		packages_get_property("${pkg_id}" "${json_idx}"
			"toolsDependencies.N" _num_tools QUIET)
		if (_num_tools GREATER 0)
			foreach (_tool_idx RANGE 1 "${_num_tools}")
				packages_get_property("${pkg_id}" "${json_idx}"
					"toolsDependencies.${_tool_idx}.name" _tool_name)
				list(APPEND _tool_name_list "${_tool_name}")
				packages_get_property("${pkg_id}" "${json_idx}"
					"toolsDependencies.${_tool_idx}.version" _tool_version)
				list(APPEND _tool_version_list "${_tool_version}")
				packages_get_property("${pkg_id}" "${json_idx}"
					"toolsDependencies.${_tool_idx}.packager" _tool_packager)
				list(APPEND _tool_packager_list "${_tool_packager}")
			endforeach()
		endif()
	elseif(_num_tools GREATER 0)
		# Standard JSON format
		foreach (_tool_idx RANGE 1 "${_num_tools}")
			packages_get_platform_property("${pl_id}"
				"toolsDependencies.${_tool_idx}.name" _tool_name)
			list(APPEND _tool_name_list "${_tool_name}")
			packages_get_platform_property("${pl_id}"
				"toolsDependencies.${_tool_idx}.version" _tool_version)
			list(APPEND _tool_version_list "${_tool_version}")
			packages_get_platform_property("${pl_id}"
				"toolsDependencies.${_tool_idx}.packager" _tool_packager)
			list(APPEND _tool_packager_list "${_tool_packager}")
		endforeach()
	endif()

endmacro()

#libraries

