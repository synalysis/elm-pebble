#include "elmc_generated.h"
#include "elmc_pebble.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#if defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-variable"
#endif

#define ELMC_UNION_ALTITUDECORNER 1
#define ELMC_UNION_ALTITUDESLOT 1
#define ELMC_UNION_BASICS_FALSE 2
#define ELMC_UNION_BASICS_TRUE 1
#define ELMC_UNION_BATTERYCORNER 1
#define ELMC_UNION_BATTERYLEVELCHANGED 5
#define ELMC_UNION_CELSIUS 1
#define ELMC_UNION_CLEARTIDE 8
#define ELMC_UNION_COMPANION_TYPES_CELSIUS 1
#define ELMC_UNION_COMPANION_TYPES_CLEARTIDE 8
#define ELMC_UNION_COMPANION_TYPES_EAST 3
#define ELMC_UNION_COMPANION_TYPES_FAHRENHEIT 2
#define ELMC_UNION_COMPANION_TYPES_FEET 2
#define ELMC_UNION_COMPANION_TYPES_METERS 1
#define ELMC_UNION_COMPANION_TYPES_METERSPERSECOND 1
#define ELMC_UNION_COMPANION_TYPES_MILESPERHOUR 2
#define ELMC_UNION_COMPANION_TYPES_NORTH 1
#define ELMC_UNION_COMPANION_TYPES_NORTHEAST 2
#define ELMC_UNION_COMPANION_TYPES_NORTHWEST 8
#define ELMC_UNION_COMPANION_TYPES_POLARDAY 2
#define ELMC_UNION_COMPANION_TYPES_POLARNIGHT 3
#define ELMC_UNION_COMPANION_TYPES_PROVIDEALTITUDE 9
#define ELMC_UNION_COMPANION_TYPES_PROVIDEMOON 3
#define ELMC_UNION_COMPANION_TYPES_PROVIDEMOONPHASE 4
#define ELMC_UNION_COMPANION_TYPES_PROVIDESUN 2
#define ELMC_UNION_COMPANION_TYPES_PROVIDETIDE 7
#define ELMC_UNION_COMPANION_TYPES_PROVIDETIMEZONE 1
#define ELMC_UNION_COMPANION_TYPES_PROVIDEWEATHER 5
#define ELMC_UNION_COMPANION_TYPES_PROVIDEWIND 6
#define ELMC_UNION_COMPANION_TYPES_REQUESTSUNDATA 2
#define ELMC_UNION_COMPANION_TYPES_REQUESTUPDATE 1
#define ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER 3
#define ELMC_UNION_COMPANION_TYPES_SETCORNERUPDATEINTERVAL 10
#define ELMC_UNION_COMPANION_TYPES_SOUTH 5
#define ELMC_UNION_COMPANION_TYPES_SOUTHEAST 4
#define ELMC_UNION_COMPANION_TYPES_SOUTHWEST 6
#define ELMC_UNION_COMPANION_TYPES_SUNCYCLE 1
#define ELMC_UNION_COMPANION_TYPES_WEST 7
#define ELMC_UNION_CONNECTIONCHANGED 6
#define ELMC_UNION_COUNTDOWNSLOT 3
#define ELMC_UNION_CURRENTDATETIME 1
#define ELMC_UNION_DEFAULTFONT 1
#define ELMC_UNION_EAST 3
#define ELMC_UNION_FAHRENHEIT 2
#define ELMC_UNION_FALSE 2
#define ELMC_UNION_FEET 2
#define ELMC_UNION_FROMPHONE 10
#define ELMC_UNION_GOTHEALTHSUPPORTED 7
#define ELMC_UNION_GOTSTEPSTODAY 8
#define ELMC_UNION_HEALTHEVENT 9
#define ELMC_UNION_HOURCHANGED 3
#define ELMC_UNION_JUST 1
#define ELMC_UNION_MAIN_ALTITUDECORNER 1
#define ELMC_UNION_MAIN_BATTERYCORNER 1
#define ELMC_UNION_MAIN_BATTERYLEVELCHANGED 5
#define ELMC_UNION_MAIN_CONNECTIONCHANGED 6
#define ELMC_UNION_MAIN_CURRENTDATETIME 1
#define ELMC_UNION_MAIN_FROMPHONE 10
#define ELMC_UNION_MAIN_GOTHEALTHSUPPORTED 7
#define ELMC_UNION_MAIN_GOTSTEPSTODAY 8
#define ELMC_UNION_MAIN_HEALTHEVENT 9
#define ELMC_UNION_MAIN_HOURCHANGED 3
#define ELMC_UNION_MAIN_MINUTECHANGED 2
#define ELMC_UNION_MAIN_MOONCORNER 3
#define ELMC_UNION_MAIN_REQUESTREFRESH 11
#define ELMC_UNION_MAIN_SECONDCHANGED 4
#define ELMC_UNION_MAIN_STEPSCORNER 2
#define ELMC_UNION_MAIN_SUNCORNER 2
#define ELMC_UNION_MAIN_TEMPCORNER 1
#define ELMC_UNION_MAIN_WINDCORNER 2
#define ELMC_UNION_MAYBE_JUST 1
#define ELMC_UNION_MAYBE_NOTHING 2
#define ELMC_UNION_METERS 1
#define ELMC_UNION_METERSPERSECOND 1
#define ELMC_UNION_MILESPERHOUR 2
#define ELMC_UNION_MINUTECHANGED 2
#define ELMC_UNION_MOONCORNER 3
#define ELMC_UNION_NORTH 1
#define ELMC_UNION_NORTHEAST 2
#define ELMC_UNION_NORTHWEST 8
#define ELMC_UNION_NOTHING 2
#define ELMC_UNION_PEBBLE_HEALTH_STEPCOUNT 1
#define ELMC_UNION_PEBBLE_UI_RESOURCES_DEFAULTFONT 1
#define ELMC_UNION_PEBBLE_UI_RESOURCES_VECTORSTATICMOUNTAIN 1
#define ELMC_UNION_PEBBLE_UI_ROTATION 1
#define ELMC_UNION_POLARDAY 2
#define ELMC_UNION_POLARNIGHT 3
#define ELMC_UNION_PROVIDEALTITUDE 9
#define ELMC_UNION_PROVIDEMOON 3
#define ELMC_UNION_PROVIDEMOONPHASE 4
#define ELMC_UNION_PROVIDESUN 2
#define ELMC_UNION_PROVIDETIDE 7
#define ELMC_UNION_PROVIDETIMEZONE 1
#define ELMC_UNION_PROVIDEWEATHER 5
#define ELMC_UNION_PROVIDEWIND 6
#define ELMC_UNION_REQUESTREFRESH 11
#define ELMC_UNION_REQUESTSUNDATA 2
#define ELMC_UNION_REQUESTUPDATE 1
#define ELMC_UNION_REQUESTWEATHER 3
#define ELMC_UNION_ROTATION 1
#define ELMC_UNION_SECONDCHANGED 4
#define ELMC_UNION_SETCORNERUPDATEINTERVAL 10
#define ELMC_UNION_SIMPLELINE 2
#define ELMC_UNION_SOUTH 5
#define ELMC_UNION_SOUTHEAST 4
#define ELMC_UNION_SOUTHWEST 6
#define ELMC_UNION_STEPCOUNT 1
#define ELMC_UNION_STEPSCORNER 2
#define ELMC_UNION_SUNCORNER 2
#define ELMC_UNION_SUNCYCLE 1
#define ELMC_UNION_TEMPCORNER 1
#define ELMC_UNION_TRUE 1
#define ELMC_UNION_VECTORSTATICMOUNTAIN 1
#define ELMC_UNION_WEST 7
#define ELMC_UNION_WINDCORNER 2
#define ELMC_UNION_YES_RENDER_ALTITUDESLOT 1
#define ELMC_UNION_YES_RENDER_COUNTDOWNSLOT 3
#define ELMC_UNION_YES_RENDER_SIMPLELINE 2

const char *elmc_debug_union_ctor_name(elmc_int_t tag) {
  switch (tag) {
    case 4: return "SecondChanged";
    case 5: return "BatteryLevelChanged";
    case 6: return "ConnectionChanged";
    case 7: return "GotHealthSupported";
    case 8: return "GotStepsToday";
    case 9: return "HealthEvent";
    case 10: return "FromPhone";
    case 11: return "RequestRefresh";
    default: return NULL;
  }
}

enum {
  ELMC_FIELD_MAIN_MODEL_ALTITUDE = 14,
  ELMC_FIELD_MAIN_MODEL_BATTERYLEVEL = 4,
  ELMC_FIELD_MAIN_MODEL_CONNECTED = 5,
  ELMC_FIELD_MAIN_MODEL_CORNERCYCLE = 3,
  ELMC_FIELD_MAIN_MODEL_CORNERUPDATEINTERVALSEC = 15,
  ELMC_FIELD_MAIN_MODEL_DISPLAYSHAPE = 1,
  ELMC_FIELD_MAIN_MODEL_HEALTHSUPPORTED = 16,
  ELMC_FIELD_MAIN_MODEL_HOMETZOFFSETMIN = 6,
  ELMC_FIELD_MAIN_MODEL_LASTSUNFETCHDAYKEY = 18,
  ELMC_FIELD_MAIN_MODEL_LASTWEATHERFETCHHOURKEY = 19,
  ELMC_FIELD_MAIN_MODEL_LAYOUT = 0,
  ELMC_FIELD_MAIN_MODEL_MOONPHASEE6 = 10,
  ELMC_FIELD_MAIN_MODEL_MOONRISEMIN = 8,
  ELMC_FIELD_MAIN_MODEL_MOONSETMIN = 9,
  ELMC_FIELD_MAIN_MODEL_NOW = 2,
  ELMC_FIELD_MAIN_MODEL_STEPSTODAY = 17,
  ELMC_FIELD_MAIN_MODEL_SUN = 7,
  ELMC_FIELD_MAIN_MODEL_TIDE = 13,
  ELMC_FIELD_MAIN_MODEL_WEATHER = 11,
  ELMC_FIELD_MAIN_MODEL_WIND = 12,
  ELMC_FIELD_MAIN_SLOTSPEC_AVAILABLE = 1,
  ELMC_FIELD_MAIN_SLOTSPEC_EXCLUSIVE = 2,
  ELMC_FIELD_MAIN_SLOTSPEC_ID = 0,
  ELMC_FIELD_MAIN_TIDE_KIND = 3,
  ELMC_FIELD_MAIN_TIDE_LEVELCM = 1,
  ELMC_FIELD_MAIN_TIDE_NEXTMIN = 0,
  ELMC_FIELD_MAIN_TIDE_PROGRESS = 2,
  ELMC_FIELD_MAIN_WEATHER_CONDITION = 1,
  ELMC_FIELD_MAIN_WEATHER_PRECIPMM10 = 2,
  ELMC_FIELD_MAIN_WEATHER_PRESSUREHPA = 4,
  ELMC_FIELD_MAIN_WEATHER_TEMPERATURE = 0,
  ELMC_FIELD_MAIN_WEATHER_UV10 = 3,
  ELMC_FIELD_MAIN_WIND_DIRECTION = 0,
  ELMC_FIELD_MAIN_WIND_SPEED = 1,
  ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_X = 0,
  ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_Y = 1,
  ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_DAY = 2,
  ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_HOUR = 4,
  ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_MINUTE = 5,
  ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_MONTH = 1,
  ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_UTCOFFSETMINUTES = 7,
  ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_YEAR = 0,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_X = 0,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_Y = 1,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_H = 3,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_W = 2,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_X = 0,
  ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_Y = 1,
  ELMC_FIELD_PEBBLE_GAME_MATH_VEC2_X = 0,
  ELMC_FIELD_PEBBLE_GAME_MATH_VEC2_Y = 1,
  ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_H = 4,
  ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_W = 3,
  ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_X = 1,
  ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_Y = 2,
  ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN = 3,
  ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_HEIGHT = 1,
  ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_SHAPE = 2,
  ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_WIDTH = 0,
  ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_DAY = 2,
  ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_HOUR = 4,
  ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MINUTE = 5,
  ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MONTH = 1,
  ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_UTCOFFSETMINUTES = 7,
  ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_YEAR = 0,
  ELMC_FIELD_PEBBLE_UI_POINT_X = 0,
  ELMC_FIELD_PEBBLE_UI_POINT_Y = 1,
  ELMC_FIELD_PEBBLE_UI_RECT_H = 3,
  ELMC_FIELD_PEBBLE_UI_RECT_W = 2,
  ELMC_FIELD_PEBBLE_UI_RECT_X = 0,
  ELMC_FIELD_PEBBLE_UI_RECT_Y = 1,
  ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_HEIGHT = 3,
  ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_WIDTH = 2,
  ELMC_FIELD_PEBBLE_UI_RESOURCES_FONTINFO_HEIGHT = 2,
  ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_HEIGHT = 3,
  ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_WIDTH = 2,
  ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_BOTTOM = 1,
  ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_COUNTDOWNLABELH = 6,
  ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_COUNTDOWNTIMEH = 7,
  ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_LINEH = 3,
  ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_SINGLELINE = 5,
  ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_TEXTW = 2,
  ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_VECTOR = 4,
  ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_X = 0,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMLEFTWEATHER = 17,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT = 18,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_CX = 2,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_CY = 3,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_HANDLEN = 12,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_HUBR = 10,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_INNERRADIUS = 6,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_MINDIM = 4,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONPHASERADIUS = 8,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONRINGR = 11,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONY = 7,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_OUTERRADIUS = 5,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_PAD = 13,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_SCREENH = 1,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_SCREENW = 0,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_TIMETEXTBAND = 9,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_TOPLEFTLABEL = 15,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_TOPLEFTTITLE = 14,
  ELMC_FIELD_YES_LAYOUT_LAYOUT_TOPRIGHTDATE = 16,
  ELMC_FIELD_YES_RENDER_CORNERSLOTS_BOTTOMRIGHT = 3,
  ELMC_FIELD_YES_RENDER_CORNERSLOTS_DATE = 1,
  ELMC_FIELD_YES_RENDER_CORNERSLOTS_TOPLEFT = 0,
  ELMC_FIELD_YES_RENDER_CORNERSLOTS_WEATHER = 2,
  ELMC_FIELD_YES_RENDER_FACEDISPLAY_CORNERS = 5,
  ELMC_FIELD_YES_RENDER_FACEDISPLAY_HOMEMINUTE = 1,
  ELMC_FIELD_YES_RENDER_FACEDISPLAY_MOONPHASEE6 = 4,
  ELMC_FIELD_YES_RENDER_FACEDISPLAY_SHOWCORNERS = 0,
  ELMC_FIELD_YES_RENDER_FACEDISPLAY_SUN = 3,
  ELMC_FIELD_YES_RENDER_FACEDISPLAY_TIMETEXT = 2,
  ELMC_FIELD_YES_RENDER_SUNWINDOW_MODE = 2,
  ELMC_FIELD_YES_RENDER_SUNWINDOW_SUNRISEMIN = 0,
  ELMC_FIELD_YES_RENDER_SUNWINDOW_SUNSETMIN = 1,
  ELMC_FIELD_YES_RENDER_TICKSPEC_LABEL = 2,
  ELMC_FIELD_YES_RENDER_TICKSPEC_MINUTE = 0,
  ELMC_FIELD_YES_RENDER_TICKSPEC_OUTEREXTRA = 1
};

#define ELMC_RENDER_OP_CLEAR 2
#define ELMC_RENDER_OP_LINE 4
#define ELMC_RENDER_OP_CIRCLE 7
#define ELMC_RENDER_OP_FILL_CIRCLE 8
#define ELMC_RENDER_OP_PUSH_CONTEXT 10
#define ELMC_RENDER_OP_POP_CONTEXT 11
#define ELMC_RENDER_OP_STROKE_COLOR 14
#define ELMC_RENDER_OP_FILL_COLOR 15
#define ELMC_RENDER_OP_TEXT_COLOR 16
#define ELMC_RENDER_OP_CONTEXT_GROUP 19
#define ELMC_RENDER_OP_FILL_RADIAL 23
#define ELMC_RENDER_OP_TEXT 29
#define ELMC_RENDER_OP_VECTOR_AT 30
#define ELMC_CONTEXT_STROKE_COLOR 3
#define ELMC_CONTEXT_FILL_COLOR 4
#define ELMC_CONTEXT_TEXT_COLOR 5
#define ELMC_BUTTON_DOWN 3
#define ELMC_BUTTON_EVENT_RELEASED 2
#define ELMC_SUBSCRIPTION_SECOND_CHANGE 1
#define ELMC_SUBSCRIPTION_BATTERY 32
#define ELMC_SUBSCRIPTION_CONNECTION 64
#define ELMC_SUBSCRIPTION_APPMESSAGE 4096
#define ELMC_SUBSCRIPTION_HOUR_CHANGE 1024
#define ELMC_SUBSCRIPTION_MINUTE_CHANGE 2048
#define ELMC_SUBSCRIPTION_BUTTON_RAW 16384
#define ELMC_SUBSCRIPTION_HEALTH 2147483648LL
#define ELMC_TEXT_ALIGN_CENTER 1
#define ELMC_TEXT_OVERFLOW_WORD_WRAP 0
#define ELMC_TEXT_OVERFLOW_SHIFT 2
#define ELMC_COLOR_BLACK 192
#define ELMC_COLOR_BLUE_MOON 199
#define ELMC_COLOR_CHROME_YELLOW 248
#define ELMC_COLOR_DARK_GRAY 213
#define ELMC_COLOR_LIGHT_GRAY 234
#define ELMC_COLOR_OXFORD_BLUE 193
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

static inline ElmcValue *elmc_render_cmd6(
elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2,
elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
  ElmcValue *out = NULL;
  return elmc_render_cmd6_take(&out, kind, p0, p1, p2, p3, p4, p5) == RC_SUCCESS ? out : NULL;
}

static RC elmc_fn_Main_showCorners_native(bool *out, ElmcValue * const model);
static RC elmc_fn_Main_topLeftBatteryAvailable_native(bool *out, ElmcValue * const model);
static RC elmc_fn_Main_topLeftStepsAvailable_native(bool *out, ElmcValue * const model);
static RC elmc_fn_Main_hasWind_native(bool *out, ElmcValue * const model);
static RC elmc_fn_Main_hasMoonTimes_native(bool *out, ElmcValue * const model);
static RC elmc_fn_Main_batteryAlert_native(bool *out, ElmcValue * const model);
static RC elmc_fn_Main_haveSteps_native(bool *out, ElmcValue * const model);

