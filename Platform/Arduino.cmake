# ASM does not pass -I for include directories
set(CMAKE_INCLUDE_FLAG_ASM "-I")

# Set the suffix to match the target executable name
set(CMAKE_EXECUTABLE_SUFFIX ".elf")

foreach (lang IN ITEMS C CXX ASM)
	# If we do not set to .o, some linker scripts aren't working correctly
	set(CMAKE_${lang}_OUTPUT_EXTENSION ".o")

	# Initial configuration flags.
	set(CMAKE_${lang}_FLAGS_INIT " ")
	set(CMAKE_${lang}_FLAGS_DEBUG_INIT " -g")
	set(CMAKE_${lang}_FLAGS_MINSIZEREL_INIT " -DNDEBUG")
	set(CMAKE_${lang}_FLAGS_RELEASE_INIT " -DNDEBUG")
	set(CMAKE_${lang}_FLAGS_RELWITHDEBINFO_INIT " -g -DNDEBUG")
endforeach()

# Where is the target environment
# Add all tools paths and include paths?, tools/sdk in platform path?
# message("ARDUINO_FIND_ROOT_PATH:${ARDUINO_FIND_ROOT_PATH}")
set(CMAKE_FIND_ROOT_PATH ${ARDUINO_FIND_ROOT_PATH})

set(CMAKE_SYSTEM_INCLUDE_PATH "/include")
set(CMAKE_SYSTEM_LIBRARY_PATH "/lib")
# message("ARDUINO_SYSTEM_PROGRAM_PATH:${ARDUINO_SYSTEM_PROGRAM_PATH}")
set(CMAKE_SYSTEM_PROGRAM_PATH ${ARDUINO_SYSTEM_PROGRAM_PATH})

# Library indexing once after the board setup
if (NOT _LIBRARY_INDEXING_COMPLETED)

	# No need of indexing in try compile context?
	get_property(_in_try_compile GLOBAL PROPERTY IN_TRY_COMPILE)
	if (NOT _in_try_compile)
		# Cached global library search
		IndexArduinoLibraries(ards_libs_global
			COMMENT "Indexing Arduino libraries for the project")
	endif()
	set(_LIBRARY_INDEXING_COMPLETED TRUE)

endif()

