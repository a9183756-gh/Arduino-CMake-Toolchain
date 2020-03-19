// Including Arduino.h is required for using Serial functions
#include "Arduino.h"

// the setup routine runs once when you press reset:
void setup() {
	// initialize serial communication at 9600 bits per second:
	Serial.begin(9600);

	// print out hello world
	Serial.println("Hello World");
}

// the loop routine runs over and over again forever:
void loop() {
}