static RC elmc_fn_Main_pickBottomRight_native(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_temperatureString_native(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_windSpeedString_native(ElmcValue **out, ElmcValue *speed);
static RC elmc_fn_Main_altitudeString_native(ElmcValue **out, ElmcValue *altitude);
static RC elmc_fn_Main_batteryPercentString_native(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_stepsString_native(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_directionString_native(ElmcValue **out, ElmcValue *direction);
static RC elmc_fn_Main_monthString_native(ElmcValue **out, elmc_int_t month);
static RC elmc_fn_Companion_Internal_watchToPhoneTag_native(ElmcValue **out, elmc_int_t message);
static RC elmc_fn_Companion_Internal_watchToPhoneValue_native(ElmcValue **out, elmc_int_t message);

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue *context);
RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model);
static RC elmc_fn_Main_updateFromPhone(ElmcValue **out, ElmcValue *message, ElmcValue *model);
static RC elmc_fn_Main_scheduleCompanionFetches(ElmcValue **out, ElmcValue *model, ElmcValue *extraCmd);
static elmc_int_t elmc_fn_Main_calendarDayKey(ElmcValue *now);
static elmc_int_t elmc_fn_Main_calendarHourKey(ElmcValue *now);
static RC elmc_fn_Main_refreshStepsIfSupported(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_shouldRefreshCorners(bool *out, ElmcValue *model, elmc_int_t second);
static RC elmc_fn_Main_showCorners(ElmcValue **out, ElmcValue *model);
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_faceOps(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_faceDisplay(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_cornerSlots(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_topLeftSlot(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_dateSlot(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_weatherSlot(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_bottomRightSlot(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_sunBottomRightSlot(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_moonBottomRightSlot(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_pickSlot(ElmcValue **out, ElmcValue *model, ElmcValue *slots);
static RC elmc_fn_Main_pickFromCycledList(ElmcValue **out, ElmcValue *model, ElmcValue *items);
static RC elmc_fn_Main_pickTopLeft(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_topLeftSlots(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_topLeftBatteryAvailable(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_topLeftStepsAvailable(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_pickWeatherMode(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_availableWeatherModes(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_weatherLabel(ElmcValue **out, ElmcValue *model, ElmcValue *mode);
static RC elmc_fn_Main_hasWind(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_pickBottomRight(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_bottomRightSlots(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_hasMoonTimes(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_homeMinuteOfDay(elmc_int_t *out, ElmcValue *model);
static ElmcValue *elmc_fn_Main_eventMinuteFromPayload(elmc_int_t rise, elmc_int_t set, ElmcValue *value);
static RC elmc_fn_Main_timeString(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_temperatureString(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_windString(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_windSpeedString(ElmcValue **out, ElmcValue *speed);
static RC elmc_fn_Main_altitudeString(ElmcValue **out, ElmcValue *altitude);
static RC elmc_fn_Main_nextSunCountdown(ElmcValue **out, elmc_int_t nowMin, ElmcValue *maybeSun);
static RC elmc_fn_Main_nextMoonCountdown(ElmcValue **out, elmc_int_t nowMin, ElmcValue *maybeRise, ElmcValue *maybeSet);
static RC elmc_fn_Main_nextEventParts(ElmcValue **out, elmc_int_t nowMin, ElmcValue *riseLabel, ElmcValue *setLabel, ElmcValue *maybeRise, ElmcValue *maybeSet);
static elmc_int_t elmc_fn_Main_minutesUntilCircular(elmc_int_t fromMinute, elmc_int_t toMinute);
static RC elmc_fn_Main_durationString(ElmcValue **out, elmc_int_t minutes);
static RC elmc_fn_Main_batteryAlert(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_haveSteps(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_batteryPercentString(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_stepsString(ElmcValue **out, ElmcValue *model);
static RC elmc_fn_Main_normalizeCycleSec(elmc_int_t *out, elmc_int_t seconds);
static elmc_int_t elmc_fn_Main_cycleSlot(ElmcValue *model, elmc_int_t count_arg);
static RC elmc_fn_Main_directionString(ElmcValue **out, ElmcValue *direction);
static RC elmc_fn_Main_monthString(ElmcValue **out, elmc_int_t month);
static RC elmc_fn_Main_pad2(ElmcValue **out, elmc_int_t value);
static RC elmc_fn_Main_main(ElmcValue **out);
static RC elmc_fn_Yes_Layout_fromScreen(ElmcValue **out, elmc_int_t screenW, elmc_int_t screenH);
static RC elmc_fn_Yes_Layout_centerSquare(ElmcValue **out, ElmcValue *layout, elmc_int_t radius);
static RC elmc_fn_Yes_Render_face(ElmcValue **out, ElmcValue *layout, ElmcValue *display);
static RC elmc_fn_Yes_Render_drawDial(ElmcValue **out, ElmcValue *layout, ElmcValue *display);
static RC elmc_fn_Yes_Render_draw24HourHand(ElmcValue **out, ElmcValue *layout, elmc_int_t nowMin);
static RC elmc_fn_Yes_Render_drawOuterScale(ElmcValue **out, ElmcValue *layout);
static RC elmc_fn_Yes_Render_drawScaleTick(ElmcValue **out, ElmcValue *layout, ElmcValue *spec);
static RC elmc_fn_Yes_Render_coloredRadial(ElmcValue **out, ElmcValue *bounds, ElmcValue *fill, elmc_int_t start, elmc_int_t end);
static RC elmc_fn_Yes_Render_coloredRadialWedge(ElmcValue **out, ElmcValue *bounds, ElmcValue *color, elmc_int_t startAngle, elmc_int_t endAngle);
static RC elmc_fn_Yes_Render_drawSunWindow(ElmcValue **out, ElmcValue *center, elmc_int_t radius, ElmcValue *bounds, elmc_int_t sunriseAngle, elmc_int_t sunsetAngle, ElmcValue *sunWindow);
static RC elmc_fn_Yes_Render_drawMoonGlyph(ElmcValue **out, ElmcValue *layout, ElmcValue *maybePhase);
static RC elmc_fn_Yes_Render_drawMoonPhase(ElmcValue **out, ElmcValue *layout, ElmcValue *phaseE6);
static RC elmc_fn_Yes_Render_drawCorners(ElmcValue **out, ElmcValue *layout, ElmcValue *slots);
static RC elmc_fn_Yes_Render_drawTopLeft(ElmcValue **out, ElmcValue *layout, ElmcValue *slot);
static RC elmc_fn_Yes_Render_drawDate(ElmcValue **out, ElmcValue *layout, ElmcValue *maybeDate);
static RC elmc_fn_Yes_Render_drawWeatherCorner(ElmcValue **out, ElmcValue *layout, ElmcValue *maybeLabel);
static RC elmc_fn_Yes_Render_drawBottomRight(ElmcValue **out, ElmcValue *layout, ElmcValue *slot);
static RC elmc_fn_Yes_Render_drawBottomRightCountdown(ElmcValue **out, ElmcValue *layout, ElmcValue *label, ElmcValue *timeLine);
static RC elmc_fn_Yes_Render_defaultSunWindow(ElmcValue **out);
static RC elmc_fn_Yes_Render_textAt(ElmcValue **out, ElmcValue *color, ElmcValue *bounds, ElmcValue *value);
static RC elmc_fn_Yes_Render_pointAt(ElmcValue **out, elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle);
static elmc_int_t elmc_fn_Yes_Render_angleFromMinute(elmc_int_t minute);
static RC elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **out, ElmcValue *message);
static RC elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **out, ElmcValue *message);
static RC elmc_fn_Pebble_Ui_Color_black(ElmcValue **out);
static RC elmc_fn_Pebble_Ui_Color_oxfordBlue(ElmcValue **out);
static RC elmc_fn_Pebble_Ui_Color_blueMoon(ElmcValue **out);
static RC elmc_fn_Pebble_Ui_Color_darkGray(ElmcValue **out);
static RC elmc_fn_Pebble_Ui_Color_lightGray(ElmcValue **out);
static RC elmc_fn_Pebble_Ui_Color_white(ElmcValue **out);
static RC elmc_fn_Basics_pi(ElmcValue **out);

static RC elmc_fn_Main_pickSlot_closure_0(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      owned[0] = elmc_retain(elmc_record_get_index((argc > 0 ? args[0] : NULL), ELMC_FIELD_MAIN_SLOTSPEC_EXCLUSIVE));
      if (!elmc_as_bool(owned[0])) goto elmc_plan_block_2;
      owned[1] = elmc_retain(elmc_record_get_index((argc > 0 ? args[0] : NULL), ELMC_FIELD_MAIN_SLOTSPEC_AVAILABLE));
      goto elmc_plan_block_3;
      elmc_plan_block_2:
      Rc = elmc_new_bool(&owned[2], false);
      CHECK_RC(Rc);
      elmc_plan_block_3:
      if (elmc_as_bool(owned[0])) {
        owned[3] = owned[1];
        owned[1] = NULL;
      } else {
        owned[3] = owned[2];
        owned[2] = NULL;
      }
      *out = owned[3];
      owned[3] = NULL;
    CATCH_END
  CATCH_END

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Yes_Render_drawOuterScale_closure_0(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      Rc = elmc_new_int(&owned[0], 60);
      CHECK_RC(Rc);
      Rc = elmc_new_int(&owned[2], elmc_as_int((argc > 0 ? args[0] : NULL)) * elmc_as_int(owned[0]));
      CHECK_RC(Rc);
      owned[3] = elmc_maybe_nothing();
      ElmcValue *plan_ephemeral_box_2754 = NULL;
      Rc = elmc_new_int(&plan_ephemeral_box_2754, 10);
      CHECK_RC(Rc);
      ElmcValue *rec_values_12_26[3] = { owned[2], plan_ephemeral_box_2754, owned[3] };
      Rc = elmc_record_new_values_take(&owned[1], 3, rec_values_12_26);
      CHECK_RC(Rc);
      owned[2] = NULL;
      owned[3] = NULL;
      owned[2] = NULL;
      owned[3] = NULL;
      *out = owned[1];
      owned[1] = NULL;
    CATCH_END
  CATCH_END

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Yes_Render_drawOuterScale_closure_1(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      Rc = elmc_new_bool(&owned[0], (elmc_int_mod_by(2, elmc_as_int((argc > 0 ? args[0] : NULL))) == 1));
      CHECK_RC(Rc);
      *out = owned[0];
      owned[0] = NULL;
    CATCH_END
  CATCH_END

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Yes_Render_drawOuterScale_closure_2(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)captures;
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[8] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      Rc = elmc_new_int(&owned[0], 120);
      CHECK_RC(Rc);
      Rc = elmc_new_int(&owned[1], elmc_as_int((argc > 0 ? args[0] : NULL)) * elmc_as_int(owned[0]));
      CHECK_RC(Rc);
      owned[6] = elmc_retain(owned[1]);
      Rc = elmc_new_int(&owned[2], 2);
      CHECK_RC(Rc);
      Rc = elmc_new_int(&owned[3], elmc_as_int((argc > 0 ? args[0] : NULL)) * elmc_as_int(owned[2]));
      CHECK_RC(Rc);
      Rc = elmc_string_from_int(&owned[4], owned[3]);
      CHECK_RC(Rc);
      Rc = elmc_maybe_just_own(&owned[7], owned[4]);
      CHECK_RC(Rc);
      owned[4] = NULL;
      ElmcValue *plan_ephemeral_box_2770 = NULL;
      Rc = elmc_new_int(&plan_ephemeral_box_2770, 6);
      CHECK_RC(Rc);
      ElmcValue *rec_values_16_27[3] = { owned[6], plan_ephemeral_box_2770, owned[7] };
      Rc = elmc_record_new_values_take(&owned[5], 3, rec_values_16_27);
      CHECK_RC(Rc);
      owned[6] = NULL;
      owned[7] = NULL;
      owned[6] = NULL;
      owned[7] = NULL;
      *out = owned[5];
      owned[5] = NULL;
    CATCH_END
  CATCH_END

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Yes_Render_drawOuterScale_closure_3(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)capture_count;
  RC Rc = RC_SUCCESS;

  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    CATCH_BEGIN
      Rc = elmc_fn_Yes_Render_drawScaleTick(&owned[0], captures[0], (argc > 0 ? args[0] : NULL));
      CHECK_RC(Rc);
      *out = owned[0];
      owned[0] = NULL;
    CATCH_END
  CATCH_END

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue *context) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[34] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(context, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN));
    const elmc_int_t plan_native_int_2 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_WIDTH);
    owned[1] = elmc_retain(elmc_record_get_index(context, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN));
    const elmc_int_t plan_native_int_4 = ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_HEIGHT);
    Rc = elmc_fn_Yes_Layout_fromScreen(&owned[2], plan_native_int_2, plan_native_int_4);
    CHECK_RC(Rc);
    owned[4] = elmc_retain(owned[2]);
    owned[3] = elmc_retain(elmc_record_get_index(context, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN));
    owned[5] = elmc_retain(elmc_record_get_index(owned[3], ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_SHAPE));
    owned[6] = elmc_maybe_nothing();
    owned[7] = elmc_maybe_nothing();
    owned[8] = elmc_maybe_nothing();
    owned[9] = elmc_maybe_nothing();
    owned[10] = elmc_maybe_nothing();
    owned[11] = elmc_maybe_nothing();
    owned[12] = elmc_maybe_nothing();
    owned[13] = elmc_maybe_nothing();
    owned[14] = elmc_maybe_nothing();
    owned[15] = elmc_maybe_nothing();
    owned[16] = elmc_maybe_nothing();
    owned[17] = elmc_maybe_nothing();
    owned[18] = elmc_maybe_nothing();
    owned[19] = elmc_maybe_nothing();
    owned[20] = elmc_maybe_nothing();
    ElmcValue *plan_ephemeral_box_1298 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1298, 5);
    CHECK_RC(Rc);
    ElmcValue *rec_values_66_1[20] = { owned[4], owned[5], owned[6], elmc_int_zero(), owned[7], owned[8], elmc_retain(elmc_int_zero()), owned[9], owned[10], owned[11], owned[12], owned[13], owned[14], owned[15], owned[16], plan_ephemeral_box_1298, owned[17], owned[18], owned[19], owned[20] };
    Rc = elmc_record_new_values_take(&owned[33], 20, rec_values_66_1);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[5] = NULL;
    owned[6] = NULL;
    owned[7] = NULL;
    owned[8] = NULL;
    owned[9] = NULL;
    owned[10] = NULL;
    owned[11] = NULL;
    owned[12] = NULL;
    owned[13] = NULL;
    owned[14] = NULL;
    owned[15] = NULL;
    owned[16] = NULL;
    owned[17] = NULL;
    owned[18] = NULL;
    owned[19] = NULL;
    owned[20] = NULL;
    owned[4] = NULL;
    owned[5] = NULL;
    owned[6] = NULL;
    owned[7] = NULL;
    owned[8] = NULL;
    owned[9] = NULL;
    owned[10] = NULL;
    owned[11] = NULL;
    owned[12] = NULL;
    owned[13] = NULL;
    owned[14] = NULL;
    owned[15] = NULL;
    owned[16] = NULL;
    owned[17] = NULL;
    owned[18] = NULL;
    owned[19] = NULL;
    owned[20] = NULL;
    Rc = elmc_cmd1(&owned[21], ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_CURRENTDATETIME);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[22], ELMC_PEBBLE_CMD_GET_BATTERY_LEVEL, ELMC_PEBBLE_MSG_BATTERYLEVELCHANGED);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[23], ELMC_PEBBLE_CMD_GET_CONNECTION_STATUS, ELMC_PEBBLE_MSG_CONNECTIONCHANGED);
    CHECK_RC(Rc);
    Rc = elmc_cmd1(&owned[24], ELMC_PEBBLE_CMD_HEALTH_SUPPORTED, ELMC_PEBBLE_MSG_GOTHEALTHSUPPORTED);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[25], 3);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[26], 0);
    CHECK_RC(Rc);
    Rc = elmc_cmd2(&owned[27], ELMC_PEBBLE_CMD_COMPANION_SEND, elmc_as_int(owned[25]), elmc_as_int(owned[26]));
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[28], 4);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[29], 0);
    CHECK_RC(Rc);
    Rc = elmc_cmd2(&owned[30], ELMC_PEBBLE_CMD_COMPANION_SEND, elmc_as_int(owned[28]), elmc_as_int(owned[29]));
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_1314[6] = { owned[21], owned[22], owned[23], owned[24], owned[27], owned[30] };
    Rc = elmc_list_from_values(&owned[31], plan_list_items_1314, 6);
    CHECK_RC(Rc);
    Rc = elmc_cmd_batch(&owned[32], owned[31]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(out, owned[33], owned[32]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[70] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    switch (elmc_union_tag_as_int(msg)) {
      case ELMC_UNION_MAIN_CURRENTDATETIME: goto elmc_plan_block_2;
      case ELMC_UNION_MAIN_MINUTECHANGED: goto elmc_plan_block_4;
      case ELMC_UNION_MAIN_HOURCHANGED: goto elmc_plan_block_11;
      case ELMC_UNION_MAIN_SECONDCHANGED: goto elmc_plan_block_13;
      case ELMC_UNION_MAIN_BATTERYLEVELCHANGED: goto elmc_plan_block_25;
      case ELMC_UNION_MAIN_CONNECTIONCHANGED: goto elmc_plan_block_27;
      case ELMC_UNION_MAIN_GOTHEALTHSUPPORTED: goto elmc_plan_block_29;
      case ELMC_UNION_MAIN_GOTSTEPSTODAY: goto elmc_plan_block_36;
      case ELMC_UNION_MAIN_HEALTHEVENT: goto elmc_plan_block_38;
      case ELMC_UNION_MAIN_FROMPHONE: goto elmc_plan_block_40;
      case ELMC_UNION_MAIN_REQUESTREFRESH: goto elmc_plan_block_42;
      default: goto elmc_plan_block_45;
    }
    elmc_plan_block_2:
    owned[1] = elmc_tuple_second_borrow(msg);
    Rc = elmc_maybe_just(&owned[2], owned[1]);
    CHECK_RC(Rc);
    owned[1] = NULL;
    owned[3] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[4], owned[3], ELMC_FIELD_MAIN_MODEL_NOW, owned[2]);
    CHECK_RC(Rc);
    if (owned[4] == owned[3]) {
      owned[4] = elmc_retain(owned[4]);
    }
    owned[3] = NULL;
    owned[5] = elmc_cmd_none();
    Rc = elmc_fn_Main_scheduleCompanionFetches(&owned[0], owned[4], owned[5]);
    CHECK_RC(Rc);
    if (owned[0] == owned[5]) {
      owned[5] = NULL;
    }
    goto elmc_plan_block_45;
    elmc_plan_block_4:
    owned[6] = elmc_tuple_second_borrow(msg);
    owned[7] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_NOW));
    const bool plan_native_bool_14 = elmc_maybe_is_nothing(owned[7]);
    if (!plan_native_bool_14) goto elmc_plan_block_6;
    Rc = elmc_cmd1(&owned[8], ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_CURRENTDATETIME);
    CHECK_RC(Rc);
    owned[10] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[9], owned[10], owned[8]);
    CHECK_RC(Rc);
    goto elmc_plan_block_7;
    elmc_plan_block_6:
    owned[11] = elmc_retain(elmc_maybe_just_payload(owned[7]));
    owned[12] = owned[6];
    owned[6] = NULL;
    owned[13] = owned[11];
    owned[11] = NULL;
    Rc = elmc_record_update_index_cow_drop(&owned[14], owned[13], ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MINUTE, owned[12]);
    CHECK_RC(Rc);
    if (owned[14] == owned[13]) {
      owned[14] = elmc_retain(owned[14]);
    }
    owned[13] = NULL;
    Rc = elmc_maybe_just_own(&owned[15], owned[14]);
    CHECK_RC(Rc);
    owned[14] = NULL;
    owned[16] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[17], owned[16], ELMC_FIELD_MAIN_MODEL_NOW, owned[15]);
    CHECK_RC(Rc);
    if (owned[17] == owned[16]) {
      owned[17] = elmc_retain(owned[17]);
    }
    owned[16] = NULL;
    Rc = elmc_fn_Main_refreshStepsIfSupported(&owned[18], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_scheduleCompanionFetches(&owned[19], owned[17], owned[18]);
    CHECK_RC(Rc);
    if (owned[19] == owned[17]) {
      owned[17] = NULL;
    }
    if (owned[19] == owned[18]) {
      owned[18] = NULL;
    }
    elmc_plan_block_7:
    if (plan_native_bool_14) {
      owned[20] = owned[9];
      owned[9] = NULL;
    } else {
      owned[20] = owned[19];
      owned[19] = NULL;
    }
    owned[0] = owned[20];
    owned[20] = NULL;
    goto elmc_plan_block_45;
    elmc_plan_block_11:
    owned[21] = elmc_tuple_second_borrow(msg);
    Rc = elmc_cmd1(&owned[22], ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_CURRENTDATETIME);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_scheduleCompanionFetches(&owned[0], model, owned[22]);
    CHECK_RC(Rc);
    if (owned[0] == owned[22]) {
      owned[22] = NULL;
    }
    goto elmc_plan_block_45;
    elmc_plan_block_13:
    owned[23] = elmc_tuple_second_borrow(msg);
    bool plan_call_bool_39 = false;
    Rc = elmc_fn_Main_shouldRefreshCorners(&plan_call_bool_39, model, elmc_as_int(owned[23]));
    CHECK_RC(Rc);
    Rc = elmc_new_bool(&owned[24], plan_call_bool_39);
    CHECK_RC(Rc);
    if (!elmc_as_bool(owned[24])) goto elmc_plan_block_15;
    Rc = elmc_fn_Main_showCorners(&owned[25], model);
    CHECK_RC(Rc);
    if (!elmc_as_bool(owned[25])) goto elmc_plan_block_18;
    const elmc_int_t plan_native_int_43 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_CORNERCYCLE);
    const elmc_int_t plan_native_int_45 = plan_native_int_43 + 1;
    owned[26] = elmc_retain(model);
    Rc = elmc_record_update_index_int_cow_drop(&owned[27], owned[26], ELMC_FIELD_MAIN_MODEL_CORNERCYCLE, plan_native_int_45);
    CHECK_RC(Rc);
    if (owned[27] == owned[26]) {
      owned[27] = elmc_retain(owned[27]);
    }
    owned[26] = NULL;
    elmc_plan_block_18:
    if (elmc_as_bool(owned[25])) {
      owned[28] = owned[27];
      owned[27] = NULL;
    } else {
      owned[28] = elmc_retain(model);
    }
    owned[29] = elmc_cmd_none();
    owned[31] = owned[28];
    owned[28] = NULL;
    Rc = elmc_tuple2(&owned[30], owned[31], owned[29]);
    CHECK_RC(Rc);
    goto elmc_plan_block_16;
    elmc_plan_block_15:
    owned[32] = elmc_cmd_none();
    owned[34] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[33], owned[34], owned[32]);
    CHECK_RC(Rc);
    elmc_plan_block_16:
    if (elmc_as_bool(owned[24])) {
      owned[35] = owned[30];
      owned[30] = NULL;
    } else {
      owned[35] = owned[33];
      owned[33] = NULL;
    }
    owned[0] = owned[35];
    owned[35] = NULL;
    goto elmc_plan_block_45;
    elmc_plan_block_25:
    owned[36] = elmc_tuple_second_borrow(msg);
    Rc = elmc_new_int(&owned[37], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[38], 100);
    CHECK_RC(Rc);
    Rc = elmc_basics_clamp(&owned[39], owned[37], owned[38], owned[36]);
    CHECK_RC(Rc);
    if (owned[39] == owned[37]) {
      elmc_release(owned[39]);
      owned[37] = NULL;
    }
    if (owned[39] == owned[38]) {
      elmc_release(owned[39]);
      owned[38] = NULL;
    }
    if (owned[39] == owned[36]) {
      elmc_release(owned[39]);
      owned[36] = NULL;
    }
    Rc = elmc_maybe_just_own(&owned[40], owned[39]);
    CHECK_RC(Rc);
    owned[39] = NULL;
    owned[41] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[42], owned[41], ELMC_FIELD_MAIN_MODEL_BATTERYLEVEL, owned[40]);
    CHECK_RC(Rc);
    if (owned[42] == owned[41]) {
      owned[42] = elmc_retain(owned[42]);
    }
    owned[41] = NULL;
    owned[43] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[42], owned[43]);
    CHECK_RC(Rc);
    goto elmc_plan_block_45;
    elmc_plan_block_27:
    owned[44] = elmc_tuple_second_borrow(msg);
    Rc = elmc_maybe_just(&owned[45], owned[44]);
    CHECK_RC(Rc);
    owned[44] = NULL;
    owned[46] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[47], owned[46], ELMC_FIELD_MAIN_MODEL_CONNECTED, owned[45]);
    CHECK_RC(Rc);
    if (owned[47] == owned[46]) {
      owned[47] = elmc_retain(owned[47]);
    }
    owned[46] = NULL;
    owned[48] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[47], owned[48]);
    CHECK_RC(Rc);
    goto elmc_plan_block_45;
    elmc_plan_block_29:
    owned[49] = elmc_tuple_second_borrow(msg);
    owned[50] = elmc_retain(owned[49]);
    Rc = elmc_maybe_just_own(&owned[51], owned[50]);
    CHECK_RC(Rc);
    owned[50] = NULL;
    owned[52] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[53], owned[52], ELMC_FIELD_MAIN_MODEL_HEALTHSUPPORTED, owned[51]);
    CHECK_RC(Rc);
    if (owned[53] == owned[52]) {
      owned[53] = elmc_retain(owned[53]);
    }
    owned[52] = NULL;
    if (!elmc_as_bool(owned[49])) goto elmc_plan_block_31;
    Rc = elmc_cmd2(&owned[54], ELMC_PEBBLE_CMD_HEALTH_SUM_TODAY, 1, ELMC_PEBBLE_MSG_GOTSTEPSTODAY);
    CHECK_RC(Rc);
    goto elmc_plan_block_32;
    elmc_plan_block_31:
    owned[55] = elmc_cmd_none();
    elmc_plan_block_32:
    if (elmc_as_bool(owned[49])) {
      owned[56] = owned[54];
      owned[54] = NULL;
    } else {
      owned[56] = owned[55];
      owned[55] = NULL;
    }
    Rc = elmc_tuple2(&owned[0], owned[53], owned[56]);
    CHECK_RC(Rc);
    goto elmc_plan_block_45;
    elmc_plan_block_36:
    owned[57] = elmc_tuple_second_borrow(msg);
    Rc = elmc_maybe_just(&owned[58], owned[57]);
    CHECK_RC(Rc);
    owned[57] = NULL;
    owned[59] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[60], owned[59], ELMC_FIELD_MAIN_MODEL_STEPSTODAY, owned[58]);
    CHECK_RC(Rc);
    if (owned[60] == owned[59]) {
      owned[60] = elmc_retain(owned[60]);
    }
    owned[59] = NULL;
    owned[61] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[60], owned[61]);
    CHECK_RC(Rc);
    goto elmc_plan_block_45;
    elmc_plan_block_38:
    owned[62] = elmc_tuple_second_borrow(msg);
    Rc = elmc_fn_Main_refreshStepsIfSupported(&owned[63], model);
    CHECK_RC(Rc);
    owned[64] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[64], owned[63]);
    CHECK_RC(Rc);
    goto elmc_plan_block_45;
    elmc_plan_block_40:
    owned[65] = elmc_tuple_second_borrow(msg);
    Rc = elmc_fn_Main_updateFromPhone(&owned[66], owned[65], model);
    CHECK_RC(Rc);
    owned[67] = elmc_cmd_none();
    Rc = elmc_tuple2(&owned[0], owned[66], owned[67]);
    CHECK_RC(Rc);
    goto elmc_plan_block_45;
    elmc_plan_block_42:
    Rc = elmc_cmd2(&owned[68], ELMC_PEBBLE_CMD_COMPANION_SEND, 2, 0);
    CHECK_RC(Rc);
    owned[69] = elmc_retain(model);
    Rc = elmc_tuple2(&owned[0], owned[69], owned[68]);
    CHECK_RC(Rc);
    elmc_plan_block_45:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[1] = NULL;
  owned[21] = NULL;
  owned[23] = NULL;
  owned[36] = NULL;
  owned[44] = NULL;
  owned[49] = NULL;
  owned[57] = NULL;
  owned[62] = NULL;
  owned[65] = NULL;
  owned[6] = NULL;
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static __attribute__((noinline, noclone)) RC elmc_fn_Main_updateFromPhone(ElmcValue **out, ElmcValue *message, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[63] = {0};
  CATCH_BEGIN
    elmc_int_t plan_native_int_119 = 0;
    /* plan block 0 */
    switch (elmc_union_tag_as_int(message)) {
      case ELMC_UNION_COMPANION_TYPES_PROVIDETIMEZONE: goto elmc_plan_block_2;
      case ELMC_UNION_COMPANION_TYPES_PROVIDESUN: goto elmc_plan_block_4;
      case ELMC_UNION_COMPANION_TYPES_PROVIDEMOON: goto elmc_plan_block_6;
      case ELMC_UNION_COMPANION_TYPES_PROVIDEMOONPHASE: goto elmc_plan_block_8;
      case ELMC_UNION_COMPANION_TYPES_PROVIDEWEATHER: goto elmc_plan_block_10;
      case ELMC_UNION_COMPANION_TYPES_PROVIDEWIND: goto elmc_plan_block_12;
      case ELMC_UNION_COMPANION_TYPES_PROVIDETIDE: goto elmc_plan_block_14;
      case ELMC_UNION_COMPANION_TYPES_CLEARTIDE: goto elmc_plan_block_16;
      case ELMC_UNION_COMPANION_TYPES_PROVIDEALTITUDE: goto elmc_plan_block_18;
      case ELMC_UNION_COMPANION_TYPES_SETCORNERUPDATEINTERVAL: goto elmc_plan_block_20;
      default: goto elmc_plan_block_23;
    }
    elmc_plan_block_2:
    owned[1] = elmc_tuple_second_borrow(message);
    owned[2] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[0], owned[2], ELMC_FIELD_MAIN_MODEL_HOMETZOFFSETMIN, owned[1]);
    CHECK_RC(Rc);
    if (owned[0] == owned[2]) {
      owned[0] = elmc_retain(owned[0]);
    }
    owned[2] = NULL;
    goto elmc_plan_block_23;
    elmc_plan_block_4:
    owned[3] = elmc_tuple_second_borrow(message);
    owned[5] = elmc_tuple_first_borrow(owned[3]);
    owned[4] = elmc_tuple_second_borrow(owned[3]);
    owned[6] = elmc_tuple_first_borrow(owned[4]);
    owned[7] = elmc_tuple_second_borrow(owned[4]);
    ElmcValue *rec_values_20_2[3] = { elmc_retain(owned[5]), elmc_retain(owned[6]), elmc_retain(owned[7]) };
    Rc = elmc_record_new_values_take(&owned[8], 3, rec_values_20_2);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[6] = NULL;
    owned[7] = NULL;
    Rc = elmc_maybe_just_own(&owned[9], owned[8]);
    CHECK_RC(Rc);
    owned[8] = NULL;
    owned[10] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[0], owned[10], ELMC_FIELD_MAIN_MODEL_SUN, owned[9]);
    CHECK_RC(Rc);
    if (owned[0] == owned[10]) {
      owned[0] = elmc_retain(owned[0]);
    }
    owned[10] = NULL;
    goto elmc_plan_block_23;
    elmc_plan_block_6:
    owned[11] = elmc_tuple_second_borrow(message);
    owned[12] = elmc_tuple_first_borrow(owned[11]);
    owned[13] = elmc_tuple_second_borrow(owned[11]);
    owned[14] = elmc_tuple_first_borrow(owned[13]);
    owned[20] = elmc_tuple_second_borrow(owned[13]);
    owned[15] = elmc_fn_Main_eventMinuteFromPayload(elmc_as_int(owned[12]), elmc_as_int(owned[14]), owned[12]);
    owned[16] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[17], owned[16], ELMC_FIELD_MAIN_MODEL_MOONRISEMIN, owned[15]);
    CHECK_RC(Rc);
    if (owned[17] == owned[16]) {
      owned[17] = elmc_retain(owned[17]);
    }
    owned[16] = NULL;
    owned[18] = elmc_fn_Main_eventMinuteFromPayload(elmc_as_int(owned[12]), elmc_as_int(owned[14]), owned[14]);
    Rc = elmc_record_update_index_cow_drop(&owned[19], owned[17], ELMC_FIELD_MAIN_MODEL_MOONSETMIN, owned[18]);
    CHECK_RC(Rc);
    owned[17] = NULL;
    Rc = elmc_maybe_just(&owned[21], owned[20]);
    CHECK_RC(Rc);
    owned[20] = NULL;
    Rc = elmc_record_update_index_cow_drop(&owned[0], owned[19], ELMC_FIELD_MAIN_MODEL_MOONPHASEE6, owned[21]);
    CHECK_RC(Rc);
    owned[19] = NULL;
    goto elmc_plan_block_23;
    elmc_plan_block_8:
    owned[22] = elmc_tuple_second_borrow(message);
    Rc = elmc_maybe_just(&owned[23], owned[22]);
    CHECK_RC(Rc);
    owned[22] = NULL;
    owned[24] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[0], owned[24], ELMC_FIELD_MAIN_MODEL_MOONPHASEE6, owned[23]);
    CHECK_RC(Rc);
    if (owned[0] == owned[24]) {
      owned[0] = elmc_retain(owned[0]);
    }
    owned[24] = NULL;
    goto elmc_plan_block_23;
    elmc_plan_block_10:
    owned[25] = elmc_tuple_second_borrow(message);
    owned[29] = elmc_tuple_first_borrow(owned[25]);
    owned[26] = elmc_tuple_second_borrow(owned[25]);
    owned[30] = elmc_tuple_first_borrow(owned[26]);
    owned[27] = elmc_tuple_second_borrow(owned[26]);
    owned[31] = elmc_tuple_first_borrow(owned[27]);
    owned[28] = elmc_tuple_second_borrow(owned[27]);
    owned[32] = elmc_tuple_first_borrow(owned[28]);
    owned[33] = elmc_tuple_second_borrow(owned[28]);
    ElmcValue *rec_values_68_3[5] = { elmc_retain(owned[29]), elmc_retain(owned[30]), elmc_retain(owned[31]), elmc_retain(owned[32]), elmc_retain(owned[33]) };
    Rc = elmc_record_new_values_take(&owned[34], 5, rec_values_68_3);
    CHECK_RC(Rc);
    owned[29] = NULL;
    owned[30] = NULL;
    owned[31] = NULL;
    owned[32] = NULL;
    owned[33] = NULL;
    Rc = elmc_maybe_just_own(&owned[35], owned[34]);
    CHECK_RC(Rc);
    owned[34] = NULL;
    owned[36] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[0], owned[36], ELMC_FIELD_MAIN_MODEL_WEATHER, owned[35]);
    CHECK_RC(Rc);
    if (owned[0] == owned[36]) {
      owned[0] = elmc_retain(owned[0]);
    }
    owned[36] = NULL;
    goto elmc_plan_block_23;
    elmc_plan_block_12:
    owned[37] = elmc_tuple_second_borrow(message);
    owned[38] = elmc_tuple_first_borrow(owned[37]);
    owned[39] = elmc_tuple_second_borrow(owned[37]);
    ElmcValue *rec_values_82_4[2] = { elmc_retain(owned[38]), elmc_retain(owned[39]) };
    Rc = elmc_record_new_values_take(&owned[40], 2, rec_values_82_4);
    CHECK_RC(Rc);
    owned[38] = NULL;
    owned[39] = NULL;
    Rc = elmc_maybe_just_own(&owned[41], owned[40]);
    CHECK_RC(Rc);
    owned[40] = NULL;
    owned[42] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[0], owned[42], ELMC_FIELD_MAIN_MODEL_WIND, owned[41]);
    CHECK_RC(Rc);
    if (owned[0] == owned[42]) {
      owned[0] = elmc_retain(owned[0]);
    }
    owned[42] = NULL;
    goto elmc_plan_block_23;
    elmc_plan_block_14:
    owned[43] = elmc_tuple_second_borrow(message);
    owned[49] = elmc_tuple_first_borrow(owned[43]);
    owned[44] = elmc_tuple_second_borrow(owned[43]);
    owned[50] = elmc_tuple_first_borrow(owned[44]);
    owned[45] = elmc_tuple_second_borrow(owned[44]);
    owned[46] = elmc_tuple_first_borrow(owned[45]);
    owned[52] = elmc_tuple_second_borrow(owned[45]);
    Rc = elmc_new_int(&owned[47], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[48], 1000);
    CHECK_RC(Rc);
    Rc = elmc_basics_clamp(&owned[51], owned[47], owned[48], owned[46]);
    CHECK_RC(Rc);
    if (owned[51] == owned[47]) {
      elmc_release(owned[51]);
      owned[47] = NULL;
    }
    if (owned[51] == owned[48]) {
      elmc_release(owned[51]);
      owned[48] = NULL;
    }
    if (owned[51] == owned[46]) {
      elmc_release(owned[51]);
      owned[46] = NULL;
    }
    ElmcValue *rec_values_107_5[4] = { elmc_retain(owned[49]), elmc_retain(owned[50]), owned[51], elmc_retain(owned[52]) };
    Rc = elmc_record_new_values_take(&owned[53], 4, rec_values_107_5);
    CHECK_RC(Rc);
    owned[51] = NULL;
    owned[49] = NULL;
    owned[50] = NULL;
    owned[51] = NULL;
    owned[52] = NULL;
    Rc = elmc_maybe_just_own(&owned[54], owned[53]);
    CHECK_RC(Rc);
    owned[53] = NULL;
    owned[55] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[0], owned[55], ELMC_FIELD_MAIN_MODEL_TIDE, owned[54]);
    CHECK_RC(Rc);
    if (owned[0] == owned[55]) {
      owned[0] = elmc_retain(owned[0]);
    }
    owned[55] = NULL;
    goto elmc_plan_block_23;
    elmc_plan_block_16:
    owned[56] = elmc_maybe_nothing();
    owned[57] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[0], owned[57], ELMC_FIELD_MAIN_MODEL_TIDE, owned[56]);
    CHECK_RC(Rc);
    if (owned[0] == owned[57]) {
      owned[0] = elmc_retain(owned[0]);
    }
    owned[57] = NULL;
    goto elmc_plan_block_23;
    elmc_plan_block_18:
    owned[58] = elmc_tuple_second_borrow(message);
    Rc = elmc_maybe_just(&owned[59], owned[58]);
    CHECK_RC(Rc);
    owned[58] = NULL;
    owned[60] = elmc_retain(model);
    Rc = elmc_record_update_index_cow_drop(&owned[0], owned[60], ELMC_FIELD_MAIN_MODEL_ALTITUDE, owned[59]);
    CHECK_RC(Rc);
    if (owned[0] == owned[60]) {
      owned[0] = elmc_retain(owned[0]);
    }
    owned[60] = NULL;
    goto elmc_plan_block_23;
    elmc_plan_block_20:
    owned[61] = elmc_tuple_second_borrow(message);
    Rc = elmc_fn_Main_normalizeCycleSec(&plan_native_int_119, elmc_as_int(owned[61]));
    CHECK_RC(Rc);
    owned[62] = elmc_retain(model);
    Rc = elmc_record_update_index_int_cow_drop(&owned[0], owned[62], ELMC_FIELD_MAIN_MODEL_CORNERUPDATEINTERVALSEC, plan_native_int_119);
    CHECK_RC(Rc);
    if (owned[0] == owned[62]) {
      owned[0] = elmc_retain(owned[0]);
    }
    owned[62] = NULL;
    elmc_plan_block_23:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[11] = NULL;
  owned[12] = NULL;
  owned[13] = NULL;
  owned[14] = NULL;
  owned[1] = NULL;
  owned[20] = NULL;
  owned[22] = NULL;
  owned[25] = NULL;
  owned[26] = NULL;
  owned[27] = NULL;
  owned[28] = NULL;
  owned[29] = NULL;
  owned[30] = NULL;
  owned[31] = NULL;
  owned[32] = NULL;
  owned[33] = NULL;
  owned[37] = NULL;
  owned[38] = NULL;
  owned[39] = NULL;
  owned[3] = NULL;
  owned[43] = NULL;
  owned[44] = NULL;
  owned[45] = NULL;
  owned[46] = NULL;
  owned[49] = NULL;
  owned[4] = NULL;
  owned[50] = NULL;
  owned[52] = NULL;
  owned[58] = NULL;
  owned[5] = NULL;
  owned[61] = NULL;
  owned[6] = NULL;
  owned[7] = NULL;
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static __attribute__((noinline, noclone)) RC elmc_fn_Main_scheduleCompanionFetches(ElmcValue **out, ElmcValue *model, ElmcValue *extraCmd) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[39] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_NOW));
    const bool plan_native_bool_3 = elmc_maybe_is_nothing(owned[0]);
    if (!plan_native_bool_3) goto elmc_plan_block_2;
    owned[2] = elmc_retain(model);
    owned[3] = elmc_retain(extraCmd);
    Rc = elmc_tuple2(&owned[1], owned[2], owned[3]);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[4] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    const elmc_int_t plan_native_int_10 = elmc_fn_Main_calendarDayKey(owned[4]);
    const elmc_int_t plan_native_int_11 = elmc_fn_Main_calendarHourKey(owned[4]);
    owned[5] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_LASTSUNFETCHDAYKEY));
    ElmcValue *plan_ephemeral_box_1330 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1330, plan_native_int_10);
    CHECK_RC(Rc);
    owned[6] = plan_ephemeral_box_1330;
    Rc = elmc_maybe_just_own(&owned[7], owned[6]);
    CHECK_RC(Rc);
    owned[6] = NULL;
    Rc = elmc_new_bool(&owned[8], elmc_value_equal(owned[5], owned[7]));
    CHECK_RC(Rc);
    owned[9] = elmc_basics_not(owned[8]);
    owned[10] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_LASTWEATHERFETCHHOURKEY));
    ElmcValue *plan_ephemeral_box_1346 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1346, plan_native_int_11);
    CHECK_RC(Rc);
    owned[11] = plan_ephemeral_box_1346;
    Rc = elmc_maybe_just_own(&owned[12], owned[11]);
    CHECK_RC(Rc);
    owned[11] = NULL;
    Rc = elmc_new_bool(&owned[13], elmc_value_equal(owned[10], owned[12]));
    CHECK_RC(Rc);
    owned[14] = elmc_basics_not(owned[13]);
    if (!elmc_as_bool(owned[9])) goto elmc_plan_block_6;
    Rc = elmc_new_int(&owned[15], 3);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[16], 0);
    CHECK_RC(Rc);
    Rc = elmc_cmd2(&owned[17], ELMC_PEBBLE_CMD_COMPANION_SEND, elmc_as_int(owned[15]), elmc_as_int(owned[16]));
    CHECK_RC(Rc);
    goto elmc_plan_block_7;
    elmc_plan_block_6:
    owned[18] = elmc_cmd_none();
    elmc_plan_block_7:
    if (elmc_as_bool(owned[9])) {
      owned[19] = owned[17];
      owned[17] = NULL;
    } else {
      owned[19] = owned[18];
      owned[18] = NULL;
    }
    if (!elmc_as_bool(owned[14])) goto elmc_plan_block_11;
    Rc = elmc_new_int(&owned[20], 4);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[21], 0);
    CHECK_RC(Rc);
    Rc = elmc_cmd2(&owned[22], ELMC_PEBBLE_CMD_COMPANION_SEND, elmc_as_int(owned[20]), elmc_as_int(owned[21]));
    CHECK_RC(Rc);
    goto elmc_plan_block_12;
    elmc_plan_block_11:
    owned[23] = elmc_cmd_none();
    elmc_plan_block_12:
    if (elmc_as_bool(owned[14])) {
      owned[24] = owned[22];
      owned[22] = NULL;
    } else {
      owned[24] = owned[23];
      owned[23] = NULL;
    }
    if (!elmc_as_bool(owned[9])) goto elmc_plan_block_16;
    ElmcValue *plan_ephemeral_box_1362 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1362, plan_native_int_10);
    CHECK_RC(Rc);
    owned[25] = plan_ephemeral_box_1362;
    Rc = elmc_maybe_just_own(&owned[26], owned[25]);
    CHECK_RC(Rc);
    owned[25] = NULL;
    goto elmc_plan_block_17;
    elmc_plan_block_16:
    owned[27] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_LASTSUNFETCHDAYKEY));
    elmc_plan_block_17:
    if (elmc_as_bool(owned[9])) {
      owned[28] = owned[26];
      owned[26] = NULL;
    } else {
      owned[28] = owned[27];
      owned[27] = NULL;
    }
    {
      ElmcValue *__cow_base = elmc_retain(model);
      Rc = elmc_record_update_index_cow_drop(&owned[29], __cow_base, ELMC_FIELD_MAIN_MODEL_LASTSUNFETCHDAYKEY, owned[28]);
      if (Rc == RC_SUCCESS) {
        /* in-place: transfer retain to dest; copy: cow_drop already released */
        __cow_base = NULL;
      } else {
        elmc_release(__cow_base);
      }
      CHECK_RC(Rc);
    }
    if (!elmc_as_bool(owned[14])) goto elmc_plan_block_21;
    ElmcValue *plan_ephemeral_box_1378 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1378, plan_native_int_11);
    CHECK_RC(Rc);
    owned[30] = plan_ephemeral_box_1378;
    Rc = elmc_maybe_just_own(&owned[31], owned[30]);
    CHECK_RC(Rc);
    owned[30] = NULL;
    goto elmc_plan_block_22;
    elmc_plan_block_21:
    owned[32] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_LASTWEATHERFETCHHOURKEY));
    elmc_plan_block_22:
    if (elmc_as_bool(owned[14])) {
      owned[33] = owned[31];
      owned[31] = NULL;
    } else {
      owned[33] = owned[32];
      owned[32] = NULL;
    }
    Rc = elmc_record_update_index_cow_drop(&owned[37], owned[29], ELMC_FIELD_MAIN_MODEL_LASTWEATHERFETCHHOURKEY, owned[33]);
    CHECK_RC(Rc);
    owned[29] = NULL;
    ElmcValue *plan_list_items_1394[3] = { extraCmd, owned[19], owned[24] };
    Rc = elmc_list_from_values(&owned[34], plan_list_items_1394, 3);
    CHECK_RC(Rc);
    Rc = elmc_cmd_batch(&owned[35], owned[34]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[36], owned[37], owned[35]);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_3) {
      owned[38] = owned[1];
      owned[1] = NULL;
    } else {
      owned[38] = owned[36];
      owned[36] = NULL;
    }
    *out = owned[38];
    owned[38] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static elmc_int_t elmc_fn_Main_calendarDayKey(ElmcValue *now) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  /* plan block 0 */
  const elmc_int_t plan_native_int_1 = ELMC_RECORD_GET_INDEX_INT(now, ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_YEAR);
  const elmc_int_t plan_native_int_4 = ELMC_RECORD_GET_INDEX_INT(now, ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MONTH);
  const elmc_int_t plan_native_int_8 = ELMC_RECORD_GET_INDEX_INT(now, ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_DAY);
  return plan_native_int_1 * 10000 + plan_native_int_4 * 100 + plan_native_int_8;
}

