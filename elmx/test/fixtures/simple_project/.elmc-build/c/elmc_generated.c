#include "elmc_generated.h"
#include "elmc_pebble.h"
#include <stdbool.h>
#include <stdio.h>

#if defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wunused-function"
#endif

#define ELMC_UNION_ACCELTAP 7
#define ELMC_UNION_ACTIVEKCALORIES 7
#define ELMC_UNION_ACTIVESECONDS 2
#define ELMC_UNION_ALIGNCENTER 2
#define ELMC_UNION_ALIGNLEFT 1
#define ELMC_UNION_ALIGNRIGHT 3
#define ELMC_UNION_ANTIALIASED 2
#define ELMC_UNION_ARC 21
#define ELMC_UNION_BACK 1
#define ELMC_UNION_BERLIN 2
#define ELMC_UNION_BITMAPINRECT 12
#define ELMC_UNION_BITMAPSEQUENCEAT 16
#define ELMC_UNION_BLACKWHITE 1
#define ELMC_UNION_CANCELLED 3
#define ELMC_UNION_CANVASLAYER 1
#define ELMC_UNION_CELSIUS 1
#define ELMC_UNION_CIRCLE 9
#define ELMC_UNION_CLOCKSTYLE24H 10
#define ELMC_UNION_CLOUDY 2
#define ELMC_UNION_COLOR 2
#define ELMC_UNION_COMPANION_TYPES_BERLIN 2
#define ELMC_UNION_COMPANION_TYPES_BLACK 1
#define ELMC_UNION_COMPANION_TYPES_BLUE 4
#define ELMC_UNION_COMPANION_TYPES_CELSIUS 1
#define ELMC_UNION_COMPANION_TYPES_CLEAR 1
#define ELMC_UNION_COMPANION_TYPES_CLOUDY 2
#define ELMC_UNION_COMPANION_TYPES_CURRENTLOCATION 1
#define ELMC_UNION_COMPANION_TYPES_DRIZZLE 4
#define ELMC_UNION_COMPANION_TYPES_FAHRENHEIT 2
#define ELMC_UNION_COMPANION_TYPES_FOG 3
#define ELMC_UNION_COMPANION_TYPES_GREEN 3
#define ELMC_UNION_COMPANION_TYPES_NEWYORK 4
#define ELMC_UNION_COMPANION_TYPES_PROVIDECONDITION 2
#define ELMC_UNION_COMPANION_TYPES_PROVIDETEMPERATURE 1
#define ELMC_UNION_COMPANION_TYPES_RAIN 5
#define ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER 1
#define ELMC_UNION_COMPANION_TYPES_SETBACKGROUNDCOLOR 3
#define ELMC_UNION_COMPANION_TYPES_SETSHOWDATE 5
#define ELMC_UNION_COMPANION_TYPES_SETTEXTCOLOR 4
#define ELMC_UNION_COMPANION_TYPES_SHOWERS 7
#define ELMC_UNION_COMPANION_TYPES_SNOW 6
#define ELMC_UNION_COMPANION_TYPES_STORM 8
#define ELMC_UNION_COMPANION_TYPES_UNKNOWNWEATHER 9
#define ELMC_UNION_COMPANION_TYPES_WHITE 2
#define ELMC_UNION_COMPANION_TYPES_YELLOW 5
#define ELMC_UNION_COMPANION_TYPES_ZURICH 3
#define ELMC_UNION_COMPOSITINGMODE 6
#define ELMC_UNION_CORECOMPLIANCE_TRIPLECHECK 1
#define ELMC_UNION_COREDEVICESP2D 11
#define ELMC_UNION_COREDEVICESP2DBLACK 33
#define ELMC_UNION_COREDEVICESP2DWHITE 34
#define ELMC_UNION_COREDEVICESPR2 13
#define ELMC_UNION_COREDEVICESPR2BLACK20 39
#define ELMC_UNION_COREDEVICESPR2GOLD14 41
#define ELMC_UNION_COREDEVICESPR2SILVER14 42
#define ELMC_UNION_COREDEVICESPR2SILVER20 40
#define ELMC_UNION_COREDEVICESPT2 12
#define ELMC_UNION_COREDEVICESPT2BLACKGREY 35
#define ELMC_UNION_COREDEVICESPT2BLACKRED 36
#define ELMC_UNION_COREDEVICESPT2SILVERBLUE 37
#define ELMC_UNION_COREDEVICESPT2SILVERGREY 38
#define ELMC_UNION_CURRENTLOCATION 1
#define ELMC_UNION_CURRENTTIMESTRING 9
#define ELMC_UNION_DECREMENT 2
#define ELMC_UNION_DEFAULTFONT 1
#define ELMC_UNION_DOUBLE 3
#define ELMC_UNION_DOWN 4
#define ELMC_UNION_DOWNPRESSED 6
#define ELMC_UNION_DRIZZLE 4
#define ELMC_UNION_FAHRENHEIT 2
#define ELMC_UNION_FAILED 4
#define ELMC_UNION_FILL 3
#define ELMC_UNION_FILLCIRCLE 10
#define ELMC_UNION_FILLCOLOR 4
#define ELMC_UNION_FILLRADIAL 22
#define ELMC_UNION_FILLRECT 8
#define ELMC_UNION_FINISHED 3
#define ELMC_UNION_FIRMWAREVERSIONSTRING 15
#define ELMC_UNION_FOG 3
#define ELMC_UNION_FRIDAY 5
#define ELMC_UNION_GETBATTERYLEVEL 4
#define ELMC_UNION_GETCONNECTIONSTATUS 5
#define ELMC_UNION_GRAY 6
#define ELMC_UNION_GROUP 11
#define ELMC_UNION_HEARTRATEBPM 8
#define ELMC_UNION_HIGH 4
#define ELMC_UNION_HZ10 1
#define ELMC_UNION_HZ100 4
#define ELMC_UNION_HZ25 2
#define ELMC_UNION_HZ50 3
#define ELMC_UNION_INFOCUS 1
#define ELMC_UNION_INCREMENT 1
#define ELMC_UNION_INDEXED 1
#define ELMC_UNION_INVALIDREADING 2
#define ELMC_UNION_LAUNCHPHONE 3
#define ELMC_UNION_LAUNCHQUICKLAUNCH 6
#define ELMC_UNION_LAUNCHSMARTSTRAP 8
#define ELMC_UNION_LAUNCHSYSTEM 1
#define ELMC_UNION_LAUNCHTIMELINEACTION 7
#define ELMC_UNION_LAUNCHUNKNOWN 9
#define ELMC_UNION_LAUNCHUSER 2
#define ELMC_UNION_LAUNCHWAKEUP 4
#define ELMC_UNION_LAUNCHWORKER 5
#define ELMC_UNION_LINE 6
#define ELMC_UNION_LONG 2
#define ELMC_UNION_LONGPRESSED 3
#define ELMC_UNION_LOW 2
#define ELMC_UNION_MAIN_ACCELTAP 7
#define ELMC_UNION_MAIN_CLOCKSTYLE24H 10
#define ELMC_UNION_MAIN_CURRENTTIMESTRING 9
#define ELMC_UNION_MAIN_DECREMENT 2
#define ELMC_UNION_MAIN_DOWNPRESSED 6
#define ELMC_UNION_MAIN_FIRMWAREVERSIONSTRING 15
#define ELMC_UNION_MAIN_INCREMENT 1
#define ELMC_UNION_MAIN_PROVIDETEMPERATURE 8
#define ELMC_UNION_MAIN_SELECTPRESSED 5
#define ELMC_UNION_MAIN_TICK 3
#define ELMC_UNION_MAIN_TIMEZONEISSET 11
#define ELMC_UNION_MAIN_TIMEZONENAME 12
#define ELMC_UNION_MAIN_UPPRESSED 4
#define ELMC_UNION_MAIN_WATCHCOLORNAME 14
#define ELMC_UNION_MAIN_WATCHMODELNAME 13
#define ELMC_UNION_MATTEBLACK 8
#define ELMC_UNION_MAX 5
#define ELMC_UNION_MEDIUM 3
#define ELMC_UNION_MONDAY 1
#define ELMC_UNION_MOVEMENTUPDATE 2
#define ELMC_UNION_NEWYORK 4
#define ELMC_UNION_NOANIMATEDBITMAP 1
#define ELMC_UNION_NOANIMATEDVECTOR 1
#define ELMC_UNION_NOMICROPHONE 1
#define ELMC_UNION_NOSTATICBITMAP 1
#define ELMC_UNION_NOSTATICVECTOR 1
#define ELMC_UNION_NUDGE 4
#define ELMC_UNION_OFF 1
#define ELMC_UNION_ORANGE 5
#define ELMC_UNION_OUTOFFOCUS 2
#define ELMC_UNION_PATHFILLED 17
#define ELMC_UNION_PATHOUTLINE 18
#define ELMC_UNION_PATHOUTLINEOPEN 19
#define ELMC_UNION_PEBBLE_ACCEL_HZ10 1
#define ELMC_UNION_PEBBLE_ACCEL_HZ100 4
#define ELMC_UNION_PEBBLE_ACCEL_HZ25 2
#define ELMC_UNION_PEBBLE_ACCEL_HZ50 3
#define ELMC_UNION_PEBBLE_APPFOCUS_INFOCUS 1
#define ELMC_UNION_PEBBLE_APPFOCUS_OUTOFFOCUS 2
#define ELMC_UNION_PEBBLE_BUTTON_BACK 1
#define ELMC_UNION_PEBBLE_BUTTON_DOWN 4
#define ELMC_UNION_PEBBLE_BUTTON_LONGPRESSED 3
#define ELMC_UNION_PEBBLE_BUTTON_PRESSED 1
#define ELMC_UNION_PEBBLE_BUTTON_RELEASED 2
#define ELMC_UNION_PEBBLE_BUTTON_SELECT 3
#define ELMC_UNION_PEBBLE_BUTTON_UP 2
#define ELMC_UNION_PEBBLE_COMPASS_INVALIDREADING 2
#define ELMC_UNION_PEBBLE_COMPASS_UNAVAILABLE 1
#define ELMC_UNION_PEBBLE_DATALOG_TAG 1
#define ELMC_UNION_PEBBLE_DICTATION_CANCELLED 3
#define ELMC_UNION_PEBBLE_DICTATION_FAILED 4
#define ELMC_UNION_PEBBLE_DICTATION_FINISHED 3
#define ELMC_UNION_PEBBLE_DICTATION_NOMICROPHONE 1
#define ELMC_UNION_PEBBLE_DICTATION_PHONEDISCONNECTED 2
#define ELMC_UNION_PEBBLE_DICTATION_RECOGNIZING 2
#define ELMC_UNION_PEBBLE_DICTATION_STARTING 1
#define ELMC_UNION_PEBBLE_HARDWARE_DOUBLE 3
#define ELMC_UNION_PEBBLE_HARDWARE_GETBATTERYLEVEL 4
#define ELMC_UNION_PEBBLE_HARDWARE_GETCONNECTIONSTATUS 5
#define ELMC_UNION_PEBBLE_HARDWARE_HIGH 4
#define ELMC_UNION_PEBBLE_HARDWARE_LONG 2
#define ELMC_UNION_PEBBLE_HARDWARE_LOW 2
#define ELMC_UNION_PEBBLE_HARDWARE_MAX 5
#define ELMC_UNION_PEBBLE_HARDWARE_MEDIUM 3
#define ELMC_UNION_PEBBLE_HARDWARE_NUDGE 4
#define ELMC_UNION_PEBBLE_HARDWARE_OFF 1
#define ELMC_UNION_PEBBLE_HARDWARE_PLAYTONE 6
#define ELMC_UNION_PEBBLE_HARDWARE_SETBACKLIGHT 3
#define ELMC_UNION_PEBBLE_HARDWARE_SHORT 1
#define ELMC_UNION_PEBBLE_HARDWARE_STOPTONE 7
#define ELMC_UNION_PEBBLE_HARDWARE_VIBRATE 1
#define ELMC_UNION_PEBBLE_HARDWARE_VIBRATEPATTERN 2
#define ELMC_UNION_PEBBLE_HEALTH_ACTIVEKCALORIES 7
#define ELMC_UNION_PEBBLE_HEALTH_ACTIVESECONDS 2
#define ELMC_UNION_PEBBLE_HEALTH_HEARTRATEBPM 8
#define ELMC_UNION_PEBBLE_HEALTH_MOVEMENTUPDATE 2
#define ELMC_UNION_PEBBLE_HEALTH_RESTFULSLEEPSECONDS 5
#define ELMC_UNION_PEBBLE_HEALTH_RESTINGKCALORIES 6
#define ELMC_UNION_PEBBLE_HEALTH_SIGNIFICANTUPDATE 1
#define ELMC_UNION_PEBBLE_HEALTH_SLEEPSECONDS 4
#define ELMC_UNION_PEBBLE_HEALTH_SLEEPUPDATE 3
#define ELMC_UNION_PEBBLE_HEALTH_STEPCOUNT 1
#define ELMC_UNION_PEBBLE_HEALTH_WALKEDDISTANCEMETERS 3
#define ELMC_UNION_PEBBLE_PLATFORM_BLACKWHITE 1
#define ELMC_UNION_PEBBLE_PLATFORM_COLOR 2
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHPHONE 3
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHQUICKLAUNCH 6
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHSMARTSTRAP 8
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHSYSTEM 1
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHTIMELINEACTION 7
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHUNKNOWN 9
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHUSER 2
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHWAKEUP 4
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHWORKER 5
#define ELMC_UNION_PEBBLE_PLATFORM_RECTANGULAR 1
#define ELMC_UNION_PEBBLE_PLATFORM_ROUND 2
#define ELMC_UNION_PEBBLE_TIME_FRIDAY 5
#define ELMC_UNION_PEBBLE_TIME_MONDAY 1
#define ELMC_UNION_PEBBLE_TIME_SATURDAY 6
#define ELMC_UNION_PEBBLE_TIME_SUNDAY 7
#define ELMC_UNION_PEBBLE_TIME_THURSDAY 4
#define ELMC_UNION_PEBBLE_TIME_TUESDAY 2
#define ELMC_UNION_PEBBLE_TIME_WEDNESDAY 3
#define ELMC_UNION_PEBBLE_UI_ALIGNCENTER 2
#define ELMC_UNION_PEBBLE_UI_ALIGNLEFT 1
#define ELMC_UNION_PEBBLE_UI_ALIGNRIGHT 3
#define ELMC_UNION_PEBBLE_UI_ANTIALIASED 2
#define ELMC_UNION_PEBBLE_UI_ARC 21
#define ELMC_UNION_PEBBLE_UI_BITMAPINRECT 12
#define ELMC_UNION_PEBBLE_UI_BITMAPSEQUENCEAT 16
#define ELMC_UNION_PEBBLE_UI_CANVASLAYER 1
#define ELMC_UNION_PEBBLE_UI_CIRCLE 9
#define ELMC_UNION_PEBBLE_UI_CLEAR 4
#define ELMC_UNION_PEBBLE_UI_COLOR_INDEXED 1
#define ELMC_UNION_PEBBLE_UI_COLOR_RGBA 2
#define ELMC_UNION_PEBBLE_UI_COMPOSITINGMODE 6
#define ELMC_UNION_PEBBLE_UI_FILL 3
#define ELMC_UNION_PEBBLE_UI_FILLCIRCLE 10
#define ELMC_UNION_PEBBLE_UI_FILLCOLOR 4
#define ELMC_UNION_PEBBLE_UI_FILLRADIAL 22
#define ELMC_UNION_PEBBLE_UI_FILLRECT 8
#define ELMC_UNION_PEBBLE_UI_GROUP 11
#define ELMC_UNION_PEBBLE_UI_LINE 6
#define ELMC_UNION_PEBBLE_UI_PATHFILLED 17
#define ELMC_UNION_PEBBLE_UI_PATHOUTLINE 18
#define ELMC_UNION_PEBBLE_UI_PATHOUTLINEOPEN 19
#define ELMC_UNION_PEBBLE_UI_PIXEL 5
#define ELMC_UNION_PEBBLE_UI_RECTOP 7
#define ELMC_UNION_PEBBLE_UI_RESOURCES_DEFAULTFONT 1
#define ELMC_UNION_PEBBLE_UI_RESOURCES_NOANIMATEDBITMAP 1
#define ELMC_UNION_PEBBLE_UI_RESOURCES_NOANIMATEDVECTOR 1
#define ELMC_UNION_PEBBLE_UI_RESOURCES_NOSTATICBITMAP 1
#define ELMC_UNION_PEBBLE_UI_RESOURCES_NOSTATICVECTOR 1
#define ELMC_UNION_PEBBLE_UI_ROTATEDBITMAP 13
#define ELMC_UNION_PEBBLE_UI_ROTATION 1
#define ELMC_UNION_PEBBLE_UI_ROUNDRECT 20
#define ELMC_UNION_PEBBLE_UI_STROKECOLOR 3
#define ELMC_UNION_PEBBLE_UI_STROKEWIDTH 1
#define ELMC_UNION_PEBBLE_UI_TEXT 3
#define ELMC_UNION_PEBBLE_UI_TEXTCOLOR 5
#define ELMC_UNION_PEBBLE_UI_TEXTINT 1
#define ELMC_UNION_PEBBLE_UI_TEXTLABEL 2
#define ELMC_UNION_PEBBLE_UI_TRAILINGELLIPSIS 2
#define ELMC_UNION_PEBBLE_UI_VECTORAT 14
#define ELMC_UNION_PEBBLE_UI_VECTORSEQUENCEAT 15
#define ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION 1
#define ELMC_UNION_PEBBLE_UI_WINDOWNODE 1
#define ELMC_UNION_PEBBLE_UI_WINDOWSTACK 1
#define ELMC_UNION_PEBBLE_UI_WORDWRAP 1
#define ELMC_UNION_PEBBLE_WATCHINFO_BLACK 2
#define ELMC_UNION_PEBBLE_WATCHINFO_BLUE 9
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESP2D 11
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESP2DBLACK 33
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESP2DWHITE 34
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPR2 13
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPR2BLACK20 39
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPR2GOLD14 41
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPR2SILVER14 42
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPR2SILVER20 40
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPT2 12
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPT2BLACKGREY 35
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPT2BLACKRED 36
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPT2SILVERBLUE 37
#define ELMC_UNION_PEBBLE_WATCHINFO_COREDEVICESPT2SILVERGREY 38
#define ELMC_UNION_PEBBLE_WATCHINFO_GRAY 6
#define ELMC_UNION_PEBBLE_WATCHINFO_GREEN 10
#define ELMC_UNION_PEBBLE_WATCHINFO_MATTEBLACK 8
#define ELMC_UNION_PEBBLE_WATCHINFO_ORANGE 5
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLE2HR 8
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLE2HRAQUA 27
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLE2HRBLACK 23
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLE2HRFLAME 25
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLE2HRLIME 24
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLE2HRWHITE 26
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLE2SE 9
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLE2SEBLACK 28
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLE2SEWHITE 29
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLEORIGINAL 2
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLESTEEL 3
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLETIME 4
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLETIME2 10
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLETIME2BLACK 30
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLETIME2GOLD 32
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLETIME2SILVER 31
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLETIMEROUND14 6
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLETIMEROUND20 7
#define ELMC_UNION_PEBBLE_WATCHINFO_PEBBLETIMESTEEL 5
#define ELMC_UNION_PEBBLE_WATCHINFO_PINK 11
#define ELMC_UNION_PEBBLE_WATCHINFO_RED 4
#define ELMC_UNION_PEBBLE_WATCHINFO_STAINLESSSTEEL 7
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMEBLACK 13
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMERED 14
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMEROUNDBLACK14 19
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMEROUNDBLACK20 21
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMEROUNDROSEGOLD14 22
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMEROUNDSILVER14 18
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMEROUNDSILVER20 20
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMESTEELBLACK 16
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMESTEELGOLD 17
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMESTEELSILVER 15
#define ELMC_UNION_PEBBLE_WATCHINFO_TIMEWHITE 12
#define ELMC_UNION_PEBBLE_WATCHINFO_UNKNOWNCOLOR 1
#define ELMC_UNION_PEBBLE_WATCHINFO_UNKNOWNMODEL 1
#define ELMC_UNION_PEBBLE_WATCHINFO_WHITE 3
#define ELMC_UNION_PEBBLE2HR 8
#define ELMC_UNION_PEBBLE2HRAQUA 27
#define ELMC_UNION_PEBBLE2HRBLACK 23
#define ELMC_UNION_PEBBLE2HRFLAME 25
#define ELMC_UNION_PEBBLE2HRLIME 24
#define ELMC_UNION_PEBBLE2HRWHITE 26
#define ELMC_UNION_PEBBLE2SE 9
#define ELMC_UNION_PEBBLE2SEBLACK 28
#define ELMC_UNION_PEBBLE2SEWHITE 29
#define ELMC_UNION_PEBBLEORIGINAL 2
#define ELMC_UNION_PEBBLESTEEL 3
#define ELMC_UNION_PEBBLETIME 4
#define ELMC_UNION_PEBBLETIME2 10
#define ELMC_UNION_PEBBLETIME2BLACK 30
#define ELMC_UNION_PEBBLETIME2GOLD 32
#define ELMC_UNION_PEBBLETIME2SILVER 31
#define ELMC_UNION_PEBBLETIMEROUND14 6
#define ELMC_UNION_PEBBLETIMEROUND20 7
#define ELMC_UNION_PEBBLETIMESTEEL 5
#define ELMC_UNION_PHONEDISCONNECTED 2
#define ELMC_UNION_PINK 11
#define ELMC_UNION_PIXEL 5
#define ELMC_UNION_PLAYTONE 6
#define ELMC_UNION_PRESSED 1
#define ELMC_UNION_PROVIDECONDITION 2
#define ELMC_UNION_RGBA 2
#define ELMC_UNION_RAIN 5
#define ELMC_UNION_RECOGNIZING 2
#define ELMC_UNION_RECTOP 7
#define ELMC_UNION_RECTANGULAR 1
#define ELMC_UNION_RED 4
#define ELMC_UNION_RELEASED 2
#define ELMC_UNION_REQUESTWEATHER 1
#define ELMC_UNION_RESTFULSLEEPSECONDS 5
#define ELMC_UNION_RESTINGKCALORIES 6
#define ELMC_UNION_ROTATEDBITMAP 13
#define ELMC_UNION_ROTATION 1
#define ELMC_UNION_ROUND 2
#define ELMC_UNION_ROUNDRECT 20
#define ELMC_UNION_SATURDAY 6
#define ELMC_UNION_SELECT 3
#define ELMC_UNION_SELECTPRESSED 5
#define ELMC_UNION_SETBACKGROUNDCOLOR 3
#define ELMC_UNION_SETBACKLIGHT 3
#define ELMC_UNION_SETSHOWDATE 5
#define ELMC_UNION_SETTEXTCOLOR 4
#define ELMC_UNION_SHORT 1
#define ELMC_UNION_SHOWERS 7
#define ELMC_UNION_SIGNIFICANTUPDATE 1
#define ELMC_UNION_SLEEPSECONDS 4
#define ELMC_UNION_SLEEPUPDATE 3
#define ELMC_UNION_SNOW 6
#define ELMC_UNION_STAINLESSSTEEL 7
#define ELMC_UNION_STARTING 1
#define ELMC_UNION_STEPCOUNT 1
#define ELMC_UNION_STOPTONE 7
#define ELMC_UNION_STORM 8
#define ELMC_UNION_STROKECOLOR 3
#define ELMC_UNION_STROKEWIDTH 1
#define ELMC_UNION_SUNDAY 7
#define ELMC_UNION_TAG 1
#define ELMC_UNION_TEXT 3
#define ELMC_UNION_TEXTCOLOR 5
#define ELMC_UNION_TEXTINT 1
#define ELMC_UNION_TEXTLABEL 2
#define ELMC_UNION_THURSDAY 4
#define ELMC_UNION_TICK 3
#define ELMC_UNION_TIMEBLACK 13
#define ELMC_UNION_TIMERED 14
#define ELMC_UNION_TIMEROUNDBLACK14 19
#define ELMC_UNION_TIMEROUNDBLACK20 21
#define ELMC_UNION_TIMEROUNDROSEGOLD14 22
#define ELMC_UNION_TIMEROUNDSILVER14 18
#define ELMC_UNION_TIMEROUNDSILVER20 20
#define ELMC_UNION_TIMESTEELBLACK 16
#define ELMC_UNION_TIMESTEELGOLD 17
#define ELMC_UNION_TIMESTEELSILVER 15
#define ELMC_UNION_TIMEWHITE 12
#define ELMC_UNION_TIMEZONEISSET 11
#define ELMC_UNION_TIMEZONENAME 12
#define ELMC_UNION_TRAILINGELLIPSIS 2
#define ELMC_UNION_TRIPLECHECK 1
#define ELMC_UNION_TUESDAY 2
#define ELMC_UNION_UNAVAILABLE 1
#define ELMC_UNION_UNKNOWNCOLOR 1
#define ELMC_UNION_UNKNOWNMODEL 1
#define ELMC_UNION_UNKNOWNWEATHER 9
#define ELMC_UNION_UP 2
#define ELMC_UNION_UPPRESSED 4
#define ELMC_UNION_VECTORAT 14
#define ELMC_UNION_VECTORSEQUENCEAT 15
#define ELMC_UNION_VIBRATE 1
#define ELMC_UNION_VIBRATEPATTERN 2
#define ELMC_UNION_WAITINGFORCOMPANION 1
#define ELMC_UNION_WALKEDDISTANCEMETERS 3
#define ELMC_UNION_WATCHCOLORNAME 14
#define ELMC_UNION_WATCHMODELNAME 13
#define ELMC_UNION_WEDNESDAY 3
#define ELMC_UNION_WINDOWNODE 1
#define ELMC_UNION_WINDOWSTACK 1
#define ELMC_UNION_WORDWRAP 1
#define ELMC_UNION_YELLOW 5
#define ELMC_UNION_ZURICH 3

