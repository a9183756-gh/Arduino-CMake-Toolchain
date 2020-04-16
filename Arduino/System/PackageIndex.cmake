# Copyright (c) 2020 Arduino CMake Toolchain

# No need to include this recursively
if(_PACKAGE_INDEX_INCLUDED)
	return()
endif()
set(_PACKAGE_INDEX_INCLUDED TRUE)

if (NOT DEFINED ARDUINO_PACKAGE_NAMESPACE)
	set(ARDUINO_PACKAGE_NAMESPACE "ard_pkgs")
endif()

#******************************************************************************
# Indexing of arduino packages. Used after indexing standard package paths
# (See PackagePathIndex.cmake)

include(CMakeParseArguments)
include(Arduino/Utilities/CommonUtils)
include(Arduino/Utilities/JSONParser)
include(Arduino/System/PackagePathIndex)

#==============================================================================
# Parse the JSON files given or contained in the standard Arduino paths to
# index all the available packages. All the indexed packages are stored in a
# global variable namespace ${ARDUINO_PACKAGE_NAMESPACE}.
#
# After indexing the packages, a call to 'packages_get_list' return all 
# the indexed packages (arduino, digistump etc.). The returned list contains
# the identifier of each package.
#
# It is also possible to search an arduino platform or an arduino tool
# within all the indexed packages, using the function packages_find_platforms
# or packages_find_tools.
#
# The package identifier can be used (in 'pkg_id' argument) in a call to
# 'packages_get_property' to return the JSON property corresponding to
# the package.
#
function(IndexArduinoPackages)

	cmake_parse_arguments(parsed_args "" "INDEX_LIST" "" ${ARGN})

	# If no argument passed, it implies standard paths
	if ("${parsed_args_UNPARSED_ARGUMENTS}" STREQUAL "")
		packages_get_default_packages(json_files_list)
	else()
		set(json_files_list "${parsed_args_UNPARSED_ARGUMENTS}")
	endif()

	set(namespace "${ARDUINO_PACKAGE_NAMESPACE}")

	# If the namespace is already used for indexing, the additional platforms
	# will be appended to the list
	if (DEFINED "${namespace}/json_count")
		set(json_count "${${namespace}/json_count}")
	else()
		set(json_count 0)
		set("${namespace}/list" "")
	endif()

	if (DEFINED parsed_args_INDEX_LIST)
		set("${parsed_args_INDEX_LIST}" "")
	endif()

	foreach(json_file IN LISTS json_files_list)

		message(STATUS "Found Arduino package ${json_file}")
		file(READ "${json_file}" json_content)
		math(EXPR json_count "${json_count} + 1")
		set(json_namespace "${namespace}/ard_pkg.${json_count}")
		json_parse("${json_content}" "${json_namespace}")
		json_set_parent_scope("${json_namespace}")

		json_get_value("${json_namespace}" "packages.N" num_packages)
		if (num_packages EQUAL 0)
			continue()
		endif()

		foreach (pkg_idx RANGE 1 "${num_packages}")

			set(pkg "packages.${pkg_idx}")

			# Check if the package is installed
			json_get_value("${json_namespace}" "${pkg}.name" pkg_name)

			set(pkg_id "${pkg_name}")
			string(MAKE_C_IDENTIFIER "${pkg_id}" pkg_id)

			# Add the package to the list of not already in list
			if (NOT DEFINED "${namespace}.${pkg_id}/json_namespaces")
				list(APPEND "${namespace}/list" "${pkg_id}")
			endif()

			# Also add to the returned list containing newly added packages
			if (DEFINED parsed_args_INDEX_LIST)
				list(APPEND "${parsed_args_INDEX_LIST}" "${pkg_id}")
			endif()

			# Add the properties of the package
			set("${namespace}.${pkg_id}/packager" "${pkg_name}" PARENT_SCOPE)
			list(APPEND "${namespace}.${pkg_id}/json_namespaces"
				${json_namespace})
			set("${namespace}.${pkg_id}/json_namespaces"
				"${${namespace}.${pkg_id}/json_namespaces}" PARENT_SCOPE)
			list(APPEND "${namespace}.${pkg_id}/json_files"
				${json_file})
			set("${namespace}.${pkg_id}/json_files"
				"${${namespace}.${pkg_id}/json_files}" PARENT_SCOPE)
			list(APPEND "${namespace}.${pkg_id}/json_prefixes" ${pkg})
			set("${namespace}.${pkg_id}/json_prefixes"
				"${${namespace}.${pkg_id}/json_prefixes}" PARENT_SCOPE)

		endforeach()
	endforeach()

	set("${namespace}/json_count" "${json_count}" PARENT_SCOPE)
	set("${namespace}/list" "${${namespace}/list}" PARENT_SCOPE)
	if (DEFINED parsed_args_INDEX_LIST)
		set("${parsed_args_INDEX_LIST}" "${${parsed_args_INDEX_LIST}}"
			PARENT_SCOPE)
	endif()
	# packages_print_properties("${namespace}")

