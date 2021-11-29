cmake_minimum_required(VERSION 3.2.0)

project(Test NONE)

include(CTest)

# Interpret if() arguments without quotes as variables/keywords
if (NOT CMAKE_VERSION VERSION_LESS 3.1)
    cmake_policy(SET CMP0054 NEW)
endif()

if (ARDUINO_SMOKE_TEST)
	set(ARDUINO_MAX_BOARDS_PER_PLATFORM 1)
elseif(NOT DEFINED ARDUINO_MAX_BOARDS_PER_PLATFORM)
	set(ARDUINO_MAX_BOARDS_PER_PLATFORM 0)
endif()

get_filename_component(ARDUINO_TOOLCHAIN_DIR
	"${CMAKE_SOURCE_DIR}/.." ABSOLUTE)
list(APPEND CMAKE_MODULE_PATH "${ARDUINO_TOOLCHAIN_DIR}")

include(Arduino/Utilities/CommonUtils)
include(Arduino/System/PackagePathIndex)
include(Arduino/System/BoardsIndex)
include(Arduino/System/BoardToolchain)
include(Arduino/PackageManager/BoardsManager)

# Templates directory
set(templates_dir "${ARDUINO_TOOLCHAIN_DIR}/Tests/Templates")

# Build root directory
if ("${ARDUINO_BUILD_ROOT_DIR}" STREQUAL "")
	set(build_root_dir "${CMAKE_BINARY_DIR}/build")
else()
	set(build_root_dir "${ARDUINO_BUILD_ROOT_DIR}")
endif()

# System root directory
if ("${ARDUINO_SYSTEM_ROOT_DIR}" STREQUAL "")
	set(sys_root_dir "${CMAKE_BINARY_DIR}/toolchain")
	# Prepare system directory
	file(REMOVE_RECURSE "${sys_root_dir}")
	file(MAKE_DIRECTORY "${sys_root_dir}")
else()
	set(sys_root_dir "${ARDUINO_SYSTEM_ROOT_DIR}")
endif()

# Results root directory
if ("${ARDUINO_RESULT_ROOT_DIR}" STREQUAL "")
	set(result_root_dir "${CMAKE_BINARY_DIR}/test_results")
else()
	set(result_root_dir "${ARDUINO_RESULT_ROOT_DIR}")
endif()

# Utility function to escape URL chanracters
function(_tests_escape_url _str return_str)
	set(_tests_url_special_char_list
		"!" "@" "$" "%" "^" "&" "*" "(" ")" "\""
		"'" ":" "?" "<" ">" "," "`" " " "\t" "\\;")
	set(_tests_url_escape_char_list
		"%21" "%40" "%24" "%25" "%5E" "%26" "%2A" "%28" "%29" "%22"
		"%27" "%3A" "%3F" "%3C" "%3E" "%2C" "%60" "%20" "%09" "%3B")

	string(LENGTH "${_str}" _str_len)
	set(_idx 0)
	set(_return_str "")
	while(_idx LESS _str_len)
		string(SUBSTRING "${_str}" "${_idx}" 1 _str_chr)
		list(FIND _tests_url_special_char_list "${_str_chr}" _chr_idx)
		if (_chr_idx LESS 0)
			set(_return_str "${_return_str}${_str_chr}")
		else()
			list(GET _tests_url_escape_char_list "${_chr_idx}" _replace_str)
			set(_return_str "${_return_str}${_replace_str}")
		endif()
		math(EXPR _idx "${_idx} + 1")
	endwhile()
	set("${return_str}" "${_return_str}" PARENT_SCOPE)

endfunction()

