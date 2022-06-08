# Copyright (c) 2020 Arduino CMake Toolchain

#=============================================================================
# A toolchain for the Arduino compatile boards.
# Please refer to README.md for the usage.

# If the version of CMake used is below 3.9, exit with error.
# Version below 3.9.0 has no proper support for INTERPROCEDURAL_OPTIMIZATION.
#
# Version below 3.7.0 has no support for CMAKE_SYSTEM_CUSTOM_CODE, which
# is required when there is some dynamic information, like Board options,
# that needs to be included in the toolchain. Here just including the user
# provided path will not work, because the user variables, cache or root
# binary directory path etc. are not passed to try_compile.

#[[
CLang building works only with llvm toolchain.

todo: CMAKE_<LANG>_FLAGS_INIT¶

USE_CLANG_AS_COMPILER - ON means CLang, OFF means GCC

GCC_COMPILERS_IN_USR_BIN - ON - GCC compilers are in /usr/bin, OFF - GCC compilers are in the dedicated dir
GCC_PREFIX_DOUBLE_USE - ON - gcc compilers name begins with "target double", OFF - doesn't
GCC_SUFFIX_VERSION_USE - ON means the tools will be called like gcc-11, OFF means tools will not have the postfix

LLVM_TOOLS_IN_USR_BIN - ON - LLVM compilers are in /usr/bin, OFF - LLVM compilers are in the dedicated dir
LLVM_SUFFIX_VERSION_USE - ON means the tools will be called like llvm-readelf-14 and clang-14, OFF means tools will not have the postfix
#]]

cmake_minimum_required(VERSION 3.9 FATAL_ERROR)

set(USE_CLANG_AS_COMPILER ON)
#set(REST_OF_TOOLCHAIN_IS_LLVM ON)
set(GCC_PREFIX_DOUBLE_USE ON)
set(GCC_COMPILERS_IN_USR_BIN OFF)
set(GCC_SUFFIX_VERSION_USE OFF)


if(NOT DEFINED CMAKE_HOST_WIN32)
	if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
		set(CMAKE_HOST_WIN32 ON)
	else()
		set(CMAKE_HOST_WIN32 OFF)
	endif()
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
	if(NOT DEFINED llvm_Version)
		set(llvm_Version 14)
	endif()

	if(NOT DEFINED LLVM_SUFFIX_VERSION_USE)
		set(LLVM_SUFFIX_VERSION_USE OFF)
	endif()
	if(NOT DEFINED GCC_PREFIX_DOUBLE_USE)
		set(GCC_PREFIX_DOUBLE_USE OFF)
	endif()
	if(NOT DEFINED GCC_SUFFIX_VERSION_USE)
		set(GCC_SUFFIX_VERSION_USE OFF)
	endif()
	if(NOT DEFINED GCC_SUFFIX_FLAVOUR_USE)
		set(GCC_SUFFIX_FLAVOUR_USE OFF)
	endif()

	get_filename_component(DUMP_DIR "${CMAKE_CURRENT_LIST_DIR}" DIRECTORY)  # CACHE PATH "The dir where we have unpacked CLang"
	message(STATUS "DUMP_DIR ${DUMP_DIR}")
else()
	if(NOT DEFINED GCC_COMPILERS_IN_USR_BIN)
		set(GCC_COMPILERS_IN_USR_BIN ON)
	endif()

	if(NOT DEFINED LLVM_TOOLS_IN_USR_BIN)
		set(LLVM_TOOLS_IN_USR_BIN OFF)
	endif()
endif()

if(NOT DEFINED USE_CLANG_AS_COMPILER)
	message(FATAL_ERROR "Set USE_CLANG_AS_COMPILER into ON if you want to build with CLang(++) and into OFF if you want to build with G(CC|++).")
endif()

if(NOT DEFINED REST_OF_TOOLCHAIN_IS_LLVM)
	if(USE_CLANG_AS_COMPILER)
		set(REST_OF_TOOLCHAIN_IS_LLVM ON)
	else()
		set(REST_OF_TOOLCHAIN_IS_LLVM OFF)
	endif()
endif()


if(CMAKE_HOST_WIN32)
	set(GCC_COMPILERS_IN_USR_BIN OFF)
	set(LLVM_TOOLS_IN_USR_BIN OFF)
else()
	if(NOT DEFINED GCC_COMPILERS_IN_USR_BIN)
		message(FATAL_ERROR "You must specify GCC_COMPILERS_IN_USR_BIN")
	endif()
endif()

if(NOT DEFINED LLVM_TOOLS_IN_USR_BIN)
	message(FATAL_ERROR "You must specify LLVM_TOOLS_IN_USR_BIN")
endif()

if(GCC_COMPILERS_IN_USR_BIN)
	if(NOT DEFINED GCC_PREFIX_DOUBLE_USE)
		set(GCC_PREFIX_DOUBLE_USE ON)
	endif()
	if(NOT DEFINED GCC_SUFFIX_VERSION_USE)
		set(GCC_SUFFIX_VERSION_USE OFF)
	endif()
endif()

if(NOT DEFINED GCC_PREFIX_DOUBLE_USE)
	message(FATAL_ERROR "You must specify GCC_PREFIX_DOUBLE_USE")
