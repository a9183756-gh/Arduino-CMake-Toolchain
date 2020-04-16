# Copyright (c) 2020 Arduino CMake Toolchain

# No need to include this recursively
if(_BOARDS_INDEX_INCLUDED)
	return()
endif()
set(_BOARDS_INDEX_INCLUDED TRUE)

#******************************************************************************
# Indexing of arduino boards. For indexing arduino boards, arduino platforms
# needs to be indexed using 'IndexArduinoPlatforms' (See PlatformIndex.cmake).

include(CMakeParseArguments)
include(Arduino/Utilities/CommonUtils)
include(Arduino/Utilities/PropertiesReader)
include(Arduino/System/PackageIndex)
include(Arduino/System/PlatformIndex)

#==============================================================================
# Index the arduino boards of all the installed arduino platforms from 
# boards.txt file. This function calls the 'IndexArduinoPlatforms' internally
# to index the installed arduino platforms, and hence no need to call it 
# explicitly before calling IndexArduinoBoards. All the indexed arduino 
# boards are stored in the given 'namespace'.
#
# This function passes ARGN arguments transparently to IndexArduinoPlatforms
# and thus filter constraints can be passed that allows indexing the boards
# only from specific platforms. There are no board specific filters available
# currently.
#
# All the indexed arduino boards are stored in the given 'namespace'. After
# indexing the boards, a call to 'boards_get_list' returns all the installed
# arduino boards (e.g. arduino.avr.uno, arduino.samd.mkrwifi1010,
# esp32.esp32.esp32, esp8266.esp8266.generic etc.). To find the property and
# platform property of a board, the functions 'boards_get_property' and 
# 'boards_get_platform_property' respectively can then be used.
#
function(IndexArduinoBoards namespace)

	# The namespace that will be used for indexing platforms
	set(pl_namespace "${namespace}/ard_plat")
	set(pl_count 0)

	# Index all the installed arduino platforms first
	IndexArduinoPlatforms("${pl_namespace}" ${ARGN})
	platforms_get_list("${pl_namespace}" _pl_list)

	# List all the boards within the indexed platforms
	set("${namespace}/brd_list" "")
	foreach (pl_id IN LISTS _pl_list)

		math(EXPR pl_count "${pl_count} + 1")
		platforms_get_property("${pl_namespace}" "${pl_id}" "/pl_path" pl_path)
		platforms_get_property("${pl_namespace}" "${pl_id}" "architecture"
			pl_arch)

		# Read all properties from boards.txt for the platform
		set(brd_namespace "${namespace}/ard_boards.${pl_count}")
		properties_read("${pl_path}/boards.txt" "${brd_namespace}")

		# boards list in the platform
		properties_get_list("${brd_namespace}" "^[^.]+\\.name$"
			_board_names_prop_list)

		foreach(_board_name_prop IN LISTS _board_names_prop_list)
			string(REGEX MATCH "^([^.]+)\\.name$" match "${_board_name_prop}")

			# Find board prefix used in boards.txt and board name
			set(_board_prefix "${CMAKE_MATCH_1}")
			string(MAKE_C_IDENTIFIER "${_board_prefix}" _board_prefix_id)
			set(_board_id "${pl_id}.${_board_prefix_id}")
			set(_board_short_id "${pl_arch}.${_board_prefix_id}") # Selection ID
			properties_get_value("${brd_namespace}" "${_board_prefix}.hide"
				_board_hide QUIET DEFAULT "FALSE")
			if (_board_hide)
				continue()
			endif()

			list(APPEND "${namespace}/brd_list" "${_board_id}")
			set("${namespace}.${_board_id}/brd_namespace"
				"${brd_namespace}")
			set("${namespace}.${_board_id}/pl_id" "${pl_id}")
			set("${namespace}.${_board_id}/distinct_id" "${_board_short_id}")
			set("${namespace}.${_board_id}/short_id" "${_board_short_id}")
			set("${namespace}.${_board_id}/brd_prefix"
				"${_board_prefix}")

		endforeach()

		# Read all properties from programmers.txt for the platform
		set(prog_namespace "${namespace}/ard_prog.${pl_count}")
		if (EXISTS "${pl_path}/programmers.txt")
			properties_read("${pl_path}/programmers.txt" "${prog_namespace}")
		endif()

		# programmers list in the platform
		properties_get_list("${prog_namespace}" "^[^.]+\\.name$"
			_prog_names_prop_list)

		foreach(_prog_name_prop IN LISTS _prog_names_prop_list)

			string(REGEX MATCH "^([^.]+)\\.name$" match "${_prog_name_prop}")

			# Find programmer prefix used in programmers.txt and name
			set(_prog_prefix "${CMAKE_MATCH_1}")
			string(MAKE_C_IDENTIFIER "${_prog_prefix}" _prog_prefix_id)
			set(_prog_id "${pl_id}.${_prog_prefix_id}")
			set(_prog_short_id "${pl_arch}.${_prog_prefix_id}")

			list(APPEND "${namespace}/prog_list" "${_prog_id}")
			set("${namespace}/prog.${_prog_id}/prog_namespace"
				"${prog_namespace}")
			set("${namespace}/prog.${_prog_id}/pl_id" "${pl_id}")
			set("${namespace}/prog.${_prog_id}/distinct_id"
				"${_prog_short_id}")
			set("${namespace}/prog.${_prog_id}/prog_prefix" "${_prog_prefix}")

		endforeach()

	endforeach()

	# If the selection ID of a board is ambiguous, set full ID as the selection
	# ID for the board
	foreach(_board_id IN LISTS "${namespace}/brd_list")

		set(_board_distinct_id "${${namespace}.${_board_id}/distinct_id}")
		boards_find_board_in_list("${${namespace}/brd_list}"
			"${_board_distinct_id}" match_id_list)
		list(LENGTH match_id_list match_id_len)
		if (match_id_len GREATER 1)
			set(_board_distinct_id "${_board_id}")
			set("${namespace}.${_board_id}/distinct_id" "${_board_id}")
		endif()

	endforeach()

	# If the selection ID of a programmer is ambiguous, set full ID as the
	# selection ID for the programmer
	foreach(_prog_id IN LISTS "${namespace}/prog_list")

		set(_prog_distinct_id "${${namespace}/prog.${_prog_id}/distinct_id}")
		_boards_find_programmer("${namespace}" "${_prog_distinct_id}"
			match_id_list)
		list(LENGTH match_id_list match_id_len)
		if (match_id_len GREATER 1)
			set(_prog_distinct_id "${_prog_id}")
			set("${namespace}/prog.${_prog_id}/distinct_id" "${_prog_id}")
		endif()

	endforeach()

	boards_set_parent_scope("${namespace}")