# Utility function to check and set skip regular expressions to
# skip the known issues
function(_tests_get_skip_regex_for_test pl_id distinct_id return_regex)

	set(_idx 0)
	set(_host_name "")
	if (${CMAKE_HOST_APPLE})
		set(_host_name "macosx")
	elseif (${CMAKE_HOST_UNIX})
		set(_host_name "linux")
	elseif (${CMAKE_HOST_WIN32})
        set(_host_name "windows")
    endif()

	set(all_skipped_tests ${skipped_tests_list})
	if (_host_name)
		list(APPEND all_skipped_tests ${skipped_tests_list.${_host_name}})
	endif()

	list(LENGTH all_skipped_tests _num_rules)
	set(_output_regex_list "")
	while(_idx LESS _num_rules)
		list(GET all_skipped_tests ${_idx} _pl_id_regex)
		math(EXPR _idx "${_idx} + 1")
		list(GET all_skipped_tests ${_idx} _distinct_id_regex)
		math(EXPR _idx "${_idx} + 1")
		list(GET all_skipped_tests ${_idx} _output_regex)
		math(EXPR _idx "${_idx} + 1")
		if ("${pl_id}" MATCHES "^${_pl_id_regex}$" AND
			"${distinct_id}" MATCHES "^${_distinct_id_regex}$")
			list(APPEND _output_regex_list "${_output_regex}")
		endif()
	endwhile()

	string(REPLACE ";" "|" _output_regex "${_output_regex_list}")
	set("${return_regex}" "${_output_regex}" PARENT_SCOPE)

endfunction()