#define ELMC_RENDER_OP_CLEAR 2
#define ELMC_RENDER_OP_PIXEL 3
#define ELMC_RENDER_OP_LINE 4
#define ELMC_RENDER_OP_PUSH_CONTEXT 10
#define ELMC_RENDER_OP_POP_CONTEXT 11
#define ELMC_RENDER_OP_STROKE_WIDTH 12
#define ELMC_RENDER_OP_ANTIALIASED 13
#define ELMC_RENDER_OP_STROKE_COLOR 14
#define ELMC_RENDER_OP_FILL_COLOR 15
#define ELMC_RENDER_OP_TEXT_COLOR 16
#define ELMC_RENDER_OP_ROUND_RECT 17
#define ELMC_RENDER_OP_ARC 18
#define ELMC_RENDER_OP_PATH_FILLED 20
#define ELMC_RENDER_OP_PATH_OUTLINE 21
#define ELMC_RENDER_OP_PATH_OUTLINE_OPEN 22
#define ELMC_RENDER_OP_TEXT_INT_WITH_FONT 27
#define ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT 28
#define ELMC_BUTTON_UP 1
#define ELMC_BUTTON_SELECT 2
#define ELMC_BUTTON_DOWN 3
#define ELMC_BUTTON_EVENT_PRESSED 1
#define ELMC_SUBSCRIPTION_SECOND_CHANGE 1
#define ELMC_SUBSCRIPTION_ACCEL_TAP 16
#define ELMC_SUBSCRIPTION_BUTTON_RAW 16384
#define ELMC_COLOR_BLACK 192
#define ELMC_COLOR_WHITE 255