endfunction()

#==============================================================================
# This function returns all the installed arduino boards. Must be called after
# a call to 'IndexArduinoBoards'.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
# <return_list> [OUT]: The list of installed boards
#
function(boards_get_list namespace return_list)
	if (NOT DEFINED ${namespace}/brd_list)
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()
	set("${return_list}" "${${namespace}/brd_list}" PARENT_SCOPE)
endfunction()

#==============================================================================
# This function returns the property value of the specified board.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
# <board_identifier> [IN]: board identifier (one of the entries in the list
# returned by 'boards_get_list'
# <prop_name> [IN]: A property corresponding to the board in boards.txt file.
# The board prefix is omitted, when passing the property name.
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(boards_get_property namespace board_identifier prop_name return_value)
	if (NOT DEFINED "${namespace}/brd_list")
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()

	if (NOT DEFINED "${namespace}.${board_identifier}/brd_namespace")
		error_exit("Board '${board_identifier}' not found "
			"in '${namespace}'!!!")
	endif()

	# If the property starts with '/' it is platform property and not JSON
	string(SUBSTRING "${prop_name}" 0 1 first_letter)
	if ("${first_letter}" STREQUAL "/")
		if (NOT DEFINED "${namespace}.${board_identifier}${prop_name}")
			error_exit("Board '${board_identifier}' property "
				"'${prop_name}' not found in '${namespace}'!!!")
		endif()
		set("${return_value}" "${${namespace}.${board_identifier}${prop_name}}"
			PARENT_SCOPE)
	else()
		set(brd_namespace "${${namespace}.${board_identifier}/brd_namespace}")
		set(_board_prefix "${${namespace}.${board_identifier}/brd_prefix}")
		properties_get_value("${brd_namespace}" "${_board_prefix}.${prop_name}"
			_value ${ARGN})
		set("${return_value}" "${_value}" PARENT_SCOPE)
	endif()
endfunction()

#==============================================================================
# This function returns all the properties of the given arduino board.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
# <board_identifier> [IN]: board identifier (one of the entries in the list
# returned by 'boards_get_list')
# <pattern> [IN]: Regular expression pattern
# <return_list> [OUT]: The list of all board properties
#
function(boards_get_property_list namespace board_identifier pattern return_list)
	if (NOT DEFINED "${namespace}/brd_list")
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()
	if (NOT DEFINED "${namespace}.${board_identifier}/brd_namespace")
		error_exit("Board '${board_identifier}' not found "
			"in '${namespace}'!!!")
	endif()
	set(brd_namespace "${${namespace}.${board_identifier}/brd_namespace}")
	set(_board_prefix "${${namespace}.${board_identifier}/brd_prefix}")
	string(REPLACE "." "\\." _board_prefix_regex "${_board_prefix}")
	properties_get_list("${brd_namespace}"
		"^${_board_prefix_regex}\\.${pattern}" _list)
	foreach (_elem IN LISTS _list)
		string_regex_replace_start("${_board_prefix_regex}\\." ""
			_elem "${_elem}")
		list(APPEND _list2 "${_elem}")
	endforeach()
	set("${return_list}" "${_list2}" PARENT_SCOPE)
endfunction()

#==============================================================================
# This function returns the platform property value of the specified board.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
# <board_identifier> [IN]: board identifier (one of the entries in the list
# returned by 'boards_get_list')
# <prop_name> [IN]: JSON property name (rooted at the specified platform
# entry, corresponding to the board, within the JSON file)
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(boards_get_platform_property namespace board_identifier prop_name
	return_value)

	if (NOT DEFINED "${namespace}/brd_list")
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()
	if (NOT DEFINED "${namespace}.${board_identifier}/pl_id")
		error_exit("Board '${board_identifier}' not found "
			"in '${namespace}'!!!")
	endif()
	set(pl_id "${${namespace}.${board_identifier}/pl_id}")
	set(pl_namespace "${namespace}/ard_plat")
	platforms_get_property("${pl_namespace}" "${pl_id}" "${prop_name}"
		_value ${ARGN})
	set("${return_value}" "${_value}" PARENT_SCOPE)
endfunction()

#==============================================================================
# This function returns all the programmers. Must be called after a call to
# 'IndexArduinoBoards'.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
# <return_list> [OUT]: The list of programmers
#
function(programmers_get_list namespace return_list)
	if (NOT DEFINED ${namespace}/prog_list)
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()
	set("${return_list}" "${${namespace}/prog_list}" PARENT_SCOPE)
endfunction()

#==============================================================================
# This function returns the property value of the specified programmer.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
# <prog_id> [IN]: programmer id (${ARDUINO_PROGRAMMER_ID})
# <prop_name> [IN]: A property corresponding to the programmer in
# programmers.txt file. The programmer prefix is omitted, when passing the
# property name.
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(boards_get_programmer_property namespace prog_id prop_name
	return_value)

	if (NOT DEFINED "${namespace}/prog_list")
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()
	if (NOT DEFINED "${namespace}/prog.${prog_id}/prog_namespace")
		error_exit("Programmer '${prog_id}' not found "
			"in '${namespace}'!!!")
	endif()
	set(prog_namespace "${${namespace}/prog.${prog_id}/prog_namespace}")
	set(_prog_prefix "${${namespace}/prog.${prog_id}/prog_prefix}")
	properties_get_value("${prog_namespace}" "${_prog_prefix}.${prop_name}"
		_value ${ARGN})
	set("${return_value}" "${_value}" PARENT_SCOPE)
endfunction()

#==============================================================================
# This function returns all the properties of the given arduino programmer.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
# <prog_id> [IN]: programmer id (${ARDUINO_PROGRAMMER_ID})
# <pattern> [IN]: Regular expression pattern
# <return_list> [OUT]: The list of all board properties
#
function(boards_get_programmer_prop_list namespace prog_id pattern return_list)

	if (NOT DEFINED "${namespace}/prog_list")
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()
	if (NOT DEFINED "${namespace}/prog.${prog_id}/prog_namespace")
		error_exit("Programmer '${prog_id}' not found "
			"in '${namespace}'!!!")
	endif()

	set(prog_namespace "${${namespace}/prog.${prog_id}/prog_namespace}")
	set(_prog_prefix "${${namespace}/prog.${prog_id}/prog_prefix}")
	string(REPLACE "." "\\." _prog_prefix_regex "${_prog_prefix}")

	properties_get_list("${prog_namespace}"
		"^${_prog_prefix_regex}\\.${pattern}" _list)
	foreach (_elem IN LISTS _list)
		string_regex_replace_start("${_prog_prefix_regex}\\." ""
			_elem "${_elem}")
		list(APPEND _list2 "${_elem}")
	endforeach()
	set("${return_list}" "${_list2}" PARENT_SCOPE)