# Setup board tests
function(SetupBoardTests)

	# Call the platform setup workflow, to ensure that the platform is ready
	# to be used for setting up tests for the boards. Platform setup may
	# involve installation (if package management is enabled) and indexing
	# of the boards on the platform.
	PlatformSetupWorkflow()

	message("ARDUINO_PLATFORM_ID:${ARDUINO_PLATFORM_ID}")
	if ("${ARDUINO_PLATFORM_ID}" STREQUAL "")
		message(FATAL_ERROR "'${ARDUINO_PLATFORM}' is not setup successfully. "
			"No tests will be run on the platform.")
		return()
	endif()

	# Index all the installed platforms and boards
	boards_get_list(ard_boards boards_list)

	# Choose the provided board
	if ("${boards_list}" STREQUAL "" AND NOT "${ARDUINO_BOARD}" STREQUAL "")
		message(WARNING "No board matches '${ARDUINO_BOARD}'!!! "
			"No tests will be run on '${_install_pl}' platform.")
	endif()

	# Load skipped tests info
	include("${ARDUINO_TOOLCHAIN_DIR}/Tests/skipped_tests.cmake")

	# Setup toolchain and test for each of the indexed boards
	set(all_boards_list)
	foreach(board_id IN LISTS boards_list)
		boards_get_property(ard_boards "${board_id}" "name" board_name)
		boards_get_property(ard_boards "${board_id}" "/pl_id" pl_id)
		boards_get_property(ard_boards "${board_id}" "/distinct_id" distinct_id)

		if (NOT DEFINED "_setup_cnt_${pl_id}")
			set("_setup_cnt_${pl_id}" 0)
		endif()

		math(EXPR "_setup_cnt_${pl_id}" "${_setup_cnt_${pl_id}} + 1")
		if (ARDUINO_MAX_BOARDS_PER_PLATFORM GREATER 0 AND
			"${_setup_cnt_${pl_id}}" GREATER ARDUINO_MAX_BOARDS_PER_PLATFORM)
			continue()
		endif()

		message(STATUS "Setting up test for ${board_name} [${distinct_id}]")

		# Configure the board/platform info for the use of results preparation
		string_escape_quoting(board_name)
		set(_board_sys_dir "${sys_root_dir}/${distinct_id}")
		configure_file("${templates_dir}/TestResults/BoardInfo.cmake.in"
			"${_board_sys_dir}/BoardInfo.cmake" @ONLY)

		# setup the toolchain
		SelectArduinoBoardEx(ard_boards "${board_id}"
			BOARD_OPTIONS_FILE "${_board_sys_dir}/BoardOptions.cmake")
		SetupBoardToolchain(ard_boards "${board_id}" "${_board_sys_dir}"
			RESULT_VARIABLE _result)
		if (NOT _result EQUAL 0)
			message(WARNING "Toolchain setup for '${board_name}' failed!!! "
				"Tests for the board may fail.")
		endif()

		_tests_get_skip_regex_for_test("${pl_id}" "${distinct_id}"
			_skip_regex)

		# Add the test
		set(_board_build_dir "${build_root_dir}/${distinct_id}")
		set(_board_result_dir "${result_root_dir}/${distinct_id}")
		# To handle skipped tests in old version of CMake, we need to run
		# through a wrapper shell script, that returns a different return
		# code than the usual 1 returned by CMake on error.
		set(_test_dir "${ARDUINO_TOOLCHAIN_DIR}/Tests")
		if (EXISTS "/bin/sh")
			set(shell_cmd "/bin/sh" "${_test_dir}/RunTestWrapper.sh"
				"${_board_result_dir}")
		elseif(CMAKE_HOST_WIN32)
			set(shell_cmd "${_test_dir}/RunTestWrapper.bat"
				"${_board_result_dir}")
		else()
			set(shell_cmd)
		endif()
		add_test(NAME "${distinct_id}"
			COMMAND ${shell_cmd} "${CMAKE_COMMAND}"
				-D "CMAKE_GENERATOR=${CMAKE_GENERATOR}"
				-D "ARDUINO_TOOLCHAIN_DIR=${ARDUINO_TOOLCHAIN_DIR}"
				-D "ARDUINO_BUILD_ROOT_DIR=${build_root_dir}"
				-D "ARDUINO_SYSTEM_ROOT_DIR=${sys_root_dir}"
				-D "ARDUINO_RESULT_ROOT_DIR=${result_root_dir}"
				-D "ARDUINO_BOARD_OPTIONS_FILE=${ARDUINO_BOARD_OPTIONS_FILE}"
				-D "ARDUINO_BOARD_ID=${distinct_id}"
				-D "ARDUINO_PKG_MGR_DL_CACHE=${ARDUINO_PKG_MGR_DL_CACHE}"
				-D "ARDUINO_SKIP_REGULAR_EXPRESSION=${_skip_regex}"
				-P "${CMAKE_CURRENT_SOURCE_DIR}/RunBoardTest.cmake"
			WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
		)

		set_tests_properties("${distinct_id}" PROPERTIES
			FIXTURES_REQUIRED "PlTestResults"
			SKIP_RETURN_CODE 100
			TIMEOUT 3600
		)

		if ("${shell_cmd}" STREQUAL "" AND
			NOT "${_skip_regex}" STREQUAL "" AND
			NOT CMAKE_VERSION VERSION_LESS "3.16.0")
			set_tests_properties("${distinct_id}" PROPERTIES
				SKIP_REGULAR_EXPRESSION "skipped known issue"
			)
		endif()

		list(APPEND all_boards_list "${distinct_id}")

	endforeach()

	# Setup a test for results preparation
	add_test(NAME "PreparePlTestResults"
		COMMAND "${CMAKE_COMMAND}"
			-D "ARDUINO_TOOLCHAIN_DIR=${ARDUINO_TOOLCHAIN_DIR}"
			-D "ARDUINO_BUILD_ROOT_DIR=${build_root_dir}"
			-D "ARDUINO_SYSTEM_ROOT_DIR=${sys_root_dir}"
			-D "ARDUINO_RESULT_ROOT_DIR=${result_root_dir}"
			-D "ARDUINO_PLATFORM_DIR=${pl_path}"
			-D "ARDUINO_BOARDS_LIST=${all_boards_list}"
			-P "${CMAKE_CURRENT_SOURCE_DIR}/PreparePlTestResults.cmake"
			WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
	)

	set_tests_properties("PreparePlTestResults" PROPERTIES
		FIXTURES_CLEANUP "PlTestResults"
	)