#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_GABBRO)
#include <pebble.h>
static inline void elmc_agent_generated_probe(uint32_t tag) {
  static uint32_t seen_tags[16];
  static int seen_count = 0;
  for (int i = 0; i < seen_count; i++) {
    if (seen_tags[i] == tag) return;
  }
  if (seen_count >= 16) return;
  DataLoggingSessionRef session = data_logging_create(tag, DATA_LOGGING_BYTE_ARRAY, 1, false);
  if (session) {
    seen_tags[seen_count++] = tag;
    data_logging_finish(session);
  }
}
#else
static inline void elmc_agent_generated_probe(uint32_t tag) {
  (void)tag;
}
#endif

static elmc_int_t elmc_fn_Main_helper_native(const elmc_int_t value);

static ElmcValue *elmc_fn_Main_helper(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_advanced(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_counterOf(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_temperatureOf(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_requestWeather(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_requestSystemInfo(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_handleAppMsg(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_handlePlatformMsg(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_statusDraw(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_counterDraw(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_temperatureValue(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Companion_Watch_sendWatchToPhone(ElmcValue ** const args, const int argc);

static ElmcValue *elmc_fn_Main_helper(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  elmc_int_t value = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  return elmc_new_int(elmc_fn_Main_helper_native(value));
}

static elmc_int_t elmc_fn_Main_helper_native(const elmc_int_t value) {
  (void)value;

  return (value + 2);
}

static ElmcValue *elmc_fn_Main_advanced(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *n = (argc > 0) ? args[0] : NULL;
  (void)n;

  // inlined Main.helper

  const elmc_int_t native_let_base_1 = (elmc_as_int(n) + 2);

  ElmcValue *tmp_1;
  if ((native_let_base_1 > 10)) {
    tmp_1 = elmc_new_int(native_let_base_1);
  } else {
    tmp_1 = elmc_new_int((native_let_base_1 + 1));
  }

  return tmp_1;
}

static ElmcValue *elmc_fn_Main_counterOf(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;

  ElmcValue *tmp_1 = elmc_record_get_index(model, 1 /* value */);

  return tmp_1;
}

static ElmcValue *elmc_fn_Main_temperatureOf(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;

  ElmcValue *tmp_1 = elmc_record_get_index(model, 0 /* temperature */);

  return tmp_1;
}

static ElmcValue *elmc_fn_Main_requestWeather(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *location = (argc > 0) ? args[0] : NULL;
  (void)location;

  ElmcValue *tmp_1 = elmc_tuple2_ints(ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER, elmc_as_int(location));

  ElmcValue *call_args_2[1] = { tmp_1 };
  ElmcValue *tmp_2 = elmc_fn_Companion_Watch_sendWatchToPhone(call_args_2, 1);

  elmc_release(tmp_1);

  return tmp_2;
}

static ElmcValue *elmc_fn_Main_requestSystemInfo(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;

  ElmcValue *tmp_1 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING, ELMC_PEBBLE_MSG_CURRENTTIMESTRING);

  ElmcValue *tmp_2 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H, ELMC_PEBBLE_MSG_CLOCKSTYLE24H);

  ElmcValue *tmp_3 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET, ELMC_PEBBLE_MSG_TIMEZONEISSET);

  ElmcValue *tmp_4 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_TIMEZONE, ELMC_PEBBLE_MSG_TIMEZONENAME);

  ElmcValue *tmp_5 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_WATCH_MODEL, ELMC_PEBBLE_MSG_WATCHMODELNAME);

  ElmcValue *tmp_6 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_WATCH_COLOR, ELMC_PEBBLE_MSG_WATCHCOLORNAME);

  ElmcValue *tmp_7 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION, ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING);

  ElmcValue *list_items_8[7] = { tmp_1, tmp_2, tmp_3, tmp_4, tmp_5, tmp_6, tmp_7 };
  ElmcValue *tmp_8 = elmc_list_from_values_take(list_items_8, 7);

  return tmp_8;
}

ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *launchContext = (argc > 0) ? args[0] : NULL;
  (void)launchContext;

  ElmcValue *call_args_1[1] = { ELMC_RECORD_GET_INDEX(launchContext, 2 /* reason */) };
  ElmcValue *tmp_1 = elmc_fn_Pebble_Platform_launchReasonToInt(call_args_1, 1);

  const elmc_int_t native_i_2 = elmc_as_int(tmp_1);
  elmc_release(tmp_1);

  const elmc_int_t native_let_initial_3 = native_i_2;

  const char *rec_field_names_3[2] = { "temperature", "value" };
  elmc_int_t rec_values_3[2] = { 0, native_let_initial_3 };
  ElmcValue *tmp_3 = elmc_record_new_static_ints(2, rec_field_names_3, rec_values_3);

  ElmcValue *tmp_4 = elmc_new_int(ELMC_UNION_COMPANION_TYPES_BERLIN);

  ElmcValue *call_args_5[1] = { tmp_4 };
  ElmcValue *tmp_5 = elmc_fn_Main_requestWeather(call_args_5, 1);

  elmc_release(tmp_4);

  ElmcValue *tmp_6 = elmc_fn_Main_requestSystemInfo(NULL, 0);
  ElmcValue *list_items_7[2] = { tmp_5, tmp_6 };
  ElmcValue *tmp_7 = elmc_list_from_values_take(list_items_7, 2);

  ElmcValue *tmp_8 = elmc_tuple2_take(tmp_3, tmp_7);

  return tmp_8;
}

ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;
  (void)msg;
  (void)model;

  const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
    case ELMC_PEBBLE_MSG_TICK:
      ElmcValue *call_args_2[2] = { msg, model };
      tmp_1 = elmc_fn_Main_handlePlatformMsg(call_args_2, 2);

      break;
    case ELMC_PEBBLE_MSG_UPPRESSED:
      ElmcValue *call_args_3[2] = { msg, model };
      tmp_1 = elmc_fn_Main_handlePlatformMsg(call_args_3, 2);

      break;
    case ELMC_PEBBLE_MSG_SELECTPRESSED:
      ElmcValue *call_args_4[2] = { msg, model };
      tmp_1 = elmc_fn_Main_handlePlatformMsg(call_args_4, 2);

      break;
    case ELMC_PEBBLE_MSG_DOWNPRESSED:
      ElmcValue *call_args_5[2] = { msg, model };
      tmp_1 = elmc_fn_Main_handlePlatformMsg(call_args_5, 2);

      break;
    case ELMC_PEBBLE_MSG_ACCELTAP:
      ElmcValue *call_args_6[2] = { msg, model };
      tmp_1 = elmc_fn_Main_handlePlatformMsg(call_args_6, 2);

      break;
    default:
      ElmcValue *call_args_7[2] = { msg, model };
      tmp_1 = elmc_fn_Main_handleAppMsg(call_args_7, 2);

      break;

  }

  return tmp_1;
}

static ElmcValue *elmc_fn_Main_handleAppMsg(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;
  (void)msg;
  (void)model;

  const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
    case ELMC_PEBBLE_MSG_INCREMENT:
      // inlined Main.counterOf
      const elmc_int_t native_let_counter_2 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
      ElmcValue *call_args_2[1] = { model };
      ElmcValue *tmp_2 = elmc_fn_Main_temperatureOf(call_args_2, 1);
      ElmcValue *tmp_3 = elmc_new_int((native_let_counter_2 + 1));
      const char *rec_field_names_4[2] = { "temperature", "value" };
      ElmcValue *rec_values_4[2] = { tmp_2, tmp_3 };
      ElmcValue *tmp_4 = elmc_record_new_static_take(2, rec_field_names_4, rec_values_4);
      ElmcValue *tmp_5 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_4, tmp_5);

      break;
    case ELMC_PEBBLE_MSG_DECREMENT:
      // inlined Main.counterOf
      const elmc_int_t native_let_counter_7 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
      ElmcValue *call_args_7[1] = { model };
      ElmcValue *tmp_7 = elmc_fn_Main_temperatureOf(call_args_7, 1);
      ElmcValue *tmp_8 = elmc_new_int((native_let_counter_7 - 1));
      const char *rec_field_names_9[2] = { "temperature", "value" };
      ElmcValue *rec_values_9[2] = { tmp_7, tmp_8 };
      ElmcValue *tmp_9 = elmc_record_new_static_take(2, rec_field_names_9, rec_values_9);
      ElmcValue *tmp_10 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_9, tmp_10);

      break;
    case ELMC_PEBBLE_MSG_PROVIDETEMPERATURE:
      ElmcValue *tmp_12 = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
      ElmcValue *tmp_13 = elmc_maybe_just(tmp_12);
      elmc_release(tmp_12);
      ElmcValue *call_args_14[1] = { model };
      ElmcValue *tmp_14 = elmc_fn_Main_counterOf(call_args_14, 1);
      const char *rec_field_names_15[2] = { "temperature", "value" };
      ElmcValue *rec_values_15[2] = { tmp_13, tmp_14 };
      ElmcValue *tmp_15 = elmc_record_new_static_take(2, rec_field_names_15, rec_values_15);
      ElmcValue *tmp_16 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_15, tmp_16);

      break;
    case ELMC_PEBBLE_MSG_CURRENTTIMESTRING:
      ElmcValue *tmp_18 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_19 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_18, tmp_19);

      break;
    case ELMC_PEBBLE_MSG_CLOCKSTYLE24H:
      ElmcValue *tmp_21 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_22 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_21, tmp_22);

      break;
    case ELMC_PEBBLE_MSG_TIMEZONEISSET:
      ElmcValue *tmp_24 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_25 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_24, tmp_25);

      break;
    case ELMC_PEBBLE_MSG_TIMEZONENAME:
      ElmcValue *tmp_27 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_28 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_27, tmp_28);

      break;
    case ELMC_PEBBLE_MSG_WATCHMODELNAME:
      ElmcValue *tmp_30 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_31 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_30, tmp_31);

      break;
    case ELMC_PEBBLE_MSG_WATCHCOLORNAME:
      ElmcValue *tmp_33 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_34 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_33, tmp_34);

      break;
    case ELMC_PEBBLE_MSG_FIRMWAREVERSIONSTRING:
      ElmcValue *tmp_36 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_37 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_36, tmp_37);

      break;
    default:
      ElmcValue *tmp_39 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_40 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_39, tmp_40);

      break;

  }

  return tmp_1;
}

