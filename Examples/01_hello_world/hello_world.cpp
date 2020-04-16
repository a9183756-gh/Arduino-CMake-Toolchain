// Including Arduino.h is required for using Serial functions
#include "Arduino.h"

// the setup routine runs once when you press reset:
void setup() {

// Ensure that the code builds on platforms without serial
#if defined(HAVE_HWSERIAL0)

	// initialize serial communication at 9600 bits per second:
	Serial.begin(9600);

	// print out hello world
	Serial.println("Hello World");

#endif

// Ensure that the code builds on platforms without inbuilt LED
#ifdef LED_BUILTIN

	// Setup to blink the inbuilt LED
	pinMode(LED_BUILTIN, OUTPUT);

#endif
}

// the loop routine runs over and over again forever:
void loop() {

// Ensure that the code builds on platforms without inbuilt LED
#ifdef LED_BUILTIN

	// Blink the inbuilt LED
	digitalWrite(LED_BUILTIN, HIGH);   // turn the LED on (HIGH is the voltage level)
	delay(1000);                       // wait for a second
	digitalWrite(LED_BUILTIN, LOW);    // turn the LED off by making the voltage LOW
	delay(1000);                       // wait for a second

#endif

}