endfunction()

# Setup platform tests
function(SetupPlatformTests pl_url ref_url_list return_pl_tests)

	if (EXISTS "${pl_url}")
		set(_json_file "${pl_url}")
		_tests_escape_url("${_json_file}" _json_file_)
		set(pkg_url "file:///${_json_file}")
		set(_pkg_url "file:///${_json_file_}")
	else()
		BoardManager_DownloadPackage("${pl_url}"
			JSON_FILES_LIST _json_file)
		set(pkg_url "${pl_url}")
		set(_pkg_url "${pl_url}")
	endif()

	if ("${_json_file}" STREQUAL "")
		message(WARNING "Failed to setup tests for ${pl_url}!")
		return()
	endif()

	IndexArduinoPackages("${_json_file}")
	packages_find_platforms(pl_list JSON_FILES ${_json_file} ${ARGN})

	foreach(pl_id IN LISTS pl_list)

		packages_get_platform_property("${pl_id}" "name" pl_name)
		packages_get_platform_property("${pl_id}" "version" pl_version)
		packages_get_platform_property("${pl_id}" "architecture" pl_arch)
		string(TOUPPER ${pl_arch} pl_arch)
		packages_get_platform_property("${pl_id}" "/pkg_id" pkg_id)
		packages_get_platform_property("${pl_id}" "/json_idx" json_idx)
		packages_get_property("${pkg_id}" "${json_idx}" "name" pkg_name)
		packages_get_property("${pkg_id}" "${json_idx}" "maintainer"
			pkg_maint DEFAULT "${pkg_name}")
		packages_get_property("${pkg_id}" "${json_idx}" "help.online"
			help_url QUIET)
		packages_get_property("${pkg_id}" "${json_idx}" "websiteURL"
			web_url QUIET)
		packages_get_property("${pkg_id}" "${json_idx}" "email" e_mail QUIET)
		if (NOT "${e_mail}" STREQUAL "")
			set(_e_mail "mailto:${e_mail}")
		endif()
		packages_get_platform_property("${pl_id}" "url" installer_url QUIET)

		message(STATUS "Setting up test for \"${pl_name}\"")
		set(test_id "${pl_id}")
		set(_n 1)
		while (TRUE)
			list(FIND "${return_pl_tests}" "${test_id}" _idx)
			if (_idx LESS 0)
				break()
			endif()
			math(EXPR _n "${_n} + 1")
			set(test_id "${pl_id}.${_n}")
		endwhile()

		# Configure the platform info for the use of results preparation
		string(REPLACE "|" "\\|" pl_name "${pl_name}")
		set(_pl_sys_dir "${sys_root_dir}/${test_id}")
		string_escape_quoting(pl_name)
		string_escape_quoting(pkg_name)
		string_escape_quoting(pkg_maint)
		configure_file("${templates_dir}/TestResults/PlatformInfo.cmake.in"
			"${_pl_sys_dir}/PlatformInfo.cmake" @ONLY)

		# Add the test for the platform
		set(_pl_build_dir "${build_root_dir}/${test_id}")
		set(_pl_results_dir "${result_root_dir}/${test_id}")
		# To handle skipped tests in old version of CMake, we need to run
		# through a wrapper shell script, that returns a different return
		# code than the usual 1 returned by CMake on error.
		set(_test_dir "${ARDUINO_TOOLCHAIN_DIR}/Tests")
		if (EXISTS "/bin/sh")
			set(shell_cmd "/bin/sh" "${_test_dir}/RunTestWrapper.sh"
				"${_pl_results_dir}")
		elseif(CMAKE_HOST_WIN32)
			set(shell_cmd "${_test_dir}/RunTestWrapper.bat"
				"${_pl_results_dir}")
		else()
			set(shell_cmd)
		endif()
		add_test(NAME "${test_id}"
			COMMAND ${shell_cmd} "${CMAKE_COMMAND}"
				-D "CMAKE_GENERATOR=${CMAKE_GENERATOR}"
				-D "ARDUINO_BOARD_OPTIONS_FILE=${ARDUINO_BOARD_OPTIONS_FILE}"
				-D "ARDUINO_BOARD_MANAGER_URL=${pl_url}"
				-D "ARDUINO_BOARD_MANAGER_REF_URL=${ref_url_list}"
				-D "ARDUINO_BOARD=${_brd_id}"
				-D "ARDUINO_TOOLCHAIN_DIR=${ARDUINO_TOOLCHAIN_DIR}"
				-D "ARDUINO_BUILD_ROOT_DIR=${_pl_build_dir}"
				-D "ARDUINO_SYSTEM_ROOT_DIR=${_pl_sys_dir}"
				-D "ARDUINO_RESULT_ROOT_DIR=${_pl_results_dir}"
				-D "ARDUINO_PLATFORM=${pl_id}"
				-D "ARDUINO_PKG_MGR_DL_CACHE=${ARDUINO_PKG_MGR_DL_CACHE}"
				-D "ARDUINO_MAX_BOARDS_PER_PLATFORM=${ARDUINO_MAX_BOARDS_PER_PLATFORM}"
				-D "ARDUINO_NO_INSTALLED_REFERENCES=${ARDUINO_NO_INSTALLED_REFERENCES}"
				-P "${CMAKE_CURRENT_SOURCE_DIR}/RunPlatformTest.cmake"
			WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
		)

		set_tests_properties("${test_id}" PROPERTIES
			FIXTURES_REQUIRED "TestResults"
			SKIP_RETURN_CODE 100
			TIMEOUT 3600
		)
		if ("${shell_cmd}" STREQUAL "" AND
			NOT CMAKE_VERSION VERSION_LESS "3.16.0")
			set_tests_properties("${test_id}" PROPERTIES
				SKIP_REGULAR_EXPRESSION "Skipped known issues!")
		endif()

		list(APPEND "${return_pl_tests}" "${test_id}")

	endforeach()

	set("${return_pl_tests}" "${${return_pl_tests}}" PARENT_SCOPE)