endfunction()

#==============================================================================
# As explained in 'IndexArduinoPackages', this function returns all the indexed
# arduino packages. Must be called after a call to 'IndexArduinoPackages'.
#
# Arguments:
# <return_list> [OUT]: The list of installed platforms
#
function(packages_get_list return_list)

	set(namespace "${ARDUINO_PACKAGE_NAMESPACE}")
	set("${return_list}" "${${namespace}/list}" PARENT_SCOPE)

endfunction()

#==============================================================================
# As explained in 'IndexArduinoPackages', this function returns the property
# value of the specified package.
#
# Arguments:
# <pkg_id> [IN]: package identifier (one of the entries in the list
# returned by 'packages_get_list'
# <json_idx> [IN]: JSON index (zero based). This is an index into the list
# retured by 'packages_get_property(... "/json_files")'. This is used only
# for JSON properties and not for those that start with "/"
# <prop_name> [IN]: JSON property name (rooted at the specified package
# entry within the JSON file) or one of "/*" properties
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(packages_get_property pkg_id json_idx prop_name return_value)

	set(namespace "${ARDUINO_PACKAGE_NAMESPACE}")

	if (NOT DEFINED "${namespace}.${pkg_id}/json_namespaces")
		error_exit("Package '${pkg_id}' not found!!!")
	endif()

	# If the property starts with '/' it implies local property and JSON
	string(SUBSTRING "${prop_name}" 0 1 first_letter)
	if ("${first_letter}" STREQUAL "/")
		if (NOT DEFINED "${namespace}.${pkg_id}${prop_name}")
			error_exit("Package '${pkg_id}' property '${prop_name}' "
				"not found!!!")
		endif()
		set("${return_value}" "${${namespace}.${pkg_id}${prop_name}}"
			PARENT_SCOPE)
	else()
		list(GET "${namespace}.${pkg_id}/json_namespaces" ${json_idx}
			json_namespace)
		if (NOT json_namespace)
			error_exit("Invalid JSON index ${json_idx} in '${pkg_id}'")
		endif()

		list(GET "${namespace}.${pkg_id}/json_prefixes" ${json_idx}
			json_prefix)
		json_get_value("${json_namespace}" "${json_prefix}.${prop_name}" _value
			${ARGN})
		set("${return_value}" "${_value}" PARENT_SCOPE)
	endif()

endfunction()

#==============================================================================
# Print all the properties of all the indexed packages (for debugging)
#
function(packages_print_properties)

	set(namespace "${ARDUINO_PACKAGE_NAMESPACE}")

	# message("printing ${namespace}")
	get_cmake_property(_variableNames VARIABLES)
	string(REGEX REPLACE "\\." "\\\\." namespace_regex "${namespace}")
	list_filter_include_regex(_variableNames "^${namespace_regex}(\\.|/)")
	foreach (_variableName ${_variableNames})
		message("${_variableName}=${${_variableName}}")
	endforeach()

endfunction()

