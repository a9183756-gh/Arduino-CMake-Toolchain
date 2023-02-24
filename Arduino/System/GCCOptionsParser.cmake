#[=======================================================================[.rst:

GCCOptionsParser
------------

A library that helps you with filtering gcc options to remove unneeded ones.

Feel free to inline. The repo is here: https://github.com/KOLANICH-libs/GCCOptionsParser.cmake

Unlicense
^^^^^^^^^

This is free and unencumbered software released into the public domain.
Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.
In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
For more information, please refer to <https://unlicense.org/>

Functions
^^^^^^^^^
.. command:: parseGCCOptions

  Parses GCC (and compatible compilers) command line options.

  ::

    parseGCCOptions(<prefix> argsString)

    Calling this will create in the scope variables containing the options in the same order they appear in the command line.
    Then you can ignore the unneeded variablaes

#]=======================================================================]

function(parseGCCOptions prefix argsString)
	separate_arguments(argsStringSplit NATIVE_COMMAND "${argsString}")
	list(GET argsStringSplit 0 executable)
	list(SUBLIST argsStringSplit 1 -1 argsStringSplit)

	set(rest "")
	set(language_version "")
	set(defines "")
	set(opt "")
	set(warnings "")
	set(features "")
	set(discarded "")
	set(action "")
	set(debug_info "")
	set(target "")
	set(files "")
	set(deps "")

	foreach(a ${argsStringSplit})
		if(a MATCHES "^-M(F|D|MD)$")
			list(APPEND deps "${a}")
			continue()
		endif()
		if(a MATCHES "^-std=((gnu|c)(\\+\\+)?[0-9az]+)$")
			list(APPEND language_version "${CMAKE_MATCH_1}")
			continue()
		endif()
		if(a MATCHES "^-m")
			list(APPEND target "${a}")
			continue()
		endif()
		if(a MATCHES "^-g([0-9]*|gdb)$")
			list(APPEND debug_info "${a}")
			continue()
		endif()
		if(a MATCHES "^-(c)$")
			list(APPEND action "${a}")
			continue()
		endif()
		if(a MATCHES "^-W|^-w$")
			list(APPEND warnings "${a}")
			continue()
		endif()
		if(a MATCHES "^-D(.+)$")
			list(APPEND defines "${CMAKE_MATCH_1}")
			continue()
		endif()
		if(a MATCHES "^-f")
			list(APPEND features "${a}")
			continue()
		endif()
		if(a MATCHES "^-O")
			list(APPEND opt "${a}")
			continue()
		endif()
		list(APPEND rest "${a}")
	endforeach()

	set("${prefix}_executable" "${executable}" PARENT_SCOPE)
	set("${prefix}_features" "${features}" PARENT_SCOPE)
	set("${prefix}_language_version" "${language_version}" PARENT_SCOPE)
	set("${prefix}_warnings" "${warnings}" PARENT_SCOPE)
	set("${prefix}_defines" "${defines}" PARENT_SCOPE)
	set("${prefix}_opt" "${opt}" PARENT_SCOPE)
	set("${prefix}_action" "${action}" PARENT_SCOPE)
	set("${prefix}_debug_info" "${debug_info}" PARENT_SCOPE)
	set("${prefix}_target" "${target}" PARENT_SCOPE)
	set("${prefix}_rest" "${rest}" PARENT_SCOPE)
	set("${prefix}_deps" "${deps}" PARENT_SCOPE)
endfunction()