static elmc_int_t elmc_fn_Main_calendarHourKey(ElmcValue *now) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  /* plan block 0 */
  const elmc_int_t plan_native_int_1 = elmc_fn_Main_calendarDayKey(now);
  const elmc_int_t plan_native_int_3 = plan_native_int_1 * 100;
  const elmc_int_t plan_native_int_4 = ELMC_RECORD_GET_INDEX_INT(now, ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_HOUR);
  return plan_native_int_3 + plan_native_int_4;
}

static RC elmc_fn_Main_refreshStepsIfSupported(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[3] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_HEALTHSUPPORTED));
    const bool plan_native_bool_3 = elmc_maybe_is_nothing(owned[0]);
    const bool plan_native_bool_5 = ((plan_native_bool_3 ? 1 : 0) == 0);
    if (!plan_native_bool_5) goto elmc_plan_block_3;
    owned[2] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    Rc = elmc_cmd2(&owned[1], ELMC_PEBBLE_CMD_HEALTH_SUM_TODAY, 1, ELMC_PEBBLE_MSG_GOTSTEPSTODAY);
    CHECK_RC(Rc);
    goto elmc_plan_block_8;
    elmc_plan_block_3:
    owned[1] = elmc_cmd_none();
    elmc_plan_block_8:
    *out = owned[1];
    owned[1] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_shouldRefreshCorners(bool *out, ElmcValue *model, elmc_int_t second) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[3] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const elmc_int_t plan_native_int_2 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_CORNERUPDATEINTERVALSEC);
    elmc_int_t plan_call_int_3 = 0;
    Rc = elmc_fn_Main_normalizeCycleSec(&plan_call_int_3, plan_native_int_2);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[0], plan_call_int_3);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[1], second);
    CHECK_RC(Rc);
    /* elm/core: Basics.modBy */
    Rc = elmc_basics_mod_by(&owned[2], owned[0], owned[1]);
    CHECK_RC(Rc);
    const bool plan_native_bool_7 = (elmc_as_int(owned[2]) == 0);
    *out = plan_native_bool_7;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_showCorners(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[7] = {0};
  CATCH_BEGIN
    /* plan block 0 */
#if defined(PBL_ROUND)
    Rc = elmc_new_bool(&owned[0], true);
    CHECK_RC(Rc);
#else
    Rc = elmc_new_bool(&owned[0], false);
    CHECK_RC(Rc);
#endif
    owned[1] = elmc_basics_not(owned[0]);
    if (!elmc_as_bool(owned[1])) goto elmc_plan_block_2;
    owned[2] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_SUN));
    const bool plan_native_bool_5 = elmc_maybe_is_nothing(owned[2]);
    Rc = elmc_new_bool(&owned[3], plan_native_bool_5);
    CHECK_RC(Rc);
    owned[4] = elmc_basics_not(owned[3]);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    Rc = elmc_new_bool(&owned[5], false);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (elmc_as_bool(owned[1])) {
      owned[6] = owned[4];
      owned[4] = NULL;
    } else {
      owned[6] = owned[5];
      owned[5] = NULL;
    }
    *out = owned[6];
    owned[6] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Main_showCorners_native(bool *out, ElmcValue * const model) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_showCorners(&boxed, model);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_bool(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_HEALTHSUPPORTED));
    const bool plan_native_bool_3 = elmc_maybe_is_nothing(owned[0]);
    const bool plan_native_bool_5 = ((plan_native_bool_3 ? 1 : 0) == 0);
    if (!plan_native_bool_5) goto elmc_plan_block_3;
    owned[2] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    Rc = elmc_sub1(&owned[1], ELMC_SUBSCRIPTION_HEALTH, ELMC_PEBBLE_MSG_HEALTHEVENT);
    CHECK_RC(Rc);
    goto elmc_plan_block_8;
    elmc_plan_block_3:
    Rc = elmc_sub0(&owned[1], 0);
    CHECK_RC(Rc);
    elmc_plan_block_8:
    Rc = elmc_sub1(&owned[3], ELMC_SUBSCRIPTION_MINUTE_CHANGE, ELMC_PEBBLE_MSG_MINUTECHANGED);
    CHECK_RC(Rc);
    Rc = elmc_sub1(&owned[4], ELMC_SUBSCRIPTION_HOUR_CHANGE, ELMC_PEBBLE_MSG_HOURCHANGED);
    CHECK_RC(Rc);
    Rc = elmc_sub1(&owned[5], ELMC_SUBSCRIPTION_SECOND_CHANGE, ELMC_PEBBLE_MSG_SECONDCHANGED);
    CHECK_RC(Rc);
    Rc = elmc_sub1(&owned[6], ELMC_SUBSCRIPTION_BATTERY, ELMC_PEBBLE_MSG_BATTERYLEVELCHANGED);
    CHECK_RC(Rc);
    Rc = elmc_sub1(&owned[7], ELMC_SUBSCRIPTION_CONNECTION, ELMC_PEBBLE_MSG_CONNECTIONCHANGED);
    CHECK_RC(Rc);
    Rc = elmc_sub1(&owned[8], ELMC_SUBSCRIPTION_APPMESSAGE, ELMC_PEBBLE_MSG_FROMPHONE);
    CHECK_RC(Rc);
    Rc = elmc_sub3(&owned[9], ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_DOWN, ELMC_BUTTON_EVENT_RELEASED, ELMC_PEBBLE_MSG_REQUESTREFRESH);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_1410[8] = { owned[3], owned[4], owned[5], owned[6], owned[7], owned[8], owned[9], owned[1] };
    Rc = elmc_list_from_values(&owned[10], plan_list_items_1410, 8);
    CHECK_RC(Rc);
    *out = owned[10];
    owned[10] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_faceOps(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  // #region agent log
  elmc_agent_generated_probe(0xED998200);
  // #endregion

  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_LAYOUT));
    Rc = elmc_fn_Main_faceDisplay(&owned[1], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_face(out, owned[0], owned[1]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_faceDisplay(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    elmc_int_t plan_native_int_14 = 0;
    /* plan block 0 */
    Rc = elmc_fn_Main_showCorners(&owned[0], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_homeMinuteOfDay(&plan_native_int_14, model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_timeString(&owned[1], model);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_SUN));
    owned[3] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_MOONPHASEE6));
    Rc = elmc_fn_Main_cornerSlots(&owned[4], model);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_1426 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1426, plan_native_int_14);
    CHECK_RC(Rc);
    ElmcValue *rec_values_19_6[6] = { owned[0], plan_ephemeral_box_1426, owned[1], owned[2], owned[3], owned[4] };
    Rc = elmc_record_new_values_take(out, 6, rec_values_19_6);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;
    owned[2] = NULL;
    owned[3] = NULL;
    owned[4] = NULL;
    owned[0] = NULL;
    owned[1] = NULL;
    owned[2] = NULL;
    owned[3] = NULL;
    owned[4] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_cornerSlots(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_fn_Main_topLeftSlot(&owned[0], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_dateSlot(&owned[1], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_weatherSlot(&owned[2], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_bottomRightSlot(&owned[3], model);
    CHECK_RC(Rc);
    ElmcValue *rec_values_13_7[4] = { owned[0], owned[1], owned[2], owned[3] };
    Rc = elmc_record_new_values_take(out, 4, rec_values_13_7);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;
    owned[2] = NULL;
    owned[3] = NULL;
    owned[0] = NULL;
    owned[1] = NULL;
    owned[2] = NULL;
    owned[3] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_topLeftSlot(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_fn_Main_pickTopLeft(&owned[0], model);
    CHECK_RC(Rc);
    if (elmc_as_int(owned[0]) != ELMC_UNION_MAIN_BATTERYCORNER) {
      if (elmc_as_int(owned[0]) == ELMC_UNION_MAIN_STEPSCORNER) goto elmc_plan_block_4;
      else goto elmc_plan_block_7;
    }
    Rc = elmc_fn_Main_batteryPercentString_native(&owned[2], model);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1442 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Battery", 7 };
    owned[3] = elmc_retain(&plan_str_immortal_1442);
    ElmcValue *rec_values_9_8[2] = { owned[2], owned[3] };
    Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_9_8);
    CHECK_RC(Rc);
    owned[2] = NULL;
    owned[3] = NULL;
    owned[2] = NULL;
    owned[3] = NULL;
    goto elmc_plan_block_7;
    elmc_plan_block_4:
    Rc = elmc_fn_Main_stepsString_native(&owned[4], model);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1458 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Steps", 5 };
    owned[5] = elmc_retain(&plan_str_immortal_1458);
    ElmcValue *rec_values_18_9[2] = { owned[4], owned[5] };
    Rc = elmc_record_new_values_take(&owned[1], 2, rec_values_18_9);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[5] = NULL;
    owned[4] = NULL;
    owned[5] = NULL;
    elmc_plan_block_7:
    *out = owned[1];
    owned[1] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_dateSlot(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_NOW));
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    owned[1] = elmc_maybe_nothing();
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[2] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    const elmc_int_t plan_native_int_5 = ELMC_RECORD_GET_INDEX_INT(owned[2], ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MONTH);
    Rc = elmc_fn_Main_monthString_native(&owned[3], plan_native_int_5);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1474 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)" ", 1 };
    owned[4] = elmc_retain(&plan_str_immortal_1474);
    Rc = elmc_new_int(&owned[5], ELMC_RECORD_GET_INDEX_INT(owned[2], ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_DAY));
    CHECK_RC(Rc);
    Rc = elmc_string_from_int(&owned[6], owned[5]);
    CHECK_RC(Rc);
    Rc = elmc_string_append(&owned[7], owned[4], owned[6]);
    CHECK_RC(Rc);
    Rc = elmc_string_append(&owned[8], owned[3], owned[7]);
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[9], owned[8]);
    CHECK_RC(Rc);
    owned[8] = NULL;
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[10] = owned[1];
      owned[1] = NULL;
    } else {
      owned[10] = owned[9];
      owned[9] = NULL;
    }
    *out = owned[10];
    owned[10] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_weatherSlot(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_fn_Main_pickWeatherMode(&owned[0], model);
    CHECK_RC(Rc);
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    owned[1] = elmc_maybe_nothing();
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[2] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    Rc = elmc_fn_Main_weatherLabel(&owned[3], model, owned[2]);
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[4], owned[3]);
    CHECK_RC(Rc);
    owned[3] = NULL;
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[5] = owned[1];
      owned[1] = NULL;
    } else {
      owned[5] = owned[4];
      owned[4] = NULL;
    }
    *out = owned[5];
    owned[5] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_bottomRightSlot(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_fn_Main_pickBottomRight_native(&owned[0], model);
    CHECK_RC(Rc);
    switch (elmc_as_int(owned[0])) {
      case ELMC_UNION_MAIN_ALTITUDECORNER: goto elmc_plan_block_2;
      case ELMC_UNION_MAIN_SUNCORNER: goto elmc_plan_block_9;
      case ELMC_UNION_MAIN_MOONCORNER: goto elmc_plan_block_11;
      default: goto elmc_plan_block_14;
    }
    elmc_plan_block_2:
    owned[2] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_ALTITUDE));
    const bool plan_native_bool_5 = elmc_maybe_is_nothing(owned[2]);
    if (!plan_native_bool_5) goto elmc_plan_block_4;
    Rc = elmc_new_int(&owned[3], 2);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1490 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"--", 2 };
    owned[4] = elmc_retain(&plan_str_immortal_1490);
    Rc = elmc_tuple2(&owned[5], owned[3], owned[4]);
    CHECK_RC(Rc);
    goto elmc_plan_block_5;
    elmc_plan_block_4:
    owned[6] = elmc_retain(elmc_maybe_just_payload(owned[2]));
    Rc = elmc_new_int(&owned[7], 1);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_altitudeString_native(&owned[8], owned[6]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[9], owned[7], owned[8]);
    CHECK_RC(Rc);
    elmc_plan_block_5:
    if (plan_native_bool_5) {
      owned[10] = owned[5];
      owned[5] = NULL;
    } else {
      owned[10] = owned[9];
      owned[9] = NULL;
    }
    owned[1] = owned[10];
    owned[10] = NULL;
    goto elmc_plan_block_14;
    elmc_plan_block_9:
    Rc = elmc_fn_Main_sunBottomRightSlot(&owned[1], model);
    CHECK_RC(Rc);
    goto elmc_plan_block_14;
    elmc_plan_block_11:
    Rc = elmc_fn_Main_moonBottomRightSlot(&owned[1], model);
    CHECK_RC(Rc);
    elmc_plan_block_14:
    *out = owned[1];
    owned[1] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static __attribute__((noinline, noclone)) RC elmc_fn_Main_sunBottomRightSlot(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[37] = {0};
  CATCH_BEGIN
    elmc_int_t plan_native_int_11 = 0;
    elmc_int_t plan_native_int_36 = 0;
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_SUN));
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    owned[1] = elmc_maybe_nothing();
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[2] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    owned[3] = elmc_retain(elmc_record_get_index(owned[2], ELMC_FIELD_YES_RENDER_SUNWINDOW_MODE));
    Rc = elmc_maybe_just_own(&owned[4], owned[3]);
    CHECK_RC(Rc);
    owned[3] = NULL;
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[5] = owned[1];
      owned[1] = NULL;
    } else {
      owned[5] = owned[4];
      owned[4] = NULL;
    }
    const bool plan_native_bool_9 = elmc_maybe_is_nothing(owned[5]);
    if (!plan_native_bool_9) goto elmc_plan_block_7;
    Rc = elmc_fn_Main_homeMinuteOfDay(&plan_native_int_11, model);
    CHECK_RC(Rc);
    owned[6] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_SUN));
    Rc = elmc_fn_Main_nextSunCountdown(&owned[7], plan_native_int_11, owned[6]);
    CHECK_RC(Rc);
    const bool plan_native_bool_14 = elmc_maybe_is_nothing(owned[7]);
    if (!plan_native_bool_14) goto elmc_plan_block_10;
    Rc = elmc_new_int(&owned[8], 2);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1506 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"--", 2 };
    owned[9] = elmc_retain(&plan_str_immortal_1506);
    Rc = elmc_tuple2(&owned[10], owned[8], owned[9]);
    CHECK_RC(Rc);
    goto elmc_plan_block_11;
    elmc_plan_block_10:
    owned[11] = elmc_retain(elmc_maybe_just_payload(owned[7]));
    owned[14] = elmc_tuple_first_borrow(owned[11]);
    owned[15] = elmc_tuple_second_borrow(owned[11]);
    Rc = elmc_new_int(&owned[12], 3);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[13], owned[14], owned[15]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[16], owned[12], owned[13]);
    CHECK_RC(Rc);
    elmc_plan_block_11:
    if (plan_native_bool_14) {
      owned[17] = owned[10];
      owned[10] = NULL;
    } else {
      owned[17] = owned[16];
      owned[16] = NULL;
    }
    goto elmc_plan_block_8;
    elmc_plan_block_7:
    owned[18] = elmc_retain(elmc_maybe_just_payload(owned[5]));
    if (!elmc_union_tag_matches(owned[18], ELMC_UNION_COMPANION_TYPES_POLARDAY)) {
      if (elmc_union_tag_matches(owned[18], ELMC_UNION_COMPANION_TYPES_POLARNIGHT)) goto elmc_plan_block_18;
      else goto elmc_plan_block_20;
    }
    Rc = elmc_new_int(&owned[20], 2);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1522 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Sun day", 7 };
    owned[21] = elmc_retain(&plan_str_immortal_1522);
    Rc = elmc_tuple2(&owned[19], owned[20], owned[21]);
    CHECK_RC(Rc);
    goto elmc_plan_block_8;
    elmc_plan_block_18:
    Rc = elmc_new_int(&owned[22], 2);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1538 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Sun night", 9 };
    owned[23] = elmc_retain(&plan_str_immortal_1538);
    Rc = elmc_tuple2(&owned[19], owned[22], owned[23]);
    CHECK_RC(Rc);
    goto elmc_plan_block_8;
    elmc_plan_block_20:
    Rc = elmc_fn_Main_homeMinuteOfDay(&plan_native_int_36, model);
    CHECK_RC(Rc);
    owned[24] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_SUN));
    Rc = elmc_fn_Main_nextSunCountdown(&owned[25], plan_native_int_36, owned[24]);
    CHECK_RC(Rc);
    const bool plan_native_bool_39 = elmc_maybe_is_nothing(owned[25]);
    if (!plan_native_bool_39) goto elmc_plan_block_22;
    Rc = elmc_new_int(&owned[26], 2);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1554 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"--", 2 };
    owned[27] = elmc_retain(&plan_str_immortal_1554);
    Rc = elmc_tuple2(&owned[28], owned[26], owned[27]);
    CHECK_RC(Rc);
    goto elmc_plan_block_23;
    elmc_plan_block_22:
    owned[29] = elmc_retain(elmc_maybe_just_payload(owned[25]));
    owned[32] = elmc_tuple_first_borrow(owned[29]);
    owned[33] = elmc_tuple_second_borrow(owned[29]);
    Rc = elmc_new_int(&owned[30], 3);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[31], owned[32], owned[33]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[34], owned[30], owned[31]);
    CHECK_RC(Rc);
    elmc_plan_block_23:
    if (plan_native_bool_39) {
      owned[35] = owned[28];
      owned[28] = NULL;
    } else {
      owned[35] = owned[34];
      owned[34] = NULL;
    }
    owned[19] = owned[35];
    owned[35] = NULL;
    elmc_plan_block_8:
    if (plan_native_bool_9) {
      owned[36] = owned[17];
      owned[17] = NULL;
    } else {
      owned[36] = owned[19];
      owned[19] = NULL;
    }
    *out = owned[36];
    owned[36] = NULL;
  CATCH_END
  owned[14] = NULL;
  owned[15] = NULL;
  owned[32] = NULL;
  owned[33] = NULL;
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_moonBottomRightSlot(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[19] = {0};
  CATCH_BEGIN
    elmc_int_t plan_native_int_10 = 0;
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_MOONRISEMIN));
    owned[1] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_MOONSETMIN));
    const bool plan_native_bool_3 = elmc_maybe_is_nothing(owned[0]);
    const bool plan_native_bool_4 = elmc_maybe_is_nothing(owned[1]);
    const bool plan_native_bool_5 = (plan_native_bool_3 && plan_native_bool_4);
    if (!plan_native_bool_5) goto elmc_plan_block_2;
    Rc = elmc_new_int(&owned[2], 2);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1570 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"--", 2 };
    owned[3] = elmc_retain(&plan_str_immortal_1570);
    Rc = elmc_tuple2(&owned[4], owned[2], owned[3]);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    Rc = elmc_fn_Main_homeMinuteOfDay(&plan_native_int_10, model);
    CHECK_RC(Rc);
    owned[5] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_MOONRISEMIN));
    owned[6] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_MOONSETMIN));
    Rc = elmc_fn_Main_nextMoonCountdown(&owned[7], plan_native_int_10, owned[5], owned[6]);
    CHECK_RC(Rc);
    const bool plan_native_bool_14 = elmc_maybe_is_nothing(owned[7]);
    if (!plan_native_bool_14) goto elmc_plan_block_6;
    Rc = elmc_new_int(&owned[8], 2);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1586 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"--", 2 };
    owned[9] = elmc_retain(&plan_str_immortal_1586);
    Rc = elmc_tuple2(&owned[10], owned[8], owned[9]);
    CHECK_RC(Rc);
    goto elmc_plan_block_7;
    elmc_plan_block_6:
    owned[11] = elmc_retain(elmc_maybe_just_payload(owned[7]));
    owned[14] = elmc_tuple_first_borrow(owned[11]);
    owned[15] = elmc_tuple_second_borrow(owned[11]);
    Rc = elmc_new_int(&owned[12], 3);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[13], owned[14], owned[15]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[16], owned[12], owned[13]);
    CHECK_RC(Rc);
    elmc_plan_block_7:
    if (plan_native_bool_14) {
      owned[17] = owned[10];
      owned[10] = NULL;
    } else {
      owned[17] = owned[16];
      owned[16] = NULL;
    }
    elmc_plan_block_3:
    if (plan_native_bool_5) {
      owned[18] = owned[4];
      owned[4] = NULL;
    } else {
      owned[18] = owned[17];
      owned[17] = NULL;
    }
    *out = owned[18];
    owned[18] = NULL;
  CATCH_END
  owned[14] = NULL;
  owned[15] = NULL;
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_pickSlot(ElmcValue **out, ElmcValue *model, ElmcValue *slots) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[9] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_closure_new_rc(&owned[0], elmc_fn_Main_pickSlot_closure_0, 1, 0, NULL);
    CHECK_RC(Rc);
    Rc = elmc_list_find_first(&owned[1], owned[0], slots);
    CHECK_RC(Rc);
    const bool plan_native_bool_4 = elmc_maybe_is_nothing(owned[1]);
    if (!plan_native_bool_4) goto elmc_plan_block_2;
    Rc = elmc_list_filter_record_field(&owned[2], slots, 1);
    CHECK_RC(Rc);
    Rc = elmc_list_map_record_field(&owned[3], owned[2], 0);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_pickFromCycledList(&owned[4], model, owned[3]);
    CHECK_RC(Rc);
    if (owned[4] == owned[3]) {
      owned[3] = NULL;
    }
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[5] = elmc_retain(elmc_maybe_just_payload(owned[1]));
    owned[6] = elmc_retain(elmc_record_get_index(owned[5], ELMC_FIELD_MAIN_SLOTSPEC_ID));
    Rc = elmc_maybe_just_own(&owned[7], owned[6]);
    CHECK_RC(Rc);
    owned[6] = NULL;
    elmc_plan_block_3:
    if (plan_native_bool_4) {
      owned[8] = owned[4];
      owned[4] = NULL;
    } else {
      owned[8] = owned[7];
      owned[7] = NULL;
    }
    *out = owned[8];
    owned[8] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_pickFromCycledList(ElmcValue **out, ElmcValue *model, ElmcValue *items) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_2 = elmc_as_bool(elmc_list_is_empty(items));
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    owned[0] = elmc_maybe_nothing();
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    /* elm/core: List.length */
    Rc = elmc_list_length(&owned[1], items);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_7 = elmc_fn_Main_cycleSlot(model, elmc_as_int(owned[1]));
    Rc = elmc_list_nth_maybe_int(&owned[2], items, plan_native_int_7);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[3] = owned[0];
      owned[0] = NULL;
    } else {
      owned[3] = owned[2];
      owned[2] = NULL;
    }
    *out = owned[3];
    owned[3] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_pickTopLeft(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_fn_Main_topLeftSlots(&owned[0], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_pickSlot(&owned[1], model, owned[0]);
    CHECK_RC(Rc);
    if (owned[1] == owned[0]) {
      owned[0] = NULL;
    }
    const bool plan_native_bool_3 = elmc_maybe_is_nothing(owned[1]);
    if (!plan_native_bool_3) goto elmc_plan_block_2;
    Rc = elmc_new_int(&owned[2], 1);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[3] = elmc_retain(elmc_maybe_just_payload(owned[1]));
    elmc_plan_block_3:
    if (plan_native_bool_3) {
      owned[4] = owned[2];
      owned[2] = NULL;
    } else {
      owned[4] = owned[3];
      owned[3] = NULL;
    }
    *out = owned[4];
    owned[4] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_topLeftSlots(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[10] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], 1);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_topLeftBatteryAvailable(&owned[3], model);
    CHECK_RC(Rc);
    Rc = elmc_new_bool(&owned[4], false);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(owned[0]);
    ElmcValue *rec_values_10_10[3] = { owned[2], owned[3], owned[4] };
    Rc = elmc_record_new_values_take(&owned[1], 3, rec_values_10_10);
    CHECK_RC(Rc);
    owned[2] = NULL;
    owned[3] = NULL;
    owned[4] = NULL;
    owned[2] = NULL;
    owned[3] = NULL;
    owned[4] = NULL;
    Rc = elmc_new_int(&owned[6], 2);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_topLeftStepsAvailable(&owned[7], model);
    CHECK_RC(Rc);
    Rc = elmc_new_bool(&owned[8], false);
    CHECK_RC(Rc);
    ElmcValue *rec_values_20_11[3] = { owned[6], owned[7], owned[8] };
    Rc = elmc_record_new_values_take(&owned[5], 3, rec_values_20_11);
    CHECK_RC(Rc);
    owned[6] = NULL;
    owned[7] = NULL;
    owned[8] = NULL;
    owned[6] = NULL;
    owned[7] = NULL;
    owned[8] = NULL;
    ElmcValue *plan_list_items_1602[2] = { owned[1], owned[5] };
    Rc = elmc_list_from_values(&owned[9], plan_list_items_1602, 2);
    CHECK_RC(Rc);
    *out = owned[9];
    owned[9] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_topLeftBatteryAvailable(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[12] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_CONNECTED));
    Rc = elmc_new_bool(&owned[1], false);
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[2], owned[1]);
    CHECK_RC(Rc);
    owned[1] = NULL;
    Rc = elmc_new_bool(&owned[3], elmc_value_equal(owned[0], owned[2]));
    CHECK_RC(Rc);
    owned[4] = elmc_basics_not(owned[3]);
    if (!elmc_as_bool(owned[4])) goto elmc_plan_block_2;
    Rc = elmc_fn_Main_batteryAlert(&owned[5], model);
    CHECK_RC(Rc);
    if (!elmc_as_bool(owned[5])) goto elmc_plan_block_5;
    Rc = elmc_new_bool(&owned[6], true);
    CHECK_RC(Rc);
    goto elmc_plan_block_6;
    elmc_plan_block_5:
    Rc = elmc_fn_Main_haveSteps(&owned[7], model);
    CHECK_RC(Rc);
    owned[8] = elmc_basics_not(owned[7]);
    elmc_plan_block_6:
    if (elmc_as_bool(owned[5])) {
      owned[9] = owned[6];
      owned[6] = NULL;
    } else {
      owned[9] = owned[8];
      owned[8] = NULL;
    }
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    Rc = elmc_new_bool(&owned[10], false);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (elmc_as_bool(owned[4])) {
      owned[11] = owned[9];
      owned[9] = NULL;
    } else {
      owned[11] = owned[10];
      owned[10] = NULL;
    }
    *out = owned[11];
    owned[11] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Main_topLeftBatteryAvailable_native(bool *out, ElmcValue * const model) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_topLeftBatteryAvailable(&boxed, model);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_bool(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_topLeftStepsAvailable(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_CONNECTED));
    Rc = elmc_new_bool(&owned[1], true);
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[2], owned[1]);
    CHECK_RC(Rc);
    owned[1] = NULL;
    const bool plan_native_bool_5 = elmc_value_equal(owned[0], owned[2]);
    if (!plan_native_bool_5) goto elmc_plan_block_2;
    Rc = elmc_fn_Main_haveSteps(&owned[3], model);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    Rc = elmc_new_bool(&owned[4], false);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_5) {
      owned[5] = owned[3];
      owned[3] = NULL;
    } else {
      owned[5] = owned[4];
      owned[4] = NULL;
    }
    *out = owned[5];
    owned[5] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Main_topLeftStepsAvailable_native(bool *out, ElmcValue * const model) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_topLeftStepsAvailable(&boxed, model);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_bool(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_pickWeatherMode(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_fn_Main_availableWeatherModes(&owned[0], model);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_pickFromCycledList(out, model, owned[0]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_availableWeatherModes(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_WEATHER));
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    owned[1] = elmc_list_nil();
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[2] = elmc_list_nil();
    Rc = elmc_new_int(&owned[3], 1);
    CHECK_RC(Rc);
    /* elm/core: List.cons */
    Rc = elmc_list_cons(&owned[4], owned[3], owned[2]);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_hasWind(&owned[5], model);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[6], 2);
    CHECK_RC(Rc);
    const bool plan_native_bool_11 = (!(elmc_as_int(owned[5]) == 0));
    if (!plan_native_bool_11) goto elmc_plan_block_7;
    /* elm/core: List.cons */
    Rc = elmc_list_cons(&owned[7], owned[6], owned[4]);
    CHECK_RC(Rc);
    elmc_plan_block_7:
    if (plan_native_bool_11) {
      owned[8] = owned[7];
      owned[7] = NULL;
    } else {
      owned[8] = owned[4];
      owned[4] = NULL;
    }
    /* elm/core: List.reverse */
    Rc = elmc_list_reverse(&owned[9], owned[8]);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[10] = owned[1];
      owned[1] = NULL;
    } else {
      owned[10] = owned[9];
      owned[9] = NULL;
    }
    *out = owned[10];
    owned[10] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_weatherLabel(ElmcValue **out, ElmcValue *model, ElmcValue *mode) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    if (!elmc_union_tag_matches(mode, ELMC_UNION_MAIN_TEMPCORNER)) {
      if (elmc_union_tag_matches(mode, ELMC_UNION_MAIN_WINDCORNER)) goto elmc_plan_block_4;
      else goto elmc_plan_block_7;
    }
    Rc = elmc_fn_Main_temperatureString_native(&owned[0], model);
    CHECK_RC(Rc);
    goto elmc_plan_block_7;
    elmc_plan_block_4:
    Rc = elmc_fn_Main_windString(&owned[0], model);
    CHECK_RC(Rc);
    elmc_plan_block_7:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_hasWind(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[7] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_WIND));
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    Rc = elmc_new_bool(&owned[1], false);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[2] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    owned[3] = elmc_retain(elmc_record_get_index(owned[2], ELMC_FIELD_MAIN_WIND_SPEED));
    Rc = elmc_new_bool(&owned[4], (elmc_as_int(owned[3]) == 0));
    CHECK_RC(Rc);
    owned[5] = elmc_basics_not(owned[4]);
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[6] = owned[1];
      owned[1] = NULL;
    } else {
      owned[6] = owned[5];
      owned[5] = NULL;
    }
    *out = owned[6];
    owned[6] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Main_hasWind_native(bool *out, ElmcValue * const model) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_hasWind(&boxed, model);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_bool(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_pickBottomRight_native(ElmcValue **out, ElmcValue *model) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    ElmcValue *elmc_fn_Main_pickBottomRight_slots = NULL;
    Rc = elmc_fn_Main_bottomRightSlots(&elmc_fn_Main_pickBottomRight_slots, model);
    CHECK_RC(Rc);
    ElmcValue *maybe_pick = NULL;
    Rc = elmc_fn_Main_pickSlot(&maybe_pick, model, elmc_fn_Main_pickBottomRight_slots);
    CHECK_RC(Rc);
    elmc_int_t tag = elmc_maybe_with_default_int(2, maybe_pick);
    Rc = elmc_new_int(out, tag);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}