#==============================================================================
# The caller of 'IndexArduinoPackages' can use this function to set the scope
# of the indexed packages to its parent context (similar to PARENT_SCOPE of
# 'set' function)
#
macro(packages_set_parent_scope)

	set(namespace "${ARDUINO_PACKAGE_NAMESPACE}")

	if (NOT DEFINED "${namespace}/json_count")
		return()
	endif()

	foreach(json_count RANGE 1 "${${namespace}/json_count}")
		json_set_parent_scope("${namespace}/ard_pkg.${json_count}")
	endforeach()

	foreach(pkg_id IN LISTS "${namespace}/list")
		set("${namespace}.${pkg_id}/packager"
			"${${namespace}.${pkg_id}/packager}" PARENT_SCOPE)
		set("${namespace}.${pkg_id}/json_namespaces"
			"${${namespace}.${pkg_id}/json_namespaces}" PARENT_SCOPE)
		set("${namespace}.${pkg_id}/json_files"
			"${${namespace}.${pkg_id}/json_files}" PARENT_SCOPE)
		set("${namespace}.${pkg_id}/json_prefixes"
			"${${namespace}.${pkg_id}/json_prefixes}" PARENT_SCOPE)
	endforeach()

	set("${namespace}/json_count" "${${namespace}/json_count}" PARENT_SCOPE)
	set("${namespace}/list" "${${namespace}/list}" PARENT_SCOPE)

endmacro()