endfunction()

#==============================================================================
# This function returns the packager property value of the specified board.
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
# <board_identifier> [IN]: board identifier (one of the entries in the list
# returned by 'boards_get_list')
# <prop_name> [IN]: JSON property name (rooted at the specified packager
# entry, corresponding to the board, within the JSON file)
# <return_value> [OUT]: The value of the property is returned in this variable
#
function(boards_get_packager_property namespace board_identifier prop_name
	return_value)

	if (NOT DEFINED "${namespace}/brd_list")
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()
	if (NOT DEFINED "${namespace}.${board_identifier}/pl_id")
		error_exit("Board '${board_identifier}' not found "
			"in '${namespace}'!!!")
	endif()
	set(pl_id "${${namespace}.${board_identifier}/pl_id}")
	set(pl_namespace "${namespace}/ard_plat")
	platforms_get_packager_property("${pl_namespace}" "${pl_id}"
		"${prop_name}" _value ${ARGN})
	set("${return_value}" "${_value}" PARENT_SCOPE)
endfunction()

#==============================================================================
# Print all the properties of all the boards (for debugging)
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
#
function(boards_print_properties namespace)
	# message("printing ${namespace}")
	get_cmake_property(_variableNames VARIABLES)
	string(REGEX REPLACE "\\." "\\\\." namespace_regex "${namespace}")
	list_filter_include_regex(_variableNames "^${namespace_regex}(\\.|/)")
	foreach (_variableName ${_variableNames})
		message("${_variableName}=${${_variableName}}")
	endforeach()
endfunction()

#==============================================================================
# The caller of 'IndexArduinoBoards' can use this function to set the scope
# of the indexed boards to its parent context (similar to PARENT_SCOPE of
# 'set' function)
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
#
macro(boards_set_parent_scope namespace)

	if (NOT DEFINED "${namespace}/brd_list")
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()

	foreach(_board_id IN LISTS "${namespace}/brd_list")

		set(brd_namespace "${${namespace}.${_board_id}/brd_namespace}")
		properties_set_parent_scope("${brd_namespace}")

		set("${namespace}.${_board_id}/brd_namespace"
			"${${namespace}.${_board_id}/brd_namespace}" PARENT_SCOPE)
		set("${namespace}.${_board_id}/pl_id"
			"${${namespace}.${_board_id}/pl_id}" PARENT_SCOPE)
		set("${namespace}.${_board_id}/distinct_id"
			"${${namespace}.${_board_id}/distinct_id}" PARENT_SCOPE)
		set("${namespace}.${_board_id}/short_id"
			"${${namespace}.${_board_id}/short_id}" PARENT_SCOPE)
		set("${namespace}.${_board_id}/brd_prefix"
			"${${namespace}.${_board_id}/brd_prefix}" PARENT_SCOPE)

	endforeach()

	foreach(_prog_id IN LISTS "${namespace}/prog_list")

		set(prog_namespace "${${namespace}/prog.${_prog_id}/prog_namespace}")
		properties_set_parent_scope("${prog_namespace}")

		set("${namespace}/prog.${_prog_id}/prog_namespace"
			"${${namespace}/prog.${_prog_id}/prog_namespace}" PARENT_SCOPE)
		set("${namespace}/prog.${_prog_id}/pl_id"
			"${${namespace}/prog.${_prog_id}/pl_id}" PARENT_SCOPE)
		set("${namespace}/prog.${_prog_id}/distinct_id"
			"${${namespace}/prog.${_prog_id}/distinct_id}" PARENT_SCOPE)
		set("${namespace}/prog.${_prog_id}/prog_prefix"
			"${${namespace}/prog.${_prog_id}/prog_prefix}" PARENT_SCOPE)

	endforeach()

	set("${namespace}/pl_count" "${pl_count}" PARENT_SCOPE)
	set("${namespace}/brd_list" "${${namespace}/brd_list}" PARENT_SCOPE)
	set("${namespace}/prog_list" "${${namespace}/prog_list}" PARENT_SCOPE)

	set(pl_namespace "${namespace}/ard_plat")
	platforms_set_parent_scope("${pl_namespace}")

endmacro()