static RC elmc_fn_Main_pickBottomRight(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  return elmc_fn_Main_pickBottomRight_native(out, model);
}

static RC elmc_fn_Main_bottomRightSlots(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[18] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], 1);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_ALTITUDE));
    const bool plan_native_bool_4 = elmc_maybe_is_nothing(owned[1]);
    Rc = elmc_new_bool(&owned[2], plan_native_bool_4);
    CHECK_RC(Rc);
    owned[5] = elmc_basics_not(owned[2]);
    Rc = elmc_new_bool(&owned[6], false);
    CHECK_RC(Rc);
    owned[4] = elmc_retain(owned[0]);
    ElmcValue *rec_values_13_12[3] = { owned[4], owned[5], owned[6] };
    Rc = elmc_record_new_values_take(&owned[3], 3, rec_values_13_12);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[5] = NULL;
    owned[6] = NULL;
    owned[4] = NULL;
    owned[5] = NULL;
    owned[6] = NULL;
    Rc = elmc_new_int(&owned[10], 2);
    CHECK_RC(Rc);
    owned[7] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_SUN));
    const bool plan_native_bool_17 = elmc_maybe_is_nothing(owned[7]);
    Rc = elmc_new_bool(&owned[8], plan_native_bool_17);
    CHECK_RC(Rc);
    owned[11] = elmc_basics_not(owned[8]);
    Rc = elmc_new_bool(&owned[12], false);
    CHECK_RC(Rc);
    ElmcValue *rec_values_26_13[3] = { owned[10], owned[11], owned[12] };
    Rc = elmc_record_new_values_take(&owned[9], 3, rec_values_26_13);
    CHECK_RC(Rc);
    owned[10] = NULL;
    owned[11] = NULL;
    owned[12] = NULL;
    owned[10] = NULL;
    owned[11] = NULL;
    owned[12] = NULL;
    Rc = elmc_new_int(&owned[14], 3);
    CHECK_RC(Rc);
    Rc = elmc_fn_Main_hasMoonTimes(&owned[15], model);
    CHECK_RC(Rc);
    Rc = elmc_new_bool(&owned[16], false);
    CHECK_RC(Rc);
    ElmcValue *rec_values_36_14[3] = { owned[14], owned[15], owned[16] };
    Rc = elmc_record_new_values_take(&owned[13], 3, rec_values_36_14);
    CHECK_RC(Rc);
    owned[14] = NULL;
    owned[15] = NULL;
    owned[16] = NULL;
    owned[14] = NULL;
    owned[15] = NULL;
    owned[16] = NULL;
    ElmcValue *plan_list_items_1618[3] = { owned[3], owned[9], owned[13] };
    Rc = elmc_list_from_values(&owned[17], plan_list_items_1618, 3);
    CHECK_RC(Rc);
    *out = owned[17];
    owned[17] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_hasMoonTimes(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[8] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_MOONRISEMIN));
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    Rc = elmc_new_bool(&owned[1], plan_native_bool_2);
    CHECK_RC(Rc);
    owned[2] = elmc_basics_not(owned[1]);
    if (!elmc_as_bool(owned[2])) goto elmc_plan_block_2;
    Rc = elmc_new_bool(&owned[3], true);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[4] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_MOONSETMIN));
    const bool plan_native_bool_8 = elmc_maybe_is_nothing(owned[4]);
    Rc = elmc_new_bool(&owned[5], plan_native_bool_8);
    CHECK_RC(Rc);
    owned[6] = elmc_basics_not(owned[5]);
    elmc_plan_block_3:
    if (elmc_as_bool(owned[2])) {
      owned[7] = owned[3];
      owned[3] = NULL;
    } else {
      owned[7] = owned[6];
      owned[6] = NULL;
    }
    *out = owned[7];
    owned[7] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Main_hasMoonTimes_native(bool *out, ElmcValue * const model) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_hasMoonTimes(&boxed, model);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_bool(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_homeMinuteOfDay(elmc_int_t *out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_NOW));
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    if (plan_native_bool_2) goto elmc_plan_block_3;
    owned[1] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    const elmc_int_t plan_native_int_6 = ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_HOUR);
    const elmc_int_t plan_native_int_9 = ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MINUTE);
    const elmc_int_t plan_native_int_12 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_HOMETZOFFSETMIN);
    const elmc_int_t plan_native_int_14 = ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_UTCOFFSETMINUTES);
    const elmc_int_t plan_native_int_15 = (plan_native_int_6 * 60 + plan_native_int_9 + plan_native_int_12) - plan_native_int_14;
    elmc_plan_block_3:
    const elmc_int_t plan_native_int_17 = (plan_native_bool_2) ? 720 : elmc_int_mod_by(1440, plan_native_int_15);
    *out = plan_native_int_17;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static ElmcValue * elmc_fn_Main_eventMinuteFromPayload(elmc_int_t rise, elmc_int_t set, ElmcValue *value) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  ElmcValue *owned[4] = {0};
  /* plan block 0 */
  const bool plan_native_bool_4 = (rise == 0);
  const bool plan_native_bool_9 = (plan_native_bool_4) ? (set == 0) : false;
  if (!plan_native_bool_9) goto elmc_plan_block_7;
  owned[0] = elmc_maybe_nothing();
  goto elmc_plan_block_8;
  elmc_plan_block_7:
  owned[1] = elmc_retain(value);
  owned[2] = NULL;
  {
    RC __alloc_rc = elmc_maybe_just_own(&owned[2], owned[1]);
    if (__alloc_rc != RC_SUCCESS) {
      ELMC_RC_LOG_FAIL(__alloc_rc, "elmc_maybe_just_own", "allocation failed");
      owned[2] = NULL;;
    }
  }
  owned[1] = NULL;
  elmc_plan_block_8:
  if (plan_native_bool_9) {
    owned[3] = owned[0];
    owned[0] = NULL;
  } else {
    owned[3] = owned[2];
    owned[2] = NULL;
  }
  {
    ElmcValue *__ret = owned[3];
    elmc_owned_null_aliases(owned, 4, __ret);
    elmc_release_array_lifo(owned, 4);
    return __ret;
  }
}

static RC elmc_fn_Main_timeString(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    elmc_int_t plan_native_int_1 = 0;
    /* plan block 0 */
    Rc = elmc_fn_Main_homeMinuteOfDay(&plan_native_int_1, model);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_3 = elmc_int_idiv(plan_native_int_1, 60);
    Rc = elmc_fn_Main_pad2(&owned[0], plan_native_int_3);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1634 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)":", 1 };
    owned[1] = elmc_retain(&plan_str_immortal_1634);
    const elmc_int_t plan_native_int_7 = elmc_int_mod_by(60, plan_native_int_1);
    Rc = elmc_fn_Main_pad2(&owned[2], plan_native_int_7);
    CHECK_RC(Rc);
    Rc = elmc_string_append(&owned[3], owned[1], owned[2]);
    CHECK_RC(Rc);
    /* elm/core: String.append */
    Rc = elmc_string_append(out, owned[0], owned[3]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_temperatureString_native(ElmcValue **out, ElmcValue *model) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    ElmcValue *outer_maybe = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_WEATHER);
    if (elmc_maybe_is_nothing(outer_maybe)) {
      Rc = elmc_new_string(out, "--");
      CHECK_RC(Rc);
    } else {
      ElmcValue *outer = elmc_maybe_just_payload(outer_maybe);
      ElmcValue *union_val = elmc_record_get_index(outer, ELMC_FIELD_MAIN_WEATHER_TEMPERATURE);
      const int case_msg_tag_1 = (union_val && (union_val)->tag == ELMC_TAG_INT ? elmc_as_int(union_val) : (union_val && (union_val)->tag == ELMC_TAG_TUPLE2 && (union_val)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(union_val)->payload)->first) : -1));
      switch (case_msg_tag_1) {
        case ELMC_UNION_COMPANION_TYPES_CELSIUS: {
          char native_suffix_buf_1[22];
          snprintf(native_suffix_buf_1, sizeof(native_suffix_buf_1), "%lldC", (long long)elmc_int_idiv((elmc_union_payload_int(union_val) + 5), 10));
          Rc = elmc_new_string(out, native_suffix_buf_1);
          CHECK_RC(Rc);
          break;
        }
        case ELMC_UNION_COMPANION_TYPES_FAHRENHEIT: {
          char native_suffix_buf_2[22];
          snprintf(native_suffix_buf_2, sizeof(native_suffix_buf_2), "%lldF", (long long)elmc_int_idiv((elmc_union_payload_int(union_val) + 5), 10));
          Rc = elmc_new_string(out, native_suffix_buf_2);
          CHECK_RC(Rc);
          break;
        }
      }
    }
  CATCH_END
  return Rc;
}
static RC elmc_fn_Main_temperatureString(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  return elmc_fn_Main_temperatureString_native(out, model);
}

static RC elmc_fn_Main_windString(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_WIND));
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    static ElmcValue plan_str_immortal_1650 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"--", 2 };
    owned[1] = elmc_retain(&plan_str_immortal_1650);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[2] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    owned[3] = elmc_retain(elmc_record_get_index(owned[2], ELMC_FIELD_MAIN_WIND_DIRECTION));
    Rc = elmc_fn_Main_directionString_native(&owned[4], owned[3]);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1666 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)" ", 1 };
    owned[5] = elmc_retain(&plan_str_immortal_1666);
    owned[6] = elmc_retain(elmc_record_get_index(owned[2], ELMC_FIELD_MAIN_WIND_SPEED));
    Rc = elmc_fn_Main_windSpeedString_native(&owned[7], owned[6]);
    CHECK_RC(Rc);
    Rc = elmc_string_append(&owned[8], owned[5], owned[7]);
    CHECK_RC(Rc);
    Rc = elmc_string_append(&owned[9], owned[4], owned[8]);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[10] = owned[1];
      owned[1] = NULL;
    } else {
      owned[10] = owned[9];
      owned[9] = NULL;
    }
    *out = owned[10];
    owned[10] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_windSpeedString_native(ElmcValue **out, ElmcValue *speed) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    const int case_msg_tag_1 = (speed && (speed)->tag == ELMC_TAG_INT ? elmc_as_int(speed) : (speed && (speed)->tag == ELMC_TAG_TUPLE2 && (speed)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(speed)->payload)->first) : -1));
    switch (case_msg_tag_1) {
      case ELMC_UNION_COMPANION_TYPES_METERSPERSECOND: {
        char native_suffix_buf_1[22];
        snprintf(native_suffix_buf_1, sizeof(native_suffix_buf_1), "%lldm/s", (long long)elmc_union_payload_int(speed));
        Rc = elmc_new_string(out, native_suffix_buf_1);
        CHECK_RC(Rc);
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_MILESPERHOUR: {
        char native_suffix_buf_2[22];
        snprintf(native_suffix_buf_2, sizeof(native_suffix_buf_2), "%lldmph", (long long)elmc_union_payload_int(speed));
        Rc = elmc_new_string(out, native_suffix_buf_2);
        CHECK_RC(Rc);
        break;
      }
    }
  CATCH_END
  return Rc;
}
static RC elmc_fn_Main_windSpeedString(ElmcValue **out, ElmcValue *speed) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  return elmc_fn_Main_windSpeedString_native(out, speed);
}

static RC elmc_fn_Main_altitudeString_native(ElmcValue **out, ElmcValue *altitude) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    const int case_msg_tag_1 = (altitude && (altitude)->tag == ELMC_TAG_INT ? elmc_as_int(altitude) : (altitude && (altitude)->tag == ELMC_TAG_TUPLE2 && (altitude)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(altitude)->payload)->first) : -1));
    switch (case_msg_tag_1) {
      case ELMC_UNION_COMPANION_TYPES_METERS: {
        char native_suffix_buf_1[22];
        snprintf(native_suffix_buf_1, sizeof(native_suffix_buf_1), "%lldm", (long long)elmc_union_payload_int(altitude));
        Rc = elmc_new_string(out, native_suffix_buf_1);
        CHECK_RC(Rc);
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_FEET: {
        char native_suffix_buf_2[22];
        snprintf(native_suffix_buf_2, sizeof(native_suffix_buf_2), "%lldft", (long long)elmc_union_payload_int(altitude));
        Rc = elmc_new_string(out, native_suffix_buf_2);
        CHECK_RC(Rc);
        break;
      }
    }
  CATCH_END
  return Rc;
}
static RC elmc_fn_Main_altitudeString(ElmcValue **out, ElmcValue *altitude) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  return elmc_fn_Main_altitudeString_native(out, altitude);
}

static RC elmc_fn_Main_nextSunCountdown(ElmcValue **out, elmc_int_t nowMin, ElmcValue *maybeSun) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[10] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(maybeSun);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    owned[0] = elmc_maybe_nothing();
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[1] = elmc_retain(elmc_maybe_just_payload(maybeSun));
    static ElmcValue plan_str_immortal_1682 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"SR", 2 };
    owned[2] = elmc_retain(&plan_str_immortal_1682);
    static ElmcValue plan_str_immortal_1698 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"SS", 2 };
    owned[3] = elmc_retain(&plan_str_immortal_1698);
    Rc = elmc_new_int(&owned[4], ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_YES_RENDER_SUNWINDOW_SUNRISEMIN));
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[5], owned[4]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    Rc = elmc_new_int(&owned[6], ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_YES_RENDER_SUNWINDOW_SUNSETMIN));
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[7], owned[6]);
    CHECK_RC(Rc);
    owned[6] = NULL;
    Rc = elmc_fn_Main_nextEventParts(&owned[8], nowMin, owned[2], owned[3], owned[5], owned[7]);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[9] = owned[0];
      owned[0] = NULL;
    } else {
      owned[9] = owned[8];
      owned[8] = NULL;
    }
    *out = owned[9];
    owned[9] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_nextMoonCountdown(ElmcValue **out, elmc_int_t nowMin, ElmcValue *maybeRise, ElmcValue *maybeSet) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[13] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_3 = elmc_maybe_is_nothing(maybeRise);
    const bool plan_native_bool_5 = ((plan_native_bool_3 ? 1 : 0) == 0);
    const bool plan_native_bool_6 = elmc_maybe_is_nothing(maybeSet);
    const bool plan_native_bool_8 = ((plan_native_bool_6 ? 1 : 0) == 0);
    const bool plan_native_bool_9 = (plan_native_bool_5 && plan_native_bool_8);
    if (!plan_native_bool_9) goto elmc_plan_block_2;
    owned[0] = elmc_retain(elmc_maybe_just_payload(maybeRise));
    owned[1] = elmc_retain(elmc_maybe_just_payload(maybeSet));
    const elmc_int_t plan_native_int_13 = elmc_fn_Main_minutesUntilCircular(nowMin, elmc_as_int(owned[0]));
    const elmc_int_t plan_native_int_14 = elmc_fn_Main_minutesUntilCircular(nowMin, elmc_as_int(owned[1]));
    const bool plan_native_bool_15 = (plan_native_int_13 < plan_native_int_14);
    const bool plan_native_bool_18 = (plan_native_bool_15) ? true : (plan_native_int_13 == plan_native_int_14);
    if (!plan_native_bool_18) goto elmc_plan_block_10;
    static ElmcValue plan_str_immortal_1714 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"MR", 2 };
    owned[2] = elmc_retain(&plan_str_immortal_1714);
    Rc = elmc_fn_Main_durationString(&owned[3], plan_native_int_13);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[4], owned[2], owned[3]);
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[5], owned[4]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    goto elmc_plan_block_11;
    elmc_plan_block_10:
    static ElmcValue plan_str_immortal_1730 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"MS", 2 };
    owned[6] = elmc_retain(&plan_str_immortal_1730);
    Rc = elmc_fn_Main_durationString(&owned[7], plan_native_int_14);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[8], owned[6], owned[7]);
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[9], owned[8]);
    CHECK_RC(Rc);
    owned[8] = NULL;
    elmc_plan_block_11:
    if (plan_native_bool_18) {
      owned[10] = owned[5];
      owned[5] = NULL;
    } else {
      owned[10] = owned[9];
      owned[9] = NULL;
    }
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[11] = elmc_maybe_nothing();
    elmc_plan_block_3:
    if (plan_native_bool_9) {
      owned[12] = owned[10];
      owned[10] = NULL;
    } else {
      owned[12] = owned[11];
      owned[11] = NULL;
    }
    *out = owned[12];
    owned[12] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static __attribute__((noinline, noclone)) RC elmc_fn_Main_nextEventParts(ElmcValue **out, elmc_int_t nowMin, ElmcValue *riseLabel, ElmcValue *setLabel, ElmcValue *maybeRise, ElmcValue *maybeSet) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[18] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_5 = elmc_maybe_is_nothing(maybeRise);
    const bool plan_native_bool_7 = ((plan_native_bool_5 ? 1 : 0) == 0);
    const bool plan_native_bool_8 = elmc_maybe_is_nothing(maybeSet);
    const bool plan_native_bool_10 = ((plan_native_bool_8 ? 1 : 0) == 0);
    const bool plan_native_bool_11 = (plan_native_bool_7 && plan_native_bool_10);
    if (!plan_native_bool_11) goto elmc_plan_block_2;
    owned[0] = elmc_retain(elmc_maybe_just_payload(maybeRise));
    owned[1] = elmc_retain(elmc_maybe_just_payload(maybeSet));
    const bool plan_native_bool_15 = (nowMin < elmc_as_int(owned[0]));
    if (!plan_native_bool_15) goto elmc_plan_block_5;
    const elmc_int_t plan_native_int_18 = (elmc_as_int(owned[0])) - nowMin;
    Rc = elmc_fn_Main_durationString(&owned[2], plan_native_int_18);
    CHECK_RC(Rc);
    owned[3] = elmc_retain(riseLabel);
    Rc = elmc_tuple2(&owned[4], owned[3], owned[2]);
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[5], owned[4]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    goto elmc_plan_block_6;
    elmc_plan_block_5:
    const bool plan_native_bool_25 = (nowMin < elmc_as_int(owned[1]));
    if (!plan_native_bool_25) goto elmc_plan_block_9;
    const elmc_int_t plan_native_int_28 = (elmc_as_int(owned[1])) - nowMin;
    Rc = elmc_fn_Main_durationString(&owned[6], plan_native_int_28);
    CHECK_RC(Rc);
    owned[7] = elmc_retain(setLabel);
    Rc = elmc_tuple2(&owned[8], owned[7], owned[6]);
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[9], owned[8]);
    CHECK_RC(Rc);
    owned[8] = NULL;
    goto elmc_plan_block_10;
    elmc_plan_block_9:
    const elmc_int_t plan_native_int_35 = elmc_as_int(owned[0]) + 1440;
    const elmc_int_t plan_native_int_37 = plan_native_int_35 - nowMin;
    Rc = elmc_fn_Main_durationString(&owned[10], plan_native_int_37);
    CHECK_RC(Rc);
    owned[11] = elmc_retain(riseLabel);
    Rc = elmc_tuple2(&owned[12], owned[11], owned[10]);
    CHECK_RC(Rc);
    Rc = elmc_maybe_just_own(&owned[13], owned[12]);
    CHECK_RC(Rc);
    owned[12] = NULL;
    elmc_plan_block_10:
    if (plan_native_bool_25) {
      owned[14] = owned[9];
      owned[9] = NULL;
    } else {
      owned[14] = owned[13];
      owned[13] = NULL;
    }
    elmc_plan_block_6:
    if (plan_native_bool_15) {
      owned[15] = owned[5];
      owned[5] = NULL;
    } else {
      owned[15] = owned[14];
      owned[14] = NULL;
    }
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[16] = elmc_maybe_nothing();
    elmc_plan_block_3:
    if (plan_native_bool_11) {
      owned[17] = owned[15];
      owned[15] = NULL;
    } else {
      owned[17] = owned[16];
      owned[16] = NULL;
    }
    *out = owned[17];
    owned[17] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static elmc_int_t elmc_fn_Main_minutesUntilCircular(elmc_int_t fromMinute, elmc_int_t toMinute) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  /* plan block 0 */
  return elmc_int_mod_by(1440, (toMinute - fromMinute + 1440));
}

static RC elmc_fn_Main_durationString(ElmcValue **out, elmc_int_t minutes) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], elmc_int_idiv(minutes, 60));
    CHECK_RC(Rc);
    Rc = elmc_string_from_int(&owned[1], owned[0]);
    CHECK_RC(Rc);
    static ElmcValue plan_str_immortal_1746 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)":", 1 };
    owned[2] = elmc_retain(&plan_str_immortal_1746);
    const elmc_int_t plan_native_int_6 = elmc_int_mod_by(60, minutes);
    Rc = elmc_fn_Main_pad2(&owned[3], plan_native_int_6);
    CHECK_RC(Rc);
    Rc = elmc_string_append(&owned[4], owned[2], owned[3]);
    CHECK_RC(Rc);
    /* elm/core: String.append */
    Rc = elmc_string_append(out, owned[1], owned[4]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_batteryAlert(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_BATTERYLEVEL));
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    Rc = elmc_new_bool(&owned[1], false);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[2] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    const bool plan_native_bool_6 = (elmc_as_int(owned[2]) < 25);
    if (plan_native_bool_6) {
      ElmcValue *plan_ephemeral_box_1762 = NULL;
      Rc = elmc_new_bool(&plan_ephemeral_box_1762, 1);
      CHECK_RC(Rc);
      owned[3] = elmc_retain(plan_ephemeral_box_1762);
      elmc_release(plan_ephemeral_box_1762);
    } else {
      ElmcValue *plan_ephemeral_box_1778 = NULL;
      Rc = elmc_new_bool(&plan_ephemeral_box_1778, (elmc_as_int(owned[2]) == 25));
      CHECK_RC(Rc);
      owned[3] = elmc_retain(plan_ephemeral_box_1778);
      elmc_release(plan_ephemeral_box_1778);
    }
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[4] = owned[1];
      owned[1] = NULL;
    } else {
      owned[4] = owned[3];
      owned[3] = NULL;
    }
    *out = owned[4];
    owned[4] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Main_batteryAlert_native(bool *out, ElmcValue * const model) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_batteryAlert(&boxed, model);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_bool(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_haveSteps(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[3] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_STEPSTODAY));
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(owned[0]);
    if (plan_native_bool_2) goto elmc_plan_block_3;
    owned[1] = elmc_retain(elmc_maybe_just_payload(owned[0]));
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      ElmcValue *plan_ephemeral_box_1794 = NULL;
      Rc = elmc_new_bool(&plan_ephemeral_box_1794, 0);
      CHECK_RC(Rc);
      owned[2] = elmc_retain(plan_ephemeral_box_1794);
      elmc_release(plan_ephemeral_box_1794);
    } else {
      ElmcValue *plan_ephemeral_box_1810 = NULL;
      Rc = elmc_new_bool(&plan_ephemeral_box_1810, (elmc_as_int(owned[1]) > 0));
      CHECK_RC(Rc);
      owned[2] = elmc_retain(plan_ephemeral_box_1810);
      elmc_release(plan_ephemeral_box_1810);
    }
    *out = owned[2];
    owned[2] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}
static RC elmc_fn_Main_haveSteps_native(bool *out, ElmcValue * const model) {
  ElmcValue *boxed = NULL;
  RC Rc = elmc_fn_Main_haveSteps(&boxed, model);
  if (Rc != RC_SUCCESS) return Rc;
  *out = elmc_as_bool(boxed);
  elmc_release(boxed);
  return RC_SUCCESS;
}

static RC elmc_fn_Main_batteryPercentString_native(ElmcValue **out, ElmcValue *model) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    ElmcValue *maybe_val = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_BATTERYLEVEL);
    elmc_int_t level = elmc_maybe_with_default_int(0, maybe_val);
    char level_buf[22];
    snprintf(level_buf, sizeof(level_buf), "%lld%%", (long long)level);
    Rc = elmc_new_string(out, level_buf);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}
static RC elmc_fn_Main_batteryPercentString(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  return elmc_fn_Main_batteryPercentString_native(out, model);
}

static RC elmc_fn_Main_stepsString_native(ElmcValue **out, ElmcValue *model) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    ElmcValue *maybe_val = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_STEPSTODAY);
    if (elmc_maybe_is_nothing(maybe_val)) {
      Rc = elmc_new_string(out, "--");
      CHECK_RC(Rc);
    } else {
      elmc_int_t steps = elmc_as_int(elmc_maybe_just_payload(maybe_val));
      char steps_buf[22];
      if (steps >= 10000) {
        snprintf(steps_buf, sizeof(steps_buf), "%lldk", (long long)elmc_int_idiv(steps, 1000));
      } else {
        snprintf(steps_buf, sizeof(steps_buf), "%lld", (long long)steps);
      }
      Rc = elmc_new_string(out, steps_buf);
      CHECK_RC(Rc);
    }
  CATCH_END
  return Rc;
}
static RC elmc_fn_Main_stepsString(ElmcValue **out, ElmcValue *model) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  return elmc_fn_Main_stepsString_native(out, model);
}

static RC elmc_fn_Main_normalizeCycleSec(elmc_int_t *out, elmc_int_t seconds) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_2 = (seconds == 10);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    Rc = elmc_new_bool(&owned[0], true);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    const bool plan_native_bool_6 = (seconds == 30);
    if (plan_native_bool_6) {
      ElmcValue *plan_ephemeral_box_1826 = NULL;
      Rc = elmc_new_bool(&plan_ephemeral_box_1826, 1);
      CHECK_RC(Rc);
      owned[1] = elmc_retain(plan_ephemeral_box_1826);
      elmc_release(plan_ephemeral_box_1826);
    } else {
      ElmcValue *plan_ephemeral_box_1842 = NULL;
      Rc = elmc_new_bool(&plan_ephemeral_box_1842, (seconds == 60));
      CHECK_RC(Rc);
      owned[1] = elmc_retain(plan_ephemeral_box_1842);
      elmc_release(plan_ephemeral_box_1842);
    }
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[2] = owned[0];
      owned[0] = NULL;
    } else {
      owned[2] = owned[1];
      owned[1] = NULL;
    }
    if (!elmc_as_bool(owned[2])) goto elmc_plan_block_12;
    goto elmc_plan_block_13;
    elmc_plan_block_12:
    Rc = elmc_new_int(&owned[3], 5);
    CHECK_RC(Rc);
    elmc_plan_block_13:
    const elmc_int_t plan_native_int_15 = (elmc_as_bool(owned[2])) ? seconds : 5;
    *out = plan_native_int_15;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static elmc_int_t elmc_fn_Main_cycleSlot(ElmcValue *model, elmc_int_t count_arg) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  /* plan block 0 */
  const elmc_int_t plan_native_int_2 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_CORNERCYCLE);
  return elmc_int_mod_by(count_arg, plan_native_int_2);
}