static ElmcValue *elmc_fn_Main_handlePlatformMsg(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;
  (void)msg;
  (void)model;

  const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
    case ELMC_PEBBLE_MSG_TICK:

      // inlined Main.counterOf
      ElmcValue *tmp_2 = elmc_new_int(ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */));

      // inlined Main.helper

      const elmc_int_t native_let_base_3 = (elmc_as_int(tmp_2) + 2);

      elmc_int_t native_if_3;
      if ((native_let_base_3 > 10)) {

      native_if_3 = native_let_base_3;
    } else {

      native_if_3 = (native_let_base_3 + 1);
    }

      // inlined Main.advanced

      const elmc_int_t native_let_next_4 = native_if_3;

      ElmcValue *call_args_4[1] = { model };
      ElmcValue *tmp_4 = elmc_fn_Main_temperatureOf(call_args_4, 1);

      ElmcValue *tmp_5 = elmc_new_int(native_let_next_4);
      const char *rec_field_names_6[2] = { "temperature", "value" };
      ElmcValue *rec_values_6[2] = { tmp_4, tmp_5 };
      ElmcValue *tmp_6 = elmc_record_new_static_take(2, rec_field_names_6, rec_values_6);

      ElmcValue *tmp_7 = elmc_cmd1(ELMC_PEBBLE_CMD_TIMER_AFTER_MS, 1000);

      ElmcValue *tmp_8 = elmc_tuple2_take(tmp_6, tmp_7);

      elmc_release(tmp_2);

      tmp_1 = tmp_8;
      break;
    case ELMC_PEBBLE_MSG_UPPRESSED:

      // inlined Main.counterOf

      const elmc_int_t native_let_counter_9 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);

      ElmcValue *tmp_9 = elmc_new_int((native_let_counter_9 + 1));

      ElmcValue *call_args_10[1] = { model };
      ElmcValue *tmp_10 = elmc_fn_Main_temperatureOf(call_args_10, 1);

      ElmcValue *tmp_11 = elmc_retain(tmp_9);
      const char *rec_field_names_12[2] = { "temperature", "value" };
      ElmcValue *rec_values_12[2] = { tmp_10, tmp_11 };
      ElmcValue *tmp_12 = elmc_record_new_static_take(2, rec_field_names_12, rec_values_12);

      ElmcValue *tmp_13 = elmc_cmd2(ELMC_PEBBLE_CMD_STORAGE_WRITE_INT, 1, elmc_as_int(tmp_9));

      ElmcValue *tmp_14 = elmc_tuple2_take(tmp_12, tmp_13);

      elmc_release(tmp_9);

      tmp_1 = tmp_14;
      break;
    case ELMC_PEBBLE_MSG_SELECTPRESSED:
      ElmcValue *tmp_15 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_16 = elmc_new_int(ELMC_UNION_COMPANION_TYPES_BERLIN);
      ElmcValue *call_args_17[1] = { tmp_16 };
      ElmcValue *tmp_17 = elmc_fn_Main_requestWeather(call_args_17, 1);
      elmc_release(tmp_16);
      ElmcValue *tmp_18 = elmc_fn_Main_requestSystemInfo(NULL, 0);
      ElmcValue *list_items_19[2] = { tmp_17, tmp_18 };
      ElmcValue *tmp_19 = elmc_list_from_values_take(list_items_19, 2);
      tmp_1 = elmc_tuple2_take(tmp_15, tmp_19);

      break;
    case ELMC_PEBBLE_MSG_DOWNPRESSED:
      // inlined Main.counterOf
      const elmc_int_t native_let_counter_21 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
      ElmcValue *call_args_21[1] = { model };
      ElmcValue *tmp_21 = elmc_fn_Main_temperatureOf(call_args_21, 1);
      ElmcValue *tmp_22 = elmc_new_int((native_let_counter_21 - 1));
      const char *rec_field_names_23[2] = { "temperature", "value" };
      ElmcValue *rec_values_23[2] = { tmp_21, tmp_22 };
      ElmcValue *tmp_23 = elmc_record_new_static_take(2, rec_field_names_23, rec_values_23);
      ElmcValue *tmp_24 = elmc_cmd1(ELMC_PEBBLE_CMD_STORAGE_DELETE, 1);
      tmp_1 = elmc_tuple2_take(tmp_23, tmp_24);

      break;
    case ELMC_PEBBLE_MSG_ACCELTAP:
      // inlined Main.counterOf
      const elmc_int_t native_let_counter_26 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);
      ElmcValue *call_args_26[1] = { model };
      ElmcValue *tmp_26 = elmc_fn_Main_temperatureOf(call_args_26, 1);
      ElmcValue *tmp_27 = elmc_new_int((native_let_counter_26 + 1));
      const char *rec_field_names_28[2] = { "temperature", "value" };
      ElmcValue *rec_values_28[2] = { tmp_26, tmp_27 };
      ElmcValue *tmp_28 = elmc_record_new_static_take(2, rec_field_names_28, rec_values_28);
      ElmcValue *tmp_29 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_28, tmp_29);

      break;
    default:
      ElmcValue *tmp_31 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_32 = elmc_int_zero();
      tmp_1 = elmc_tuple2_take(tmp_31, tmp_32);

      break;

  }

  return tmp_1;
}

ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *_ = (argc > 0) ? args[0] : NULL;
  (void)_;

  ElmcValue *tmp_1 = elmc_sub1(ELMC_SUBSCRIPTION_SECOND_CHANGE, ELMC_PEBBLE_MSG_TICK);

  ElmcValue *tmp_2 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_UPPRESSED);

  ElmcValue *tmp_3 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_SELECT, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_SELECTPRESSED);

  ElmcValue *tmp_4 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_DOWN, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_DOWNPRESSED);

  ElmcValue *tmp_5 = elmc_sub1(ELMC_SUBSCRIPTION_ACCEL_TAP, ELMC_PEBBLE_MSG_ACCELTAP);

  ElmcValue *list_items_6[5] = { tmp_1, tmp_2, tmp_3, tmp_4, tmp_5 };
  ElmcValue *tmp_6 = elmc_list_from_values_take(list_items_6, 5);

  return tmp_6;
}