#==============================================================================
# This function selects a matching arduino board specified by the user. It also
# generates a file BoardOptions.cmake and entries in CMake cache, which can be
# used by the user to choose an arduino board and menu options for the next
# invocation of cmake.
#
# If no board is selected (e.g. first invocation of CMake without any board 
# specified by the user), the toolchain will exit with error later in 
# Arduiono-Determine.cmake.
#
# If a board is selected successully, then some variables are set, which can
# be used by the caller to set up the toolchain (See BoardToolchain.cmake).
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
#
# Return Variables:
# ARDUINO_BOARD_IDENTIFIER: Identifier of the selected board
# ARDUINO_PROGRAMMER_ID: Identifier of the selected programmer
# ARDUINO_SEL_MENU_OPT_ID_LIST: List of identifiers corresponding to the
# selected menu options.
#
function(SelectArduinoBoard namespace)

	if (NOT DEFINED "${namespace}/brd_list")
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()

	set(pl_namespace "${namespace}/ard_plat")

	# Include board options
	_boards_include_board_options("${CMAKE_BINARY_DIR}/BoardOptions.cmake")

	# Initialize ARDUINO_BOARD cache option for the board selection.
	# message("ARDUINO_BOARD:${ARDUINO_BOARD}")
	set(ARDUINO_BOARD "${ARDUINO_BOARD}" CACHE STRING
		"Arduino board for which the project is build for")
	set_property(CACHE ARDUINO_BOARD PROPERTY STRINGS "")

	# Once ARDUINO_BOARD is selected (either through cache or through the
	# board options), find the selected board identifier
	if (NOT "${ARDUINO_BOARD}" STREQUAL "")
		boards_find_board_in_list("${${namespace}/brd_list}" "${ARDUINO_BOARD}"
			ARDUINO_BOARD_IDENTIFIER)
		# message("ARDUINO_BOARD_IDENTIFIER:${ARDUINO_BOARD_IDENTIFIER}")
	endif()

	# Initialize ARDUINO_PROGRAMMER cache option for the programmer selection.
	set(ARDUINO_PROGRAMMER "${ARDUINO_PROGRAMMER}" CACHE STRING
		"Arduino programmer used to upload program or burn bootloader")
	set_property(CACHE ARDUINO_PROGRAMMER PROPERTY STRINGS "")

	# Once ARDUINO_PROGRAMMER is selected (either through cache or through the
	# board options), find the selected programmer identifier
	if (NOT "${ARDUINO_PROGRAMMER}" STREQUAL "")
		_boards_find_programmer("${namespace}" "${ARDUINO_PROGRAMMER}"
			prog_id_list)
		if (NOT "${prog_id_list}" STREQUAL "")
			# No ambiguity informed here! Select first one. TODO
			list(GET prog_id_list 0 ARDUINO_PROGRAMMER_ID)
		else()
			set(ARDUINO_PROGRAMMER_ID)
		endif()
	endif()

	# Generate board options in file and in cache
	_boards_gen_board_options("${namespace}"
		"${${namespace}/brd_list}"
		"${${namespace}/prog_list}"
		"${CMAKE_BINARY_DIR}/BoardOptions.cmake"
		TRUE)

	# Set Last used Board options file
	if (ARDUINO_BOARD_OPTIONS_FILE)
		set(_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE
			"${ARDUINO_BOARD_OPTIONS_FILE}" CACHE INTERNAL "" FORCE)
	elseif (NOT _LAST_USED_ARDUINO_BOARD_OPTIONS_FILE)
		set(_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE
			"${CMAKE_BINARY_DIR}/BoardOptions.cmake" CACHE INTERNAL "" FORCE)
		add_configure_dependency("${_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE}")
	endif()

	file(TIMESTAMP "${_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE}" _ts)
	set(_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE_TS "${_ts}" CACHE INTERNAL ""
		FORCE)

	# Return if no board selected
	if (NOT ARDUINO_BOARD_SEL_ID)
		return()
	endif()

	# Display the selected board
	set(_board "${ARDUINO_BOARD_NAME} [${ARDUINO_BOARD_SEL_ID}]")
	message(STATUS "Selected Arduino Board: ${_board}")

	# Display the selected menu options
	foreach(_menu_identifier IN LISTS ARDUINO_SEL_MENU_ID_LIST)
		set(_menu_name "${ARDUINO.${_menu_identifier}.NAME}")
		set(_menu_opt_identifier "${ARDUINO.${_menu_identifier}.SEL_OPT}")
		set(_menu_opt_name "${ARDUINO.${_menu_opt_identifier}.NAME}")
		set(ARDUINO_${_menu_identifier} "${_menu_opt_identifier}")
		set(_sel_menu "\"${_menu_name}\" = \"${_menu_opt_name}\"")
		message(STATUS "Selected board option: ${_sel_menu}")
	endforeach()

	# Display the selected programmer
	set(_prog "${ARDUINO_ARDUINO_PROGRAMMER_NAME} [${ARDUINO_PROGRAMMER_ID}]")
	if (ARDUINO_PROGRAMMER_ID)
		message(STATUS "Selected Arduino Programmer: ${_prog}")
	endif()

	# Set the selection to the parent scope
	_boards_transfer_menu_properties("${namespace}" 
		"${ARDUINO_BOARD_IDENTIFIER}")

	set(ARDUINO_BOARD_IDENTIFIER "${ARDUINO_BOARD_IDENTIFIER}" PARENT_SCOPE)
	set(ARDUINO_PROGRAMMER_ID "${ARDUINO_PROGRAMMER_ID}" PARENT_SCOPE)

endfunction()

#==============================================================================
# This function selects a matching arduino board for the given board in order
# to use it for generating the toolchain for the board. Note that this function
# ensures that the default menu options for the board are utilized in the
# toolchain generation. If requested through the option BOARD_OPTIONS_FILE,
# this function can also generate the boards options in that file. CMake cache
# entries are not updated by this function. This function is used typically
# to generate system code for multiple boards at the same time (e.g. for tests)
# and has almost same functionality as 'SelectArduinoBoard' and hence may in 
# future be merged with 'SelectArduinoBoard'.
#
# After the board is selected successully, the caller can set up the toolchain
# (See BoardToolchain.cmake).
#
# Arguments:
# <namespace> [IN]: The namespace passed to 'IndexArduinoBoards'
# <board> [IN]: The board to be selected. Typically in the format
# [ [ [<packager>.]<architecture>.]<prefix>]
#
# Options:
# BOARD_OPTIONS_FILE: The file path where the board options is to
# be generated. If this option is not specified, the board options
# content is not generated.
# ARDUINO_PROGRAMMER: Arduino programmer to be used. Similar format
# as the <board> argument.
#
# Return Variables:
# ARDUINO_BOARD_IDENTIFIER: Identifier of the selected board
# ARDUINO_PROGRAMMER_ID: Identifier of the selected programmer
# ARDUINO_SEL_MENU_OPT_ID_LIST: List of identifiers corresponding to the
# selected menu options.
#
function(SelectArduinoBoardEx namespace board)

	cmake_parse_arguments(parsed_args ""
		"BOARD_OPTIONS_FILE;ARDUINO_PROGRAMMER" "" ${ARGN})

	if (NOT DEFINED "${namespace}/brd_list")
		error_exit("Boards namespace '${namespace}' not found!!!")
	endif()

	set(pl_namespace "${namespace}/ard_plat")

	# Find the board ID corresponding to the board
	boards_find_board_in_list("${${namespace}/brd_list}" "${board}"
		ARDUINO_BOARD_IDENTIFIER)
	if("${ARDUINO_BOARD_IDENTIFIER}" STREQUAL "")
		error_exit("Board '${board}' not found!!!")
	else()
		list(LENGTH ARDUINO_BOARD_IDENTIFIER _num_boards)
		if (_num_boards GREATER 1)
			string(REPLACE ";" ", " _board_msg "${ARDUINO_BOARD_IDENTIFIER}")
			error_exit("Board '${board}' is ambiguous!!! "
				"Can be set to one of ${_board_msg}!!!")
		endif()
	endif()

	# If ARDUINO_PROGRAMMER is provided, find the programmer identifier
	set(ARDUINO_PROGRAMMER_ID)
	if (NOT "${parsed_args_ARDUINO_PROGRAMMER}" STREQUAL "")
		_boards_find_programmer("${namespace}"
			"${parsed_args_ARDUINO_PROGRAMMER}" ARDUINO_PROGRAMMER_ID)
		if ("${ARDUINO_PROGRAMMER_ID}" STREQUAL "")
			error_exit(
				"Programmer '${parsed_args_ARDUINO_PROGRAMMER}' not found!!!")
		else()
			list(LENGTH ARDUINO_PROGRAMMER_ID _num_prog)
			if (_num_prog GREATER 1)
				string(REPLACE ";" ", " _prog_msg "${ARDUINO_PROGRAMMER_ID}")
				error_exit(
					"Programmer '${parsed_args_ARDUINO_PROGRAMMER}' is "
					"ambiguous!!! Can be set to one of ${_prog_msg}!!!")
			endif()
		endif()
	endif()

	# Generate board options in file and in cache
	if (NOT "${parsed_args_BOARD_OPTIONS_FILE}" STREQUAL "")
		_boards_gen_board_options("${namespace}"
			"${ARDUINO_BOARD_IDENTIFIER}"
			"${ARDUINO_PROGRAMMER_ID}"
			"${parsed_args_BOARD_OPTIONS_FILE}"
			FALSE)
	endif()

	if (CMAKE_VERBOSE_MAKEFILE)
		# Display the selected board
		set(_board "${ARDUINO_BOARD_NAME} [${ARDUINO_BOARD_SEL_ID}]")
		message(STATUS "Selected Arduino Board: ${_board}")
	endif()

	# Display the selected menu options
	foreach(_menu_identifier IN LISTS ARDUINO_SEL_MENU_ID_LIST)
		set(_menu_opt_identifier "${ARDUINO.${_menu_identifier}.SEL_OPT}")
		set(ARDUINO_${_menu_identifier} "${_menu_opt_identifier}")
		if (CMAKE_VERBOSE_MAKEFILE)
			set(_menu_name "${ARDUINO.${_menu_identifier}.NAME}")
			set(_menu_opt_name "${ARDUINO.${_menu_opt_identifier}.NAME}")
			set(_sel_menu "\"${_menu_name}\" = \"${_menu_opt_name}\"")
			message(STATUS "Selected board option: ${_sel_menu}")
		endif()
	endforeach()

	# Set the selection to the parent scope
	_boards_transfer_menu_properties("${namespace}"
		"${ARDUINO_BOARD_IDENTIFIER}")

	set(ARDUINO_BOARD_IDENTIFIER "${ARDUINO_BOARD_IDENTIFIER}" PARENT_SCOPE)
	set(ARDUINO_PROGRAMMER_ID "${ARDUINO_PROGRAMMER_ID}" PARENT_SCOPE)