static RC elmc_fn_Main_directionString_native(ElmcValue **out, ElmcValue *direction) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    const int case_msg_tag_1 = elmc_union_tag_as_int(direction);
    static ElmcValue native_str_immortal_2 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"N", 1 };
    static ElmcValue native_str_immortal_3 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"NE", 2 };
    static ElmcValue native_str_immortal_4 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"E", 1 };
    static ElmcValue native_str_immortal_5 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"SE", 2 };
    static ElmcValue native_str_immortal_6 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"S", 1 };
    static ElmcValue native_str_immortal_7 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"SW", 2 };
    static ElmcValue native_str_immortal_8 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"W", 1 };
    static ElmcValue native_str_immortal_9 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"NW", 2 };
    switch (case_msg_tag_1) {
      case ELMC_UNION_COMPANION_TYPES_NORTH: {
        *out = &native_str_immortal_2;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_NORTHEAST: {
        *out = &native_str_immortal_3;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_EAST: {
        *out = &native_str_immortal_4;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_SOUTHEAST: {
        *out = &native_str_immortal_5;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_SOUTH: {
        *out = &native_str_immortal_6;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_SOUTHWEST: {
        *out = &native_str_immortal_7;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_WEST: {
        *out = &native_str_immortal_8;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_NORTHWEST: {
        *out = &native_str_immortal_9;
        break;
      }
    }
  CATCH_END
  return Rc;
}
static RC elmc_fn_Main_directionString(ElmcValue **out, ElmcValue *direction) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  return elmc_fn_Main_directionString_native(out, direction);
}

static RC elmc_fn_Main_monthString_native(ElmcValue **out, elmc_int_t month) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    static ElmcValue native_str_immortal_lut_1[13] = {
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Dec", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Jan", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Feb", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Mar", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Apr", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"May", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Jun", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Jul", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Aug", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Sep", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Oct", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Nov", 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"Dec", 3 }
    };
    *out = &native_str_immortal_lut_1[((month) >= 0 && (month) < 12) ? (month) : 12];
  CATCH_END
  return Rc;
}
static RC elmc_fn_Main_monthString(ElmcValue **out, elmc_int_t month) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  return elmc_fn_Main_monthString_native(out, month);
}

static RC elmc_fn_Main_pad2(ElmcValue **out, elmc_int_t value) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_2 = (value < 10);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    static ElmcValue plan_str_immortal_1858 = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"0", 1 };
    owned[0] = elmc_retain(&plan_str_immortal_1858);
    ElmcValue *plan_ephemeral_box_1890 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1890, value);
    CHECK_RC(Rc);
    Rc = elmc_string_from_int(&owned[1], plan_ephemeral_box_1890);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_1890);
    Rc = elmc_string_append(&owned[2], owned[0], owned[1]);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    ElmcValue *plan_ephemeral_box_1922 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1922, value);
    CHECK_RC(Rc);
    Rc = elmc_string_from_int(&owned[3], plan_ephemeral_box_1922);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_1922);
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[4] = owned[2];
      owned[2] = NULL;
    } else {
      owned[4] = owned[3];
      owned[3] = NULL;
    }
    *out = owned[4];
    owned[4] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Main_main(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(out, 0);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}

static RC elmc_fn_Yes_Layout_fromScreen(ElmcValue **out, elmc_int_t screenW, elmc_int_t screenH) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[40] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const elmc_int_t plan_native_int_2 = ((screenW <= screenH) ? screenW : screenH);
    const elmc_int_t plan_native_int_4 = elmc_int_idiv(screenW, 2);
    const elmc_int_t plan_native_int_6 = elmc_int_idiv(screenH, 2);
    const elmc_int_t plan_native_int_10 = elmc_int_idiv(plan_native_int_2, 2) - 22;
    const elmc_int_t plan_native_int_14 = plan_native_int_6 + elmc_int_idiv(plan_native_int_2, 5);
    Rc = elmc_new_int(&owned[0], 10);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[1], elmc_int_idiv(plan_native_int_10, 5));
    CHECK_RC(Rc);
    /* elm/core: Basics.max */
    Rc = elmc_basics_max(&owned[2], owned[0], owned[1]);
    CHECK_RC(Rc);
    if (owned[2] == owned[0]) {
      elmc_release(owned[2]);
      owned[0] = NULL;
    }
    if (owned[2] == owned[1]) {
      elmc_release(owned[2]);
      owned[1] = NULL;
    }
    const elmc_int_t plan_native_int_62 = (plan_native_int_6 - elmc_int_idiv(plan_native_int_10, 2)) - 14;
    Rc = elmc_new_int(&owned[3], 4);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[4], elmc_int_idiv((plan_native_int_10 * 6), 50));
    CHECK_RC(Rc);
    /* elm/core: Basics.max */
    Rc = elmc_basics_max(&owned[32], owned[3], owned[4]);
    CHECK_RC(Rc);
    if (owned[32] == owned[3]) {
      elmc_release(owned[32]);
      owned[3] = NULL;
    }
    if (owned[32] == owned[4]) {
      elmc_release(owned[32]);
      owned[4] = NULL;
    }
    Rc = elmc_new_int(&owned[5], 8);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[6], elmc_int_idiv((plan_native_int_10 * 10), 50));
    CHECK_RC(Rc);
    /* elm/core: Basics.max */
    Rc = elmc_basics_max(&owned[33], owned[5], owned[6]);
    CHECK_RC(Rc);
    if (owned[33] == owned[5]) {
      elmc_release(owned[33]);
      owned[5] = NULL;
    }
    if (owned[33] == owned[6]) {
      elmc_release(owned[33]);
      owned[6] = NULL;
    }
    Rc = elmc_new_int(&owned[7], 10);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_38 = plan_native_int_10 * 18;
    Rc = elmc_new_int(&owned[8], elmc_int_idiv(plan_native_int_38, 50));
    CHECK_RC(Rc);
    /* elm/core: Basics.max */
    Rc = elmc_basics_max(&owned[9], owned[7], owned[8]);
    CHECK_RC(Rc);
    if (owned[9] == owned[7]) {
      elmc_release(owned[9]);
      owned[7] = NULL;
    }
    if (owned[9] == owned[8]) {
      elmc_release(owned[9]);
      owned[8] = NULL;
    }
    const elmc_int_t plan_native_int_176 = plan_native_int_10 - (elmc_as_int(owned[9]));
    Rc = elmc_new_int(&owned[10], 4);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[11], elmc_int_idiv(plan_native_int_2, 36));
    CHECK_RC(Rc);
    /* elm/core: Basics.max */
    Rc = elmc_basics_max(&owned[12], owned[10], owned[11]);
    CHECK_RC(Rc);
    if (owned[12] == owned[10]) {
      elmc_release(owned[12]);
      owned[10] = NULL;
    }
    if (owned[12] == owned[11]) {
      elmc_release(owned[12]);
      owned[11] = NULL;
    }
    const elmc_int_t plan_native_int_48 = screenH - (elmc_as_int(owned[12]));
    Rc = elmc_new_int(&owned[13], 14);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_1938 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1938, screenH);
    CHECK_RC(Rc);
    owned[14] = plan_ephemeral_box_1938;
    owned[30] = owned[2];
    owned[2] = NULL;
    Rc = elmc_new_int(&owned[15], 0);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_67 = 0;
    Rc = elmc_new_int(&owned[16], 28);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_68 = plan_native_int_62;
    elmc_int_t rec_values_70_15[4] = { plan_native_int_67, plan_native_int_68, screenW, 28 };
    Rc = elmc_record_new_values_ints(&owned[31], 4, rec_values_70_15);
    CHECK_RC(Rc);
    owned[34] = elmc_retain(owned[12]);
    owned[17] = elmc_retain(owned[12]);
    owned[18] = elmc_retain(owned[12]);
    Rc = elmc_new_int(&owned[19], 40);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[20], 16);
    CHECK_RC(Rc);
    elmc_int_t rec_values_86_16[4] = { elmc_as_int(owned[17]), elmc_as_int(owned[18]), 40, 16 };
    Rc = elmc_record_new_values_ints(&owned[35], 4, rec_values_86_16);
    CHECK_RC(Rc);
    owned[21] = elmc_retain(owned[12]);
    const elmc_int_t plan_native_int_97 = elmc_as_int(owned[12]) + 16;
    Rc = elmc_new_int(&owned[22], 44);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[23], 12);
    CHECK_RC(Rc);
    elmc_int_t rec_values_99_17[4] = { elmc_as_int(owned[21]), plan_native_int_97, 44, 12 };
    Rc = elmc_record_new_values_ints(&owned[36], 4, rec_values_99_17);
    CHECK_RC(Rc);
    owned[24] = elmc_retain(owned[12]);
    Rc = elmc_new_int(&owned[25], 48);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_111 = 14;
    elmc_int_t rec_values_111_18[4] = { screenW - 52, elmc_as_int(owned[24]), 48, plan_native_int_111 };
    Rc = elmc_record_new_values_ints(&owned[37], 4, rec_values_111_18);
    CHECK_RC(Rc);
    owned[26] = elmc_retain(owned[12]);
    const elmc_int_t plan_native_int_124 = elmc_int_idiv(screenW, 2) - (elmc_as_int(owned[12]));
    const elmc_int_t plan_native_int_125 = 14;
    elmc_int_t rec_values_125_19[4] = { elmc_as_int(owned[26]), plan_native_int_48 - 14, plan_native_int_124, plan_native_int_125 };
    Rc = elmc_record_new_values_ints(&owned[38], 4, rec_values_125_19);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_1954 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1954, screenW - 64 + 3);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_1970 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1970, plan_native_int_48 - 38);
    CHECK_RC(Rc);
    ElmcValue *rec_values_137_20[2] = { plan_ephemeral_box_1954, plan_ephemeral_box_1970 };
    Rc = elmc_record_new_values_take(&owned[28], 2, rec_values_137_20);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_146 = screenW - 64;
    Rc = elmc_new_int(&owned[27], 60);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_149 = 14;
    elmc_int_t rec_values_149_21[4] = { plan_native_int_146, plan_native_int_48 - 14, 60, plan_native_int_149 };
    Rc = elmc_record_new_values_ints(&owned[29], 4, rec_values_149_21);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_1986 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_1986, screenW - 64);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2002 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2002, plan_native_int_48);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2018 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2018, 62);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2034 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2034, 12);
    CHECK_RC(Rc);
    ElmcValue *rec_values_162_22[8] = { plan_ephemeral_box_1986, plan_ephemeral_box_2002, plan_ephemeral_box_2018, owned[13], owned[28], owned[29], plan_ephemeral_box_2034, elmc_retain(owned[13]) };
    Rc = elmc_record_new_values_take(&owned[39], 8, rec_values_162_22);
    CHECK_RC(Rc);
    owned[13] = NULL;
    owned[28] = NULL;
    owned[29] = NULL;
    owned[28] = NULL;
    owned[29] = NULL;
    ElmcValue *plan_ephemeral_box_2050 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2050, screenW);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2066 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2066, plan_native_int_4);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2082 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2082, plan_native_int_6);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2098 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2098, plan_native_int_2);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2114 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2114, plan_native_int_10);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2130 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2130, plan_native_int_10 - 5);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2146 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2146, plan_native_int_14);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2162 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2162, plan_native_int_176);
    CHECK_RC(Rc);
    ElmcValue *rec_values_183_23[19] = { plan_ephemeral_box_2050, owned[14], plan_ephemeral_box_2066, plan_ephemeral_box_2082, plan_ephemeral_box_2098, plan_ephemeral_box_2114, plan_ephemeral_box_2130, plan_ephemeral_box_2146, owned[30], owned[31], owned[32], owned[33], plan_ephemeral_box_2162, owned[34], owned[35], owned[36], owned[37], owned[38], owned[39] };
    Rc = elmc_record_new_values_take(out, 19, rec_values_183_23);
    CHECK_RC(Rc);
    owned[14] = NULL;
    owned[30] = NULL;
    owned[31] = NULL;
    owned[32] = NULL;
    owned[33] = NULL;
    owned[34] = NULL;
    owned[35] = NULL;
    owned[36] = NULL;
    owned[37] = NULL;
    owned[38] = NULL;
    owned[39] = NULL;
    owned[30] = NULL;
    owned[31] = NULL;
    owned[32] = NULL;
    owned[33] = NULL;
    owned[34] = NULL;
    owned[35] = NULL;
    owned[36] = NULL;
    owned[37] = NULL;
    owned[38] = NULL;
    owned[39] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Layout_centerSquare(ElmcValue **out, ElmcValue *layout, elmc_int_t radius) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    /* plan block 0 */
    const elmc_int_t plan_native_int_2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_5 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    elmc_int_t rec_values_18_24[4] = { plan_native_int_2 - radius, plan_native_int_5 - radius, radius * 2, radius * 2 };
    Rc = elmc_record_new_values_ints(out, 4, rec_values_18_24);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}

