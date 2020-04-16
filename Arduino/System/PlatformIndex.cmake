# Copyright (c) 2020 Arduino CMake Toolchain

# No need to include this recursively
if(_PLATFORM_INDEX_INCLUDED)
	return()
endif()
set(_PLATFORM_INDEX_INCLUDED TRUE)

#******************************************************************************
# Indexing of installed arduino platforms. Used after indexing the Arduino
# packages (See PackageIndex.cmake).

include(Arduino/Utilities/CommonUtils)
include(Arduino/System/PackageIndex)

#==============================================================================
# Function that indexes the installed Arduino platforms. If this function is
# called after indexing the packages using IndexArduinoPackages(), then the
# default installed packages will NOT be indexed in this function. Otherwise,
# (i.e. if this function is called without indexing any packages), the default
# installed packages are indexed. Note that, explicitly indexing the packages
# (i.e. using the functions like IndexArduinoPackages, packages_find_platforms,
# BoardManager_InstallPlatform etc) provides better control of what platforms
# are indexed.
#
# After indexing the packages (if required, as explained before), this function
# simply calls the 'packages_find_platforms' to get the installed platforms and
# stores the list in the given namespace. The same filter applicable to 
# 'packages_find_platforms' is applicable here as well in order to specify the
# constraints on what platforms are indexed.
#
# After calling this function to index the platforms, a call to the function
# 'platforms_get_list' returns all the indexed (installed) arduino platforms
# (e.g. arduino.avr, esp8266.esp8266 etc). The returned list contains the
# identifier of each platform.
#
# The platform identifier can further be used (as 'pl_id' argument) in a 
# call to 'platforms_get_property' to return the JSON property corresponding
# to the platform.
#
function(IndexArduinoPlatforms namespace)

	# If no packages have been indexed so far, index the default packages.
	# This is for the backward compatible behaviour of simply calling
	# IndexArduinoBoards, without explicitly calling any other functions.
	# However, explicitly calling other functions (IndexArduinoPackages,
	# packages_find_platforms etc)
	packages_get_list(_pkg_list)
	if ("${_pkg_list}" STREQUAL "")
		IndexArduinoPackages()
	endif()

	packages_find_platforms(_installed_pl_list INSTALLED ${ARGN})

	foreach(pl_id IN LISTS _installed_pl_list)

		packages_get_platform_property("${pl_id}" "/pkg_id" pkg_id)
		set("${namespace}.${pl_id}/pkg_id" "${pkg_id}" PARENT_SCOPE)
		packages_get_platform_property("${pl_id}" "/json_idx" json_idx)
		set("${namespace}.${pl_id}/json_idx" "${json_idx}" PARENT_SCOPE)
		packages_get_platform_property("${pl_id}" "/pl_prefix" pl_prefix)
		set("${namespace}.${pl_id}/pl_prefix" "${pl_prefix}" PARENT_SCOPE)
		packages_get_platform_property("${pl_id}" "/pl_path" pl_path)
		set("${namespace}.${pl_id}/pl_path" "${pl_path}" PARENT_SCOPE)
		packages_get_platform_property("${pl_id}" "/local_path" local_path)
		set("${namespace}.${pl_id}/local_path" "${local_path}" PARENT_SCOPE)
		packages_get_platform_property("${pl_id}" "/hw_path" hw_path)
		set("${namespace}.${pl_id}/hw_path" "${hw_path}" PARENT_SCOPE)
		message(STATUS "Found Arduino Platform: ${pl_path}")
		
	endforeach()

	set("${namespace}/pl_list" "${_installed_pl_list}" PARENT_SCOPE)
	# platforms_print_properties("${namespace}")

endfunction()

#==============================================================================
# As explained in 'IndexArduinoPlatforms', this function returns all the
# installed arduino platforms. Must be called after a call to 
# 'IndexArduinoPlatforms'.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoPlatforms'
# <return_list> [OUT]: The list of installed platforms
#
function(platforms_get_list namespace return_list)
	if (NOT DEFINED ${namespace}/pl_list)
		error_exit("Platform namespace '${namespace}' not found!!!")
	endif()
	set("${return_list}" "${${namespace}/pl_list}" PARENT_SCOPE)
endfunction()

