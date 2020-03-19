# Change Log

## Version 0.1

Initial version

### Features

* CMake Arduino toolchain (passed to CMake using -DCMAKE\_TOOLCHAIN\_FILE=[arduino\_toolchain\_path]/Arduino-Toolchain.cmake)
    * Support for all Arduino compatible platforms (such as **ESP32**, **pinoccio**, etc.)
    * Generic CMake scripting interface without requiring Arduino specialities
    * Arduino IDE compatible build (e.g. use of build rules and flags in board.local.txt)
    * Selection of boad and board-specific options as in Arduino IDE tools menu (See `CMAKE_BOARD_OPTIONS_FILE`)
* Upload binary to Arduino board (See `target_enable_arduino_upload`)
    * Upload using serial port
    * Remote provisioning through network
* Support for Arduino libraries (see `target_link_arduino_libraries`)
    * Arduino *native* libraries (e.g. Ethernet, Wire)
    * User installed 3rd Party libraries (e.g. IRremote)
    * Project specific libraries (${CMAKE\_SOURCE\_DIR}/libraries)