endfunction()

# Setup package tests
function(SetupPackageTests pkg_url_list return_pl_tests)

	foreach(_pkg_url IN LISTS pkg_url_list)

		# Split comma seperated list of URLs
		string(REPLACE "," ";" _url_list "${_pkg_url}")

		# First one in the list should contain the required board
		list(GET _url_list 0 _pl_url)
		set(_ref_url_list "${_url_list}")
		list(REMOVE_AT _ref_url_list 0)

		list(APPEND _ref_url_list ${ARDUINO_BOARD_MANAGER_REF_URL})

		SetupPlatformTests("${_pl_url}" "${_ref_url_list}"
			"${return_pl_tests}" ${ARGN})
	endforeach()

	set("${return_pl_tests}" "${${return_pl_tests}}" PARENT_SCOPE)

endfunction()

enable_testing()

set(all_pl_tests)
if ("${ARDUINO_RESULT_ROOT_DIR}" STREQUAL "") # Setup package tests

	InitializeArduinoPackagePathList()

	# Find filter arguments to SetupPackageTests
	set(_filter_args)
	set(_brd_id "")
	# From board options file
	if (NOT "${ARDUINO_BOARD_OPTIONS_FILE}" STREQUAL "")
		include("${ARDUINO_BOARD_OPTIONS_FILE}")
	endif()
	# From ARDUINO_PACKAGER...
	if (NOT "${ARDUINO_PACKAGER}" STREQUAL "")
		message(STATUS "Filter option: ARDUINO_PACKAGER=${ARDUINO_PACKAGER}")
		set(_pkg_id "${ARDUINO_PACKAGER}")
		list(APPEND _filter_args "PACKAGE_ID" "${_pkg_id}")
	endif()
	# From ARDUINO_PLATFORM...
	if (NOT "${ARDUINO_PLATFORM}" STREQUAL "")
		message(STATUS "Filter option: ARDUINO_PLATFORM=${ARDUINO_PLATFORM}")
		set(_arch_id "")
		set(_pkg_id "")
		string_split("${ARDUINO_PLATFORM}" "." _arch_id _pkg_id _ign)
		if (NOT _arch_id STREQUAL "")
			list(APPEND _filter_args "ARCH_ID" "${_arch_id}")
		endif()
		if (NOT _pkg_id STREQUAL "")
			list(APPEND _filter_args "PACKAGE_ID" "${_pkg_id}")
		endif()
	endif()
	# From ARDUINO_BOARD...
	if (NOT "${ARDUINO_BOARD}" STREQUAL "")
		message(STATUS "Filter option: ARDUINO_BOARD=${ARDUINO_BOARD}")
		set(_arch_id "")
		set(_pkg_id "")
		string_split("${ARDUINO_BOARD}" "." _brd_id _arch_id _pkg_id _ign)
		if (NOT _arch_id STREQUAL "")
			list(APPEND _filter_args "ARCH_ID" "${_arch_id}")
		endif()
		if (NOT _pkg_id STREQUAL "")
			list(APPEND _filter_args "PACKAGE_ID" "${_pkg_id}")
		endif()
	endif()

	# Setup platform tests from the board manager URL packages
	if (NOT "${ARDUINO_BOARD_MANAGER_URL}" STREQUAL "")

		message(STATUS "Filter option: "
			"ARDUINO_BOARD_MANAGER_URL=${ARDUINO_BOARD_MANAGER_URL}")

		# if a CMake list (';' seperated) of comma seperated URLs are provided
		# or a file containing one URL per line is provided, then one platform
		# test is added for each of the platforms contained in the package,
		# which in turn installs (if necessary) and adds boards tests for the
		# platform. Note that running one platform at a time ensures that we
		# utilize disk space only for one package at a time, rather than trying
		# to install all the boards in all the packages at once.
		if (EXISTS "${ARDUINO_BOARD_MANAGER_URL}")
			if (NOT IS_DIRECTORY "${ARDUINO_BOARD_MANAGER_URL}")
				file(STRINGS "${ARDUINO_BOARD_MANAGER_URL}" _url_list)
				set(_filtered_url_list)
				foreach(_url IN LISTS _url_list)
					if (NOT _url MATCHES "^[ \t]*#")
						list(APPEND _filtered_url_list "${_url}")
					endif()
				endforeach()
				SetupPackageTests("${_filtered_url_list}" all_pl_tests
					${_filter_args})
			endif()
		else()
			SetupPackageTests("${ARDUINO_BOARD_MANAGER_URL}" all_pl_tests
				${_filter_args})
		endif()
	else()
		packages_get_default_packages(def_json_files)
		SetupPackageTests("${def_json_files}" all_pl_tests INSTALLED
			${_filter_args})
	endif()

	# Setup a test for preparing the test results
	add_test(NAME "PrepareTestResults"
		COMMAND "${CMAKE_COMMAND}"
			-D "ARDUINO_TOOLCHAIN_DIR=${ARDUINO_TOOLCHAIN_DIR}"
			-D "ARDUINO_BUILD_ROOT_DIR=${build_root_dir}"
			-D "ARDUINO_SYSTEM_ROOT_DIR=${sys_root_dir}"
			-D "ARDUINO_RESULT_ROOT_DIR=${result_root_dir}"
			-D "ARDUINO_PL_TEST_LIST=${all_pl_tests}"
			-P "${CMAKE_CURRENT_SOURCE_DIR}/PrepareTestResults.cmake"
			WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
	)

	set_tests_properties("PrepareTestResults" PROPERTIES
		FIXTURES_CLEANUP "TestResults"
	)

else() # Setup board tests

	SetupBoardTests()
	
endif()

