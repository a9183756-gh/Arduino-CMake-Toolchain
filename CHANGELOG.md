# Change Log

## Version 1.1

### Features

* Support for many more official and 3rd party Arduino platforms
* Support for limited target debugging facilities on some platforms
* Local package management of platforms and tools without requiring Arduino IDE
* Multiple bug fixes including the "board not working after upload" issue

## Version 1.0

Initial version

### Features

* CMake Arduino toolchain (passed to CMake using `-D CMAKE_TOOLCHAIN_FILE=/path/to/Arduino-toolchain.cmake)`
    * Support for all Arduino compatible platforms (such as **AVR**, **ESP32**, etc.)
    * Generic CMake scripting interface without requiring Arduino specific functions
    * Arduino IDE compatible build (e.g. use of build rules and flags in board.local.txt, pre/postbuild hooks etc.)
    * Selection of board and board-specific menu options as in Arduino IDE tools menu (See `ARDUINO_BOARD_OPTIONS_FILE`)
* Generate Arduino HEX binaries and upload to Arduino boards (See `target_enable_arduino_upload`)
    * Upload using serial port
    * Remote provisioning through network
    * Upload using programmer
    * Burn bootloader
* Support linking with Arduino libraries (see `target_link_arduino_libraries`)
    * Arduino *native* libraries (e.g. Ethernet, Wire)
    * User installed 3rd Party Arduino libraries (e.g. IRremote)
    * Project specific Arduino libraries (those present in `<CMAKE_SOURCE_DIR>/libraries`)
    * Support for automatic dependency resolution (Arduino IDE like, but unprofessional)