#==============================================================================
# As explained in 'IndexArduinoPackages', this function can be used to find
# one or more arduino platforms within the indexed packages satisfying the
# given constraints. Must be called after a call to 'IndexArduinoPackages'.
#
# The constraints can be specified through a filter containing one or more
# of packager, JSON files, architecture, platform version and installed flag.
#
# One of the platform IDs from the returned list can be used in a call to
# 'packages_get_platform_property' to query the property of the platform.
# Note that the platform IDs in the returned list are valid only till the
# next call to 'packages_find_platforms'.
#
# Arguments:
# <return_list> [OUT]: The list of platforms that meet the constraint.
#
# Filter options:
# PACKAGER <packager>: Packager that provide the platform
# JSON_FILES <file>...: One or more JSON files that provide the platform
# ARCHITECTURE <arch>: Platform architecture
# VERSION_EQUAL/VERSION_GREATER_EQUAL <version>: Platform version.
# If there are more than one that satisfies the version for a given PACKAGER
# and ARCHITECTURE, the highest one satisfying other constraints is returned.
# INSTALL_PREFERRED: Preference given to installed platform
# INSTALLED: Must be an installed platform
#
function(packages_find_platforms return_list)

	cmake_parse_arguments(parsed_args "INSTALL_PREFERRED;INSTALLED"
		"PACKAGER;ARCHITECTURE;VERSION_EQUAL;VERSION_GREATER_EQUAL"
		"JSON_FILES" ${ARGN})

	set(namespace "${ARDUINO_PACKAGE_NAMESPACE}")

	if (NOT DEFINED "${namespace}/json_count")
		set("${return_list}" "" PARENT_SCOPE)
		return()
	endif()

	# Handle some spelling mistake in package name
	if ("${parsed_args_PACKAGER}" STREQUAL "arudino")
		set(parsed_args_PACKAGER "arduino")
	endif()

	set(match_pl_list)
	foreach(pkg_id IN LISTS "${namespace}/list")

		# Check for matching packager
		set(pkg_name "${${namespace}.${pkg_id}/packager}")
		if (NOT "${parsed_args_PACKAGER}" STREQUAL "" AND
			NOT "${pkg_name}" STREQUAL "${parsed_args_PACKAGER}")
			# Packager does not match
			continue()
		endif()

		# Loop through all the JSON files of the packager
		list(LENGTH "${namespace}.${pkg_id}/json_namespaces" _num_json)
		set(json_idx 0)
		while(json_idx LESS _num_json)
			list(GET "${namespace}.${pkg_id}/json_namespaces" ${json_idx}
				json_namespace)
			list(GET "${namespace}.${pkg_id}/json_files" ${json_idx}
				json_file)
			list(GET "${namespace}.${pkg_id}/json_prefixes" ${json_idx}
				json_prefix)
			set(_curr_json_idx "${json_idx}")
			math(EXPR json_idx "${json_idx} + 1")

			# Check for matching JSON file
			if (NOT "${parsed_args_JSON_FILES}" STREQUAL "")
				list(FIND parsed_args_JSON_FILES "${json_file}" _match_idx)
				if (_match_idx LESS 0)
					# JSON file does not match
					continue()
				endif()
			endif()

			# Go through all the platforms to collect all matching
			json_get_value("${json_namespace}" "${json_prefix}.platforms.N"
				num_platforms)
			if (num_platforms EQUAL 0)
				continue()
			endif()

			# json directory
			get_filename_component(json_dir "${json_file}" DIRECTORY)

			foreach (pl_idx RANGE 1 ${num_platforms})
				set(pl "${json_prefix}.platforms.${pl_idx}")

				# Check for matching architecture
				json_get_value("${json_namespace}" "${pl}.architecture" pl_arch)
				if (NOT "${parsed_args_ARCHITECTURE}" STREQUAL "" AND
					NOT "${pl_arch}" STREQUAL "${parsed_args_ARCHITECTURE}")
					continue()
				endif()

				# Check for matching version
				json_get_value("${json_namespace}" "${pl}.version" pl_version)
				if (NOT "${parsed_args_VERSION_EQUAL}" STREQUAL "" AND
					NOT "${pl_version}" VERSION_EQUAL
					"${parsed_args_VERSION_EQUAL}")
					continue()
				endif()
				if (NOT "${parsed_args_VERSION_GREATER_EQUAL}" STREQUAL "" AND
                    NOT "${pl_version}" VERSION_GREATER_EQUAL
						"${parsed_args_VERSION_GREATER_EQUAL}")
                    continue()
                endif()

				# Check for installation match
				_packages_get_platform_path("${json_dir}" "${pkg_name}"
					"${pl_arch}" "${pl_version}" _pl_path _local_path _hw_path)
				# If the platform is not installed, redirect to the local
				# package management path
				if (NOT EXISTS "${_pl_path}/boards.txt")
					_packages_get_platform_path(
						"${ARDUINO_PACKAGE_MANAGER_PATH}" "${pkg_name}"
						"${pl_arch}" "${pl_version}" _pl_path
						_local_path _hw_path)
				endif()

				if (EXISTS "${_pl_path}/boards.txt")
					set(b_installed TRUE)
				else()
					set(b_installed FALSE)
				endif()

				if (parsed_args_INSTALLED)
					if (NOT b_installed)
						continue()
					endif()
				endif()

				if (parsed_args_INSTALL_PREFERRED)
					if (NOT b_installed)
						set(pl_version "0.${pl_version}")
					else()
						set(pl_version "1.${pl_version}")
					endif()
				endif()

				# Add the platform to the list to be returned
				string(MAKE_C_IDENTIFIER "${pl_arch}" pl_arch_id)
				set(pl_id "${pkg_id}.${pl_arch_id}")
				list(FIND match_pl_list "${pl_id}" _match_idx)
				if (_match_idx LESS 0)
					list(APPEND match_pl_list "${pl_id}")
				endif()

				if (_match_idx LESS 0 OR
					${pl_version} VERSION_GREATER
                    "${${namespace}/pl.${pl_id}/pl_version}}")

					set("${namespace}/pl.${pl_id}/pkg_id" "${pkg_id}")
					set("${namespace}/pl.${pl_id}/json_idx"
						"${_curr_json_idx}")
					set("${namespace}/pl.${pl_id}/pl_prefix"
						"platforms.${pl_idx}")
					set("${namespace}/pl.${pl_id}/pl_version" "${pl_version}")
					set("${namespace}/pl.${pl_id}/pl_path" "${_pl_path}")
					set("${namespace}/pl.${pl_id}/local_path" "${_local_path}")
					set("${namespace}/pl.${pl_id}/hw_path" "${_hw_path}")
					set("${namespace}/pl.${pl_id}/installed" "${b_installed}")

				endif()

			endforeach()
		endwhile()

	endforeach()

	foreach(pl_id IN LISTS match_pl_list)

		set("${namespace}/pl.${pl_id}/pkg_id"
			"${${namespace}/pl.${pl_id}/pkg_id}" PARENT_SCOPE)
		set("${namespace}/pl.${pl_id}/json_idx"
			"${${namespace}/pl.${pl_id}/json_idx}" PARENT_SCOPE)
		set("${namespace}/pl.${pl_id}/pl_prefix"
			"${${namespace}/pl.${pl_id}/pl_prefix}" PARENT_SCOPE)
		set("${namespace}/pl.${pl_id}/pl_path"
			"${${namespace}/pl.${pl_id}/pl_path}" PARENT_SCOPE)
		set("${namespace}/pl.${pl_id}/local_path"
			"${${namespace}/pl.${pl_id}/local_path}" PARENT_SCOPE)
		set("${namespace}/pl.${pl_id}/hw_path"
			"${${namespace}/pl.${pl_id}/hw_path}" PARENT_SCOPE)
		set("${namespace}/pl.${pl_id}/installed"
			"${${namespace}/pl.${pl_id}/installed}" PARENT_SCOPE)

	endforeach()

	set("${return_list}" "${match_pl_list}" PARENT_SCOPE)