static RC elmc_fn_Yes_Render_face(ElmcValue **out, ElmcValue *layout, ElmcValue *display) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[9] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_render_cmd6_take(&owned[0], ELMC_RENDER_OP_CLEAR, ELMC_COLOR_BLACK, 0, 0, 0, 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_2178[1] = { owned[0] };
    Rc = elmc_list_from_values(&owned[1], plan_list_items_2178, 1);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_drawDial(&owned[2], layout, display);
    CHECK_RC(Rc);
    owned[3] = elmc_retain(elmc_record_get_index(display, ELMC_FIELD_YES_RENDER_FACEDISPLAY_SHOWCORNERS));
    if (!elmc_as_bool(owned[3])) goto elmc_plan_block_2;
    owned[4] = elmc_retain(elmc_record_get_index(display, ELMC_FIELD_YES_RENDER_FACEDISPLAY_CORNERS));
    Rc = elmc_fn_Yes_Render_drawCorners(&owned[5], layout, owned[4]);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[6] = elmc_list_nil();
    elmc_plan_block_3:
    if (elmc_as_bool(owned[3])) {
      owned[7] = owned[5];
      owned[5] = NULL;
    } else {
      owned[7] = owned[6];
      owned[6] = NULL;
    }
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[8], owned[2], owned[7]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(out, owned[1], owned[8]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawDial(ElmcValue **out, ElmcValue *layout, ElmcValue *display) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[65] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_fn_Yes_Render_defaultSunWindow(&owned[0]);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(elmc_record_get_index(display, ELMC_FIELD_YES_RENDER_FACEDISPLAY_SUN));
    /* elm/core: Maybe.withDefault */
    owned[2] = elmc_maybe_with_default(owned[0], owned[1]);
    if (owned[2] == owned[0]) {
      elmc_release(owned[2]);
      owned[0] = NULL;
    }
    owned[3] = elmc_retain(elmc_record_get_index(display, ELMC_FIELD_YES_RENDER_FACEDISPLAY_SUN));
    const bool plan_native_bool_6 = elmc_maybe_is_nothing(owned[3]);
    Rc = elmc_new_bool(&owned[4], plan_native_bool_6);
    CHECK_RC(Rc);
    owned[5] = elmc_basics_not(owned[4]);
    const elmc_int_t plan_native_int_9 = ELMC_RECORD_GET_INDEX_INT(owned[2], ELMC_FIELD_YES_RENDER_SUNWINDOW_SUNRISEMIN);
    const elmc_int_t plan_native_int_10 = elmc_fn_Yes_Render_angleFromMinute(plan_native_int_9);
    const elmc_int_t plan_native_int_11 = ELMC_RECORD_GET_INDEX_INT(owned[2], ELMC_FIELD_YES_RENDER_SUNWINDOW_SUNSETMIN);
    const elmc_int_t plan_native_int_12 = elmc_fn_Yes_Render_angleFromMinute(plan_native_int_11);
    const elmc_int_t plan_native_int_13 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_OUTERRADIUS);
    Rc = elmc_fn_Yes_Layout_centerSquare(&owned[6], layout, plan_native_int_13);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_15 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_INNERRADIUS);
    Rc = elmc_fn_Yes_Layout_centerSquare(&owned[7], layout, plan_native_int_15);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_22 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_23 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    ElmcValue *plan_ephemeral_box_2194 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2194, plan_native_int_22);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2210 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2210, plan_native_int_23);
    CHECK_RC(Rc);
    ElmcValue *rec_values_23_25[2] = { plan_ephemeral_box_2194, plan_ephemeral_box_2210 };
    Rc = elmc_record_new_values_take(&owned[8], 2, rec_values_23_25);
    CHECK_RC(Rc);
    owned[9] = elmc_retain(elmc_record_get_index(owned[8], 0 /* x */));
    owned[10] = elmc_retain(elmc_record_get_index(owned[8], 1 /* y */));
    const elmc_int_t plan_native_int_27 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_OUTERRADIUS);
    Rc = elmc_tuple2_ints(&owned[11], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2226 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2226, ELMC_COLOR_OXFORD_BLUE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[12], plan_ephemeral_box_2226, owned[11]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2226);
    ElmcValue *plan_ephemeral_box_2242 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2242, plan_native_int_27);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[13], plan_ephemeral_box_2242, owned[12]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2242);
    Rc = elmc_tuple2(&owned[14], owned[10], owned[13]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[15], owned[9], owned[14]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2258 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2258, ELMC_RENDER_OP_FILL_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[16], plan_ephemeral_box_2258, owned[15]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2258);
    ElmcValue *plan_list_items_2274[1] = { owned[16] };
    Rc = elmc_list_from_values(&owned[17], plan_list_items_2274, 1);
    CHECK_RC(Rc);
    if (!elmc_as_bool(owned[5])) goto elmc_plan_block_2;
    Rc = elmc_new_int(&owned[18], ELMC_COLOR_BLUE_MOON);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_coloredRadialWedge(&owned[19], owned[6], owned[18], plan_native_int_10, plan_native_int_12);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[20] = elmc_list_nil();
    elmc_plan_block_3:
    if (elmc_as_bool(owned[5])) {
      owned[21] = owned[19];
      owned[19] = NULL;
    } else {
      owned[21] = owned[20];
      owned[20] = NULL;
    }
    owned[22] = elmc_retain(elmc_record_get_index(owned[8], 0 /* x */));
    owned[23] = elmc_retain(elmc_record_get_index(owned[8], 1 /* y */));
    const elmc_int_t plan_native_int_46 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_INNERRADIUS);
    Rc = elmc_tuple2_ints(&owned[24], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2290 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2290, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[25], plan_ephemeral_box_2290, owned[24]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2290);
    ElmcValue *plan_ephemeral_box_2306 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2306, plan_native_int_46);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[26], plan_ephemeral_box_2306, owned[25]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2306);
    Rc = elmc_tuple2(&owned[27], owned[23], owned[26]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[28], owned[22], owned[27]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2322 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2322, ELMC_RENDER_OP_FILL_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[29], plan_ephemeral_box_2322, owned[28]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2322);
    ElmcValue *plan_list_items_2338[1] = { owned[29] };
    Rc = elmc_list_from_values(&owned[30], plan_list_items_2338, 1);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_57 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_INNERRADIUS);
    Rc = elmc_fn_Yes_Render_drawSunWindow(&owned[31], owned[8], plan_native_int_57, owned[7], plan_native_int_10, plan_native_int_12, owned[2]);
    CHECK_RC(Rc);
    owned[32] = elmc_retain(elmc_record_get_index(owned[8], 0 /* x */));
    owned[33] = elmc_retain(elmc_record_get_index(owned[8], 1 /* y */));
    const elmc_int_t plan_native_int_62 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_OUTERRADIUS);
    Rc = elmc_tuple2_ints(&owned[34], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2354 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2354, ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[35], plan_ephemeral_box_2354, owned[34]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2354);
    ElmcValue *plan_ephemeral_box_2370 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2370, plan_native_int_62);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[36], plan_ephemeral_box_2370, owned[35]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2370);
    Rc = elmc_tuple2(&owned[37], owned[33], owned[36]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[38], owned[32], owned[37]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2386 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2386, ELMC_RENDER_OP_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[39], plan_ephemeral_box_2386, owned[38]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2386);
    owned[40] = elmc_retain(elmc_record_get_index(owned[8], 0 /* x */));
    owned[41] = elmc_retain(elmc_record_get_index(owned[8], 1 /* y */));
    const elmc_int_t plan_native_int_75 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_INNERRADIUS);
    Rc = elmc_tuple2_ints(&owned[42], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2402 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2402, ELMC_COLOR_DARK_GRAY);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[43], plan_ephemeral_box_2402, owned[42]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2402);
    ElmcValue *plan_ephemeral_box_2418 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2418, plan_native_int_75);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[44], plan_ephemeral_box_2418, owned[43]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2418);
    Rc = elmc_tuple2(&owned[45], owned[41], owned[44]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[46], owned[40], owned[45]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2434 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2434, ELMC_RENDER_OP_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[47], plan_ephemeral_box_2434, owned[46]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2434);
    ElmcValue *plan_list_items_2450[2] = { owned[39], owned[47] };
    Rc = elmc_list_from_values(&owned[48], plan_list_items_2450, 2);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_drawOuterScale(&owned[49], layout);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_88 = ELMC_RECORD_GET_INDEX_INT(display, ELMC_FIELD_YES_RENDER_FACEDISPLAY_HOMEMINUTE);
    Rc = elmc_fn_Yes_Render_draw24HourHand(&owned[50], layout, plan_native_int_88);
    CHECK_RC(Rc);
    owned[51] = elmc_retain(elmc_record_get_index(display, ELMC_FIELD_YES_RENDER_FACEDISPLAY_MOONPHASEE6));
    Rc = elmc_fn_Yes_Render_drawMoonGlyph(&owned[52], layout, owned[51]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[53], ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    owned[54] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_TIMETEXTBAND));
    owned[55] = elmc_retain(elmc_record_get_index(display, ELMC_FIELD_YES_RENDER_FACEDISPLAY_TIMETEXT));
    Rc = elmc_fn_Yes_Render_textAt(&owned[56], owned[53], owned[54], owned[55]);
    CHECK_RC(Rc);
    if (owned[56] == owned[53]) {
      owned[53] = NULL;
    }
    if (owned[56] == owned[54]) {
      owned[54] = NULL;
    }
    if (owned[56] == owned[55]) {
      owned[55] = NULL;
    }
    ElmcValue *plan_list_items_2466[1] = { owned[56] };
    Rc = elmc_list_from_values(&owned[57], plan_list_items_2466, 1);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[58], owned[52], owned[57]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[59], owned[50], owned[58]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[60], owned[49], owned[59]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[61], owned[48], owned[60]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[62], owned[31], owned[61]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[63], owned[30], owned[62]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[64], owned[21], owned[63]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(out, owned[17], owned[64]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_draw24HourHand(ElmcValue **out, ElmcValue *layout, elmc_int_t nowMin) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[21] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const elmc_int_t plan_native_int_2 = elmc_fn_Yes_Render_angleFromMinute(nowMin);
    const elmc_int_t plan_native_int_3 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_4 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    const elmc_int_t plan_native_int_5 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_HANDLEN);
    Rc = elmc_fn_Yes_Render_pointAt(&owned[0], plan_native_int_3, plan_native_int_4, plan_native_int_5, plan_native_int_2);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_8 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_9 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    const elmc_int_t plan_native_int_10 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_PEBBLE_UI_POINT_X);
    const elmc_int_t plan_native_int_11 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_PEBBLE_UI_POINT_Y);
    Rc = elmc_new_int(&owned[1], 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2482 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2482, ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[2], plan_ephemeral_box_2482, owned[1]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2482);
    ElmcValue *plan_ephemeral_box_2498 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2498, plan_native_int_11);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[3], plan_ephemeral_box_2498, owned[2]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2498);
    ElmcValue *plan_ephemeral_box_2514 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2514, plan_native_int_10);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[4], plan_ephemeral_box_2514, owned[3]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2514);
    ElmcValue *plan_ephemeral_box_2530 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2530, plan_native_int_9);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[5], plan_ephemeral_box_2530, owned[4]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2530);
    ElmcValue *plan_ephemeral_box_2546 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2546, plan_native_int_8);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[6], plan_ephemeral_box_2546, owned[5]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2546);
    ElmcValue *plan_ephemeral_box_2562 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2562, ELMC_RENDER_OP_LINE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[7], plan_ephemeral_box_2562, owned[6]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2562);
    const elmc_int_t plan_native_int_21 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_22 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    const elmc_int_t plan_native_int_23 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_HUBR);
    Rc = elmc_tuple2_ints(&owned[8], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2578 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2578, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[9], plan_ephemeral_box_2578, owned[8]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2578);
    ElmcValue *plan_ephemeral_box_2594 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2594, plan_native_int_23);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[10], plan_ephemeral_box_2594, owned[9]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2594);
    ElmcValue *plan_ephemeral_box_2610 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2610, plan_native_int_22);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[11], plan_ephemeral_box_2610, owned[10]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2610);
    ElmcValue *plan_ephemeral_box_2626 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2626, plan_native_int_21);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[12], plan_ephemeral_box_2626, owned[11]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2626);
    ElmcValue *plan_ephemeral_box_2642 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2642, ELMC_RENDER_OP_FILL_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[13], plan_ephemeral_box_2642, owned[12]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2642);
    const elmc_int_t plan_native_int_34 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_35 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    const elmc_int_t plan_native_int_36 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_HUBR);
    Rc = elmc_tuple2_ints(&owned[14], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2658 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2658, ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[15], plan_ephemeral_box_2658, owned[14]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2658);
    ElmcValue *plan_ephemeral_box_2674 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2674, plan_native_int_36);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[16], plan_ephemeral_box_2674, owned[15]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2674);
    ElmcValue *plan_ephemeral_box_2690 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2690, plan_native_int_35);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[17], plan_ephemeral_box_2690, owned[16]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2690);
    ElmcValue *plan_ephemeral_box_2706 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2706, plan_native_int_34);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[18], plan_ephemeral_box_2706, owned[17]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2706);
    ElmcValue *plan_ephemeral_box_2722 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2722, ELMC_RENDER_OP_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[19], plan_ephemeral_box_2722, owned[18]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2722);
    ElmcValue *plan_list_items_2738[3] = { owned[7], owned[13], owned[19] };
    Rc = elmc_list_from_values(&owned[20], plan_list_items_2738, 3);
    CHECK_RC(Rc);
    *out = owned[20];
    owned[20] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawOuterScale(ElmcValue **out, ElmcValue *layout) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[11] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_closure_new_rc(&owned[1], elmc_fn_Yes_Render_drawOuterScale_closure_1, 1, 0, NULL);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[2], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[3], 23);
    CHECK_RC(Rc);
    Rc = elmc_list_range(&owned[4], owned[2], owned[3]);
    CHECK_RC(Rc);
    Rc = elmc_list_filter(&owned[5], owned[1], owned[4]);
    CHECK_RC(Rc);
    ElmcValue *list_walk_map_head_0 = elmc_list_nil();
    if (owned[5] && owned[5]->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *direct_ilp_0 = (ElmcIntListPayload *)owned[5]->payload;
      int direct_ilen_0 = direct_ilp_0 ? direct_ilp_0->length : 0;
      for (int direct_ii_0 = 0;
      Rc == RC_SUCCESS && direct_ii_0 < direct_ilen_0;
      direct_ii_0++) {
        ElmcValue *__map_head_box__ = NULL;
        Rc = elmc_new_int(&__map_head_box__, direct_ilp_0->values[direct_ii_0]);
        CHECK_RC(Rc);
        ElmcValue *list_walk_map_item_0 = NULL;
        ElmcValue *loop_args[1] = { __map_head_box__ };
        Rc = elmc_fn_Yes_Render_drawOuterScale_closure_0(&list_walk_map_item_0, loop_args, 1, NULL, 0);
        elmc_release(__map_head_box__);
        CHECK_RC(Rc);
        {
          ElmcValue *singleton = NULL;
          Rc = elmc_list_cons(&singleton, list_walk_map_item_0, elmc_list_nil());
          CHECK_RC(Rc);
          elmc_release(list_walk_map_item_0);
          list_walk_map_item_0 = NULL;
          ElmcValue *next = NULL;
          Rc = elmc_list_append(&next, list_walk_map_head_0, singleton);
          CHECK_RC(Rc);
          elmc_release(singleton);
          elmc_release(list_walk_map_head_0);
          list_walk_map_head_0 = next;
        }
      }
    } else {
      ElmcValue *list_walk_map_cursor_0 = owned[5];
      while (list_walk_map_cursor_0 && list_walk_map_cursor_0->tag == ELMC_TAG_LIST && list_walk_map_cursor_0->payload != NULL) {
        ElmcCons *list_walk_map_node_0 = (ElmcCons *)list_walk_map_cursor_0->payload;
        ElmcValue *list_walk_map_item_0 = NULL;
        ElmcValue *loop_args[1] = { list_walk_map_node_0->head };
        Rc = elmc_fn_Yes_Render_drawOuterScale_closure_0(&list_walk_map_item_0, loop_args, 1, NULL, 0);
        CHECK_RC(Rc);
        {
          ElmcValue *singleton = NULL;
          Rc = elmc_list_cons(&singleton, list_walk_map_item_0, elmc_list_nil());
          CHECK_RC(Rc);
          elmc_release(list_walk_map_item_0);
          list_walk_map_item_0 = NULL;
          ElmcValue *next = NULL;
          Rc = elmc_list_append(&next, list_walk_map_head_0, singleton);
          CHECK_RC(Rc);
          elmc_release(singleton);
          elmc_release(list_walk_map_head_0);
          list_walk_map_head_0 = next;
        }
        list_walk_map_cursor_0 = list_walk_map_node_0->tail;
      }
    }
    owned[9] = list_walk_map_head_0;
    ElmcValue *list_map_cursor_head_2 = elmc_list_nil();
    for (elmc_int_t list_map_cursor_i_2 = 0; list_map_cursor_i_2 <= 11; list_map_cursor_i_2++) {
      ElmcValue *list_map_cursor_item_2 = NULL;
      ElmcValue *loop_args[1];
      Rc = elmc_new_int(&loop_args[0], list_map_cursor_i_2);
      CHECK_RC(Rc);
      Rc = elmc_fn_Yes_Render_drawOuterScale_closure_2(&list_map_cursor_item_2, loop_args, 1, NULL, 0);
      CHECK_RC(Rc);
      elmc_release(loop_args[0]);
      {
        ElmcValue *singleton = NULL;
        Rc = elmc_list_cons(&singleton, list_map_cursor_item_2, elmc_list_nil());
        CHECK_RC(Rc);
        elmc_release(list_map_cursor_item_2);
        list_map_cursor_item_2 = NULL;
        ElmcValue *next = NULL;
        Rc = elmc_list_append(&next, list_map_cursor_head_2, singleton);
        CHECK_RC(Rc);
        elmc_release(singleton);
        elmc_release(list_map_cursor_head_2);
        list_map_cursor_head_2 = next;
      }
    }
    owned[10] = list_map_cursor_head_2;
    owned[7] = elmc_retain(layout);
    ElmcValue *plan_cap_11[1] = { owned[7] };
    Rc = elmc_closure_new_rc(&owned[6], elmc_fn_Yes_Render_drawOuterScale_closure_3, 1, 1, plan_cap_11);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[8], owned[9], owned[10]);
    CHECK_RC(Rc);
    Rc = elmc_list_concat_map(out, owned[6], owned[8]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawScaleTick(ElmcValue **out, ElmcValue *layout, ElmcValue *spec) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[27] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const elmc_int_t plan_native_int_2 = ELMC_RECORD_GET_INDEX_INT(spec, ELMC_FIELD_YES_RENDER_TICKSPEC_MINUTE);
    const elmc_int_t plan_native_int_3 = elmc_fn_Yes_Render_angleFromMinute(plan_native_int_2);
    const elmc_int_t plan_native_int_4 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_5 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    const elmc_int_t plan_native_int_6 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_OUTERRADIUS);
    Rc = elmc_fn_Yes_Render_pointAt(&owned[0], plan_native_int_4, plan_native_int_5, plan_native_int_6, plan_native_int_3);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_8 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_9 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    const elmc_int_t plan_native_int_10 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_OUTERRADIUS);
    const elmc_int_t plan_native_int_11 = ELMC_RECORD_GET_INDEX_INT(spec, ELMC_FIELD_YES_RENDER_TICKSPEC_OUTEREXTRA);
    const elmc_int_t plan_native_int_12 = plan_native_int_10 + plan_native_int_11;
    Rc = elmc_fn_Yes_Render_pointAt(&owned[1], plan_native_int_8, plan_native_int_9, plan_native_int_12, plan_native_int_3);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(elmc_record_get_index(spec, ELMC_FIELD_YES_RENDER_TICKSPEC_LABEL));
    const bool plan_native_bool_15 = elmc_maybe_is_nothing(owned[2]);
    if (!plan_native_bool_15) goto elmc_plan_block_2;
    const elmc_int_t plan_native_int_17 = ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_PEBBLE_UI_POINT_X);
    const elmc_int_t plan_native_int_18 = ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_PEBBLE_UI_POINT_Y);
    const elmc_int_t plan_native_int_19 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_PEBBLE_UI_POINT_X);
    const elmc_int_t plan_native_int_20 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_PEBBLE_UI_POINT_Y);
    Rc = elmc_new_int(&owned[3], 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2786 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2786, ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[4], plan_ephemeral_box_2786, owned[3]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2786);
    ElmcValue *plan_ephemeral_box_2802 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2802, plan_native_int_20);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[5], plan_ephemeral_box_2802, owned[4]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2802);
    ElmcValue *plan_ephemeral_box_2818 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2818, plan_native_int_19);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[6], plan_ephemeral_box_2818, owned[5]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2818);
    ElmcValue *plan_ephemeral_box_2834 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2834, plan_native_int_18);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[7], plan_ephemeral_box_2834, owned[6]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2834);
    ElmcValue *plan_ephemeral_box_2850 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2850, plan_native_int_17);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[8], plan_ephemeral_box_2850, owned[7]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2850);
    ElmcValue *plan_ephemeral_box_2866 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2866, ELMC_RENDER_OP_LINE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[9], plan_ephemeral_box_2866, owned[8]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2866);
    ElmcValue *plan_list_items_2882[1] = { owned[9] };
    Rc = elmc_list_from_values(&owned[10], plan_list_items_2882, 1);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[11] = elmc_retain(elmc_maybe_just_payload(owned[2]));
    const elmc_int_t plan_native_int_32 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_33 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    const elmc_int_t plan_native_int_34 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_OUTERRADIUS);
    const elmc_int_t plan_native_int_36 = plan_native_int_34 + 14;
    Rc = elmc_fn_Yes_Render_pointAt(&owned[12], plan_native_int_32, plan_native_int_33, plan_native_int_36, plan_native_int_3);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_38 = ELMC_RECORD_GET_INDEX_INT(owned[12], ELMC_FIELD_PEBBLE_UI_POINT_X);
    const elmc_int_t plan_native_int_42 = ELMC_RECORD_GET_INDEX_INT(owned[12], ELMC_FIELD_PEBBLE_UI_POINT_Y);
    Rc = elmc_new_int(&owned[14], 18);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[15], 12);
    CHECK_RC(Rc);
    elmc_int_t rec_values_54_28[4] = { plan_native_int_38 - 9, plan_native_int_42 - 14, 18, 12 };
    Rc = elmc_record_new_values_ints(&owned[13], 4, rec_values_54_28);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_56 = ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_PEBBLE_UI_POINT_X);
    const elmc_int_t plan_native_int_57 = ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_PEBBLE_UI_POINT_Y);
    const elmc_int_t plan_native_int_58 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_PEBBLE_UI_POINT_X);
    const elmc_int_t plan_native_int_59 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_PEBBLE_UI_POINT_Y);
    Rc = elmc_new_int(&owned[16], 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_2898 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2898, ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[17], plan_ephemeral_box_2898, owned[16]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2898);
    ElmcValue *plan_ephemeral_box_2914 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2914, plan_native_int_59);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[18], plan_ephemeral_box_2914, owned[17]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2914);
    ElmcValue *plan_ephemeral_box_2930 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2930, plan_native_int_58);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[19], plan_ephemeral_box_2930, owned[18]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2930);
    ElmcValue *plan_ephemeral_box_2946 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2946, plan_native_int_57);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[20], plan_ephemeral_box_2946, owned[19]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2946);
    ElmcValue *plan_ephemeral_box_2962 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2962, plan_native_int_56);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[21], plan_ephemeral_box_2962, owned[20]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2962);
    ElmcValue *plan_ephemeral_box_2978 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_2978, ELMC_RENDER_OP_LINE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[22], plan_ephemeral_box_2978, owned[21]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_2978);
    Rc = elmc_new_int(&owned[23], ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_textAt(&owned[24], owned[23], owned[13], owned[11]);
    CHECK_RC(Rc);
    if (owned[24] == owned[23]) {
      owned[23] = NULL;
    }
    ElmcValue *plan_list_items_2994[2] = { owned[22], owned[24] };
    Rc = elmc_list_from_values(&owned[25], plan_list_items_2994, 2);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_15) {
      owned[26] = owned[10];
      owned[10] = NULL;
    } else {
      owned[26] = owned[25];
      owned[25] = NULL;
    }
    *out = owned[26];
    owned[26] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_coloredRadial(ElmcValue **out, ElmcValue *bounds, ElmcValue *fill, elmc_int_t start, elmc_int_t end) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[10] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[1] = elmc_retain(fill);
    ElmcValue *plan_ephemeral_box_3010 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3010, ELMC_CONTEXT_FILL_COLOR);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[0], plan_ephemeral_box_3010, owned[1]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3010);
    owned[3] = elmc_retain(fill);
    ElmcValue *plan_ephemeral_box_3026 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3026, ELMC_CONTEXT_STROKE_COLOR);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[2], plan_ephemeral_box_3026, owned[3]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3026);
    ElmcValue *plan_list_items_3042[2] = { owned[0], owned[2] };
    Rc = elmc_list_from_values(&owned[4], plan_list_items_3042, 2);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_12 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_X);
    const elmc_int_t plan_native_int_13 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_Y);
    const elmc_int_t plan_native_int_14 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_W);
    const elmc_int_t plan_native_int_15 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_H);
    Rc = elmc_render_cmd6_take(&owned[5], ELMC_RENDER_OP_FILL_RADIAL, plan_native_int_12, plan_native_int_13, plan_native_int_14, plan_native_int_15, start, end);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_3058[1] = { owned[5] };
    Rc = elmc_list_from_values(&owned[6], plan_list_items_3058, 1);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[7], owned[4], owned[6]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3074 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3074, ELMC_RENDER_OP_CONTEXT_GROUP);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[8], plan_ephemeral_box_3074, owned[7]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3074);
    ElmcValue *plan_list_items_3090[1] = { owned[8] };
    Rc = elmc_list_from_values(&owned[9], plan_list_items_3090, 1);
    CHECK_RC(Rc);
    *out = owned[9];
    owned[9] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_coloredRadialWedge(ElmcValue **out, ElmcValue *bounds, ElmcValue *color, elmc_int_t startAngle, elmc_int_t endAngle) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_4 = (endAngle < startAngle);
    if (!plan_native_bool_4) goto elmc_plan_block_2;
    Rc = elmc_fn_Yes_Render_coloredRadial(&owned[0], bounds, color, startAngle, 65536);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_coloredRadial(&owned[1], bounds, color, 0, endAngle);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[2], owned[0], owned[1]);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    Rc = elmc_fn_Yes_Render_coloredRadial(&owned[3], bounds, color, startAngle, endAngle);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_4) {
      owned[4] = owned[2];
      owned[2] = NULL;
    } else {
      owned[4] = owned[3];
      owned[3] = NULL;
    }
    *out = owned[4];
    owned[4] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawSunWindow(ElmcValue **out, ElmcValue *center, elmc_int_t radius, ElmcValue *bounds, elmc_int_t sunriseAngle, elmc_int_t sunsetAngle, ElmcValue *sunWindow) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[4] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(sunWindow, ELMC_FIELD_YES_RENDER_SUNWINDOW_MODE));
    switch (elmc_union_tag_as_int(owned[0])) {
      case ELMC_UNION_COMPANION_TYPES_SUNCYCLE: goto elmc_plan_block_2;
      case ELMC_UNION_COMPANION_TYPES_POLARDAY: goto elmc_plan_block_4;
      case ELMC_UNION_COMPANION_TYPES_POLARNIGHT: goto elmc_plan_block_6;
      default: goto elmc_plan_block_9;
    }
    elmc_plan_block_2:
    Rc = elmc_new_int(&owned[2], ELMC_COLOR_CHROME_YELLOW);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_coloredRadialWedge(&owned[1], bounds, owned[2], sunriseAngle, sunsetAngle);
    CHECK_RC(Rc);
    goto elmc_plan_block_9;
    elmc_plan_block_4:
    const elmc_int_t plan_native_int_14 = ELMC_RECORD_GET_INDEX_INT(center, ELMC_FIELD_PEBBLE_UI_POINT_X);
    const elmc_int_t plan_native_int_15 = ELMC_RECORD_GET_INDEX_INT(center, ELMC_FIELD_PEBBLE_UI_POINT_Y);
    Rc = elmc_render_cmd6_take(&owned[3], ELMC_RENDER_OP_FILL_CIRCLE, plan_native_int_14, plan_native_int_15, radius, ELMC_COLOR_CHROME_YELLOW, 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_3106[1] = { owned[3] };
    Rc = elmc_list_from_values(&owned[1], plan_list_items_3106, 1);
    CHECK_RC(Rc);
    goto elmc_plan_block_9;
    elmc_plan_block_6:
    owned[1] = elmc_list_nil();
    elmc_plan_block_9:
    *out = owned[1];
    owned[1] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawMoonGlyph(ElmcValue **out, ElmcValue *layout, ElmcValue *maybePhase) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[21] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(maybePhase);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    const elmc_int_t plan_native_int_9 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_10 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONY);
    ElmcValue *plan_ephemeral_box_3122 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3122, plan_native_int_9);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3138 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3138, plan_native_int_10);
    CHECK_RC(Rc);
    ElmcValue *rec_values_10_29[2] = { plan_ephemeral_box_3122, plan_ephemeral_box_3138 };
    Rc = elmc_record_new_values_take(&owned[0], 2, rec_values_10_29);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    owned[2] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    const elmc_int_t plan_native_int_14 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONPHASERADIUS);
    Rc = elmc_tuple2_ints(&owned[3], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3154 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3154, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[4], plan_ephemeral_box_3154, owned[3]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3154);
    ElmcValue *plan_ephemeral_box_3170 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3170, plan_native_int_14);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[5], plan_ephemeral_box_3170, owned[4]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3170);
    Rc = elmc_tuple2(&owned[6], owned[2], owned[5]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[7], owned[1], owned[6]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3186 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3186, ELMC_RENDER_OP_FILL_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[8], plan_ephemeral_box_3186, owned[7]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3186);
    owned[9] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    owned[10] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    const elmc_int_t plan_native_int_27 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONPHASERADIUS);
    Rc = elmc_tuple2_ints(&owned[11], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3202 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3202, ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[12], plan_ephemeral_box_3202, owned[11]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3202);
    ElmcValue *plan_ephemeral_box_3218 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3218, plan_native_int_27);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[13], plan_ephemeral_box_3218, owned[12]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3218);
    Rc = elmc_tuple2(&owned[14], owned[10], owned[13]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[15], owned[9], owned[14]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3234 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3234, ELMC_RENDER_OP_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[16], plan_ephemeral_box_3234, owned[15]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3234);
    ElmcValue *plan_list_items_3250[2] = { owned[8], owned[16] };
    Rc = elmc_list_from_values(&owned[17], plan_list_items_3250, 2);
    CHECK_RC(Rc);
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[18] = elmc_retain(elmc_maybe_just_payload(maybePhase));
    Rc = elmc_fn_Yes_Render_drawMoonPhase(&owned[19], layout, owned[18]);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[20] = owned[17];
      owned[17] = NULL;
    } else {
      owned[20] = owned[19];
      owned[19] = NULL;
    }
    *out = owned[20];
    owned[20] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static __attribute__((noinline, noclone)) RC elmc_fn_Yes_Render_drawMoonPhase(ElmcValue **out, ElmcValue *layout, ElmcValue *phaseE6) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[116] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const elmc_int_t plan_native_int_2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t plan_native_int_8 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONY);
    ElmcValue *plan_ephemeral_box_3266 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3266, plan_native_int_2);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3282 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3282, plan_native_int_8);
    CHECK_RC(Rc);
    ElmcValue *rec_values_8_30[2] = { plan_ephemeral_box_3266, plan_ephemeral_box_3282 };
    Rc = elmc_record_new_values_take(&owned[0], 2, rec_values_8_30);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[1], ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONPHASERADIUS));
    CHECK_RC(Rc);
    owned[2] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    const elmc_int_t plan_native_int_23 = (elmc_as_int(owned[2])) - (elmc_as_int(owned[1]));
    owned[3] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    const elmc_int_t plan_native_int_24 = (elmc_as_int(owned[3])) - (elmc_as_int(owned[1]));
    elmc_int_t rec_values_26_31[4] = { plan_native_int_23, plan_native_int_24, (elmc_as_int(owned[1])) * 2, (elmc_as_int(owned[1])) * 2 };
    Rc = elmc_record_new_values_ints(&owned[4], 4, rec_values_26_31);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[5], 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[6], 1000000);
    CHECK_RC(Rc);
    Rc = elmc_basics_clamp(&owned[7], owned[5], owned[6], phaseE6);
    CHECK_RC(Rc);
    if (owned[7] == owned[5]) {
      elmc_release(owned[7]);
      owned[5] = NULL;
    }
    if (owned[7] == owned[6]) {
      elmc_release(owned[7]);
      owned[6] = NULL;
    }
    Rc = elmc_basics_to_float(&owned[8], owned[7]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[9], 1000000);
    CHECK_RC(Rc);
    Rc = elmc_new_float(&owned[10], elmc_as_float(owned[8]) / elmc_as_float(owned[9]));
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[11], 1);
    CHECK_RC(Rc);
    Rc = elmc_basics_turns(&owned[12], owned[10]);
    CHECK_RC(Rc);
    Rc = elmc_basics_cos(&owned[13], owned[12]);
    CHECK_RC(Rc);
    Rc = elmc_new_float(&owned[14], elmc_as_float(owned[11]) - elmc_as_float(owned[13]));
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[15], 2);
    CHECK_RC(Rc);
    Rc = elmc_new_float(&owned[16], elmc_as_float(owned[14]) / elmc_as_float(owned[15]));
    CHECK_RC(Rc);
    const bool plan_native_bool_40 = (elmc_as_int(owned[7]) < 500000);
    Rc = elmc_basics_to_float(&owned[17], owned[1]);
    CHECK_RC(Rc);
    Rc = elmc_basics_turns(&owned[18], owned[10]);
    CHECK_RC(Rc);
    Rc = elmc_basics_cos(&owned[19], owned[18]);
    CHECK_RC(Rc);
    Rc = elmc_new_float(&owned[20], elmc_as_float(owned[17]) * elmc_as_float(owned[19]));
    CHECK_RC(Rc);
    Rc = elmc_basics_round(&owned[21], owned[20]);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[22], elmc_as_int(owned[7]) - 500000);
    CHECK_RC(Rc);
    Rc = elmc_basics_abs(&owned[23], owned[22]);
    CHECK_RC(Rc);
    const bool plan_native_bool_49 = (elmc_as_int(owned[23]) < 20000);
    if (plan_native_bool_49) goto elmc_plan_block_3;
    Rc = elmc_new_int(&owned[24], elmc_as_int(owned[7]) - 500000);
    CHECK_RC(Rc);
    Rc = elmc_basics_abs(&owned[25], owned[24]);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    const bool plan_native_bool_55 = (plan_native_bool_49) ? true : (elmc_as_int(owned[25]) == 20000);
    if (!plan_native_bool_55) goto elmc_plan_block_7;
    owned[26] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    owned[27] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    Rc = elmc_tuple2_ints(&owned[28], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3298 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3298, ELMC_COLOR_LIGHT_GRAY);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[29], plan_ephemeral_box_3298, owned[28]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3298);
    Rc = elmc_tuple2(&owned[30], owned[1], owned[29]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[31], owned[27], owned[30]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[32], owned[26], owned[31]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3314 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3314, ELMC_RENDER_OP_FILL_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[33], plan_ephemeral_box_3314, owned[32]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3314);
    owned[34] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    owned[35] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    Rc = elmc_tuple2_ints(&owned[36], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3330 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3330, ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[37], plan_ephemeral_box_3330, owned[36]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3330);
    Rc = elmc_tuple2(&owned[38], owned[1], owned[37]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[39], owned[35], owned[38]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[40], owned[34], owned[39]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3346 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3346, ELMC_RENDER_OP_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[41], plan_ephemeral_box_3346, owned[40]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3346);
    ElmcValue *plan_list_items_3362[2] = { owned[33], owned[41] };
    Rc = elmc_list_from_values(&owned[42], plan_list_items_3362, 2);
    CHECK_RC(Rc);
    goto elmc_plan_block_8;
    elmc_plan_block_7:
    const bool plan_native_bool_84 = (elmc_as_int(owned[7]) < 20000);
    const bool plan_native_bool_88 = (plan_native_bool_84) ? true : (elmc_as_int(owned[7]) == 20000);
    if (!plan_native_bool_88) goto elmc_plan_block_16;
    Rc = elmc_new_bool(&owned[43], true);
    CHECK_RC(Rc);
    goto elmc_plan_block_17;
    elmc_plan_block_16:
    const bool plan_native_bool_91 = (elmc_as_int(owned[7]) > 980000);
    if (plan_native_bool_91) {
      ElmcValue *plan_ephemeral_box_3378 = NULL;
      Rc = elmc_new_bool(&plan_ephemeral_box_3378, 1);
      CHECK_RC(Rc);
      owned[44] = elmc_retain(plan_ephemeral_box_3378);
      elmc_release(plan_ephemeral_box_3378);
    } else {
      ElmcValue *plan_ephemeral_box_3394 = NULL;
      Rc = elmc_new_bool(&plan_ephemeral_box_3394, (elmc_as_int(owned[7]) == 980000));
      CHECK_RC(Rc);
      owned[44] = elmc_retain(plan_ephemeral_box_3394);
      elmc_release(plan_ephemeral_box_3394);
    }
    elmc_plan_block_17:
    if (plan_native_bool_88) {
      owned[45] = owned[43];
      owned[43] = NULL;
    } else {
      owned[45] = owned[44];
      owned[44] = NULL;
    }
    if (!elmc_as_bool(owned[45])) goto elmc_plan_block_26;
    owned[46] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    owned[47] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    Rc = elmc_tuple2_ints(&owned[48], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3410 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3410, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[49], plan_ephemeral_box_3410, owned[48]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3410);
    Rc = elmc_tuple2(&owned[50], owned[1], owned[49]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[51], owned[47], owned[50]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[52], owned[46], owned[51]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3426 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3426, ELMC_RENDER_OP_FILL_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[53], plan_ephemeral_box_3426, owned[52]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3426);
    owned[54] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    owned[55] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    Rc = elmc_tuple2_ints(&owned[56], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3442 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3442, ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[57], plan_ephemeral_box_3442, owned[56]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3442);
    Rc = elmc_tuple2(&owned[58], owned[1], owned[57]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[59], owned[55], owned[58]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[60], owned[54], owned[59]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3458 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3458, ELMC_RENDER_OP_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[61], plan_ephemeral_box_3458, owned[60]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3458);
    ElmcValue *plan_list_items_3474[2] = { owned[53], owned[61] };
    Rc = elmc_list_from_values(&owned[62], plan_list_items_3474, 2);
    CHECK_RC(Rc);
    goto elmc_plan_block_27;
    elmc_plan_block_26:
    if (!plan_native_bool_40) goto elmc_plan_block_30;
    Rc = elmc_new_int(&owned[63], ELMC_COLOR_LIGHT_GRAY);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_coloredRadial(&owned[64], owned[4], owned[63], 0, 32768);
    CHECK_RC(Rc);
    goto elmc_plan_block_31;
    elmc_plan_block_30:
    Rc = elmc_new_int(&owned[65], ELMC_COLOR_LIGHT_GRAY);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_coloredRadial(&owned[66], owned[4], owned[65], 32768, 65536);
    CHECK_RC(Rc);
    elmc_plan_block_31:
    if (plan_native_bool_40) {
      owned[67] = owned[64];
      owned[64] = NULL;
    } else {
      owned[67] = owned[66];
      owned[66] = NULL;
    }
    Rc = elmc_basics_abs(&owned[68], owned[21]);
    CHECK_RC(Rc);
    const bool plan_native_bool_138 = (elmc_as_int(owned[68]) < ((1 >= elmc_int_idiv((elmc_as_int(owned[1])), 8)) ? 1 : elmc_int_idiv((elmc_as_int(owned[1])), 8)));
    if (!plan_native_bool_138) goto elmc_plan_block_35;
    owned[69] = elmc_list_nil();
    goto elmc_plan_block_36;
    elmc_plan_block_35:
    Rc = elmc_new_float(&owned[70], 0.5);
    CHECK_RC(Rc);
    const bool plan_native_bool_141 = (elmc_as_int(owned[16]) < elmc_as_int(owned[70]));
    if (!plan_native_bool_141) goto elmc_plan_block_39;
    owned[71] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    const elmc_int_t plan_native_int_144 = elmc_as_int(owned[71]) + elmc_as_int(owned[21]);
    owned[72] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    Rc = elmc_tuple2_ints(&owned[73], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3490 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3490, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[74], plan_ephemeral_box_3490, owned[73]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3490);
    Rc = elmc_tuple2(&owned[75], owned[1], owned[74]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[76], owned[72], owned[75]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3506 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3506, plan_native_int_144);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[77], plan_ephemeral_box_3506, owned[76]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3506);
    ElmcValue *plan_ephemeral_box_3522 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3522, ELMC_RENDER_OP_FILL_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[78], plan_ephemeral_box_3522, owned[77]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3522);
    ElmcValue *plan_list_items_3538[1] = { owned[78] };
    Rc = elmc_list_from_values(&owned[79], plan_list_items_3538, 1);
    CHECK_RC(Rc);
    goto elmc_plan_block_40;
    elmc_plan_block_39:
    owned[80] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    const elmc_int_t plan_native_int_159 = elmc_as_int(owned[80]) + elmc_as_int(owned[21]);
    owned[81] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    Rc = elmc_tuple2_ints(&owned[82], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3554 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3554, ELMC_COLOR_LIGHT_GRAY);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[83], plan_ephemeral_box_3554, owned[82]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3554);
    Rc = elmc_tuple2(&owned[84], owned[1], owned[83]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[85], owned[81], owned[84]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3570 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3570, plan_native_int_159);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[86], plan_ephemeral_box_3570, owned[85]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3570);
    ElmcValue *plan_ephemeral_box_3586 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3586, ELMC_RENDER_OP_FILL_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[87], plan_ephemeral_box_3586, owned[86]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3586);
    ElmcValue *plan_list_items_3602[1] = { owned[87] };
    Rc = elmc_list_from_values(&owned[88], plan_list_items_3602, 1);
    CHECK_RC(Rc);
    elmc_plan_block_40:
    if (plan_native_bool_141) {
      owned[89] = owned[79];
      owned[79] = NULL;
    } else {
      owned[89] = owned[88];
      owned[88] = NULL;
    }
    elmc_plan_block_36:
    if (plan_native_bool_138) {
      owned[90] = owned[69];
      owned[69] = NULL;
    } else {
      owned[90] = owned[89];
      owned[89] = NULL;
    }
    owned[91] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    owned[92] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    Rc = elmc_tuple2_ints(&owned[93], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3618 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3618, ELMC_COLOR_BLACK);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[94], plan_ephemeral_box_3618, owned[93]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3618);
    Rc = elmc_tuple2(&owned[95], owned[1], owned[94]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[96], owned[92], owned[95]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[97], owned[91], owned[96]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3634 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3634, ELMC_RENDER_OP_FILL_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[98], plan_ephemeral_box_3634, owned[97]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3634);
    ElmcValue *plan_list_items_3650[1] = { owned[98] };
    Rc = elmc_list_from_values(&owned[99], plan_list_items_3650, 1);
    CHECK_RC(Rc);
    owned[100] = elmc_retain(elmc_record_get_index(owned[0], 0 /* x */));
    owned[101] = elmc_retain(elmc_record_get_index(owned[0], 1 /* y */));
    Rc = elmc_tuple2_ints(&owned[102], 0, 0);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3666 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3666, ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[103], plan_ephemeral_box_3666, owned[102]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3666);
    Rc = elmc_tuple2(&owned[104], owned[1], owned[103]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[105], owned[101], owned[104]);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[106], owned[100], owned[105]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3682 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3682, ELMC_RENDER_OP_CIRCLE);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[107], plan_ephemeral_box_3682, owned[106]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3682);
    ElmcValue *plan_list_items_3698[1] = { owned[107] };
    Rc = elmc_list_from_values(&owned[108], plan_list_items_3698, 1);
    CHECK_RC(Rc);
    owned[110] = owned[90];
    owned[90] = NULL;
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[109], owned[110], owned[108]);
    CHECK_RC(Rc);
    owned[112] = owned[67];
    owned[67] = NULL;
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[111], owned[112], owned[109]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[113], owned[99], owned[111]);
    CHECK_RC(Rc);
    elmc_plan_block_27:
    if (elmc_as_bool(owned[45])) {
      owned[114] = owned[62];
      owned[62] = NULL;
    } else {
      owned[114] = owned[113];
      owned[113] = NULL;
    }
    elmc_plan_block_8:
    if (plan_native_bool_55) {
      owned[115] = owned[42];
      owned[42] = NULL;
    } else {
      owned[115] = owned[114];
      owned[114] = NULL;
    }
    *out = owned[115];
    owned[115] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawCorners(ElmcValue **out, ElmcValue *layout, ElmcValue *slots) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[10] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(slots, ELMC_FIELD_YES_RENDER_CORNERSLOTS_TOPLEFT));
    Rc = elmc_fn_Yes_Render_drawTopLeft(&owned[1], layout, owned[0]);
    CHECK_RC(Rc);
    owned[2] = elmc_retain(elmc_record_get_index(slots, ELMC_FIELD_YES_RENDER_CORNERSLOTS_DATE));
    Rc = elmc_fn_Yes_Render_drawDate(&owned[3], layout, owned[2]);
    CHECK_RC(Rc);
    owned[4] = elmc_retain(elmc_record_get_index(slots, ELMC_FIELD_YES_RENDER_CORNERSLOTS_WEATHER));
    Rc = elmc_fn_Yes_Render_drawWeatherCorner(&owned[5], layout, owned[4]);
    CHECK_RC(Rc);
    owned[6] = elmc_retain(elmc_record_get_index(slots, ELMC_FIELD_YES_RENDER_CORNERSLOTS_BOTTOMRIGHT));
    Rc = elmc_fn_Yes_Render_drawBottomRight(&owned[7], layout, owned[6]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[8], owned[5], owned[7]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(&owned[9], owned[3], owned[8]);
    CHECK_RC(Rc);
    /* elm/core: List.append */
    Rc = elmc_list_append(out, owned[1], owned[9]);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawTopLeft(ElmcValue **out, ElmcValue *layout, ElmcValue *slot) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[9] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    owned[1] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_TOPLEFTTITLE));
    owned[2] = elmc_retain(elmc_record_get_index(slot, 1 /* value */));
    Rc = elmc_fn_Yes_Render_textAt(&owned[3], owned[0], owned[1], owned[2]);
    CHECK_RC(Rc);
    if (owned[3] == owned[0]) {
      owned[0] = NULL;
    }
    if (owned[3] == owned[1]) {
      owned[1] = NULL;
    }
    if (owned[3] == owned[2]) {
      owned[2] = NULL;
    }
    Rc = elmc_new_int(&owned[4], ELMC_COLOR_DARK_GRAY);
    CHECK_RC(Rc);
    owned[5] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_TOPLEFTLABEL));
    owned[6] = elmc_retain(elmc_record_get_index(slot, 0 /* caption */));
    Rc = elmc_fn_Yes_Render_textAt(&owned[7], owned[4], owned[5], owned[6]);
    CHECK_RC(Rc);
    if (owned[7] == owned[4]) {
      owned[4] = NULL;
    }
    if (owned[7] == owned[5]) {
      owned[5] = NULL;
    }
    if (owned[7] == owned[6]) {
      owned[6] = NULL;
    }
    ElmcValue *plan_list_items_3714[2] = { owned[3], owned[7] };
    Rc = elmc_list_from_values(&owned[8], plan_list_items_3714, 2);
    CHECK_RC(Rc);
    *out = owned[8];
    owned[8] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawDate(ElmcValue **out, ElmcValue *layout, ElmcValue *maybeDate) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[7] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(maybeDate);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    owned[0] = elmc_list_nil();
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[1] = elmc_retain(elmc_maybe_just_payload(maybeDate));
    Rc = elmc_new_int(&owned[2], ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    owned[3] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_TOPRIGHTDATE));
    Rc = elmc_fn_Yes_Render_textAt(&owned[4], owned[2], owned[3], owned[1]);
    CHECK_RC(Rc);
    if (owned[4] == owned[2]) {
      owned[2] = NULL;
    }
    if (owned[4] == owned[3]) {
      owned[3] = NULL;
    }
    ElmcValue *plan_list_items_3730[1] = { owned[4] };
    Rc = elmc_list_from_values(&owned[5], plan_list_items_3730, 1);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[6] = owned[0];
      owned[0] = NULL;
    } else {
      owned[6] = owned[5];
      owned[5] = NULL;
    }
    *out = owned[6];
    owned[6] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawWeatherCorner(ElmcValue **out, ElmcValue *layout, ElmcValue *maybeLabel) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[7] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    const bool plan_native_bool_2 = elmc_maybe_is_nothing(maybeLabel);
    if (!plan_native_bool_2) goto elmc_plan_block_2;
    owned[0] = elmc_list_nil();
    goto elmc_plan_block_3;
    elmc_plan_block_2:
    owned[1] = elmc_retain(elmc_maybe_just_payload(maybeLabel));
    Rc = elmc_new_int(&owned[2], ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    owned[3] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMLEFTWEATHER));
    Rc = elmc_fn_Yes_Render_textAt(&owned[4], owned[2], owned[3], owned[1]);
    CHECK_RC(Rc);
    if (owned[4] == owned[2]) {
      owned[2] = NULL;
    }
    if (owned[4] == owned[3]) {
      owned[3] = NULL;
    }
    ElmcValue *plan_list_items_3746[1] = { owned[4] };
    Rc = elmc_list_from_values(&owned[5], plan_list_items_3746, 1);
    CHECK_RC(Rc);
    elmc_plan_block_3:
    if (plan_native_bool_2) {
      owned[6] = owned[0];
      owned[0] = NULL;
    } else {
      owned[6] = owned[5];
      owned[5] = NULL;
    }
    *out = owned[6];
    owned[6] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawBottomRight(ElmcValue **out, ElmcValue *layout, ElmcValue *slot) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[21] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    switch (elmc_union_tag_as_int(slot)) {
      case ELMC_UNION_YES_RENDER_ALTITUDESLOT: goto elmc_plan_block_2;
      case ELMC_UNION_YES_RENDER_SIMPLELINE: goto elmc_plan_block_4;
      case ELMC_UNION_YES_RENDER_COUNTDOWNSLOT: goto elmc_plan_block_6;
      default: goto elmc_plan_block_9;
    }
    elmc_plan_block_2:
    owned[1] = elmc_tuple_second_borrow(slot);
    owned[2] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT));
    owned[3] = elmc_retain(elmc_record_get_index(owned[2], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_VECTOR));
    owned[4] = elmc_retain(elmc_record_get_index(owned[3], 0 /* x */));
    owned[5] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT));
    owned[6] = elmc_retain(elmc_record_get_index(owned[5], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_VECTOR));
    owned[7] = elmc_retain(elmc_record_get_index(owned[6], 1 /* y */));
    Rc = elmc_render_cmd6_take(&owned[8], ELMC_RENDER_OP_VECTOR_AT, 1, elmc_as_int(owned[4]), elmc_as_int(owned[7]), 0, 0, 0);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[9], ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    owned[10] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT));
    owned[11] = elmc_retain(elmc_record_get_index(owned[10], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_SINGLELINE));
    Rc = elmc_fn_Yes_Render_textAt(&owned[12], owned[9], owned[11], owned[1]);
    CHECK_RC(Rc);
    if (owned[12] == owned[9]) {
      owned[9] = NULL;
    }
    if (owned[12] == owned[11]) {
      owned[11] = NULL;
    }
    ElmcValue *plan_list_items_3762[2] = { owned[8], owned[12] };
    Rc = elmc_list_from_values(&owned[0], plan_list_items_3762, 2);
    CHECK_RC(Rc);
    goto elmc_plan_block_9;
    elmc_plan_block_4:
    owned[13] = elmc_tuple_second_borrow(slot);
    Rc = elmc_new_int(&owned[14], ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    owned[15] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT));
    owned[16] = elmc_retain(elmc_record_get_index(owned[15], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_SINGLELINE));
    Rc = elmc_fn_Yes_Render_textAt(&owned[17], owned[14], owned[16], owned[13]);
    CHECK_RC(Rc);
    if (owned[17] == owned[14]) {
      owned[14] = NULL;
    }
    if (owned[17] == owned[16]) {
      owned[16] = NULL;
    }
    ElmcValue *plan_list_items_3778[1] = { owned[17] };
    Rc = elmc_list_from_values(&owned[0], plan_list_items_3778, 1);
    CHECK_RC(Rc);
    goto elmc_plan_block_9;
    elmc_plan_block_6:
    owned[18] = elmc_tuple_second_borrow(slot);
    owned[19] = elmc_tuple_first_borrow(owned[18]);
    owned[20] = elmc_tuple_second_borrow(owned[18]);
    Rc = elmc_fn_Yes_Render_drawBottomRightCountdown(&owned[0], layout, owned[19], owned[20]);
    CHECK_RC(Rc);
    elmc_plan_block_9:
    *out = owned[0];
    owned[0] = NULL;
  CATCH_END
  owned[13] = NULL;
  owned[18] = NULL;
  owned[19] = NULL;
  owned[1] = NULL;
  owned[20] = NULL;
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_drawBottomRightCountdown(ElmcValue **out, ElmcValue *layout, ElmcValue *label, ElmcValue *timeLine) {
  /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[8] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[0] = elmc_retain(elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT));
    const elmc_int_t plan_native_int_4 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_COUNTDOWNLABELH);
    const elmc_int_t plan_native_int_5 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_COUNTDOWNTIMEH);
    const elmc_int_t plan_native_int_6 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_BOTTOM);
    const elmc_int_t plan_native_int_8 = (plan_native_int_6 - plan_native_int_4) - plan_native_int_5;
    const elmc_int_t plan_native_int_17 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_X);
    const elmc_int_t plan_native_int_19 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_TEXTW);
    const elmc_int_t plan_native_int_20 = plan_native_int_4;
    elmc_int_t rec_values_20_32[4] = { plan_native_int_17, plan_native_int_8 - 2, plan_native_int_19, plan_native_int_20 };
    Rc = elmc_record_new_values_ints(&owned[1], 4, rec_values_20_32);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_31 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_X);
    const elmc_int_t plan_native_int_33 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_TEXTW);
    const elmc_int_t plan_native_int_34 = plan_native_int_5;
    elmc_int_t rec_values_34_33[4] = { plan_native_int_31, (plan_native_int_8 + plan_native_int_4) - 1, plan_native_int_33, plan_native_int_34 };
    Rc = elmc_record_new_values_ints(&owned[2], 4, rec_values_34_33);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[3], ELMC_COLOR_LIGHT_GRAY);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_textAt(&owned[4], owned[3], owned[1], label);
    CHECK_RC(Rc);
    if (owned[4] == owned[3]) {
      owned[3] = NULL;
    }
    Rc = elmc_new_int(&owned[5], ELMC_COLOR_WHITE);
    CHECK_RC(Rc);
    Rc = elmc_fn_Yes_Render_textAt(&owned[6], owned[5], owned[2], timeLine);
    CHECK_RC(Rc);
    if (owned[6] == owned[5]) {
      owned[5] = NULL;
    }
    ElmcValue *plan_list_items_3794[2] = { owned[4], owned[6] };
    Rc = elmc_list_from_values(&owned[7], plan_list_items_3794, 2);
    CHECK_RC(Rc);
    *out = owned[7];
    owned[7] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_defaultSunWindow(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(&owned[0], 360);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[1], 1);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3810 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3810, 1080);
    CHECK_RC(Rc);
    ElmcValue *rec_values_9_34[3] = { owned[0], plan_ephemeral_box_3810, owned[1] };
    Rc = elmc_record_new_values_take(out, 3, rec_values_9_34);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;
    owned[1] = NULL;
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_textAt(ElmcValue **out, ElmcValue *color, ElmcValue *bounds, ElmcValue *value) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    owned[1] = elmc_retain(color);
    ElmcValue *plan_ephemeral_box_3826 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3826, ELMC_CONTEXT_TEXT_COLOR);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[0], plan_ephemeral_box_3826, owned[1]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3826);
    ElmcValue *plan_list_items_3842[1] = { owned[0] };
    Rc = elmc_list_from_values(&owned[2], plan_list_items_3842, 1);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_9 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_X);
    const elmc_int_t plan_native_int_10 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_Y);
    const elmc_int_t plan_native_int_11 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_W);
    const elmc_int_t plan_native_int_12 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_H);
    Rc = elmc_render_text_cmd_take(&owned[3], ELMC_RENDER_OP_TEXT, 1, plan_native_int_9, plan_native_int_10, plan_native_int_11, plan_native_int_12, (ELMC_TEXT_ALIGN_CENTER + (ELMC_TEXT_OVERFLOW_WORD_WRAP * (1 << ELMC_TEXT_OVERFLOW_SHIFT))), value);
    CHECK_RC(Rc);
    ElmcValue *plan_list_items_3858[1] = { owned[3] };
    Rc = elmc_list_from_values(&owned[4], plan_list_items_3858, 1);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(&owned[5], owned[2], owned[4]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3874 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3874, ELMC_RENDER_OP_CONTEXT_GROUP);
    CHECK_RC(Rc);
    Rc = elmc_tuple2(out, plan_ephemeral_box_3874, owned[5]);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3874);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Yes_Render_pointAt(ElmcValue **out, elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[15] = {0};
  CATCH_BEGIN
    /* plan block 0 */
    ElmcValue *plan_ephemeral_box_3906 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3906, angle);
    CHECK_RC(Rc);
    Rc = elmc_basics_to_float(&owned[0], plan_ephemeral_box_3906);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3906);
    Rc = elmc_new_int(&owned[1], 2);
    CHECK_RC(Rc);
    Rc = elmc_new_float(&owned[2], elmc_as_float(owned[0]) * elmc_as_float(owned[1]));
    CHECK_RC(Rc);
    Rc = elmc_new_float(&owned[3], 3.141592653589793);
    CHECK_RC(Rc);
    Rc = elmc_new_float(&owned[4], elmc_as_float(owned[2]) * elmc_as_float(owned[3]));
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[5], 65536);
    CHECK_RC(Rc);
    Rc = elmc_new_float(&owned[6], elmc_as_float(owned[4]) / elmc_as_float(owned[5]));
    CHECK_RC(Rc);
    Rc = elmc_basics_sin(&owned[7], owned[6]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3938 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3938, radius);
    CHECK_RC(Rc);
    Rc = elmc_basics_to_float(&owned[8], plan_ephemeral_box_3938);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3938);
    Rc = elmc_new_float(&owned[9], elmc_as_float(owned[7]) * elmc_as_float(owned[8]));
    CHECK_RC(Rc);
    Rc = elmc_basics_round(&owned[10], owned[9]);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_23 = cx + elmc_as_int(owned[10]);
    Rc = elmc_basics_cos(&owned[11], owned[6]);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_3970 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3970, radius);
    CHECK_RC(Rc);
    Rc = elmc_basics_to_float(&owned[12], plan_ephemeral_box_3970);
    CHECK_RC(Rc);
    elmc_release(plan_ephemeral_box_3970);
    Rc = elmc_new_float(&owned[13], elmc_as_float(owned[11]) * elmc_as_float(owned[12]));
    CHECK_RC(Rc);
    Rc = elmc_basics_round(&owned[14], owned[13]);
    CHECK_RC(Rc);
    const elmc_int_t plan_native_int_24 = cy - (elmc_as_int(owned[14]));
    ElmcValue *plan_ephemeral_box_3986 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_3986, plan_native_int_23);
    CHECK_RC(Rc);
    ElmcValue *plan_ephemeral_box_4002 = NULL;
    Rc = elmc_new_int(&plan_ephemeral_box_4002, plan_native_int_24);
    CHECK_RC(Rc);
    ElmcValue *rec_values_25_35[2] = { plan_ephemeral_box_3986, plan_ephemeral_box_4002 };
    Rc = elmc_record_new_values_take(out, 2, rec_values_25_35);
    CHECK_RC(Rc);
  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static elmc_int_t elmc_fn_Yes_Render_angleFromMinute(elmc_int_t minute) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  /* plan block 0 */
  return elmc_int_mod_by(65536, (elmc_int_idiv((minute - 720) * 65536, 1440)));
}