endif()

if(NOT DEFINED GCC_SUFFIX_VERSION_USE)
	message(FATAL_ERROR "You must specify GCC_SUFFIX_VERSION_USE")
endif()

if(NOT DEFINED TOOLCHAIN_NAME)
	set(TOOLCHAIN_NAME "avr")
endif()

if(DEFINED ARDUINO_INSTALL_PATH)
	if(NOT DEFINED AVR_GCC_ROOT)
		set(AVR_GCC_ROOT "${ARDUINO_INSTALL_PATH}/hardware/tools/${TOOLCHAIN_NAME}")
	endif()
endif()
message(STATUS "AVR_GCC_ROOT ${AVR_GCC_ROOT}")

if(REST_OF_TOOLCHAIN_IS_LLVM OR USE_CLANG_AS_COMPILER)
	if(NOT DEFINED LLVM_SUFFIX_VERSION_USE)
		if(LLVM_TOOLS_IN_USR_BIN)
			set(LLVM_SUFFIX_VERSION_USE ON)
		else()
			set(LLVM_SUFFIX_VERSION_USE OFF)
		endif()
	endif()

	if(NOT DEFINED llvm_Version)
		if(CMAKE_HOST_WIN32)
			message(FATAL_ERROR "You must specify LLVM version into llvm_Version. It is used to set the right additional flags for clang.")
		else()
			include("${CMAKE_CURRENT_LIST_DIR}/Arduino/System/DetectInstalledLLVMVersion.cmake")
			detect_llvm_version(llvm_Version LLVM_ROOT "/usr/lib")
		endif()
	endif()

	if(CMAKE_HOST_WIN32)
		if(NOT DEFINED LLVM_ROOT)
			if(DEFINED DUMP_DIR)
				set(LLVM_ROOT "${DUMP_DIR}/LLVM-${llvm_Version}.0.0-win32")
			else()
				message(FATAL_ERROR "You must set DUMP_DIR if you don't specify the full path to CLang base dir in LLVM_ROOT") # CACHE PATH "Path to Clang root"
			endif()
		endif()
	else()
		if(NOT DEFINED LLVM_ROOT)
			if(LLVM_TOOLS_IN_USR_BIN)
				set(LLVM_ROOT "") # CACHE PATH "Path to Clang root"
			else()
				set(LLVM_ROOT "/usr/lib/llvm-${llvm_Version}") # CACHE PATH "Path to Clang root"
			endif()
		endif()
	endif()

	if(NOT DEFINED LLVM_SUFFIX_VERSION_USE)
		message(FATAL_ERROR "You must specify LLVM_SUFFIX_VERSION_USE")
	endif()

	if(NOT DEFINED AVR_GCC_ROOT)
		set(AVR_GCC_ROOT "/usr/${double}")
	endif()# CACHE PATH "Path to MinGW root"

	message(STATUS "CLang root: ${LLVM_ROOT}")
	message(STATUS "AVR GCC root: ${AVR_GCC_ROOT}")
endif()


#*****************************************************************************
# Set system name and basic information
set(CMAKE_SYSTEM_NAME "Arduino")

# Set module path to enable local modules search
set(ARDUINO_TOOLCHAIN_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(_ARDUINO_TOOLCHAIN_PARENT "${CMAKE_PARENT_LIST_FILE}")
set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" "${CMAKE_CURRENT_LIST_DIR}")
set (ARDUINO_TOOLCHAIN_VERSION "1.0")

# Include modules
include(Arduino/System/BoardsIndex)
include(Arduino/System/BoardToolchain)
include(Arduino/System/BoardBuildTargets)

#*****************************************************************************
# For improved speed, indexing of boards is done only once during a 
# cmake invocation. However, this toolchain file is included multiple
# times in multiple contexts (system determination context, separate
# context for each try compile etc.). After indexing, the selected
# board's toolchain info is configured to a generated file that gets
# included in every other inclusion of this toolchain.
if (NOT _BOARD_INDEXING_COMPLETED)
	get_property(_in_try_compile GLOBAL PROPERTY IN_TRY_COMPILE)
	# IN_TRY_COMPILE check seems to be not enough. Check for parent
	# script works, but may be undocumented!
	get_filename_component(parent_script "${_ARDUINO_TOOLCHAIN_PARENT}"
		NAME_WE)
	if (parent_script STREQUAL "CMakeSystem")
		check_board_options_changed(_b_changed)
		if (NOT _b_changed)
			set(_BOARD_INDEXING_COMPLETED TRUE)
		endif()
	endif()
endif()

if (NOT _BOARD_INDEXING_COMPLETED)
	SetupBoardToolchain()
	set(CMAKE_SYSTEM_CUSTOM_CODE
		"include(\"${CMAKE_BINARY_DIR}/ArduinoSystem.cmake\")"
	)
	set (_BOARD_INDEXING_COMPLETED TRUE)
endif()

# Search for programs in the build host directories
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
# For libraries and headers in the target directories
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# Workaround for CMAKE_TRY_COMPILE_TARGET_TYPE. For later ESP32 cores this file is missing
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/build_opt.h" "")

# Do not try to link during the configure time, due to the dependency on the
# core, which we do not have a target yet.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