endfunction()

#==============================================================================
# As explained in 'packages_find_platforms', this function can be used to get
# the property of one of the platforms returned by 'packages_find_platforms'.
# This function call is valid only until the next call to 
# 'packages_find_platforms' because the next call may potentially overwrite the
# properties of the platform returned in the previous call.
#
# Arguments:
# <pl_id> [IN]: platform identifier (one of the entries in the list
# returned by 'packages_find_platforms')
# <prop_name> [IN]: JSON property name (rooted at the specified platform
# entry within the JSON file) or one of '/*' property
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(packages_get_platform_property pl_id prop_name return_value)

	set(namespace "${ARDUINO_PACKAGE_NAMESPACE}")

	if (NOT DEFINED "${namespace}/pl.${pl_id}/pkg_id")
		error_exit("Platform '${pl_id}' not valid in packages!!!")
	endif()

	set(pkg_id "${${namespace}/pl.${pl_id}/pkg_id}")

	# If the property starts with '/' it implies local property and JSON
	string(SUBSTRING "${prop_name}" 0 1 first_letter)
	if ("${first_letter}" STREQUAL "/")
		if (NOT DEFINED "${namespace}/pl.${pl_id}${prop_name}")
			error_exit("Platform '${pl_id}' property '${prop_name}' "
				"not found in packages!!!")
		endif()
		set("${return_value}" "${${namespace}/pl.${pl_id}${prop_name}}"
			PARENT_SCOPE)
	else()
		set(json_idx "${${namespace}/pl.${pl_id}/json_idx}")
		set(pl_prefix "${${namespace}/pl.${pl_id}/pl_prefix}")
		packages_get_property("${pkg_id}" "${json_idx}"
			"${pl_prefix}.${prop_name}" _value ${ARGN})
		set("${return_value}" "${_value}" PARENT_SCOPE)
	endif()
	
endfunction()