endfunction()

#==============================================================================
# Check if the board options have changed since used last
# TODO: This function breaks the board options setting through CMake-GUI.
# Any change through CMake-GUI is not detected here, which needs fix.
function(check_board_options_changed _ret_var)

	if (NOT _LAST_USED_ARDUINO_BOARD_OPTIONS_FILE)
		set("${_ret_var}" FALSE PARENT_SCOPE)
		return()
	endif()

	if (ARDUINO_BOARD_OPTIONS_FILE)
		check_same_file("${ARDUINO_BOARD_OPTIONS_FILE}"
			"${_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE}" _same_file)
		if (NOT _same_file)
			set("${_ret_var}" TRUE PARENT_SCOPE)
			return()
		endif()
	endif()

	file(TIMESTAMP "${_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE}" _ts)
	if (NOT "${_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE_TS}" STREQUAL "${_ts}")
		set("${_ret_var}" TRUE PARENT_SCOPE)
	else()
		set("${_ret_var}" FALSE PARENT_SCOPE)
	endif()

endfunction()

#==============================================================================
# Find the one or more board identifiers from the given list that may 
# correspond to the user provided board identifier in 'board_id'. Note that the
# user may provide a shorter identifier that may be unambiguos in his local
# installation context and many not be globally unambiguous (e.g. gemma or
# avr.gemma may mean arduino.avr.gemma or adafruit.avr.gemma). This function is
# typically used to detect any local ambiguity in the board identifier.
# 
function(boards_find_board_in_list board_list board_id return_board_id_list)

	string(REGEX MATCH "\\[(.+)\\]$" match "${board_id}")
	if (match)
		set(board_id "${CMAKE_MATCH_1}")
	endif()

	string(REPLACE "." "\\." _board_id_regex "${board_id}")
	set(brd_id_list "${board_list}")
	list_filter_include_regex(brd_id_list "(^|\\.)${_board_id_regex}$")

	set("${return_board_id_list}" "${brd_id_list}" PARENT_SCOPE)

endfunction()

#==============================================================================
# Find the one or more platform identifiers from the given list that may
# possibly provide the board corresponding to the user provided board
# identifier in 'board_id'. Note that, determining the platform identifier
# from the board identifier is possible only if the board identifier is
# of the format <arch>.<board_prefix> or <packager>.<arch>.<board_prefix>
# and not possible if only <board_prefix> is given. Platform ID can be
# unambiguously determined from <packager>.<arch>, but even if only <arch> 
# is available, this function tries to find all possible packagers in the list
# that provide the board architecture. This function is typically used for
# local package management to install all the possible platforms that may 
# provide the board. Note that, determining whether a platform provides the
# given board is possible only after the installation of the platform.
# 
function(boards_find_platform_in_list pl_list board_id return_pl_id_list)

	string(REGEX MATCH "\\[(.+)\\]$" match "${board_id}")
	if (match)
		set(board_id "${CMAKE_MATCH_1}")
	endif()

	string(REGEX REPLACE "(^|\\.)[^.]+$" "" pl_id "${board_id}")

	platforms_find_platform_in_list("${pl_list}" "${pl_id}"
		"${return_pl_id_list}")
	set("${return_pl_id_list}" "${${return_pl_id_list}}" PARENT_SCOPE)

endfunction()

#==============================================================================
# Implementation functions (Subject to change. DO NOT USE)
#

# Include the board options file, that will have the current board selected
macro(_boards_include_board_options options_file)

	# For the first time, if not explicitly specified, use the generated
	# BoardOptions.cmake
	if (NOT ARDUINO_BOARD_OPTIONS_FILE AND
		NOT _LAST_USED_ARDUINO_BOARD_OPTIONS_FILE AND
		EXISTS "${options_file}")

		set(ARDUINO_BOARD_OPTIONS_FILE "${options_file}")

	endif()

	# Use last used board options file only if there is any change. This is 
	# to allow changing menu options either through BoardOptions.cmake or through
	# CMake GUI. Otherwise, one will be made override of the other which is not
	# user friendly.
	if (NOT ARDUINO_BOARD_OPTIONS_FILE)
		check_board_options_changed(_b_changed)
		if (_b_changed)
			set(ARDUINO_BOARD_OPTIONS_FILE
				"${_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE}")
		endif()
	endif()

	# Include the board options file.
	if (ARDUINO_BOARD_OPTIONS_FILE)
		include("${ARDUINO_BOARD_OPTIONS_FILE}")
	endif()

endmacro()