static ElmcValue *elmc_fn_Main_statusDraw(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;

  ElmcValue *call_args_1[1] = { model };
  ElmcValue *tmp_1 = elmc_fn_Main_temperatureOf(call_args_1, 1);

  ElmcValue *tmp_2;

  if (((tmp_1 && tmp_1->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)tmp_1->payload)->is_just == 1) || (tmp_1 && tmp_1->tag == ELMC_TAG_TUPLE2 && tmp_1->payload != NULL && elmc_as_int(((ElmcTuple2 *)tmp_1->payload)->first) == 1))) {
    ElmcValue *tmp_3 = elmc_new_int(ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    ElmcValue *tmp_4 = elmc_new_int(ELMC_UNION_PEBBLE_UI_RESOURCES_DEFAULTFONT);
    ElmcValue *tmp_5 = elmc_int_zero();
    ElmcValue *tmp_6 = elmc_new_int(28);
    ElmcValue *call_args_7[1] = { elmc_maybe_or_tuple_just_payload_borrow(tmp_1) };
    ElmcValue *tmp_7 = elmc_fn_Main_temperatureValue(call_args_7, 1);
    ElmcValue *tmp_8 = elmc_tuple2_ints(0, 0);
    ElmcValue *tmp_9 = elmc_tuple2_take(tmp_7, tmp_8);
    ElmcValue *tmp_10 = elmc_tuple2_take(tmp_6, tmp_9);
    ElmcValue *tmp_11 = elmc_tuple2_take(tmp_5, tmp_10);
    ElmcValue *tmp_12 = elmc_tuple2_take(tmp_4, tmp_11);
    tmp_2 = elmc_tuple2_take(tmp_3, tmp_12);

  } else {
    ElmcValue *tmp_14 = elmc_new_int(ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
    ElmcValue *tmp_15 = elmc_new_int(ELMC_UNION_PEBBLE_UI_RESOURCES_DEFAULTFONT);
    ElmcValue *tmp_16 = elmc_int_zero();
    ElmcValue *tmp_17 = elmc_new_int(28);
    ElmcValue *tmp_18 = elmc_int_zero();
    ElmcValue *tmp_19 = elmc_tuple2_ints(0, ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION);
    ElmcValue *tmp_20 = elmc_tuple2_take(tmp_18, tmp_19);
    ElmcValue *tmp_21 = elmc_tuple2_take(tmp_17, tmp_20);
    ElmcValue *tmp_22 = elmc_tuple2_take(tmp_16, tmp_21);
    ElmcValue *tmp_23 = elmc_tuple2_take(tmp_15, tmp_22);
    tmp_2 = elmc_tuple2_take(tmp_14, tmp_23);
  }

  elmc_release(tmp_1);

  return tmp_2;
}

static ElmcValue *elmc_fn_Main_counterDraw(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;

  // inlined Main.counterOf

  const elmc_int_t native_let_counter_1 = ELMC_RECORD_GET_INDEX_INT(model, 1 /* value */);

  ElmcValue *tmp_1 = elmc_new_int(ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
  ElmcValue *tmp_2 = elmc_new_int(ELMC_UNION_PEBBLE_UI_RESOURCES_DEFAULTFONT);
  ElmcValue *tmp_3 = elmc_int_zero();
  ElmcValue *tmp_4 = elmc_new_int(56);
  ElmcValue *tmp_5 = elmc_new_int(native_let_counter_1);

  ElmcValue *tmp_6 = elmc_tuple2_ints(0, 0);

  ElmcValue *tmp_7 = elmc_tuple2_take(tmp_5, tmp_6);

  ElmcValue *tmp_8 = elmc_tuple2_take(tmp_4, tmp_7);

  ElmcValue *tmp_9 = elmc_tuple2_take(tmp_3, tmp_8);

  ElmcValue *tmp_10 = elmc_tuple2_take(tmp_2, tmp_9);

  ElmcValue *tmp_11 = elmc_tuple2_take(tmp_1, tmp_10);

  return tmp_11;
}

static ElmcValue *elmc_fn_Main_temperatureValue(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *temperature = (argc > 0) ? args[0] : NULL;
  (void)temperature;

  ElmcValue *tmp_1;

  if ((temperature) && (((temperature)->tag == ELMC_TAG_INT && elmc_as_int(temperature) == 1) || ((temperature)->tag == ELMC_TAG_TUPLE2 && (temperature)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(temperature)->payload)->first) == 1))) {
    tmp_1 = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();

  } else {
    tmp_1 = ((ElmcTuple2 *)temperature->payload)->second ? elmc_retain(((ElmcTuple2 *)temperature->payload)->second) : elmc_int_zero();
  }

  return tmp_1;
}

static ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *tmp_1 = elmc_int_zero();
  return tmp_1;
}

static ElmcValue *elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *launchReason = (argc > 0) ? args[0] : NULL;
  (void)launchReason;

  const int case_msg_tag_1 = (launchReason && (launchReason)->tag == ELMC_TAG_INT ? elmc_as_int(launchReason) : (launchReason && (launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
    case ELMC_UNION_LAUNCHSYSTEM:

      tmp_1 = elmc_int_zero();
      break;
    case ELMC_UNION_LAUNCHUSER:

      tmp_1 = elmc_new_int(1);
      break;
    case ELMC_UNION_LAUNCHPHONE:

      tmp_1 = elmc_new_int(2);
      break;
    case ELMC_UNION_LAUNCHWAKEUP:

      tmp_1 = elmc_new_int(3);
      break;
    case ELMC_UNION_LAUNCHWORKER:

      tmp_1 = elmc_new_int(4);
      break;
    case ELMC_UNION_LAUNCHQUICKLAUNCH:

      tmp_1 = elmc_new_int(5);
      break;
    case ELMC_UNION_LAUNCHTIMELINEACTION:

      tmp_1 = elmc_new_int(6);
      break;
    case ELMC_UNION_LAUNCHSMARTSTRAP:

      tmp_1 = elmc_new_int(7);
      break;
    case ELMC_UNION_LAUNCHUNKNOWN:

      tmp_1 = elmc_new_int(-1);
      break;
    default:
      tmp_1 = elmc_int_zero();
      break;

  }

  return tmp_1;
}

static ElmcValue *elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *value = (argc > 0) ? args[0] : NULL;
  (void)value;

  const int case_msg_tag_1 = (value && (value)->tag == ELMC_TAG_INT ? elmc_as_int(value) : (value && (value)->tag == ELMC_TAG_TUPLE2 && (value)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(value)->payload)->first) : -1));
  ElmcValue *tmp_1 = elmc_int_zero();
  switch (case_msg_tag_1) {
    case ELMC_UNION_COMPANION_TYPES_CURRENTLOCATION:

      tmp_1 = elmc_new_int(1);
      break;
    case ELMC_UNION_COMPANION_TYPES_BERLIN:

      tmp_1 = elmc_new_int(2);
      break;
    case ELMC_UNION_COMPANION_TYPES_ZURICH:

      tmp_1 = elmc_new_int(3);
      break;
    case ELMC_UNION_COMPANION_TYPES_NEWYORK:

      tmp_1 = elmc_new_int(4);
      break;
    default:
      tmp_1 = elmc_int_zero();
      break;

  }

  return tmp_1;
}

