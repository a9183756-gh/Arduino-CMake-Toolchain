# Copyright (c) 2020 Arduino CMake Toolchain

# No need to include this recursively
if(_PACKAGE_PATH_INDEX_INCLUDED)
	return()
endif()
set(_PACKAGE_PATH_INDEX_INCLUDED TRUE)

#*****************************************************************************
# Find the standard installation and package folders of Ardunio. Currently
# this toolchain has a dependency of Arduino IDE installation and any arduino
# board management through arduino IDE. In future this dependency might be 
# removed, and instead a mechanism will be provided to download an arduino
# platform (like avr, esp32) and board management on the go.
# 
# The identified paths are stored in cached ARDUINO_* variables (see below).
#
function(InitializeArduinoPackagePathList)

	if (${CMAKE_HOST_APPLE})

		set(install_search_paths "$ENV{HOME}/Applications" /Applications /Developer/Applications
			/sw /opt/local)
		set(install_path_suffixes Arduino.app/Contents/Java Arduino.app/Contents/Resources/Java)

		file(GLOB package_search_paths "$ENV{HOME}/Library/Arduino15")
		set(package_path_suffixes "")

		file(GLOB sketchbook_search_paths "$ENV{HOME}/Library/Arduino15")
		set(sketchbook_path_suffixes "")

	elseif (${CMAKE_HOST_UNIX}) # Probably Linux or some unix-like

		file(GLOB install_search_paths /usr/share/arduino* /opt/local/arduino* /opt/arduino*
			/usr/local/share/arduino* "$ENV{HOME}/opt/arduino*")
		set(install_path_suffixes "")

		file(GLOB package_search_paths "$ENV{HOME}/.arduino15")
		set(package_path_suffixes "")

		file(GLOB sketchbook_search_paths "$ENV{HOME}/.arduino15")
		set(sketchbook_path_suffixes "")

	elseif (${CMAKE_HOST_WIN32})

		set(Prog86Path "ProgramFiles(x86)")
		set(install_search_paths "$ENV{${Prog86Path}}/Arduino" "$ENV{ProgramFiles}/Arduino")
		set(install_path_suffixes "")

		file(GLOB package_search_paths "$ENV{LOCALAPPDATA}/Arduino15")
		set(package_path_suffixes "")

		file(GLOB sketchbook_search_paths "$ENV{LOCALAPPDATA}/Arduino15"
			"[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders;Personal]/ArduinoData")
		set(sketchbook_path_suffixes "")
	else()

		message(FATAL_ERROR "Host system ${CMAKE_HOST_SYSTEM} is not supported!!!")

	endif()

	# Search for Arduino install path
	find_path(ARDUINO_INSTALL_PATH
			NAMES lib/version.txt
			PATH_SUFFIXES ${install_path_suffixes}
			HINTS ${install_search_paths}
			NO_DEFAULT_PATH
			NO_CMAKE_FIND_ROOT_PATH
			DOC "Path to Arduino IDE installation")
	# message("ARDUINO_INSTALL_PATH:${ARDUINO_INSTALL_PATH}")
	if (NOT ARDUINO_INSTALL_PATH AND NOT "${ARDUINO_ENABLE_PACKAGE_MANAGER}")
		message(FATAL_ERROR "Arduino IDE installation is not found!!!\n"
			"Use -DARDUINO_INSTALL_PATH=<path> to manually specify the path (OR)\n"
			"Use -DARDUINO_BOARD=<board_id> to try downloading the board\n")
	endif()

	# Search for Arduino library path
	find_path(ARDUINO_PACKAGE_PATH
			NAMES package_index.json
			PATH_SUFFIXES ${package_path_suffixes}
			HINTS ${package_search_paths}
			NO_DEFAULT_PATH
			NO_CMAKE_FIND_ROOT_PATH
			DOC "Path to Arduino platform packages")
	# message("ARDUINO_PACKAGE_PATH:${ARDUINO_PACKAGE_PATH}")

	# Search for sketchbook path
	find_file(ARDUINO_PREFERENCE_FILE
			NAMES preferences.txt
			PATH_SUFFIXES ${sketchbook_path_suffixes}
			HINTS ${sketchbook_search_paths}
			NO_DEFAULT_PATH
			NO_CMAKE_FIND_ROOT_PATH)
	# message("ARDUINO_PREFERENCE_FILE:${ARDUINO_PREFERENCE_FILE}")
	if (ARDUINO_PREFERENCE_FILE)
		file(STRINGS "${ARDUINO_PREFERENCE_FILE}" preferences)
		list_filter_include_regex(preferences "sketchbook.path=.*")
		string(REGEX MATCH "sketchbook.path=(.*)" match "${preferences}")
		if (match)
			file(TO_CMAKE_PATH "${CMAKE_MATCH_1}" ARDUINO_SKETCHBOOK_PATH)
			set(ARDUINO_SKETCHBOOK_PATH "${ARDUINO_SKETCHBOOK_PATH}"
				CACHE PATH "Path to Arduino Sketchbook")
		endif()
	endif()
	# message("ARDUINO_SKETCHBOOK_PATH:${ARDUINO_SKETCHBOOK_PATH}")

	# Arduino local package management path
	if (NOT ARDUINO_PACKAGE_MANAGER_PATH)
		set(ARDUINO_PACKAGE_MANAGER_PATH
			"${CMAKE_BINARY_DIR}/_pkg_mgr")
	endif()
	set(ARDUINO_PACKAGE_MANAGER_PATH "${ARDUINO_PACKAGE_MANAGER_PATH}"
		CACHE PATH "Path to local installed packages")
	if (NOT ARDUINO_PKG_MGR_DL_CACHE)
		set(ARDUINO_PKG_MGR_DL_CACHE
			"${ARDUINO_PACKAGE_MANAGER_PATH}/downloads")
	endif()
	set(ARDUINO_PKG_MGR_DL_CACHE "${ARDUINO_PKG_MGR_DL_CACHE}"
        CACHE PATH "Path to package manager downloads")

endfunction()
