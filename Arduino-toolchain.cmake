# Copyright (c) 2020 Arduino CMake Toolchain

#=============================================================================
# A toolchain for the Arduino compatile boards.
# Please refer to README.md for the usage.

# If the version of CMake used is below 3.7.0, exit with error.
#
# Intended to support CMake version 3.0.0, but there are limitations which
# requires a minimum CMake version of 3.7.0. However, wherever possible, the
# toolchain remains compatible with 3.0.0, looking for some workarounds for
# the limitations in the future. The limitations are captured below.
#
# Version below 3.2.0 has no support for continue() command. Can be fixed.
#
# Version below 3.4.0 has no support for target properties BINARY_DIR,
# SOURCE_DIR etc. These are required in target command generator expressions.
#
# Version below 3.6.0 has issues in identifying try_compile output for 
# static library. So there are some errors during the configuration, but
# may still possibly work.
#
# Version below 3.7.0 has no support for CMAKE_SYSTEM_CUSTOM_CODE, which
# is required when there is some dynamic information, like Board options,
# that needs to be included in the toolchain. Here just including the user
# provided path will not work, because the user variables, cache or root
# binary directory path etc. are not passed to try_compile.

if (CMAKE_VERSION VERSION_LESS 3.7.0)
	message(FATAL_ERROR "CMake version below 3.7.0 unsupported!!!")
endif()

# Save the policy state. We will restore it at the end.
cmake_policy(PUSH)

# Set policy to above 3.0.0
cmake_policy(VERSION 3.0.0)

# Interpret if() arguments without quotes as variables/keywords
if (NOT CMAKE_VERSION VERSION_LESS 3.1)
	cmake_policy(SET CMP0054 NEW)
endif()

#*****************************************************************************
# Set system name and basic information
set(CMAKE_SYSTEM_NAME "Arduino")