static ElmcValue *elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *message = (argc > 0) ? args[0] : NULL;
  (void)message;

  ElmcValue *tmp_1;

  tmp_1 = elmc_new_int(2);

  return tmp_1;
}

static ElmcValue *elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *message = (argc > 0) ? args[0] : NULL;
  (void)message;

  ElmcValue *tmp_1;

  ElmcValue *call_args_2[1] = { ((ElmcTuple2 *)message->payload)->second };
  tmp_1 = elmc_fn_Companion_Internal_encodeLocationCode(call_args_2, 1);

  return tmp_1;
}

static ElmcValue *elmc_fn_Companion_Watch_sendWatchToPhone(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *message = (argc > 0) ? args[0] : NULL;
  (void)message;

  ElmcValue *call_args_1[1] = { message };
  ElmcValue *tmp_1 = elmc_fn_Companion_Internal_watchToPhoneTag(call_args_1, 1);

  const elmc_int_t native_i_2 = elmc_as_int(tmp_1);
  elmc_release(tmp_1);

  ElmcValue *call_args_3[1] = { message };
  ElmcValue *tmp_3 = elmc_fn_Companion_Internal_watchToPhoneValue(call_args_3, 1);

  const elmc_int_t native_i_4 = elmc_as_int(tmp_3);
  elmc_release(tmp_3);

  ElmcValue *tmp_5 = elmc_cmd2(ELMC_PEBBLE_CMD_COMPANION_SEND, native_i_2, native_i_4);

  return tmp_5;
}

