# Arduino CMake Toolchain

**Arduino CMake toolchain** is a CMake toolchain for cross-compiling CMake based projects for all Arduino compatible boards (AVR, ESP32 etc.). Of course, this means all the benefits of CMake for Arduino compilation, like using your favourite IDE, configuration checks (e.g. `try_compile`, `CheckTypeSize`), etc. This also brings the Arduino compilation to professional users, who are limited by the Arduino IDE compilation.

## Project Roots

[Arduino-CMake-NG](https://github.com/arduino-cmake/Arduino-CMake-NG) is a great project, which could have prevented me from writing yet another Arduino CMake toolchain. However, as claimed by the project, Arduino-CMake-NG could not be easily utilized/modified for other Arduino compatible boards other than AVR, like ESP32, due to the fact that it does not fully work the way Arduino IDE works and has lot of AVR specific stuff. An other important limitation is related to portability. Arduino-CMake-NG provides Arduino specific CMake interface, requiring CMake scripts to be written/modified specifically for Arduino, rather than just passing `-D CMAKE_TOOLCHAIN_FILE=/path/to/Arduino-toolchain.cmake` to a generic CMake project.

My initial expectation was to contribute to Arduino-CMake-NG to fix the above limitations, but had to redo a lot of core logic making it very incompatible (including the usage). Also, the project Arduino-CMake-NG seems to be no longer maintained. I would like to acknowledge the authors who contributed directly/indirectly to Arduino-CMake-NG, and thus indirectly contributed to this project.

## Features

- [x] CMake Arduino toolchain (passed to CMake using `-D CMAKE_TOOLCHAIN_FILE=/path/to/Arduino-toolchain.cmake)`
    - [x] Support for all Arduino compatible platforms (such as **AVR**, **ESP32** etc.)
    - [x] Generic CMake scripting interface without requiring Arduino specific functions
    - [x] Arduino IDE compatible build (e.g. use of build rules and flags in board.local.txt, pre/postbuild hooks etc.)
    - [x] Selection of board and board-specific menu options as in Arduino IDE tools menu (See `ARDUINO_BOARD_OPTIONS_FILE`)
- [x] Generate Arduino HEX binaries and upload to Arduino boards (See `target_enable_arduino_upload`)
    - [x] Upload using serial port
    - [x] Remote provisioning through network
    - [x] Upload using programmer
    - [x] Burn bootloader
- [x] Support linking with Arduino libraries (see `target_link_arduino_libraries`)
    - [x] Arduino *native* libraries (e.g. Ethernet, Wire)
    - [x] User installed 3rd Party Arduino libraries (e.g. IRremote)
    - [x] Project specific Arduino libraries (those present in `<CMAKE_SOURCE_DIR>/libraries`)
    - [x] Support for automatic dependency resolution (Arduino IDE like, but unprofessional)
- [x] Support for debugging and utilities
    - [x] Debugging the target (Very limited support on some platforms only)
    - [ ] Serial port monitoring
- [x] Local package management without requiring installation of Arduino IDE
    - [x] Platform and tools management
    - [ ] Library management
- [ ] Support for `.ino` and '.pde' sketch files (Arduino IDE like, but unprofessional)

## Usage

The provided toolchain file (Arduino-toolchain.cmake) is passed to cmake as folows

```sh
cmake -D CMAKE_TOOLCHAIN_FILE=/path/to/Arduino-toolchain.cmake <CMAKE_SOURCE_DIR>
```
Note: As this is cross compilation, use any cross compilation compatible generator, like makefile generators (e.g. `-G "NMake Makefiles"` or `-G "MinGW Makefiles"` on Windows command prompt or `-G "Unix Makefiles"` on UNIX compatible prompts etc.).

The above command generates a file **BoardOptions.cmake** in the build directory, that enumerates all the installed Arduino boards (installed through Arduino IDE or any other board manager) and their menu options. Select the Arduino board and any non-default options for the board from the BoardOptions.cmake (Or from cmake-gui), and then reinvoke the same command above.

If you already have a customized BoardOptions.cmake file for the Arduino Board, you can use that instead, without waiting for the generation of BoardOptions.cmake, as given below.

```sh
cmake -D CMAKE_TOOLCHAIN_FILE=/path/to/Arduino-toolchain.cmake -D ARDUINO_BOARD_OPTIONS_FILE=/path/to/any/BoardOptions.cmake <CMAKE_SOURCE_DIR>
```

Note:
1. After the cmake generation is successful, changing the menu options in BoardOptions.cmake may work, but changing the board itself may not be allowed by CMake because the compiler, ABI, features determination and any cache dependencies may not be retriggered again.
1. CMake does not support build for multiple architectures in the same build tree. If a project requires to build applications for more than one type of Arduino boards, refer to CMake documentation for multiple architecture build.
1. When this toolchain is used, executables (added with `add_executable`) have the entry points setup()/loop() and not main(). Need to include "Arduino.h" for these entry points.
1. If your source files are compiled for both Arduino and other platforms like linux, then the CMake flag `ARDUINO` and the compiler flag `ARDUINO` can be used for script/code portability. Other Arduino board/architecture specific standard flags can also be used.

### Linking with Arduino code/libraries (`target_link_arduino_libraries`)

`<CMAKE_SOURCE_DIR>/CMakeLists.txt` and any other dependent CMake scripts of the project contain the standard CMake scripting using `add_library`, `add_executable` etc. without Arduino specific changes. Refer to CMake documentation for the same. However when the project source code depends on the Arduino code or libraries (i.e. if the corresponding header files are included), then appropriate linking is required, as expected. This is done using `target_link_arduino_libraries` as explained below.

If Arduino.h is included in your source files, then the target must be linked against the 'core' Arduino library as follows.

```cmake
add_library(my_library my_library.c) # my_library.c includes Arduino.h
target_link_arduino_libraries(my_library PRIVATE core)
```

If any other native or 3rd party libraries are used, then those libraries must be linked similarly as follows.

```cmake
add_executable(my_app my_app.c) # my_app.c includes Wire.h, Arduino.h
target_link_arduino_libraries(my_app PRIVATE Wire core)
```

Like Arduino IDE, if the required Arduino libraries are to be automatically identified and linked, then it can be done as follows.

```cmake
add_executable(my_app my_app.c) # my_app.c includes Wire.h, Arduino.h
# Link Wire and core automatically (PUBLIC linking in this example)
target_link_arduino_libraries(my_app AUTO_PUBLIC)
```

Note:
1. *Wire* and *core* in the above examples are not CMake targets. They are just Arduino library or include names (case-sensitive). Library and include names are the same in most libraries, but they may differ.
1. It is required only to specify the direct dependencies. Any deeper dependencies are automatically identified and linked. For example, if *SD.h* is included, it is sufficient to link with *SD*, even if *SD* depends on other Arduino libraries, like *SPI*.

These examples illustrates simple usage, but powerful enough for most use cases. However more advanced control and customization of Arduino libraries should be possible. Please refer to the [Examples](https://github.com/a9183756-gh/Arduino-CMake-Toolchain/tree/master/Examples) folder, as well as the API documentation of `target_link_arduino_libraries` (Currently documented as comments in [BoardBuildTargets.cmake](https://github.com/a9183756-gh/Arduino-CMake-Toolchain/blob/master/Arduino/System/BoardBuildTargets.cmake)).

### Uploading to the target board (`target_enable_arduino_upload`)

If support for generating HEX binary and uploading it to the board is required, then a call to `target_enable_arduino_upload` is required for each executable target, as shown below.

```cmake
add_executable(my_executable my_executable.c)
target_link_arduino_libraries(my_executable PRIVATE core) # Assuming my_executable.c includes Arduino.h
target_enable_arduino_upload(my_executable) # This adds a target upload-my_executable
```

Upload the executable (from the above example) to the board on COM3 serial port as follows

**Note:** *There are changes in the commands since release 1.1. Now there is only a common upload target available for all applications, and application specific targets need to be explicitly enabled.*

```sh
<make-command> upload TARGET=my_executable SERIAL_PORT=COM3
```

Upload the executable to the board through remote provisioning as follows

```sh
<make-command> upload TARGET=my_executable NETWORK_IP=<IP>
```

For using a programmer, select the programmer in board options or the CMake GUI, and then execute the following

```sh
<make-command> program TARGET=my_executable
```

Using the programmer, bootloader can be flashed as below

```sh
<make-command> burn-bootloader
```

If debugging is supported on the platform, you can launch the debugger as below

```sh
<make-command> debug TARGET=my_executable
```

## Serial port monitoring

Currently there is no support available for this within this toolchain. However any external serial port monitor can be used (e.g. Putty). External serial monitor may need to be closed before upload and reopened after upload, because both use the same serial port.

## Package Management

For local package management, the CMake option `ARDUINO_BOARD_MANAGER_URL` can be used to specify the board manager URL of the platform. The necessary platform is locally installed in the build directory, and utilized. An example is shown below.

```sh
cmake -D CMAKE_TOOLCHAIN_FILE=/path/to/Arduino-toolchain.cmake -D ARDUINO_BOARD_MANAGER_URL=https://dl.espressif.com/dl/package_esp32_index.json -D ARDUINO_BOARD_OPTIONS_FILE=/path/to/MyESP32BoardOptions.cmake <CMAKE_SOURCE_DIR>
```

## How it works

This toolchain follows the build process described in [Arduino Build Process](https://arduino.github.io/arduino-cli/sketch-build-process/), and processes the JSON, platform.txt and boards.txt files correponding to the Arduino platform as specified in the documentation [Arduino IDE 1.5 3rd party Hardware specification](https://arduino.github.io/arduino-cli/platform-specification/).

## License

MIT © 2020 [Arduino-CMake-Toolchain](https://github.com/a9183756-gh/Arduino-CMake-Toolchain/blob/master/LICENSE.md)