static RC elmc_fn_Companion_Internal_watchToPhoneTag_native(ElmcValue **out, elmc_int_t message) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    elmc_int_t case_int_1;
    case_int_1 = 0;
    switch (message) {
      case ELMC_UNION_COMPANION_TYPES_REQUESTUPDATE: {
        case_int_1 = 2;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_REQUESTSUNDATA: {
        case_int_1 = 3;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER: {
        case_int_1 = 4;
        break;
      }
    }
    Rc = elmc_new_int(out, case_int_1);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}
static RC elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue **out, ElmcValue *message) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  return elmc_fn_Companion_Internal_watchToPhoneTag_native(out, (message && (message)->tag == ELMC_TAG_INT ? elmc_as_int(message) : (message && (message)->tag == ELMC_TAG_TUPLE2 && (message)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(message)->payload)->first) : -1)));
}

static RC elmc_fn_Companion_Internal_watchToPhoneValue_native(ElmcValue **out, elmc_int_t message) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    elmc_int_t case_int_1;
    case_int_1 = 0;
    switch (message) {
      case ELMC_UNION_COMPANION_TYPES_REQUESTUPDATE: {
        case_int_1 = 0;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_REQUESTSUNDATA: {
        case_int_1 = 0;
        break;
      }
      case ELMC_UNION_COMPANION_TYPES_REQUESTWEATHER: {
        case_int_1 = 0;
        break;
      }
    }
    Rc = elmc_new_int(out, case_int_1);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}
static RC elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue **out, ElmcValue *message) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  return elmc_fn_Companion_Internal_watchToPhoneValue_native(out, (message && (message)->tag == ELMC_TAG_INT ? elmc_as_int(message) : (message && (message)->tag == ELMC_TAG_TUPLE2 && (message)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(message)->payload)->first) : -1)));
}

static RC elmc_fn_Pebble_Ui_Color_black(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(out, 192);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}

static RC elmc_fn_Pebble_Ui_Color_oxfordBlue(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(out, 193);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}

static RC elmc_fn_Pebble_Ui_Color_blueMoon(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(out, 199);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}

static RC elmc_fn_Pebble_Ui_Color_darkGray(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(out, 213);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}

static RC elmc_fn_Pebble_Ui_Color_lightGray(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(out, 234);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}

static RC elmc_fn_Pebble_Ui_Color_white(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_int(out, 255);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}

static RC elmc_fn_Basics_pi(ElmcValue **out) {
  /* Ownership policy: borrow_arg, borrow_result, direct_call_abi */
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    /* plan block 0 */
    Rc = elmc_new_float(out, 3.141592653589793);
    CHECK_RC(Rc);
  CATCH_END
  return Rc;
}

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_drawDial_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_drawScaleTick_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_coloredRadial_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_coloredRadial_commands_append_native(ElmcValue * const bounds, const elmc_int_t fill, const elmc_int_t start, const elmc_int_t end, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_coloredRadialWedge_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_coloredRadialWedge_commands_append_native(ElmcValue * const bounds, const elmc_int_t color, const elmc_int_t startAngle, const elmc_int_t endAngle, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_drawMoonPhase_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_drawMoonPhase_commands_append_native(ElmcValue * const layout, const elmc_int_t phaseE6, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_drawBottomRight_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_drawBottomRightCountdown_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_drawBottomRightCountdown_commands_append_native(ElmcValue * const layout, const char * const label, const char * const timeLine, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_textAt_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Yes_Render_textAt_commands_append_native(const elmc_int_t color, ElmcValue * const bounds, const char * const value, ElmcSceneWriter * const writer);

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[13] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    owned[0] = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_LAYOUT);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CLEAR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    ElmcValue *direct_call_args_3[2] = { owned[0], model };
    Rc = elmc_fn_Yes_Render_drawDial_commands_append(direct_call_args_3, 2, writer);
    CHECK_RC(Rc);

    Rc = elmc_fn_Main_showCorners(&owned[1], model);
    CHECK_RC(Rc);

    const bool native_b_6 = (bool)elmc_as_bool(owned[1]);

    if (native_b_6) {

      Rc = elmc_fn_Main_cornerSlots(&owned[2], model);
      CHECK_RC(Rc);

      owned[3] = elmc_record_get_index(owned[2], ELMC_FIELD_YES_RENDER_CORNERSLOTS_TOPLEFT);

      owned[4] = elmc_record_get_index(owned[0], ELMC_FIELD_YES_LAYOUT_LAYOUT_TOPLEFTTITLE);

      owned[5] = elmc_record_get(owned[3], "value");

      ElmcValue *native_string_9_src = owned[5];
      const char *native_string_9 =
      (native_string_9_src && native_string_9_src->tag == ELMC_TAG_STRING && native_string_9_src->payload)
      ? (const char *)native_string_9_src->payload
      : "";

      Rc = elmc_fn_Yes_Render_textAt_commands_append_native(ELMC_COLOR_WHITE, owned[4], native_string_9, writer);
      CHECK_RC(Rc);

      owned[6] = elmc_record_get_index(owned[0], ELMC_FIELD_YES_LAYOUT_LAYOUT_TOPLEFTLABEL);

      owned[7] = elmc_record_get(owned[3], "caption");

      ElmcValue *native_string_11_src = owned[7];
      const char *native_string_11 =
      (native_string_11_src && native_string_11_src->tag == ELMC_TAG_STRING && native_string_11_src->payload)
      ? (const char *)native_string_11_src->payload
      : "";

      Rc = elmc_fn_Yes_Render_textAt_commands_append_native(ELMC_COLOR_DARK_GRAY, owned[6], native_string_11, writer);
      CHECK_RC(Rc);

      owned[8] = elmc_record_get_index(owned[2], ELMC_FIELD_YES_RENDER_CORNERSLOTS_DATE);

      if (elmc_maybe_is_just(owned[8])) {

        owned[9] = elmc_record_get_index(owned[0], ELMC_FIELD_YES_LAYOUT_LAYOUT_TOPRIGHTDATE);

        ElmcValue *native_string_13_src = elmc_maybe_or_tuple_just_payload_borrow(owned[8]);
        const char *native_string_13 =
        (native_string_13_src && native_string_13_src->tag == ELMC_TAG_STRING && native_string_13_src->payload)
        ? (const char *)native_string_13_src->payload
        : "";

        Rc = elmc_fn_Yes_Render_textAt_commands_append_native(ELMC_COLOR_WHITE, owned[9], native_string_13, writer);
        CHECK_RC(Rc);

      }

      owned[10] = elmc_record_get_index(owned[2], ELMC_FIELD_YES_RENDER_CORNERSLOTS_WEATHER);

      if (elmc_maybe_is_just(owned[10])) {

        owned[11] = elmc_record_get_index(owned[0], ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMLEFTWEATHER);

        ElmcValue *native_string_15_src = elmc_maybe_or_tuple_just_payload_borrow(owned[10]);
        const char *native_string_15 =
        (native_string_15_src && native_string_15_src->tag == ELMC_TAG_STRING && native_string_15_src->payload)
        ? (const char *)native_string_15_src->payload
        : "";

        Rc = elmc_fn_Yes_Render_textAt_commands_append_native(ELMC_COLOR_WHITE, owned[11], native_string_15, writer);
        CHECK_RC(Rc);

      }

      owned[12] = elmc_record_get_index(owned[2], ELMC_FIELD_YES_RENDER_CORNERSLOTS_BOTTOMRIGHT);

      ElmcValue *direct_call_args_17[2] = { owned[0], owned[12] };
      Rc = elmc_fn_Yes_Render_drawBottomRight_commands_append(direct_call_args_17, 2, writer);
      CHECK_RC(Rc);

    }

  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}

static RC elmc_fn_Yes_Render_drawDial_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *layout = (argc > 0) ? args[0] : NULL;
  ElmcValue *display = (argc > 1) ? args[1] : NULL;

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[15] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    const elmc_int_t direct_hoisted_rec_1 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t direct_hoisted_rec_2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    const elmc_int_t direct_hoisted_rec_3 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_OUTERRADIUS);
    const elmc_int_t direct_hoisted_int_1 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_INNERRADIUS);
    const elmc_int_t direct_hoisted_int_2 = direct_hoisted_rec_3;
    /* elm/core: Maybe.withDefault */

    Rc = elmc_fn_Yes_Render_defaultSunWindow(&owned[0]);
    CHECK_RC(Rc);

    owned[1] = elmc_maybe_with_default(owned[0], ELMC_RECORD_GET_INDEX(display, ELMC_FIELD_MAIN_MODEL_SUN));

    if (owned[1] == owned[0]) {
      elmc_release(owned[1]);
      owned[0] = NULL;
    }

    owned[3] = elmc_record_get_index(display, ELMC_FIELD_MAIN_MODEL_SUN);

    owned[4] = elmc_maybe_nothing();

    const bool native_cmp_6 = elmc_value_equal(owned[3], owned[4]);

    // inlined Yes.Render.angleFromMinute

    const elmc_int_t direct_native_let_sunriseAngle_7 = elmc_angle_from_minute(ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_YES_RENDER_SUNWINDOW_SUNRISEMIN));
    // inlined Yes.Render.angleFromMinute

    const elmc_int_t direct_native_let_sunsetAngle_8 = elmc_angle_from_minute(ELMC_RECORD_GET_INDEX_INT(owned[1], ELMC_FIELD_YES_RENDER_SUNWINDOW_SUNSETMIN));

    Rc = elmc_fn_Yes_Layout_centerSquare(&owned[5], layout, direct_hoisted_int_2);
    CHECK_RC(Rc);

    Rc = elmc_fn_Yes_Layout_centerSquare(&owned[6], layout, direct_hoisted_int_1);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
    scene_cmd.p0 = direct_hoisted_rec_1;
    scene_cmd.p1 = direct_hoisted_rec_2;
    scene_cmd.p2 = direct_hoisted_int_2;
    scene_cmd.p3 = ELMC_COLOR_OXFORD_BLUE;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    if (!(native_cmp_6)) {

      Rc = elmc_new_int(&owned[7], ELMC_COLOR_BLUE_MOON);
      CHECK_RC(Rc);

      const elmc_int_t native_i_12 = elmc_as_int(owned[7]);

      Rc = elmc_fn_Yes_Render_coloredRadialWedge_commands_append_native(owned[5], native_i_12, direct_native_let_sunriseAngle_7, direct_native_let_sunsetAngle_8, writer);
      CHECK_RC(Rc);

    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
    scene_cmd.p0 = direct_hoisted_rec_1;
    scene_cmd.p1 = direct_hoisted_rec_2;
    scene_cmd.p2 = direct_hoisted_int_1;
    scene_cmd.p3 = ELMC_COLOR_BLACK;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    owned[8] = elmc_record_get_index(owned[1], ELMC_FIELD_YES_RENDER_SUNWINDOW_MODE);

    if (elmc_union_tag_matches(owned[8], ELMC_UNION_COMPANION_TYPES_POLARNIGHT)) {

    }
    else if (elmc_union_tag_matches(owned[8], ELMC_UNION_COMPANION_TYPES_POLARDAY)) {

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
      scene_cmd.p0 = direct_hoisted_rec_1;
      scene_cmd.p1 = direct_hoisted_rec_2;
      scene_cmd.p2 = direct_hoisted_int_1;
      scene_cmd.p3 = ELMC_COLOR_CHROME_YELLOW;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

    }
    else if (elmc_union_tag_matches(owned[8], ELMC_UNION_COMPANION_TYPES_SUNCYCLE)) {

      Rc = elmc_fn_Yes_Render_coloredRadialWedge_commands_append_native(owned[6], ELMC_COLOR_CHROME_YELLOW, direct_native_let_sunriseAngle_7, direct_native_let_sunsetAngle_8, writer);
      CHECK_RC(Rc);

    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CIRCLE);
    scene_cmd.p0 = direct_hoisted_rec_1;
    scene_cmd.p1 = direct_hoisted_rec_2;
    scene_cmd.p2 = direct_hoisted_int_2;
    scene_cmd.p3 = ELMC_COLOR_WHITE;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CIRCLE);
    scene_cmd.p0 = direct_hoisted_rec_1;
    scene_cmd.p1 = direct_hoisted_rec_2;
    scene_cmd.p2 = direct_hoisted_int_1;
    scene_cmd.p3 = ELMC_COLOR_DARK_GRAY;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_int_t direct_step_19 = (1 <= 23) ? 1 : -1;
    for (elmc_int_t direct_item_i_19 = 1;
    Rc == RC_SUCCESS; direct_item_i_19 += direct_step_19) {;

      elmc_int_t native_mod_20 = direct_item_i_19 & 1;
      if (!((native_mod_20 == 1))) {
        if (direct_item_i_19 == 23) break;
        continue;
      }

      Rc = elmc_new_int(&owned[9], (direct_item_i_19 * 60));
      CHECK_RC(Rc);

      Rc = elmc_new_int(&owned[10], 10);
      CHECK_RC(Rc);

      owned[11] = elmc_maybe_nothing();

      ElmcValue *rec_values_1[3] = { owned[9], owned[10], owned[11] };
      Rc = elmc_record_new_values_take(&owned[12], 3, rec_values_1);
      CHECK_RC(Rc);
      owned[9] = NULL;
      owned[10] = NULL;
      owned[11] = NULL;
      ElmcValue *direct_call_args_19[2] = {0};
      direct_call_args_19[0] = layout;
      direct_call_args_19[1] = owned[12];
      Rc = elmc_fn_Yes_Render_drawScaleTick_commands_append(direct_call_args_19, 2, writer);
      ELMC_RELEASE(owned[12]);
      owned[12] = NULL;
      CHECK_RC(Rc);

      if (direct_item_i_19 == 23) break;
    }

    elmc_int_t direct_step_21 = (0 <= 11) ? 1 : -1;
    for (elmc_int_t direct_item_i_21 = 0;
    Rc == RC_SUCCESS; direct_item_i_21 += direct_step_21) {;

      const elmc_int_t direct_tick_minute_21 = (direct_item_i_21 * 120);
      const elmc_int_t direct_tick_angle_21 = elmc_angle_from_minute(direct_tick_minute_21);
      const elmc_int_t direct_tick_inner_x_21 = elmc_polar_point_x(direct_hoisted_rec_1, direct_hoisted_rec_2, direct_hoisted_rec_3, direct_tick_angle_21);
      const elmc_int_t direct_tick_inner_y_21 = elmc_polar_point_y(direct_hoisted_rec_1, direct_hoisted_rec_2, direct_hoisted_rec_3, direct_tick_angle_21);
      const elmc_int_t direct_tick_outer_x_21 = elmc_polar_point_x(direct_hoisted_rec_1, direct_hoisted_rec_2, (direct_hoisted_rec_3 + 6), direct_tick_angle_21);
      const elmc_int_t direct_tick_outer_y_21 = elmc_polar_point_y(direct_hoisted_rec_1, direct_hoisted_rec_2, (direct_hoisted_rec_3 + 6), direct_tick_angle_21);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_LINE);
      scene_cmd.p0 = direct_tick_outer_x_21;
      scene_cmd.p1 = direct_tick_outer_y_21;
      scene_cmd.p2 = direct_tick_inner_x_21;
      scene_cmd.p3 = direct_tick_inner_y_21;
      scene_cmd.p4 = ELMC_COLOR_WHITE;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

      const elmc_int_t direct_tick_label_x_21 = elmc_polar_point_x(direct_hoisted_rec_1, direct_hoisted_rec_2, (direct_hoisted_rec_3 + 14), direct_tick_angle_21);
      const elmc_int_t direct_tick_label_y_21 = elmc_polar_point_y(direct_hoisted_rec_1, direct_hoisted_rec_2, (direct_hoisted_rec_3 + 14), direct_tick_angle_21);
      {
        ElmcValue *direct_tick_label_box_21 = NULL;
        elmc_int_t rec_values_21[4] = { (direct_tick_label_x_21 - 9), (direct_tick_label_y_21 - 14), 18, 12 };
        Rc = elmc_record_new_values_ints(&direct_tick_label_box_21, 4, rec_values_21);
        CHECK_RC(Rc);
        elmc_scene_text_from_nonzero_int(scene_cmd.text, (direct_item_i_21 * 2));
        scene_cmd.text[63] = '\0';
        Rc = elmc_fn_Yes_Render_textAt_commands_append_native(ELMC_COLOR_WHITE, direct_tick_label_box_21, scene_cmd.text, writer);
        CHECK_RC(Rc);
        elmc_release(direct_tick_label_box_21);
      }

      if (direct_item_i_21 == 11) break;
    }

    owned[9] = elmc_record_get_index(display, ELMC_FIELD_MAIN_MODEL_NOW);

    elmc_int_t native_maybe_case_22;
    if (elmc_maybe_is_just(owned[9])) {

      elmc_int_t native_mod_21 = ((((ELMC_RECORD_GET_INDEX_INT(elmc_maybe_or_tuple_just_payload_borrow(owned[9]), ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_HOUR) * 60) + ELMC_RECORD_GET_INDEX_INT(elmc_maybe_or_tuple_just_payload_borrow(owned[9]), ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MINUTE)) + ELMC_RECORD_GET_INDEX_INT(display, ELMC_FIELD_MAIN_MODEL_HOMETZOFFSETMIN)) - ELMC_RECORD_GET_INDEX_INT(elmc_maybe_or_tuple_just_payload_borrow(owned[9]), ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_UTCOFFSETMINUTES)) % 1440;
      if (native_mod_21 < 0)
        native_mod_21 += 1440;

      native_maybe_case_22 = native_mod_21;
    } else {

      native_maybe_case_22 = 720;
    }

    // inlined Main.homeMinuteOfDay
    const elmc_int_t direct_hoisted_int_23 = native_maybe_case_22;

    // inlined Yes.Render.angleFromMinute

    const elmc_int_t direct_native_let_handAngle_24 = elmc_angle_from_minute(direct_hoisted_int_23);

    const elmc_int_t native_polar_x_25 = elmc_polar_point_x(direct_hoisted_rec_1, direct_hoisted_rec_2, ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_HANDLEN), direct_native_let_handAngle_24);

    const elmc_int_t native_polar_y_26 = elmc_polar_point_y(direct_hoisted_rec_1, direct_hoisted_rec_2, ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_HANDLEN), direct_native_let_handAngle_24);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_LINE);
    scene_cmd.p0 = direct_hoisted_rec_1;
    scene_cmd.p1 = direct_hoisted_rec_2;
    scene_cmd.p2 = native_polar_x_25;
    scene_cmd.p3 = native_polar_y_26;
    scene_cmd.p4 = ELMC_COLOR_WHITE;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
    scene_cmd.p0 = direct_hoisted_rec_1;
    scene_cmd.p1 = direct_hoisted_rec_2;
    scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_HUBR);
    scene_cmd.p3 = ELMC_COLOR_BLACK;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CIRCLE);
    scene_cmd.p0 = direct_hoisted_rec_1;
    scene_cmd.p1 = direct_hoisted_rec_2;
    scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_HUBR);
    scene_cmd.p3 = ELMC_COLOR_WHITE;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    owned[10] = elmc_record_get_index(display, ELMC_FIELD_MAIN_MODEL_MOONPHASEE6);

    if (elmc_maybe_is_just(owned[10])) {

      Rc = elmc_fn_Yes_Render_drawMoonPhase_commands_append_native(layout, (elmc_maybe_or_tuple_just_payload_borrow(owned[10]) ? elmc_as_int(elmc_maybe_or_tuple_just_payload_borrow(owned[10])) : 0), writer);
      CHECK_RC(Rc);

    }
    else if (elmc_maybe_is_nothing(owned[10])) {

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
      scene_cmd.p0 = direct_hoisted_rec_1;
      scene_cmd.p1 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONY);
      scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONPHASERADIUS);
      scene_cmd.p3 = ELMC_COLOR_BLACK;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CIRCLE);
      scene_cmd.p0 = direct_hoisted_rec_1;
      scene_cmd.p1 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONY);
      scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONPHASERADIUS);
      scene_cmd.p3 = ELMC_COLOR_WHITE;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

    }

    Rc = elmc_new_int(&owned[11], ELMC_COLOR_BLACK);
    CHECK_RC(Rc);

    const elmc_int_t native_i_33 = elmc_as_int(owned[11]);

    owned[13] = elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_TIMETEXTBAND);

    Rc = elmc_fn_Main_timeString(&owned[14], display);
    CHECK_RC(Rc);

    ElmcValue *native_string_36_src = owned[14];
    const char *native_string_36 =
    (native_string_36_src && native_string_36_src->tag == ELMC_TAG_STRING && native_string_36_src->payload)
    ? (const char *)native_string_36_src->payload
    : "";

    Rc = elmc_fn_Yes_Render_textAt_commands_append_native(native_i_33, owned[13], native_string_36, writer);
    CHECK_RC(Rc);

  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