static int elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);

static int elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  (void)args;
  (void)argc;
  ElmcValue *model = (argc > 0) ? args[0] : NULL;
  (void)model;
  if (!writer) return -1;
  int direct_rc = 0;
  static ElmcPebbleDrawCmd scene_cmd;
  CATCH_BEGIN

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CLEAR);
    scene_cmd.p0 = ELMC_COLOR_WHITE;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PUSH_CONTEXT);

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_STROKE_WIDTH);
    scene_cmd.p0 = 3;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_ANTIALIASED);
    scene_cmd.p0 = 1;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_STROKE_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_ROUND_RECT);
    scene_cmd.p0 = 6;
    scene_cmd.p1 = 6;
    scene_cmd.p2 = 132;
    scene_cmd.p3 = 70;
    scene_cmd.p4 = 6;
    scene_cmd.p5 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_ARC);
    scene_cmd.p0 = 20;
    scene_cmd.p1 = 16;
    scene_cmd.p2 = 36;
    scene_cmd.p3 = 36;
    scene_cmd.p4 = 0;
    scene_cmd.p5 = 45000;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PATH_OUTLINE);
    scene_cmd.path_point_count = 5;
    scene_cmd.path_offset_x = 86;
    scene_cmd.path_offset_y = 16;
    scene_cmd.path_rotation = 0;
    scene_cmd.path_x[0] = 0;
    scene_cmd.path_y[0] = 0;

    scene_cmd.path_x[1] = 10;
    scene_cmd.path_y[1] = 4;

    scene_cmd.path_x[2] = 16;
    scene_cmd.path_y[2] = 14;

    scene_cmd.path_x[3] = 8;
    scene_cmd.path_y[3] = 24;

    scene_cmd.path_x[4] = 0;
    scene_cmd.path_y[4] = 18;

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PATH_FILLED);
    scene_cmd.path_point_count = 5;
    scene_cmd.path_offset_x = 108;
    scene_cmd.path_offset_y = 26;
    scene_cmd.path_rotation = 0;
    scene_cmd.path_x[0] = 0;
    scene_cmd.path_y[0] = 0;

    scene_cmd.path_x[1] = 8;
    scene_cmd.path_y[1] = 6;

    scene_cmd.path_x[2] = 6;
    scene_cmd.path_y[2] = 14;

    scene_cmd.path_x[3] = 2;
    scene_cmd.path_y[3] = 20;

    scene_cmd.path_x[4] = 0;
    scene_cmd.path_y[4] = 14;

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PATH_OUTLINE_OPEN);
    scene_cmd.path_point_count = 4;
    scene_cmd.path_offset_x = 10;
    scene_cmd.path_offset_y = 78;
    scene_cmd.path_rotation = 0;
    scene_cmd.path_x[0] = 0;
    scene_cmd.path_y[0] = 0;

    scene_cmd.path_x[1] = 8;
    scene_cmd.path_y[1] = 4;

    scene_cmd.path_x[2] = 16;
    scene_cmd.path_y[2] = 2;

    scene_cmd.path_x[3] = 24;
    scene_cmd.path_y[3] = 6;

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_POP_CONTEXT);

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_LINE);
    scene_cmd.p0 = 0;
    scene_cmd.p1 = 84;
    scene_cmd.p2 = 143;
    scene_cmd.p3 = 84;
    scene_cmd.p4 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PIXEL);
    scene_cmd.p0 = 72;
    scene_cmd.p1 = 84;
    scene_cmd.p2 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    ElmcValue *tmp_13 = model ? elmc_retain(model) : elmc_int_zero();

    ElmcValue *call_args_14[1] = { tmp_13 };
    ElmcValue *tmp_14 = elmc_fn_Main_temperatureOf(call_args_14, 1);

    if (((tmp_14 && tmp_14->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)tmp_14->payload)->is_just == 1) || (tmp_14 && tmp_14->tag == ELMC_TAG_TUPLE2 && tmp_14->payload != NULL && elmc_as_int(((ElmcTuple2 *)tmp_14->payload)->first) == 1))) {

      ElmcValue *call_args_15[1] = { elmc_maybe_or_tuple_just_payload_borrow(tmp_14) };
      ElmcValue *tmp_15 = elmc_fn_Main_temperatureValue(call_args_15, 1);

      const elmc_int_t native_i_16 = elmc_as_int(tmp_15);
      elmc_release(tmp_15);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = native_i_16;
      if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
        CATCH_BREAK;
      }

    }
    else if (((tmp_14 && tmp_14->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)tmp_14->payload)->is_just == 0) || (tmp_14 && tmp_14->tag == ELMC_TAG_INT && elmc_as_int(tmp_14) == 0))) {

      ElmcValue *tmp_18 = elmc_new_int(ELMC_UNION_PEBBLE_UI_WAITINGFORCOMPANION);
      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_LABEL_WITH_FONT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 0;
      scene_cmd.p2 = 28;
      scene_cmd.p3 = 0;
      scene_cmd.p4 = 0;
      if (tmp_18 && tmp_18->tag == ELMC_TAG_STRING && tmp_18->payload) {
        const char *direct_text = (const char *)tmp_18->payload;
        int direct_text_i = 0;
        while (direct_text[direct_text_i] && direct_text_i < 63) {
          scene_cmd.text[direct_text_i] = direct_text[direct_text_i];
          direct_text_i++;
        }
        scene_cmd.text[direct_text_i] = '\0';

      }

      if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
        CATCH_BREAK;
      }
      elmc_release(tmp_18);

    }

    elmc_release(tmp_14);

    elmc_release(tmp_13);

    ElmcValue *tmp_19 = model ? elmc_retain(model) : elmc_int_zero();
    // inlined Main.counterOf
    const elmc_int_t direct_hoisted_int_20 = ELMC_RECORD_GET_INDEX_INT(tmp_19, 1 /* value */);

    const elmc_int_t direct_native_let_counter_21 = direct_hoisted_int_20;

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 56;
    scene_cmd.p3 = direct_native_let_counter_21;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      CATCH_BREAK;
    }

    elmc_release(tmp_19);
  CATCH_END
  return direct_rc;

}

int elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}