#==============================================================================
# As explained in 'IndexArduinoPackages', this function can be used to find
# one or more arduino tools within the indexed packages satisfying the
# given constraints. Must be called after a call to 'IndexArduinoPackages'.
#
# The constraints can be specified through a filter containing one or more
# of packager, JSON files, tool name, tool version and installed flag.
#
# One of the tool IDs from the returned list can be used in a call to
# 'packages_get_tool_property' to query the property of the tool. Note that
# the tool IDs in the returned list are valid only till the next call to
# 'packages_find_tools'.
#
# Arguments:
# <pl_arch> [IN]: Architecture for which the tool is searched for
# <return_list> [OUT]: The list of tools that meet the constraint.
#
# Filter options:
# PACKAGER <packager>: Packager that provide the tool
# JSON_FILES <file>...: One or more JSON files that provide the tool
# NAME <name>: Name of the tool
# VERSION_EQUAL/VERSION_GREATER_EQUAL <version>: Tool version.
# If there are more than one that satisfies the version for a given tool NAME,
# the highest version satisfying other constraints is returned.
# INSTALL_PREFERRED: Preference given to installed tool
# INSTALLED: Must be an installed tool
#
function(packages_find_tools pl_arch return_list)

	cmake_parse_arguments(parsed_args "INSTALL_PREFERRED;INSTALLED"
		"PACKAGER;NAME;VERSION_EQUAL;VERSION_GREATER_EQUAL"
		"JSON_FILES" ${ARGN})

	# Parse version argument to ignore part after '-'
	if (parsed_args_VERSION_GREATER_EQUAL)
		_packages_parse_tool_version("${parsed_args_VERSION_GREATER_EQUAL}"
			parsed_args_VERSION_GREATER_EQUAL)
	endif()

	# Handle some spelling mistake in package name
	if ("${parsed_args_PACKAGER}" STREQUAL "arudino")
		set(parsed_args_PACKAGER "arduino")
	endif()

	set(namespace "${ARDUINO_PACKAGE_NAMESPACE}")

	if (NOT DEFINED "${namespace}/json_count")
		set("${return_list}" "" PARENT_SCOPE)
		return()
	endif()

	set(match_tl_list)
	foreach(pkg_id IN LISTS "${namespace}/list")

		# Check for matching packager
		set(pkg_name "${${namespace}.${pkg_id}/packager}")
		# message("match pkg_name ${pkg_name} with ${parsed_args_PACKAGER}")
		if (NOT "${parsed_args_PACKAGER}" STREQUAL "" AND
			NOT "${pkg_name}" STREQUAL "${parsed_args_PACKAGER}")
			# Packager does not match
			continue()
		endif()

		# Loop through all the JSON files of the packager
		list(LENGTH "${namespace}.${pkg_id}/json_namespaces" _num_json)
		set(json_idx 0)
		# message("_num_json:${_num_json}")
		while(json_idx LESS _num_json)
			list(GET "${namespace}.${pkg_id}/json_namespaces" ${json_idx}
				json_namespace)
			list(GET "${namespace}.${pkg_id}/json_files" ${json_idx}
				json_file)
			list(GET "${namespace}.${pkg_id}/json_prefixes" ${json_idx}
				json_prefix)
			set(_curr_json_idx "${json_idx}")
			math(EXPR json_idx "${json_idx} + 1")

			# Check for matching JSON file
			# message("match file ${json_file} with ${parsed_args_JSON_FILES}")
			if (NOT "${parsed_args_JSON_FILES}" STREQUAL "")
				list(FIND parsed_args_JSON_FILES "${json_file}" _match_idx)
				if (_match_idx LESS 0)
					# JSON file does not match
					continue()
				endif()
			endif()

			# Go through all the tools to collect all matching
			json_get_value("${json_namespace}" "${json_prefix}.tools.N"
				num_tools)
			if (num_tools EQUAL 0)
				continue()
			endif()

			# json directory
			get_filename_component(json_dir "${json_file}" DIRECTORY)

			foreach (tl_idx RANGE 1 ${num_tools})
				set(tl "${json_prefix}.tools.${tl_idx}")

				# Check for matching name
				json_get_value("${json_namespace}" "${tl}.name" tl_name)
				# message("match tl ${tl_name} with ${parsed_args_NAME}")
				if (NOT "${parsed_args_NAME}" STREQUAL "" AND
					NOT "${tl_name}" STREQUAL "${parsed_args_NAME}")
					continue()
				endif()

				# Check for matching version
				json_get_value("${json_namespace}" "${tl}.version"
					tl_version_str)
				_packages_parse_tool_version("${tl_version_str}" tl_version)
				# message("match ver ${tl_version_str} with "
				#	"${parsed_args_VERSION_EQUAL}")
				if (NOT "${parsed_args_VERSION_EQUAL}" STREQUAL "" AND
					NOT "${tl_version_str}" STREQUAL
					"${parsed_args_VERSION_EQUAL}")
					continue()
				endif()
				# message("match ver ${tl_version} with "
				#	"${parsed_args_VERSION_GREATER_EQUAL}")
				if (NOT "${parsed_args_VERSION_GREATER_EQUAL}" STREQUAL "" AND
                    "${tl_version}" VERSION_LESS
					"${parsed_args_VERSION_GREATER_EQUAL}")
                    continue()
                endif()

				# Check for installation match
				_packages_get_tool_path("${json_dir}" "${pkg_name}" "${pl_arch}"
					"${tl_name}" "${tl_version_str}" _tl_path)
				# message("aft get path ${_tl_path}")
				# If the tool is not installed, redirect to the local
				# package management path
				if (NOT IS_DIRECTORY "${_tl_path}")
					_packages_get_tool_path("${ARDUINO_PACKAGE_MANAGER_PATH}"
						"${pkg_name}" "${pl_arch}" "${tl_name}"
						"${tl_version_str}" _tl_path)
				endif()

				if (IS_DIRECTORY "${_tl_path}")
					set(b_installed TRUE)
				else()
					set(b_installed FALSE)
				endif()

				# message("match install ${_tl_path}")
				if (parsed_args_INSTALLED)
					if (NOT b_installed)
						continue()
					endif()
				endif()

				if (parsed_args_INSTALL_PREFERRED)
					if (NOT b_installed)
						set(tl_version "0.${tl_version}")
					else()
						set(tl_version "1.${tl_version}")
					endif()
				endif()
				# message("TL ${_tl_path}:${tl_version}")

				# Add the tool to the list to be returned
				string(MAKE_C_IDENTIFIER "${tl_name}" tl_name_id)
				set(tl_id "${pkg_id}.${tl_name_id}")
				list(FIND match_tl_list "${tl_id}" _match_idx)
				if (_match_idx LESS 0)
					list(APPEND match_tl_list "${tl_id}")
				endif()

				if (_match_idx LESS 0 OR
					${tl_version} VERSION_GREATER
                    "${${namespace}/tl.${tl_id}/tl_version}}")

					set("${namespace}/tl.${tl_id}/pkg_id" "${pkg_id}")
					set("${namespace}/tl.${tl_id}/json_idx" "${_curr_json_idx}")
					set("${namespace}/tl.${tl_id}/tl_prefix" "tools.${tl_idx}")
					set("${namespace}/tl.${tl_id}/tl_version" "${tl_version}")
					set("${namespace}/tl.${tl_id}/tl_path" "${_tl_path}")
					set("${namespace}/tl.${tl_id}/installed" "${b_installed}")

				endif()

			endforeach()

		endwhile()

	endforeach()

	foreach(tl_id IN LISTS match_tl_list)

		set("${namespace}/tl.${tl_id}/pkg_id"
			"${${namespace}/tl.${tl_id}/pkg_id}" PARENT_SCOPE)
		set("${namespace}/tl.${tl_id}/json_idx"
			"${${namespace}/tl.${tl_id}/json_idx}" PARENT_SCOPE)
		set("${namespace}/tl.${tl_id}/tl_prefix"
			"${${namespace}/tl.${tl_id}/tl_prefix}" PARENT_SCOPE)
		set("${namespace}/tl.${tl_id}/tl_path"
			"${${namespace}/tl.${tl_id}/tl_path}" PARENT_SCOPE)
		set("${namespace}/tl.${tl_id}/installed"
			"${${namespace}/tl.${tl_id}/installed}" PARENT_SCOPE)

	endforeach()

	set("${return_list}" "${match_tl_list}" PARENT_SCOPE)

