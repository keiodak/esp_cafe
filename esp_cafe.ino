
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
 presets[2]=amosc;
 presets[3]=ssd;
 presets[4]=bbd;
 presets[5]=cococo;
 presets[6]=cocooct;
 presets[7]=he;
 presets[8]=disc;
 presets[9]=dist;
 presets[10]=wmp;
 presets[11]=prun;
 presets[12]=bytebeats;

 FILLNOISE
 DOUBLECLK
 PRESETTER(presets[0])  
}

void loop() {
} 
