# Some issues are not related to the toolchain and occurs even in the Arduino
# IDE. Such tests are skipped, if the known issue occurs.

set(skipped_tests_list
	"esp32\\.esp32" "esp32\\.d_duino_32"
		"initializer element is not constant"
	"XMegaForArduino\\.avr" ".*"
		"cannot find crtatxmega128a1\\.o"
	"Elektor\\.avr" "avr\\.platino"
		"Arduino\\.h: No such file or directory"
	"Simba\\..*" ".*"
		"undefined reference to `main'"
	"RiddleAndCode\\.avr" ".*"
		"pins_arduino\\.h: No such file or directory"
	"SAM15x15\\.samd" "samd\\.SAM15x15"
		"conflicting types for 'utoa'"
	"megaTinyCore\\.megaavr" "megaavr\\.Xplained416"
		"'ADC_REFSEL_VREFA_gc' undeclared"
	"megaTinyCore\\.megaavr" "megaavr\\.Xplained817"
		"'ADC_REFSEL_VREFA_gc' undeclared"
	"esp8266\\.esp8266" "esp8266\\.sparkfunBlynk"
		"cannot open linker script file eagle\\.flash\\.4m1m\\.ld"
	"intorobot\\.esp8266" "esp8266\\.Nut"
		"type_traits: No such file or directory"
	"nucDuino\\.nucDuino" "nucDuino\\.DFRDuino"
		"gcc/NUC123\\.ld: No such file or directory"
	"Arrow\\.samd" "samd\\.SmartEverything_Fox3_native"
		"variant\\.h: No such file or directory"
	"FemtoCow_attiny\\.avr" "avr\\.attiny167.*"
		"#error UDR not defined"
	"ardhat\\.avr" ".*"
		"'DDRA' undeclared here"
	"SparkFun\\.samd" "samd\\.LilyMini"
		"WVariant\\.h: No such file or directory"
)

set("skipped_tests_list.linux"
	"Microsoft.win10" ".*" "is not a full path and was not found in the PATH"
	"LinkIt.arm" ".*" "PackTag.sh: Command not found"
	"stm32duino.STM32F4" ".*" "cmd: not found"
)

set("skipped_tests_list.macosx"
	"Microsoft.win10" ".*" "is not a full path and was not found in the PATH"
	"LinkIt.arm" ".*" "PackTag.sh: Command not found"
    "stm32duino.STM32F4" ".*" "cmd: not found"
)

set("skipped_tests_list.windows"
)

