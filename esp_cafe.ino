
//90s cafe, warm tones, friends, extravagant laptop bezels.
//a coffee cup as big as your head.
//if arduino was bought by a printer company is this stable?

#define BYTECODES t*(t&16384?7:5)*(3-(3&t>>9)+(3&t>>8))>>(3&-t>>(t&4096?2:16))|t>>3; 
#define PRESETAMT 12

#include "synths.h"

void setup() { 
 SETUPPERS
 lamp=true;
 LAMPLIGHT
 presets[0]=coco;
 presets[1]=echo;
 presets[2]=amosc; //earth=AM yellow+gray=OSC
 presets[3]=ssd; //simple short delay
 presets[4]=bbd; //bbd style delay
 presets[5]=cococo;  //3layer coco +-5th
 presets[6]=cocooct; //3layer coco +-OCT
 presets[7]=he; //hermonic echo
 presets[8]=disc; //flipp=basee skipp=noise ash=feedback-source
 presets[9]=dist; //simple distortion ash=feedback-source
 presets[10]=wmp; //serge-style wmp green-in > wmp > ash-out +distortion
 presets[11]=prun; //ash=OSC flipp=shiftregister skipp=sr-mod earth=AM 
 presets[12]=bytebeats;

 FILLNOISE
 DOUBLECLK
 PRESETTER(presets[0])  
}

void loop() {
} 