# Set module path to enable local modules search
set(ARDUINO_TOOLCHAIN_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(_ARDUINO_TOOLCHAIN_PARENT "${CMAKE_PARENT_LIST_FILE}")
set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" "${CMAKE_CURRENT_LIST_DIR}")
set (ARDUINO_TOOLCHAIN_VERSION "1.1")

# Include modules
include(Arduino/System/PackagePathIndex)
include(Arduino/System/PackageIndex)
include(Arduino/System/BoardsIndex)
include(Arduino/System/BoardToolchain)
include(Arduino/System/BoardBuildTargets)
include(Arduino/PackageManager/BoardsManager)

#*****************************************************************************
# For improved speed, indexing and setup of boards is done only once during a
# cmake invocation. However, this toolchain file is included multiple times
# in multiple contexts (system determination context, separate context for
# each try compile etc.). After indexing, the selected board's toolchain
# info is configured to a generated file that gets included in every other
# inclusion of this toolchain.
if (NOT _BOARD_SETUP_COMPLETED)
	get_property(_in_try_compile GLOBAL PROPERTY IN_TRY_COMPILE)
	# IN_TRY_COMPILE check seems to be not enough. Checking for parent
	# script works, but might be using undocumented feature?
	get_filename_component(parent_script "${_ARDUINO_TOOLCHAIN_PARENT}"
		NAME_WE)
	if (parent_script STREQUAL "CMakeSystem")
		check_board_options_changed(_b_changed)
		if (NOT _b_changed)
			set(_BOARD_SETUP_COMPLETED TRUE)
		endif()
	elseif(ARDUINO_SYSTEM_FILE)
		# If passing with pre-generated Arduino system code
		set(_BOARD_SETUP_COMPLETED TRUE)
		set(CMAKE_SYSTEM_CUSTOM_CODE
			"include(\"${ARDUINO_SYSTEM_FILE}\")"
		)
	endif()
endif()

	# Wrap it in a function so that the scope of variables are within
	# the function
function(IndexBoardsAndSetupBoard)

	# Find ARDUINO_INSTALL_PATH, ARDUINO_PACKAGE_PATH and
	# ARDUNIO_SKETCHBOOK_PATH
	InitializeArduinoPackagePathList()

	# Download and index the packages, and install the platforms from the
	# given board manager URL list if any
	set(_json_file "")
	set(_install_url "")
	set(_ref_url_list)
	if (NOT "${ARDUINO_BOARD_MANAGER_URL}" STREQUAL "")

		set(ARDUINO_BOARD_MANAGER_URL "${ARDUINO_BOARD_MANAGER_URL}"
			CACHE STRING "Arduino Board Manager URL" FORCE)

		# Split comma seperated list of URLs
		string(REPLACE "," ";" _url_list
			"${ARDUINO_BOARD_MANAGER_URL}")

		# First one in the list should contain the required board
		list(GET _url_list 0 _install_url)
		set(_ref_url_list "${_url_list}")
		list(REMOVE_AT _ref_url_list 0)

		# Download the package of the install URL
		if (NOT EXISTS "${_install_url}")
			BoardManager_DownloadPackage(${_install_url}
				JSON_FILES_LIST _json_file REQUIRED)
		else()
			set(_json_file "${_install_url}")
		endif()
		IndexArduinoPackages(${_json_file})

		set(ARDUINO_ENABLE_PACKAGE_MANAGER TRUE)

	else()

		IndexArduinoPackages()	

	endif()

	if (NOT "${ARDUINO_BOARD_MANAGER_REF_URL}" STREQUAL "")
		set(ARDUINO_BOARD_MANAGER_REF_URL "${ARDUINO_BOARD_MANAGER_REF_URL}"
			CACHE STRING
			"Arduino Board Manager URL only for reference platforms/tools"
			FORCE)
	endif()

	list(APPEND _ref_url_list ${ARDUINO_BOARD_MANAGER_REF_URL})
	# Download all other reference only URLs
	if (NOT "${_ref_url_list}" STREQUAL "")
		BoardManager_DownloadPackage(${_ref_url_list}
			JSON_FILES_LIST _ref_json_files)
		if (_ref_json_files)
			IndexArduinoPackages(${_ref_json_files})
		endif()
	endif()

	if (DEFINED ARDUINO_NO_INSTALLED_REFERENCES)
		set(ARDUINO_NO_INSTALLED_REFERENCES
			"${ARDUINO_NO_INSTALLED_REFERENCES}" CACHE STRING
			"Set this option to ignore any installed platforms as references"
			FORCE)
	endif()

	# Index all the pre-installed packages
	if (NOT "${ARDUINO_BOARD_MANAGER_URL}" STREQUAL "" AND
		NOT "${ARDUINO_NO_INSTALLED_REFERENCES}")

		IndexArduinoPackages()

	endif()

	# Find the necessary platforms
	set(_needed_pl_list)
	set(_report_error TRUE)
	packages_find_platforms(pl_list JSON_FILES ${_json_file}
		INSTALL_PREFERRED)
	if(NOT "${ARDUINO_PLATFORM}" STREQUAL "")

		# Find the platforms that can be installed from the board given
		platforms_find_platform_in_list("${pl_list}" "${ARDUINO_PLATFORM}"
			_needed_pl_list)

	elseif (NOT "${ARDUINO_BOARD}" STREQUAL "")

		# Find the platforms that can be installed from the board given
		boards_find_platform_in_list("${pl_list}" "${ARDUINO_BOARD}"
			_needed_pl_list)
			
	elseif (NOT "${ARDUINO_BOARD_MANAGER_URL}" STREQUAL "")

		# install all the platforms in the board manager URL, if board
		# or platform is not specified explicitly
		set(_needed_pl_list "${pl_list}")

	else()

		# In case of no mention of board or platform or board manager URL,
		# Package management is used only for installing reference tools
		# and platforms. So no need to report error.
		set(_report_error FALSE)
	endif()

	if(NOT _needed_pl_list AND _report_error)
		#message("Available platforms: ${pl_list}")
		#message(WARNING 
		#	"Not sure which Arduino platform is needed! Provide the correct "
		#	"board manager URL of the board using the option "
		#	"-DARDUINO_BOARD_MANAGER_URL=<URL>.")
	endif()

	# Filter out those that are not installed
	set(_install_pl_list "")
	foreach(_needed_pl IN LISTS _needed_pl_list)
		packages_get_platform_property("${_needed_pl}" "/installed"
			_b_installed)
		if (NOT _b_installed)
			list(APPEND _install_pl_list "${_needed_pl}")
		endif()
	endforeach()

	# Install the necessary platforms. TODO Unnecessary installation for
	# boards that are already installed
	if (_install_pl_list)
		if (ARDUINO_ENABLE_PACKAGE_MANAGER)
			foreach(pl_id IN LISTS _install_pl_list)
				BoardManager_InstallPlatform("${pl_id}" RESULT_VARIABLE
					_result)
				if (NOT _result EQUAL 0)
					message(WARNING "Installing platform '${pl_id}' failed!!! "
						"Corresponding boards won't be available for tests.")
				endif()
			endforeach()
		else()
			#string(REPLACE ";" ", " _install_pl_list "${_install_pl_list}")
			#message(WARNING
			#	"Need to install the Arduino boards ${_install_pl_list}. "
			#	"Try with the option -DARDUINO_ENABLE_PACKAGE_MANAGER=TRUE, "
			#	"for local installation in the build directory.")
		endif()
	endif()

	# Index all the installed platforms and boards
	IndexArduinoBoards("ard_boards" JSON_FILES ${_json_file})

	# Select one of the boards as selected in BoardOptions.cmake or in
	# cmake-gui or other mechanisms. If none selected, this call will
	# generate options in CMake Cache and BoardOptions.cmake to allow
	# later selection of the board
	SelectArduinoBoard(ard_boards)
	set(ARDUINO_BOARD_IDENTIFIER "${ARDUINO_BOARD_IDENTIFIER}"
		PARENT_SCOPE)
	list(LENGTH ARDUINO_BOARD_IDENTIFIER _num_board_ids)

	# if a board is selected, setup a toolchain for the board
	# Else, Arduino-Determine.cmake will print an error message later
	# Arduino-Determine.cmake.
	if (_num_board_ids EQUAL 1)
		SetupBoardToolchain(ard_boards "${ARDUINO_BOARD_IDENTIFIER}"
			"${CMAKE_BINARY_DIR}")
	endif()

endfunction()

if (NOT _BOARD_SETUP_COMPLETED)

	IndexBoardsAndSetupBoard()
	set(CMAKE_SYSTEM_CUSTOM_CODE
		"include(\"${CMAKE_BINARY_DIR}/ArduinoSystem.cmake\")"
	)
	set (_BOARD_SETUP_COMPLETED TRUE)

endif()

# Search for programs in the build host directories
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
# For libraries and headers in the target directories
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# Do not try to link during the configure time, due to the dependency on the
# core for some platforms, which we do not have a target yet.
if (NOT "${ARDUINO_TRY_STANDALONE_TOOLCHAIN}")
	set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
endif()

cmake_policy(POP)