# Generate board options for the given boards, programmers belonging to
# the given boards namespact. Content is written to the given out_file.
function(_boards_gen_board_options namespace
	brd_list prog_list out_file b_cache)

	# Generate the board options template. If this is the same file as the earlier
	# included ARDUINO_BOARD_OPTIONS_FILE, the file can get overwritten later if
	# there is a change.
	set(_templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Arduino/Templates")
	_boards_configure_file(WRITE
		"${_templates_dir}/BoardOptions/FileHeader.cmake.in"
		_board_options_part1)
	set(_board_options_part1 "${_board_options_part1}")
	set(_board_options_part2 "")
	set(_board_options_part3 "")

	list(LENGTH brd_list _num_boards)

	_boards_gen_board_options_for_boards()
	_boards_gen_board_options_for_programmers()

	_boards_write_board_options("${out_file}")

endfunction()

# Generate board options for the boards list passed in
# _boards_gen_board_options
macro(_boards_gen_board_options_for_boards)

	# All the boards have been indexed. Loop through the list and add
	# board options for the boards
	set(_last_pl_id)
	set(_sel_board_id)

	foreach(_board_id IN LISTS brd_list)

		# Init some variables
		set(brd_namespace "${${namespace}.${_board_id}/brd_namespace}")
		set(_board_prefix "${${namespace}.${_board_id}/brd_prefix}")
		set(pl_id "${${namespace}.${_board_id}/pl_id}")
		set(_board_distinct_id "${${namespace}.${_board_id}/distinct_id}")
		set(_board_short_id "${${namespace}.${_board_id}/short_id}")

		# Append the board to the ARDUINO_BOARD cache entry
		if (NOT _last_pl_id STREQUAL pl_id)
			platforms_get_property("${pl_namespace}" "${pl_id}" "name" _pl_name)
			if (b_cache)
				set_property(CACHE ARDUINO_BOARD APPEND PROPERTY STRINGS
					"**** ${_pl_name} ****")
			endif()
			_boards_configure_file(APPEND
				"${_templates_dir}/BoardOptions/BoardHeader.cmake.in"
				_board_options_part1)
			set(_last_pl_id "${pl_id}")
		endif()

		properties_get_value("${brd_namespace}" "${_board_prefix}.name"
			_board_name)
		set(_board_name_in_menu "${_board_name} [${_board_distinct_id}]")
		if (b_cache)
			set_property(CACHE ARDUINO_BOARD APPEND PROPERTY STRINGS
				"${_board_name_in_menu}")
		endif()

		# Is this the selected board for the project build?
		if ("${ARDUINO_BOARD_IDENTIFIER}" STREQUAL "${_board_id}")
			set(ARDUINO_BOARD "${_board_name_in_menu}" CACHE STRING
					"Arduino board for which the project is build for" FORCE)
			set(is_selected_board TRUE)
			set(_sel_board_id "${_board_distinct_id}")
			set(_sel_board_name "${_board_name}")
			set(_board_sel_comment "")
		else()
			set(is_selected_board FALSE)
			set(_board_sel_comment "# ")
		endif()

		_boards_configure_file(APPEND
			"${_templates_dir}/BoardOptions/BoardSel.cmake.in"
			_board_options_part1)

		# Populate the menu options of the board in order to add the menu entry
		# in the cache, along with its options
		properties_get_list("${brd_namespace}"
			"^${_board_prefix}\\.menu\\.[^.]+\\.[^.]+$" _menu_opt_prop_list)

		set(_menu_identifier_list)
		foreach(_menu_opt_prop IN LISTS _menu_opt_prop_list)

			# Find the menu where this menu option should go.
			string(REGEX MATCH "^${_board_prefix}\\.menu\\.([^.]+)\\.([^.]+)$" 
				match "${_menu_opt_prop}")
			set(_menu_prefix "${CMAKE_MATCH_1}")
			set(_menu_opt_prefix "${CMAKE_MATCH_2}")
			properties_get_value("${brd_namespace}" "menu.${_menu_prefix}"
				_menu_name QUIET)
			if (NOT _menu_name)
				set(_menu_name "${_menu_prefix}")
			endif()
			properties_get_value("${brd_namespace}" 
				"${_board_prefix}.menu.${_menu_prefix}.${_menu_opt_prefix}"
				_menu_opt_name)

			# Check the identifier or the cache used to define the selection of
			# this option and select in menu if defined. Otherwise select the
			# first option as the default option
			# Note: Due to compatibilty of Older BoardOptions.cmake while
			# avoiding the ambiguity of identifier names across boards, we
			# end of finding various identifiers and choose the best one.
			string(MAKE_C_IDENTIFIER
				"${_board_short_id}.menu.${_menu_prefix}.${_menu_opt_prefix}"
				_menu_opt_identifier)
			string(MAKE_C_IDENTIFIER
				"${_board_id}.menu.${_menu_prefix}.${_menu_opt_prefix}"
				_menu_long_opt_identifier)
			string(MAKE_C_IDENTIFIER
				"${_board_distinct_id}.menu.${_menu_prefix}.${_menu_opt_prefix}"
				_menu_distinct_opt_identifier)
			string(TOUPPER "${_menu_opt_identifier}" _menu_opt_identifier)
			string(TOUPPER "${_menu_long_opt_identifier}"
				_menu_long_opt_identifier)
			string(TOUPPER "${_menu_distinct_opt_identifier}"
				_menu_distinct_opt_identifier)

			set(ARDUINO.${_menu_opt_identifier}.NAME "${_menu_opt_name}")
			set(ARDUINO.${_menu_opt_identifier}.DISTINCT_ID
				"${_menu_distinct_opt_identifier}")

			string(MAKE_C_IDENTIFIER "${_board_short_id}.menu.${_menu_prefix}"
				_menu_identifier)
			string(TOUPPER "${_menu_identifier}" _menu_identifier)
			set(ARDUINO.${_menu_identifier}.NAME "${_menu_name}")

			set(_menu_var_name "Arduino(${_board_distinct_id})/${_menu_name}")

			if (ARDUINO_${_menu_long_opt_identifier})
				if (b_cache)
					set("${_menu_var_name}" "${_menu_opt_name}" CACHE STRING
						"Select Arduino Board option \"${_menu_name}\"" FORCE)
				endif()
				set(ARDUINO.${_menu_identifier}.SEL_OPT
					"${_menu_opt_identifier}")
				set(ARDUINO.${_menu_identifier}.SEL_OPT_LONG TRUE)
			elseif (ARDUINO_${_menu_opt_identifier} AND
				NOT "${ARDUINO.${_menu_identifier}.SEL_OPT_LONG}")
				if (b_cache)
					set("${_menu_var_name}" "${_menu_opt_name}" CACHE STRING
						"Select Arduino Board option \"${_menu_name}\"" FORCE)
				endif()
				set(ARDUINO.${_menu_identifier}.SEL_OPT
					"${_menu_opt_identifier}")
			elseif ("${${_menu_var_name}}" STREQUAL "${_menu_opt_name}")
				set(ARDUINO.${_menu_identifier}.SEL_OPT
					"${_menu_opt_identifier}")
			else()
				# Select the first option as the default option
				if (b_cache)
					set("${_menu_var_name}" "${_menu_opt_name}" CACHE STRING
						"Select Arduino Board option \"${_menu_name}\"")
				endif()
				if (NOT DEFINED ARDUINO.${_menu_identifier}.SEL_OPT)
					set(ARDUINO.${_menu_identifier}.SEL_OPT
						"${_menu_opt_identifier}")
				endif()
			endif()

			# Set the visibility of this menu containing this option based on whether
			# the board is selected
			if (b_cache)
				if ("${is_selected_board}")
					set_property(CACHE "${_menu_var_name}" PROPERTY
						TYPE "STRING")
				else()
					set_property(CACHE "${_menu_var_name}" PROPERTY
						TYPE "INTERNAL")
				endif()
			endif()
			# Add the menu option to the menu list, so as to define the identifier
			# later corresponding to its selected menu option
			list(FIND _menu_identifier_list "${_menu_identifier}" _menu_idx)
			if ("${_menu_idx}" EQUAL -1)
				list(APPEND _menu_identifier_list "${_menu_identifier}")
				set("ARDUINO.${_menu_identifier}.OPTIONS")
				if (b_cache)
					set_property(CACHE "${_menu_var_name}" PROPERTY STRINGS "")
				endif()
			endif()

			# Append the option as the menu item and the list
			if (b_cache)
				set_property(CACHE "${_menu_var_name}" APPEND PROPERTY STRINGS
					"${_menu_opt_name}")
			endif()
			list(APPEND "ARDUINO.${_menu_identifier}.OPTIONS"
				"${_menu_opt_identifier}")

		endforeach()

		_boards_configure_file(APPEND
			"${_templates_dir}/BoardOptions/MenuBoardHdr.cmake.in"
			_board_options_part2)

		# Generate content to a template board options file
		foreach(_menu_identifier IN LISTS _menu_identifier_list)
			set(_menu_name "${ARDUINO.${_menu_identifier}.NAME}")
			_boards_configure_file(APPEND
				"${_templates_dir}/BoardOptions/MenuHeader.cmake.in"
				_board_options_part2)
			foreach(_option_id IN LISTS ARDUINO.${_menu_identifier}.OPTIONS)
				set(_menu_opt_name "${ARDUINO.${_option_id}.NAME}")
				set(_menu_distinct_id "${ARDUINO.${_option_id}.DISTINCT_ID}")
				if ("${ARDUINO.${_menu_identifier}.SEL_OPT}" STREQUAL
					"${_option_id}")
					set(_menu_opt_sel_comment "")
				else()
					set(_menu_opt_sel_comment "# ")
				endif()

				# If there wont be ambiguity, choose a shorter ID for
				# the menu option, and otherwise use ambiguous free ID
				if (_num_boards GREATER 1)
					set(_menu_opt_identifier "${_menu_distinct_id}")
				else()
					set(_menu_opt_identifier "${_option_id}")
				endif()

				_boards_configure_file(APPEND
					"${_templates_dir}/BoardOptions/Menuoption.cmake.in"
					_board_options_part2)
			endforeach()
		endforeach()

		if (${is_selected_board})
			set(_sel_board_menu_identifier_list "${_menu_identifier_list}")
		endif()

	endforeach()

	set(ARDUINO_BOARD_SEL_ID "${_sel_board_id}" PARENT_SCOPE)
	set(ARDUINO_BOARD_NAME "${_sel_board_name}" PARENT_SCOPE)

	# Return each menu item and its selected option back to the caller
	foreach(_menu_identifier IN LISTS _sel_board_menu_identifier_list)
		set("ARDUINO.${_menu_identifier}.NAME"
			"${ARDUINO.${_menu_identifier}.NAME}" PARENT_SCOPE)
		set("ARDUINO.${_menu_identifier}.SEL_OPT"
			"${ARDUINO.${_menu_identifier}.SEL_OPT}" PARENT_SCOPE)
		set(_menu_opt_identifier "${ARDUINO.${_menu_identifier}.SEL_OPT}")
		set("ARDUINO.${_menu_opt_identifier}.NAME"
			"${ARDUINO.${_menu_opt_identifier}.NAME}" PARENT_SCOPE)
	endforeach()

	set(ARDUINO_SEL_MENU_ID_LIST "${_sel_board_menu_identifier_list}"
		PARENT_SCOPE)

endmacro()

# Generate board options for the programmers list passed in
# _boards_gen_board_options
macro(_boards_gen_board_options_for_programmers)

	# All the programmers have been indexed. Loop through the list and add
	# board options for the programmers
	set(_last_pl_id)
	set(_sel_prog_id)
	foreach(_prog_id IN LISTS "${namespace}/prog_list")

		# Init some variables
		set(prog_namespace "${${namespace}/prog.${_prog_id}/prog_namespace}")
		set(_prog_prefix "${${namespace}/prog.${_prog_id}/prog_prefix}")
		set(pl_id "${${namespace}/prog.${_prog_id}/pl_id}")
		set(_prog_distinct_id "${${namespace}/prog.${_prog_id}/distinct_id}")

		# Append the programmer to the ARDUINO_PROGRAMMER cache entry
		if (NOT _last_pl_id STREQUAL pl_id)
			platforms_get_property("${pl_namespace}" "${pl_id}" "name"
				_pl_name)
			if (b_cache)
				set_property(CACHE ARDUINO_PROGRAMMER APPEND PROPERTY STRINGS
					"**** ${_pl_name} ****")
			endif()
			_boards_configure_file(APPEND
				"${_templates_dir}/BoardOptions/ProgHeader.cmake.in"
				_board_options_part3)
			set(_last_pl_id "${pl_id}")
		endif()

		properties_get_value("${prog_namespace}" "${_prog_prefix}.name"
			_prog_name)
		set(_prog_name_in_menu "${_prog_name} [${_prog_distinct_id}]")
		if (b_cache)
			set_property(CACHE ARDUINO_PROGRAMMER APPEND PROPERTY STRINGS
				${_prog_name_in_menu})
		endif()

		# Is this the selected programmer for the project build?
		if ("${ARDUINO_PROGRAMMER_ID}" STREQUAL "${_prog_id}")
			set(ARDUINO_PROGRAMMER "${_prog_name_in_menu}" CACHE STRING
				"Arduino programmer used to upload program or burn bootloader"
				FORCE)
			set(_sel_prog_id "${_prog_distinct_id}")
			set(_sel_prog_name "${_prog_name}")
			set(_prog_sel_comment "")
		else()
			set(_prog_sel_comment "# ")
		endif()

		_boards_configure_file(APPEND
			"${_templates_dir}/BoardOptions/ProgSel.cmake.in"
			_board_options_part3)

	endforeach()

	set(ARDUINO_PROGRAMMER_SEL_ID "${_sel_prog_id}" PARENT_SCOPE)
	set(ARDUINO_PROGRAMMER_NAME "${_sel_prog_name}" PARENT_SCOPE)

endmacro()

# Write the template board options file
function(_boards_write_board_options out_file)

	# Write to BoardOptions.cmake template
	set(_old_board_options_content)
	if (EXISTS "${out_file}")
		file (READ "${out_file}" _old_board_options_content)
	endif()
	set(_new_board_options_content
		"${_board_options_part1}${_board_options_part2}${_board_options_part3}")
	if (NOT _old_board_options_content STREQUAL _new_board_options_content)
		if (EXISTS "${out_file}")
			file(REMOVE "${out_file}.bak")
			file(RENAME "${out_file}" "${out_file}.bak")
		endif()
		file(WRITE "${out_file}" "${_new_board_options_content}")
	endif()

endfunction()

# Used to configure a string that is part of the generated BoardOptions.txt,
# and append it to the given file
function(_boards_configure_file _opt_writer_or_append in_file out_str)
	file(READ "${in_file}" _in_file_content)
	string(CONFIGURE "${_in_file_content}" _out_content @ONLY)
	if ("${_opt_writer_or_append}" STREQUAL WRITE)
		set("${out_str}" "${_out_content}" PARENT_SCOPE)
	else()
		string_append("${out_str}" "${_out_content}")
		set("${out_str}" "${${out_str}}" PARENT_SCOPE)
	endif()
endfunction()

# Find the given programmer ID in the namespace
function(_boards_find_programmer namespace prog_id return_prog_id_list)

	string(REGEX MATCH "\\[(.+)\\]$" match "${prog_id}")
	if (match)
		set(prog_id "${CMAKE_MATCH_1}")
	endif()

	string(REPLACE "." "\\." _prog_id_regex "${prog_id}")
	set(prog_id_list "${${namespace}/prog_list}")
	list_filter_include_regex(prog_id_list "(^|\\.)${_prog_id_regex}$")

	set("${return_prog_id_list}" "${prog_id_list}" PARENT_SCOPE)

endfunction()

# Transfer the menu properties of the given board, assuming that the options
# have been selected and the corresponding CMake variables defined
macro(_boards_transfer_menu_properties ns board_id)

	set(brd_namespace "${${namespace}.${board_id}/brd_namespace}")
	set(_board_prefix "${${ns}.${board_id}/brd_prefix}")
	set(_board_short_id "${${ns}.${board_id}/short_id}")

	boards_get_property_list("${ns}" "${board_id}"
		"menu\\.([^.]+)\\.([^.]+)\\.?(.*)" _menu_options_prop_list)
	
	# message("_board_options:${_board_options}")
	set(ARDUINO_SEL_MENU_OPT_ID_LIST "")
	foreach(_menu_option_prop IN LISTS _menu_options_prop_list)

		string(REGEX MATCH "menu\\.([^.]+)\\.([^.]+)\\.?(.*)" match
			"${_menu_option_prop}")
		set(_menu_prefix "${CMAKE_MATCH_1}")
		set(_menu_opt_prefix "${CMAKE_MATCH_2}")
		set(_menu_opt_action "${CMAKE_MATCH_3}")
		string(MAKE_C_IDENTIFIER
			"ARDUINO_${_board_short_id}.menu.${_menu_prefix}"
			SELECTED_MENU_OPTION_VAR)
		string(TOUPPER "${SELECTED_MENU_OPTION_VAR}" SELECTED_MENU_OPTION_VAR)
		string(MAKE_C_IDENTIFIER
			"${_board_short_id}.menu.${_menu_prefix}.${_menu_opt_prefix}"
			EXPECTED_MENU_OPTION)
		string(TOUPPER "${EXPECTED_MENU_OPTION}" EXPECTED_MENU_OPTION)

		# message("${SELECTED_MENU_OPTION_VAR}:${${SELECTED_MENU_OPTION_VAR}}")
		# If no value selected for the menu, select the default value
		if ("${${SELECTED_MENU_OPTION_VAR}}" STREQUAL "" AND
			"${_menu_opt_action}" STREQUAL "")
			set("${SELECTED_MENU_OPTION_VAR}" "${EXPECTED_MENU_OPTION}")
		endif()

		# message("match:${${SELECTED_MENU_OPTION_VAR}}:${EXPECTED_MENU_OPTION}")
		if ("${${SELECTED_MENU_OPTION_VAR}}" STREQUAL "${EXPECTED_MENU_OPTION}"
			AND NOT "${_menu_opt_action}" STREQUAL "")

			# property of selected menu option of the selected board
			boards_get_property("${ns}" "${board_id}"
				"${_menu_option_prop}" _prop_value)
			# message("MENU: ${_menu_opt_action} => ${_prop_value}")
			properties_set_value("${brd_namespace}"
				"${_board_prefix}.${_menu_opt_action}"
				"${_prop_value}")
			list(APPEND ARDUINO_SEL_MENU_OPT_ID_LIST
				"ARDUINO_${EXPECTED_MENU_OPTION}")
		endif()

	endforeach()

	boards_set_parent_scope("${ns}")
	if (NOT "${ARDUINO_SEL_MENU_OPT_ID_LIST}" STREQUAL "")
		list(REMOVE_DUPLICATES ARDUINO_SEL_MENU_OPT_ID_LIST)
	endif()
	set(ARDUINO_SEL_MENU_OPT_ID_LIST "${ARDUINO_SEL_MENU_OPT_ID_LIST}"
		PARENT_SCOPE)

endmacro()

# Add last used board options to configure dependency to ensure that
# cmake is reconfigured on any change to the board options. This is needed
# because we do not include board options file when skipping board indexing
# (in case board options did not change).
if (_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE)
	add_configure_dependency("${_LAST_USED_ARDUINO_BOARD_OPTIONS_FILE}")
endif()