endfunction()

#==============================================================================
# As explained in 'packages_find_tools', this function can be used to get
# the property of one of the tools returned by 'packages_find_tools'. This
# function call is valid only until the next call to 'packages_find_tools'
# because the next call may potentially overwrite the properties of the
# tool returned in the previous call.
#
# Arguments:
# <tl_id> [IN]: tool identifier (one of the entries in the list
# returned by 'packages_find_tools')
# <prop_name> [IN]: JSON property name (rooted at the specified tool
# entry within the JSON file) or one of '/*' property
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(packages_get_tool_property tl_id prop_name return_value)

	set(namespace "${ARDUINO_PACKAGE_NAMESPACE}")

	if (NOT DEFINED "${namespace}/tl.${tl_id}/pkg_id")
		error_exit("Tool '${tl_id}' not valid in packages!!!")
	endif()

	set(pkg_id "${${namespace}/tl.${tl_id}/pkg_id}")

	# If the property starts with '/' it implies local property and JSON
	string(SUBSTRING "${prop_name}" 0 1 first_letter)
	if ("${first_letter}" STREQUAL "/")
		if (NOT DEFINED "${namespace}/tl.${tl_id}${prop_name}")
			error_exit("Tool '${tl_id}' property '${prop_name}' "
				"not found in packages!!!")
		endif()
		set("${return_value}" "${${namespace}/tl.${tl_id}${prop_name}}"
			PARENT_SCOPE)
	else()
		set(json_idx "${${namespace}/tl.${tl_id}/json_idx}")
		set(tl_prefix "${${namespace}/tl.${tl_id}/tl_prefix}")
		packages_get_property("${pkg_id}" "${json_idx}"
			"${tl_prefix}.${prop_name}" _value ${ARGN})
		set("${return_value}" "${_value}" PARENT_SCOPE)
	endif()
	