static RC elmc_fn_Yes_Render_drawScaleTick_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *layout = (argc > 0) ? args[0] : NULL;
  ElmcValue *spec = (argc > 1) ? args[1] : NULL;
  (void)layout;
  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[3] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    const elmc_int_t direct_hoisted_int_1 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t direct_hoisted_int_2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CY);
    const elmc_int_t direct_hoisted_int_3 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_OUTERRADIUS);
    // inlined Yes.Render.angleFromMinute

    const elmc_int_t direct_native_let_tickAngle_4 = elmc_angle_from_minute(ELMC_RECORD_GET_INDEX_INT(spec, ELMC_FIELD_YES_RENDER_TICKSPEC_MINUTE));

    const elmc_int_t native_polar_x_5 = elmc_polar_point_x(direct_hoisted_int_1, direct_hoisted_int_2, direct_hoisted_int_3, direct_native_let_tickAngle_4);

    const elmc_int_t native_polar_y_6 = elmc_polar_point_y(direct_hoisted_int_1, direct_hoisted_int_2, direct_hoisted_int_3, direct_native_let_tickAngle_4);

    const elmc_int_t native_polar_x_7 = elmc_polar_point_x(direct_hoisted_int_1, direct_hoisted_int_2, (direct_hoisted_int_3 + ELMC_RECORD_GET_INDEX_INT(spec, ELMC_FIELD_YES_RENDER_TICKSPEC_OUTEREXTRA)), direct_native_let_tickAngle_4);

    const elmc_int_t native_polar_y_8 = elmc_polar_point_y(direct_hoisted_int_1, direct_hoisted_int_2, (direct_hoisted_int_3 + ELMC_RECORD_GET_INDEX_INT(spec, ELMC_FIELD_YES_RENDER_TICKSPEC_OUTEREXTRA)), direct_native_let_tickAngle_4);

    owned[0] = elmc_record_get_index(spec, ELMC_FIELD_YES_RENDER_TICKSPEC_LABEL);

    if (elmc_maybe_is_nothing(owned[0])) {

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_LINE);
      scene_cmd.p0 = native_polar_x_7;
      scene_cmd.p1 = native_polar_y_8;
      scene_cmd.p2 = native_polar_x_5;
      scene_cmd.p3 = native_polar_y_6;
      scene_cmd.p4 = ELMC_COLOR_WHITE;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

    }
    else if (elmc_maybe_is_just(owned[0])) {

      const elmc_int_t native_polar_x_10 = elmc_polar_point_x(direct_hoisted_int_1, direct_hoisted_int_2, (direct_hoisted_int_3 + 14), direct_native_let_tickAngle_4);

      const elmc_int_t native_polar_y_11 = elmc_polar_point_y(direct_hoisted_int_1, direct_hoisted_int_2, (direct_hoisted_int_3 + 14), direct_native_let_tickAngle_4);
      const elmc_int_t direct_native_record_labelBox_x_12 = (native_polar_x_10 - 9);
      const elmc_int_t direct_native_record_labelBox_y_13 = (native_polar_y_11 - 14);
      const elmc_int_t direct_native_record_labelBox_w_14 = 18;
      const elmc_int_t direct_native_record_labelBox_h_15 = 12;

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_LINE);
      scene_cmd.p0 = native_polar_x_7;
      scene_cmd.p1 = native_polar_y_8;
      scene_cmd.p2 = native_polar_x_5;
      scene_cmd.p3 = native_polar_y_6;
      scene_cmd.p4 = ELMC_COLOR_WHITE;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

      Rc = elmc_new_int(&owned[1], ELMC_COLOR_WHITE);
      CHECK_RC(Rc);

      const elmc_int_t native_i_17 = elmc_as_int(owned[1]);

      elmc_int_t rec_values_2[4] = { direct_native_record_labelBox_x_12, direct_native_record_labelBox_y_13, direct_native_record_labelBox_w_14, direct_native_record_labelBox_h_15 };
      Rc = elmc_record_new_values_ints(&owned[2], 4, rec_values_2);
      CHECK_RC(Rc);

      ElmcValue *native_string_19_src = elmc_maybe_or_tuple_just_payload_borrow(owned[0]);
      const char *native_string_19 =
      (native_string_19_src && native_string_19_src->tag == ELMC_TAG_STRING && native_string_19_src->payload)
      ? (const char *)native_string_19_src->payload
      : "";

      Rc = elmc_fn_Yes_Render_textAt_commands_append_native(native_i_17, owned[2], native_string_19, writer);
      CHECK_RC(Rc);

    }

  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

static RC elmc_fn_Yes_Render_coloredRadial_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *bounds = (argc > 0) ? args[0] : NULL;
  elmc_int_t fill = (argc > 1 && args[1]) ? elmc_as_int(args[1]) : 0;
  elmc_int_t start = (argc > 2 && args[2]) ? elmc_as_int(args[2]) : 0;
  elmc_int_t end = (argc > 3 && args[3]) ? elmc_as_int(args[3]) : 0;

  return elmc_fn_Yes_Render_coloredRadial_commands_append_native(bounds, fill, start, end, writer);
}

static RC elmc_fn_Yes_Render_coloredRadial_commands_append_native(ElmcValue * const bounds, const elmc_int_t fill, const elmc_int_t start, const elmc_int_t end, ElmcSceneWriter * const writer) {

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PUSH_CONTEXT);

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_COLOR);
    scene_cmd.p0 = fill;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_STROKE_COLOR);
    scene_cmd.p0 = fill;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_RADIAL);
    scene_cmd.p0 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_X);
    scene_cmd.p1 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_Y);
    scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_W);
    scene_cmd.p3 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_H);
    scene_cmd.p4 = start;
    scene_cmd.p5 = end;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_POP_CONTEXT);

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

  CATCH_END
  return Rc;

}

static RC elmc_fn_Yes_Render_coloredRadialWedge_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *bounds = (argc > 0) ? args[0] : NULL;
  elmc_int_t color = (argc > 1 && args[1]) ? elmc_as_int(args[1]) : 0;
  elmc_int_t startAngle = (argc > 2 && args[2]) ? elmc_as_int(args[2]) : 0;
  elmc_int_t endAngle = (argc > 3 && args[3]) ? elmc_as_int(args[3]) : 0;

  return elmc_fn_Yes_Render_coloredRadialWedge_commands_append_native(bounds, color, startAngle, endAngle, writer);
}

static RC elmc_fn_Yes_Render_coloredRadialWedge_commands_append_native(ElmcValue * const bounds, const elmc_int_t color, const elmc_int_t startAngle, const elmc_int_t endAngle, ElmcSceneWriter * const writer) {

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    if ((endAngle < startAngle)) {

      Rc = elmc_fn_Yes_Render_coloredRadial_commands_append_native(bounds, color, startAngle, 65536, writer);
      CHECK_RC(Rc);

      Rc = elmc_fn_Yes_Render_coloredRadial_commands_append_native(bounds, color, 0, endAngle, writer);
      CHECK_RC(Rc);

    } else {

      Rc = elmc_fn_Yes_Render_coloredRadial_commands_append_native(bounds, color, startAngle, endAngle, writer);
      CHECK_RC(Rc);

    }

  CATCH_END
  return Rc;

}

static RC elmc_fn_Yes_Render_drawMoonPhase_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *layout = (argc > 0) ? args[0] : NULL;
  elmc_int_t phaseE6 = (argc > 1 && args[1]) ? elmc_as_int(args[1]) : 0;

  return elmc_fn_Yes_Render_drawMoonPhase_commands_append_native(layout, phaseE6, writer);
}

static RC elmc_fn_Yes_Render_drawMoonPhase_commands_append_native(ElmcValue * const layout, const elmc_int_t phaseE6, ElmcSceneWriter * const writer) {

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[47] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    const elmc_int_t direct_hoisted_rec_1 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_CX);
    const elmc_int_t direct_hoisted_rec_2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONY);

    const elmc_int_t direct_native_let_r_1 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_MOONPHASERADIUS);
    const elmc_int_t direct_native_record_bounds_x_2 = (direct_hoisted_rec_1 - direct_native_let_r_1);
    const elmc_int_t direct_native_record_bounds_y_3 = (direct_hoisted_rec_2 - direct_native_let_r_1);
    const elmc_int_t direct_native_record_bounds_w_4 = (direct_native_let_r_1 * 2);
    const elmc_int_t direct_native_record_bounds_h_5 = (direct_native_let_r_1 * 2);

    /* elm/core: Basics.clamp */

    owned[0] = elmc_int_zero();
    Rc = elmc_new_int(&owned[1], 1000000);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[2], phaseE6);
    CHECK_RC(Rc);

    Rc = elmc_basics_clamp(&owned[3], owned[0], owned[1], owned[2]);
    CHECK_RC(Rc);

    if (owned[3] == owned[0]) {
      elmc_release(owned[3]);
      owned[0] = NULL;
    }

    if (owned[3] == owned[1]) {
      elmc_release(owned[3]);
      owned[1] = NULL;
    }

    if (owned[3] == owned[2]) {
      elmc_release(owned[3]);
      owned[2] = NULL;
    }

    /* elm/core: Basics.toFloat */

    Rc = elmc_basics_to_float(&owned[4], owned[3]);
    CHECK_RC(Rc);

    if (owned[4] == owned[3]) {
      owned[3] = NULL;
    }

    Rc = elmc_new_int(&owned[5], 1000000);
    CHECK_RC(Rc);
    const double __denf_7 = elmc_as_float(owned[5]);
    const double __numf_7 = elmc_as_float(owned[4]);
    ElmcValue *tmp_7 = NULL;
    Rc = elmc_new_float(&tmp_7, __numf_7 / __denf_7);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[6], 1);
    CHECK_RC(Rc);
    /* elm/core: Basics.cos */

    /* elm/core: Basics.turns */

    Rc = elmc_basics_turns(&owned[7], tmp_7);
    CHECK_RC(Rc);

    Rc = elmc_basics_cos(&owned[8], owned[7]);
    CHECK_RC(Rc);

    if (owned[8] == owned[7]) {
      owned[7] = NULL;
    }

    if ((owned[6] && owned[6]->tag == ELMC_TAG_FLOAT) || (owned[8] && owned[8]->tag == ELMC_TAG_FLOAT)) {
      Rc = elmc_new_float(&owned[9], elmc_as_float(owned[6]) - elmc_as_float(owned[8]));
      CHECK_RC(Rc);
    } else {
      Rc = elmc_new_int(&owned[9], elmc_as_int(owned[6]) - elmc_as_int(owned[8]));
      CHECK_RC(Rc);
    }

    Rc = elmc_new_int(&owned[10], 2);
    CHECK_RC(Rc);
    const double __denf_12 = elmc_as_float(owned[10]);
    const double __numf_12 = elmc_as_float(owned[9]);
    ElmcValue *tmp_12 = NULL;
    Rc = elmc_new_float(&tmp_12, __numf_12 / __denf_12);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[13], 500000);
    CHECK_RC(Rc);
    Rc = elmc_basics_compare(&owned[14], owned[3], owned[13]);
    CHECK_RC(Rc);
    const bool native_cmp_15 = elmc_as_int(owned[14]) < 0;

    /* elm/core: Basics.round */

    /* elm/core: Basics.toFloat */

    Rc = elmc_new_float(&owned[15], (double)(double)direct_native_let_r_1);
    CHECK_RC(Rc);

    /* elm/core: Basics.cos */

    /* elm/core: Basics.turns */

    Rc = elmc_basics_turns(&owned[16], tmp_7);
    CHECK_RC(Rc);

    Rc = elmc_basics_cos(&owned[17], owned[16]);
    CHECK_RC(Rc);

    if (owned[17] == owned[16]) {
      owned[16] = NULL;
    }

    if ((owned[15] && owned[15]->tag == ELMC_TAG_FLOAT) || (owned[17] && owned[17]->tag == ELMC_TAG_FLOAT)) {
      Rc = elmc_new_float(&owned[18], elmc_as_float(owned[15]) * elmc_as_float(owned[17]));
      CHECK_RC(Rc);
    } else {
      Rc = elmc_new_int(&owned[18], elmc_as_int(owned[15]) * elmc_as_int(owned[17]));
      CHECK_RC(Rc);
    }

    Rc = elmc_basics_round(&owned[19], owned[18]);
    CHECK_RC(Rc);

    if (owned[19] == owned[18]) {
      owned[18] = NULL;
    }

    const elmc_int_t native_abs_arg_21 = ((owned[3] ? elmc_as_int(owned[3]) : 0) - 500000);
    const elmc_int_t native_abs_21 = (native_abs_arg_21 < 0 ? -native_abs_arg_21 : native_abs_arg_21);

    if ((native_abs_21 < 20000)) {
      Rc = elmc_new_bool(&owned[20], true);
      CHECK_RC(Rc);
    } else {
      const elmc_int_t native_abs_arg_23 = ((owned[3] ? elmc_as_int(owned[3]) : 0) - 500000);
      const elmc_int_t native_abs_23 = (native_abs_arg_23 < 0 ? -native_abs_arg_23 : native_abs_arg_23);
      Rc = elmc_new_bool(&owned[20], native_abs_23 == 20000);
      CHECK_RC(Rc);
    }
    if ((bool)elmc_as_bool(owned[20])) {

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
      scene_cmd.p0 = direct_hoisted_rec_1;
      scene_cmd.p1 = direct_hoisted_rec_2;
      scene_cmd.p2 = direct_native_let_r_1;
      scene_cmd.p3 = ELMC_COLOR_LIGHT_GRAY;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CIRCLE);
      scene_cmd.p0 = direct_hoisted_rec_1;
      scene_cmd.p1 = direct_hoisted_rec_2;
      scene_cmd.p2 = direct_native_let_r_1;
      scene_cmd.p3 = ELMC_COLOR_WHITE;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

    } else {

      Rc = elmc_new_int(&owned[23], 20000);
      CHECK_RC(Rc);
      Rc = elmc_basics_compare(&owned[24], owned[3], owned[23]);
      CHECK_RC(Rc);
      const bool native_cmp_27 = elmc_as_int(owned[24]) < 0;

      if (native_cmp_27) {
        Rc = elmc_new_bool(&owned[25], true);
        CHECK_RC(Rc);
      } else {
        Rc = elmc_new_int(&owned[26], 20000);
        CHECK_RC(Rc);
        Rc = elmc_new_bool(&owned[27], elmc_value_equal(owned[3], owned[26]));
        CHECK_RC(Rc);
        owned[25] = owned[27];
        owned[27] = NULL;
      }

      if (elmc_as_bool(owned[25])) {
        Rc = elmc_new_bool(&owned[28], true);
        CHECK_RC(Rc);
      } else {
        Rc = elmc_new_int(&owned[31], 980000);
        CHECK_RC(Rc);
        Rc = elmc_basics_compare(&owned[32], owned[3], owned[31]);
        CHECK_RC(Rc);
        const bool native_cmp_33 = elmc_as_int(owned[32]) > 0;

        if (native_cmp_33) {
          Rc = elmc_new_bool(&owned[28], true);
          CHECK_RC(Rc);
        } else {
          Rc = elmc_new_int(&owned[33], 980000);
          CHECK_RC(Rc);
          Rc = elmc_new_bool(&owned[34], elmc_value_equal(owned[3], owned[33]));
          CHECK_RC(Rc);
          owned[28] = owned[34];
          owned[34] = NULL;
        }
      }

      if ((bool)elmc_as_bool(owned[28])) {

        elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
        scene_cmd.p0 = direct_hoisted_rec_1;
        scene_cmd.p1 = direct_hoisted_rec_2;
        scene_cmd.p2 = direct_native_let_r_1;
        scene_cmd.p3 = ELMC_COLOR_BLACK;
        Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
        CHECK_RC(Rc);

        elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CIRCLE);
        scene_cmd.p0 = direct_hoisted_rec_1;
        scene_cmd.p1 = direct_hoisted_rec_2;
        scene_cmd.p2 = direct_native_let_r_1;
        scene_cmd.p3 = ELMC_COLOR_WHITE;
        Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
        CHECK_RC(Rc);

      } else {

        elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
        scene_cmd.p0 = direct_hoisted_rec_1;
        scene_cmd.p1 = direct_hoisted_rec_2;
        scene_cmd.p2 = direct_native_let_r_1;
        scene_cmd.p3 = ELMC_COLOR_BLACK;
        Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
        CHECK_RC(Rc);

        if (native_cmp_15) {

          elmc_int_t rec_values_3[4] = { direct_native_record_bounds_x_2, direct_native_record_bounds_y_3, direct_native_record_bounds_w_4, direct_native_record_bounds_h_5 };
          Rc = elmc_record_new_values_ints(&owned[35], 4, rec_values_3);
          CHECK_RC(Rc);

          Rc = elmc_new_int(&owned[36], ELMC_COLOR_LIGHT_GRAY);
          CHECK_RC(Rc);

          const elmc_int_t native_i_40 = elmc_as_int(owned[36]);

          Rc = elmc_fn_Yes_Render_coloredRadial_commands_append_native(owned[35], native_i_40, 0, 32768, writer);
          CHECK_RC(Rc);

        } else {

          elmc_int_t rec_values_4[4] = { direct_native_record_bounds_x_2, direct_native_record_bounds_y_3, direct_native_record_bounds_w_4, direct_native_record_bounds_h_5 };
          Rc = elmc_record_new_values_ints(&owned[37], 4, rec_values_4);
          CHECK_RC(Rc);

          Rc = elmc_new_int(&owned[38], ELMC_COLOR_LIGHT_GRAY);
          CHECK_RC(Rc);

          const elmc_int_t native_i_43 = elmc_as_int(owned[38]);

          Rc = elmc_fn_Yes_Render_coloredRadial_commands_append_native(owned[37], native_i_43, 32768, 65536, writer);
          CHECK_RC(Rc);

        }

        /* elm/core: Basics.abs */

        Rc = elmc_basics_abs(&owned[39], owned[19]);
        CHECK_RC(Rc);

        if (owned[39] == owned[19]) {
          owned[19] = NULL;
        }

        /* elm/core: Basics.max */

        const elmc_int_t native_max_left_45 = 1;
        const elmc_int_t native_max_right_45 = elmc_int_idiv(direct_native_let_r_1, 8);
        const elmc_int_t native_max_45 = (native_max_left_45 >= native_max_right_45) ? native_max_left_45 : native_max_right_45;

        Rc = elmc_new_int(&owned[40], native_max_45);
        CHECK_RC(Rc);

        Rc = elmc_basics_compare(&owned[41], owned[39], owned[40]);
        CHECK_RC(Rc);
        const bool native_cmp_46 = elmc_as_int(owned[41]) < 0;

        if (!(native_cmp_46)) {
          owned[43] = tmp_12 ? elmc_retain(tmp_12) : elmc_int_zero();
          Rc = elmc_new_float(&owned[45], 0.5);
          CHECK_RC(Rc);

          Rc = elmc_basics_compare(&owned[46], owned[43], owned[45]);
          CHECK_RC(Rc);
          const bool native_cmp_47 = elmc_as_int(owned[46]) < 0;

          if (native_cmp_47) {

            elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
            scene_cmd.p0 = (direct_hoisted_rec_1 + elmc_as_int(owned[19]));
            scene_cmd.p1 = direct_hoisted_rec_2;
            scene_cmd.p2 = direct_native_let_r_1;
            scene_cmd.p3 = ELMC_COLOR_BLACK;
            Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
            CHECK_RC(Rc);

          } else {

            elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_FILL_CIRCLE);
            scene_cmd.p0 = (direct_hoisted_rec_1 + elmc_as_int(owned[19]));
            scene_cmd.p1 = direct_hoisted_rec_2;
            scene_cmd.p2 = direct_native_let_r_1;
            scene_cmd.p3 = ELMC_COLOR_LIGHT_GRAY;
            Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
            CHECK_RC(Rc);

          }

        }

        elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CIRCLE);
        scene_cmd.p0 = direct_hoisted_rec_1;
        scene_cmd.p1 = direct_hoisted_rec_2;
        scene_cmd.p2 = direct_native_let_r_1;
        scene_cmd.p3 = ELMC_COLOR_WHITE;
        Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
        CHECK_RC(Rc);

      }

    }

    elmc_release(tmp_12);

    elmc_release(tmp_7);

  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

static RC elmc_fn_Yes_Render_drawBottomRight_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *layout = (argc > 0) ? args[0] : NULL;
  ElmcValue *slot = (argc > 1) ? args[1] : NULL;

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[10] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    if (elmc_union_tag_matches(slot, ELMC_UNION_ALTITUDESLOT)) {

      owned[0] = elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT);

      owned[1] = elmc_record_get_index(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_VECTOR);

      owned[2] = elmc_record_get_index(owned[1], 0 /* x */);

      int64_t direct_i_4 = elmc_as_int_number(owned[2]);

      owned[3] = elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT);

      owned[4] = elmc_record_get_index(owned[3], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_VECTOR);

      owned[5] = elmc_record_get_index(owned[4], 1 /* y */);

      int64_t direct_i_7 = elmc_as_int_number(owned[5]);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_VECTOR_AT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = direct_i_4;
      scene_cmd.p2 = direct_i_7;
      Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
      CHECK_RC(Rc);

      owned[6] = elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT);

      owned[7] = elmc_record_get_index(owned[6], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_SINGLELINE);

      ElmcValue *native_string_9_src = ((ElmcTuple2 *)slot->payload)->second;
      const char *native_string_9 =
      (native_string_9_src && native_string_9_src->tag == ELMC_TAG_STRING && native_string_9_src->payload)
      ? (const char *)native_string_9_src->payload
      : "";

      Rc = elmc_fn_Yes_Render_textAt_commands_append_native(ELMC_COLOR_WHITE, owned[7], native_string_9, writer);
      CHECK_RC(Rc);

    }
    else if (elmc_union_tag_matches(slot, ELMC_UNION_SIMPLELINE)) {

      owned[8] = elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT);

      owned[9] = elmc_record_get_index(owned[8], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_SINGLELINE);

      ElmcValue *native_string_11_src = ((ElmcTuple2 *)slot->payload)->second;
      const char *native_string_11 =
      (native_string_11_src && native_string_11_src->tag == ELMC_TAG_STRING && native_string_11_src->payload)
      ? (const char *)native_string_11_src->payload
      : "";

      Rc = elmc_fn_Yes_Render_textAt_commands_append_native(ELMC_COLOR_WHITE, owned[9], native_string_11, writer);
      CHECK_RC(Rc);

    }
    else if (elmc_union_tag_matches(slot, ELMC_UNION_COUNTDOWNSLOT) && (((ElmcTuple2 *)slot->payload)->second && ((ElmcTuple2 *)slot->payload)->second->tag == ELMC_TAG_TUPLE2 && (1) && (1))) {

      ElmcValue *native_string_13_src = elmc_tuple_first_borrow(((ElmcTuple2 *)slot->payload)->second);
      const char *native_string_13 =
      (native_string_13_src && native_string_13_src->tag == ELMC_TAG_STRING && native_string_13_src->payload)
      ? (const char *)native_string_13_src->payload
      : "";

      ElmcValue *native_string_14_src = elmc_tuple_second_borrow(((ElmcTuple2 *)slot->payload)->second);
      const char *native_string_14 =
      (native_string_14_src && native_string_14_src->tag == ELMC_TAG_STRING && native_string_14_src->payload)
      ? (const char *)native_string_14_src->payload
      : "";

      Rc = elmc_fn_Yes_Render_drawBottomRightCountdown_commands_append_native(layout, native_string_13, native_string_14, writer);
      CHECK_RC(Rc);

    }

  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

static RC elmc_fn_Yes_Render_drawBottomRightCountdown_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *layout = (argc > 0) ? args[0] : NULL;
  const char *label =
  (argc > 1 && args[1] && args[1]->tag == ELMC_TAG_STRING && args[1]->payload)
  ? (const char *)args[1]->payload
  : "";

  const char *timeLine =
  (argc > 2 && args[2] && args[2]->tag == ELMC_TAG_STRING && args[2]->payload)
  ? (const char *)args[2]->payload
  : "";

  return elmc_fn_Yes_Render_drawBottomRightCountdown_commands_append_native(layout, label, timeLine, writer);
}

static RC elmc_fn_Yes_Render_drawBottomRightCountdown_commands_append_native(ElmcValue * const layout, const char * const label, const char * const timeLine, ElmcSceneWriter * const writer) {

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[5] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    owned[0] = elmc_record_get_index(layout, ELMC_FIELD_YES_LAYOUT_LAYOUT_BOTTOMRIGHT);

    const elmc_int_t direct_native_let_labelH_2 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_COUNTDOWNLABELH);

    const elmc_int_t direct_native_let_timeH_3 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_COUNTDOWNTIMEH);

    const elmc_int_t direct_native_let_topY_4 = ((ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_BOTTOM) - direct_native_let_labelH_2) - direct_native_let_timeH_3);

    const elmc_int_t direct_native_let_labelY_5 = (direct_native_let_topY_4 - 2);
    const elmc_int_t direct_native_record_labelRect_x_6 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_X);
    const elmc_int_t direct_native_record_labelRect_y_7 = direct_native_let_labelY_5;
    const elmc_int_t direct_native_record_labelRect_w_8 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_TEXTW);
    const elmc_int_t direct_native_record_labelRect_h_9 = direct_native_let_labelH_2;

    const elmc_int_t direct_native_record_timeRect_x_10 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_X);
    const elmc_int_t direct_native_record_timeRect_y_11 = ((direct_native_let_topY_4 + direct_native_let_labelH_2) - 1);
    const elmc_int_t direct_native_record_timeRect_w_12 = ELMC_RECORD_GET_INDEX_INT(owned[0], ELMC_FIELD_YES_LAYOUT_BOTTOMRIGHTLAYOUT_TEXTW);
    const elmc_int_t direct_native_record_timeRect_h_13 = direct_native_let_timeH_3;

    Rc = elmc_new_int(&owned[1], ELMC_COLOR_LIGHT_GRAY);
    CHECK_RC(Rc);

    const elmc_int_t native_i_14 = elmc_as_int(owned[1]);

    elmc_int_t rec_values_5[4] = { direct_native_record_labelRect_x_6, direct_native_record_labelRect_y_7, direct_native_record_labelRect_w_8, direct_native_record_labelRect_h_9 };
    Rc = elmc_record_new_values_ints(&owned[2], 4, rec_values_5);
    CHECK_RC(Rc);

    Rc = elmc_fn_Yes_Render_textAt_commands_append_native(native_i_14, owned[2], label, writer);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[3], ELMC_COLOR_WHITE);
    CHECK_RC(Rc);

    const elmc_int_t native_i_17 = elmc_as_int(owned[3]);

    elmc_int_t rec_values_6[4] = { direct_native_record_timeRect_x_10, direct_native_record_timeRect_y_11, direct_native_record_timeRect_w_12, direct_native_record_timeRect_h_13 };
    Rc = elmc_record_new_values_ints(&owned[4], 4, rec_values_6);
    CHECK_RC(Rc);

    Rc = elmc_fn_Yes_Render_textAt_commands_append_native(native_i_17, owned[4], timeLine, writer);
    CHECK_RC(Rc);

  CATCH_END
  elmc_release_array_lifo(owned, DIM(owned));

  return Rc;

}

static RC elmc_fn_Yes_Render_textAt_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  elmc_int_t color = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  ElmcValue *bounds = (argc > 1) ? args[1] : NULL;
  const char *value =
  (argc > 2 && args[2] && args[2]->tag == ELMC_TAG_STRING && args[2]->payload)
  ? (const char *)args[2]->payload
  : "";

  return elmc_fn_Yes_Render_textAt_commands_append_native(color, bounds, value, writer);
}

static RC elmc_fn_Yes_Render_textAt_commands_append_native(const elmc_int_t color, ElmcValue * const bounds, const char * const value, ElmcSceneWriter * const writer) {

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PUSH_CONTEXT);

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_COLOR);
    scene_cmd.p0 = color;
    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    const elmc_int_t direct_hoisted_int_3 = (ELMC_TEXT_ALIGN_CENTER + (ELMC_TEXT_OVERFLOW_WORD_WRAP * (1 << ELMC_TEXT_OVERFLOW_SHIFT)));

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_X);
    scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_Y);
    scene_cmd.p3 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_W);
    scene_cmd.p4 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_H);
    scene_cmd.p5 = direct_hoisted_int_3;
    {
      const char *direct_text = value;
      int direct_text_i = 0;
      while (direct_text[direct_text_i] && direct_text_i < 63) {
        scene_cmd.text[direct_text_i] = direct_text[direct_text_i];
        direct_text_i++;
      }
      scene_cmd.text[direct_text_i] = '\0';

    }

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_POP_CONTEXT);

    Rc = elmc_scene_writer_push_cmd(writer, &scene_cmd);
    CHECK_RC(Rc);

  CATCH_END
  return Rc;

}