#==============================================================================
# As explained in 'IndexArduinoPlatforms', this function returns the property
# value of the specified platform.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoPlatforms'
# <pl_id> [IN]: platform identifier (one of the entries in the list
# returned by 'platforms_get_list'
# <prop_name> [IN]: JSON property name (rooted at the specified platform
# entry within the JSON file) or one of "/*" properties.
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(platforms_get_property namespace pl_id prop_name return_value)
	if (NOT DEFINED "${namespace}/pl_list")
		error_exit("Platform namespace '${namespace}' not found!!!")
	endif()

	if (NOT DEFINED "${namespace}.${pl_id}/pkg_id")
		error_exit("Platform '${pl_id}' not found in '${namespace}'!!!")
	endif()

	# If the property starts with '/' it implies a platform property and 
	# not JSON property
	string(SUBSTRING "${prop_name}" 0 1 first_letter)
	if ("${first_letter}" STREQUAL "/")
		if (NOT DEFINED "${namespace}.${pl_id}${prop_name}")
			error_exit("Platform '${pl_id}' property '${prop_name}' "
				"not found in '${namespace}'!!!")
		endif()
		set("${return_value}" "${${namespace}.${pl_id}${prop_name}}"
			PARENT_SCOPE)
	else()
		set(pkg_id "${${namespace}.${pl_id}/pkg_id}")
		set(json_idx "${${namespace}.${pl_id}/json_idx}")
		set(pl_prefix "${${namespace}.${pl_id}/pl_prefix}")
		packages_get_property("${pkg_id}" "${json_idx}"
			"${pl_prefix}.${prop_name}" _value ${ARGN})
		set("${return_value}" "${_value}" PARENT_SCOPE)
	endif()
endfunction()

#==============================================================================
# This function returns the property value of the packager corresponding to
# the specified platform.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoPlatforms'
# <pl_id> [IN]: platform identifier (one of the entries in the list
# returned by 'platforms_get_list'
# <prop_name> [IN]: JSON property name (rooted at the platform's packager
# entry within the JSON file) or one of "/*" properties.
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(platforms_get_packager_property namespace pl_id prop_name
	return_value)

	if (NOT DEFINED "${namespace}/pl_list")
		error_exit("Platform namespace '${namespace}' not found!!!")
	endif()

	if (NOT DEFINED "${namespace}.${pl_id}/pkg_id")
		error_exit(
			"Platform '${pl_id}' not found in '${namespace}'!!!")
	endif()

	set(pkg_id "${${namespace}.${pl_id}/pkg_id}")
	set(json_idx "${${namespace}.${pl_id}/json_idx}")
	packages_get_property("${pkg_id}" "${json_idx}"
		"${prop_name}" _value ${ARGN})
	set("${return_value}" "${_value}" PARENT_SCOPE)

endfunction()

#==============================================================================
# Print all the properties of all the installed platforms (for debugging)
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoPlatforms'
#
function(platforms_print_properties namespace)
	# message("printing ${namespace}")
	get_cmake_property(_variableNames VARIABLES)
	string(REGEX REPLACE "\\." "\\\\." namespace_regex "${namespace}")
	list_filter_include_regex(_variableNames "^${namespace_regex}(\\.|/)")
	foreach (_variableName ${_variableNames})
		message("${_variableName}=${${_variableName}}")
	endforeach()
endfunction()

#==============================================================================
# The caller of 'IndexArduinoPlatforms' can use this function to set the scope
# of the indexed platforms to its parent context (similar to PARENT_SCOPE of
# 'set' function)
#
# Note that this function assumes that the packages_set_parent_scope is also
# called (as needed) outside of this function.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoPlatforms'
#
macro(platforms_set_parent_scope namespace)

	if (NOT DEFINED "${namespace}/pl_list")
		error_exit("Platform namespace '${namespace}' not found!!!")
	endif()

	foreach(pl_id IN LISTS "${namespace}/pl_list")
		set("${namespace}.${pl_id}/pkg_id"
			"${${namespace}.${pl_id}/pkg_id}" PARENT_SCOPE)
		set("${namespace}.${pl_id}/json_idx"
			"${${namespace}.${pl_id}/json_idx}" PARENT_SCOPE)
		set("${namespace}.${pl_id}/pl_prefix"
			"${${namespace}.${pl_id}/pl_prefix}" PARENT_SCOPE)
		set("${namespace}.${pl_id}/pl_path"
			"${${namespace}.${pl_id}/pl_path}" PARENT_SCOPE)
		set("${namespace}.${pl_id}/local_path"
			"${${namespace}.${pl_id}/local_path}" PARENT_SCOPE)
		set("${namespace}.${pl_id}/hw_path"
			"${${namespace}.${pl_id}/hw_path}" PARENT_SCOPE)
	endforeach()

	set("${namespace}/pl_list" "${${namespace}/pl_list}" PARENT_SCOPE)

endmacro()

#==============================================================================
# Find the one or more platform identifiers from the given list that may 
# correspond to the user provided platform identifier in 'pl_id'. Note that the
# user may provide a shorter identifier that may be unambiguos in his local
# installation context and many not be globally unambiguous (e.g. avr may mean
# arduino.avr or adafruit.avr). This function is typically used to detect any
# local ambiguity in the platform identifier.
# 
function(platforms_find_platform_in_list pl_list pl_id return_pl_id_list)

	string(REPLACE "." "\\." _pl_id_regex "${pl_id}")
	set(pl_id_list "${pl_list}")
	list_filter_include_regex(pl_id_list "(^|\\.)${_pl_id_regex}$")

	set("${return_pl_id_list}" "${pl_id_list}" PARENT_SCOPE)

endfunction()

#==============================================================================
# Implementation functions (Subject to change. DO NOT USE)
#