endfunction()

#==============================================================================
# Return the list of packages (JSON files) from the default install locations
function(packages_get_default_packages return_json_files)

	if (NOT ARDUINO_INSTALL_PATH AND NOT ARDUINO_PACKAGE_PATH)
		InitializeArduinoPackagePathList()
	endif()

	set(_glob_pattern)
	if (ARDUINO_INSTALL_PATH)
		list(APPEND _glob_pattern
			"${ARDUINO_INSTALL_PATH}/hardware/package_index_bundled.json")
	endif()

	if (ARDUINO_PACKAGE_PATH)
		list(APPEND _glob_pattern
			"${ARDUINO_PACKAGE_PATH}/package_*index.json")
	endif()

	set(json_files_list)
	if (NOT "${_glob_pattern}" STREQUAL "")
		file(GLOB json_files_list ${_glob_pattern})
	endif()

	set("${return_json_files}" "${json_files_list}" PARENT_SCOPE)

endfunction()

#==============================================================================
# Implementation functions (Subject to change. DO NOT USE)
#

# Find the installation path of the platform
function(_packages_get_platform_path root_dir pkg_name pl_arch pl_version
	return_pl_path return_local_path return_hw_path)

	get_filename_component(root_dir_name "${root_dir}" NAME)
	if(root_dir_name STREQUAL "hardware")
		set("${return_pl_path}" "${root_dir}/${pkg_name}/${pl_arch}"
			PARENT_SCOPE)
		if (ARDUINO_SKETCHBOOK_PATH AND
			NOT root_dir STREQUAL ARDUINO_SKETCHBOOK_PATH)
			set("${return_local_path}" 
				"${ARDUINO_SKETCHBOOK_PATH}/${pkg_name}/${pl_arch}"
				PARENT_SCOPE)
		else()
			set("${return_local_path}" "" PARENT_SCOPE)
		endif()
		set("${return_hw_path}" "${root_dir}/${pkg_name}" PARENT_SCOPE)
	else()
		set("${return_pl_path}"
			"${root_dir}/packages/${pkg_name}/hardware/${pl_arch}/${pl_version}"
			PARENT_SCOPE)
		if (ARDUINO_SKETCHBOOK_PATH AND
			NOT root_dir STREQUAL ARDUINO_SKETCHBOOK_PATH)
			set("${return_local_path}"
				"${ARDUINO_SKETCHBOOK_PATH}/hardware/${pkg_name}/${pl_arch}"
				PARENT_SCOPE)
		else()
			set("${return_local_path}" "" PARENT_SCOPE)
		endif()
		set("${return_hw_path}"
			"${root_dir}/packages/${pkg_name}/hardware/${pl_arch}" PARENT_SCOPE)
	endif()

endfunction()

# Find the installation path of the tool
function(_packages_get_tool_path root_dir pkg_name pl_arch tl_name tl_version
	return_tl_path)

	get_filename_component(root_dir_name "${root_dir}" NAME)
	if(root_dir_name STREQUAL "hardware")
		set("${return_tl_path}" "${root_dir}/tools/${pl_arch}"
			PARENT_SCOPE)
	else()
		set("${return_tl_path}"
			"${root_dir}/packages/${pkg_name}/tools/${tl_name}/${tl_version}"
			PARENT_SCOPE)
	endif()

endfunction()

# ignore version string part after '-'
function(_packages_parse_tool_version tl_version_str return_tl_version)
	string(REPLACE "-" ";" tl_version_comp_list "${tl_version_str}")
	list(GET tl_version_comp_list 0 _tl_version)
	set("${return_tl_version}" "${_tl_version}" PARENT_SCOPE)
endfunction()

