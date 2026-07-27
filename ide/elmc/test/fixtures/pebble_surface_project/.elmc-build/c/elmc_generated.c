#include "elmc_generated.h"
#include "elmc_pebble.h"
#include <stdbool.h>
#include <stdio.h>

#if defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-variable"
#endif

#define ELMC_UNION_ACCELDATA 27
#define ELMC_UNION_ACCELTAP 8
#define ELMC_UNION_ACTIVESECONDS 2
#define ELMC_UNION_ANIMATIONFINISHED 44
#define ELMC_UNION_APPFOCUSCHANGED 39
#define ELMC_UNION_BATTERYCHANGED 9
#define ELMC_UNION_BUTTONDOWN 4
#define ELMC_UNION_BUTTONLONGDOWN 7
#define ELMC_UNION_BUTTONLONGSELECT 6
#define ELMC_UNION_BUTTONLONGUP 5
#define ELMC_UNION_BUTTONSELECT 3
#define ELMC_UNION_BUTTONUP 2
#define ELMC_UNION_COMPASSCHANGED 40
#define ELMC_UNION_CONNECTIONCHANGED 10
#define ELMC_UNION_DAYCHANGED 13
#define ELMC_UNION_DEFAULTFONT 1
#define ELMC_UNION_DICTATIONRESULT 43
#define ELMC_UNION_DICTATIONSTATUS 42
#define ELMC_UNION_DOWN 4
#define ELMC_UNION_FRAMETICK 24
#define ELMC_UNION_GOTBATTERYLEVEL 31
#define ELMC_UNION_GOTCLOCKSTYLE24H 18
#define ELMC_UNION_GOTCOMPASSHEADING 41
#define ELMC_UNION_GOTCONNECTIONSTATUS 32
#define ELMC_UNION_GOTCURRENTDATETIME 16
#define ELMC_UNION_GOTFIRMWAREVERSION 30
#define ELMC_UNION_GOTHEALTHACCESSIBLE 36
#define ELMC_UNION_GOTHEALTHSUM 35
#define ELMC_UNION_GOTHEALTHSUMTODAY 34
#define ELMC_UNION_GOTHEALTHVALUE 33
#define ELMC_UNION_GOTMAXSIZE 22
#define ELMC_UNION_GOTSTORAGESTRING 23
#define ELMC_UNION_GOTSTOREDINT 21
#define ELMC_UNION_GOTTIME 17
#define ELMC_UNION_GOTTIMEZONE 20
#define ELMC_UNION_GOTTIMEZONEISSET 19
#define ELMC_UNION_GOTWATCHCOLOR 29
#define ELMC_UNION_GOTWATCHMODEL 28
#define ELMC_UNION_HEALTHEVENT 37
#define ELMC_UNION_HOURCHANGED 11
#define ELMC_UNION_LAUNCHPHONE 3
#define ELMC_UNION_LAUNCHQUICKLAUNCH 6
#define ELMC_UNION_LAUNCHSMARTSTRAP 8
#define ELMC_UNION_LAUNCHSYSTEM 1
#define ELMC_UNION_LAUNCHTIMELINEACTION 7
#define ELMC_UNION_LAUNCHUNKNOWN 9
#define ELMC_UNION_LAUNCHUSER 2
#define ELMC_UNION_LAUNCHWAKEUP 4
#define ELMC_UNION_LAUNCHWORKER 5
#define ELMC_UNION_LIGHTCHANGED 38
#define ELMC_UNION_MAIN_ACCELDATA 27
#define ELMC_UNION_MAIN_ACCELTAP 8
#define ELMC_UNION_MAIN_ANIMATIONFINISHED 44
#define ELMC_UNION_MAIN_APPFOCUSCHANGED 39
#define ELMC_UNION_MAIN_BATTERYCHANGED 9
#define ELMC_UNION_MAIN_BUTTONDOWN 4
#define ELMC_UNION_MAIN_BUTTONLONGDOWN 7
#define ELMC_UNION_MAIN_BUTTONLONGSELECT 6
#define ELMC_UNION_MAIN_BUTTONLONGUP 5
#define ELMC_UNION_MAIN_BUTTONSELECT 3
#define ELMC_UNION_MAIN_BUTTONUP 2
#define ELMC_UNION_MAIN_COMPASSCHANGED 40
#define ELMC_UNION_MAIN_CONNECTIONCHANGED 10
#define ELMC_UNION_MAIN_DAYCHANGED 13
#define ELMC_UNION_MAIN_DICTATIONRESULT 43
#define ELMC_UNION_MAIN_DICTATIONSTATUS 42
#define ELMC_UNION_MAIN_FRAMETICK 24
#define ELMC_UNION_MAIN_GOTBATTERYLEVEL 31
#define ELMC_UNION_MAIN_GOTCLOCKSTYLE24H 18
#define ELMC_UNION_MAIN_GOTCOMPASSHEADING 41
#define ELMC_UNION_MAIN_GOTCONNECTIONSTATUS 32
#define ELMC_UNION_MAIN_GOTCURRENTDATETIME 16
#define ELMC_UNION_MAIN_GOTFIRMWAREVERSION 30
#define ELMC_UNION_MAIN_GOTHEALTHACCESSIBLE 36
#define ELMC_UNION_MAIN_GOTHEALTHSUM 35
#define ELMC_UNION_MAIN_GOTHEALTHSUMTODAY 34
#define ELMC_UNION_MAIN_GOTHEALTHVALUE 33
#define ELMC_UNION_MAIN_GOTMAXSIZE 22
#define ELMC_UNION_MAIN_GOTSTORAGESTRING 23
#define ELMC_UNION_MAIN_GOTSTOREDINT 21
#define ELMC_UNION_MAIN_GOTTIME 17
#define ELMC_UNION_MAIN_GOTTIMEZONE 20
#define ELMC_UNION_MAIN_GOTTIMEZONEISSET 19
#define ELMC_UNION_MAIN_GOTWATCHCOLOR 29
#define ELMC_UNION_MAIN_GOTWATCHMODEL 28
#define ELMC_UNION_MAIN_HEALTHEVENT 37
#define ELMC_UNION_MAIN_HOURCHANGED 11
#define ELMC_UNION_MAIN_LIGHTCHANGED 38
#define ELMC_UNION_MAIN_MINUTECHANGED 12
#define ELMC_UNION_MAIN_MONTHCHANGED 14
#define ELMC_UNION_MAIN_TICK 1
#define ELMC_UNION_MAIN_UPPRESSED 25
#define ELMC_UNION_MAIN_UPRELEASED 26
#define ELMC_UNION_MAIN_YEARCHANGED 15
#define ELMC_UNION_MINUTECHANGED 12
#define ELMC_UNION_MONTHCHANGED 14
#define ELMC_UNION_PEBBLE_BUTTON_DOWN 4
#define ELMC_UNION_PEBBLE_BUTTON_PRESSED 1
#define ELMC_UNION_PEBBLE_BUTTON_RELEASED 2
#define ELMC_UNION_PEBBLE_BUTTON_SELECT 3
#define ELMC_UNION_PEBBLE_BUTTON_UP 2
#define ELMC_UNION_PEBBLE_HEALTH_ACTIVESECONDS 2
#define ELMC_UNION_PEBBLE_HEALTH_STEPCOUNT 1
#define ELMC_UNION_PEBBLE_HEALTH_WALKEDDISTANCEMETERS 3
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHPHONE 3
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHQUICKLAUNCH 6
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHSMARTSTRAP 8
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHSYSTEM 1
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHTIMELINEACTION 7
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHUNKNOWN 9
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHUSER 2
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHWAKEUP 4
#define ELMC_UNION_PEBBLE_PLATFORM_LAUNCHWORKER 5
#define ELMC_UNION_PEBBLE_UI_RESOURCES_DEFAULTFONT 1
#define ELMC_UNION_PEBBLE_UI_ROTATION 1
#define ELMC_UNION_PRESSED 1
#define ELMC_UNION_RELEASED 2
#define ELMC_UNION_ROTATION 1
#define ELMC_UNION_SELECT 3
#define ELMC_UNION_STEPCOUNT 1
#define ELMC_UNION_TICK 1
#define ELMC_UNION_UP 2
#define ELMC_UNION_UPPRESSED 25
#define ELMC_UNION_UPRELEASED 26
#define ELMC_UNION_WALKEDDISTANCEMETERS 3
#define ELMC_UNION_YEARCHANGED 15

const char *elmc_debug_union_ctor_name(elmc_int_t tag) {
  switch (tag) {
    case 10: return "ConnectionChanged";
    case 11: return "HourChanged";
    case 12: return "MinuteChanged";
    case 13: return "DayChanged";
    case 14: return "MonthChanged";
    case 15: return "YearChanged";
    case 16: return "GotCurrentDateTime";
    case 17: return "GotTime";
    case 18: return "GotClockStyle24h";
    case 19: return "GotTimezoneIsSet";
    case 20: return "GotTimezone";
    case 21: return "GotStoredInt";
    case 22: return "GotMaxSize";
    case 23: return "GotStorageString";
    case 24: return "FrameTick";
    case 25: return "UpPressed";
    case 26: return "UpReleased";
    case 27: return "AccelData";
    case 28: return "GotWatchModel";
    case 29: return "GotWatchColor";
    case 30: return "GotFirmwareVersion";
    case 31: return "GotBatteryLevel";
    case 32: return "GotConnectionStatus";
    case 33: return "GotHealthValue";
    case 34: return "GotHealthSumToday";
    case 35: return "GotHealthSum";
    case 36: return "GotHealthAccessible";
    case 37: return "HealthEvent";
    case 38: return "LightChanged";
    case 39: return "AppFocusChanged";
    case 40: return "CompassChanged";
    case 41: return "GotCompassHeading";
    case 42: return "DictationStatus";
    case 43: return "DictationResult";
    case 44: return "AnimationFinished";
    default: return NULL;
  }
}

#define ELMC_FIELD_MAIN_MODEL_LATESTTIME 1
#define ELMC_FIELD_MAIN_MODEL_TICKS 0
#define ELMC_FIELD_PEBBLE_ACCEL_CONFIG_SAMPLESPERUPDATE 0
#define ELMC_FIELD_PEBBLE_ACCEL_CONFIG_SAMPLINGRATE 1
#define ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_X 0
#define ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_Y 1
#define ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_Z 2
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_DAY 2
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_DAYOFWEEK 3
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_HOUR 4
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_MINUTE 5
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_MONTH 1
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_SECOND 6
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_UTCOFFSETMINUTES 7
#define ELMC_FIELD_PEBBLE_CMD_CURRENTDATETIME_YEAR 0
#define ELMC_FIELD_PEBBLE_COMPASS_HEADING_DEGREES 0
#define ELMC_FIELD_PEBBLE_COMPASS_HEADING_ISVALID 1
#define ELMC_FIELD_PEBBLE_FRAME_FRAME_DTMS 0
#define ELMC_FIELD_PEBBLE_FRAME_FRAME_ELAPSEDMS 1
#define ELMC_FIELD_PEBBLE_FRAME_FRAME_FRAME 2
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_R 2
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_X 0
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_CIRCLE_Y 1
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_H 3
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_W 2
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_X 0
#define ELMC_FIELD_PEBBLE_GAME_COLLISION_RECT_Y 1
#define ELMC_FIELD_PEBBLE_GAME_MATH_VEC2_X 0
#define ELMC_FIELD_PEBBLE_GAME_MATH_VEC2_Y 1
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_BITMAP 0
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_H 4
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_W 3
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_X 1
#define ELMC_FIELD_PEBBLE_GAME_SPRITE_SPRITE_Y 2
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_HASCOMPASS 5
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_HASMICROPHONE 4
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_LAUNCHBUTTON 7
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_QUICKLAUNCHACTION 8
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON 0
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SCREEN 3
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_SUPPORTSHEALTH 6
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_WATCHMODEL 1
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_WATCHPROFILEID 2
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_COLORMODE 3
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_HEIGHT 1
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_SHAPE 2
#define ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHSCREEN_WIDTH 0
#define ELMC_FIELD_PEBBLE_SPEAKER_LIMITS_MAXNOTES 0
#define ELMC_FIELD_PEBBLE_SPEAKER_LIMITS_MAXSAMPLEBYTESTOTAL 2
#define ELMC_FIELD_PEBBLE_SPEAKER_LIMITS_MAXTRACKS 1
#define ELMC_FIELD_PEBBLE_SPEAKER_NOTE_DURATIONMS 2
#define ELMC_FIELD_PEBBLE_SPEAKER_NOTE_MIDINOTE 0
#define ELMC_FIELD_PEBBLE_SPEAKER_NOTE_VELOCITY 3
#define ELMC_FIELD_PEBBLE_SPEAKER_NOTE_WAVEFORM 1
#define ELMC_FIELD_PEBBLE_SPEAKER_TRACK_NOTES 0
#define ELMC_FIELD_PEBBLE_SPEAKER_TRACK_SAMPLE 1
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_BASEMIDINOTE 3
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_FORMAT 2
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_LOOP 4
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_NAME 1
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_NUMBYTES 5
#define ELMC_FIELD_PEBBLE_SPEAKER_RESOURCES_SAMPLEINFO_SAMPLE 0
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_DAY 2
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_DAYOFWEEK 3
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_HOUR 4
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MINUTE 5
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_MONTH 1
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_SECOND 6
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_UTCOFFSETMINUTES 7
#define ELMC_FIELD_PEBBLE_TIME_CURRENTDATETIME_YEAR 0
#define ELMC_FIELD_PEBBLE_UI_POINT_X 0
#define ELMC_FIELD_PEBBLE_UI_POINT_Y 1
#define ELMC_FIELD_PEBBLE_UI_RECT_H 3
#define ELMC_FIELD_PEBBLE_UI_RECT_W 2
#define ELMC_FIELD_PEBBLE_UI_RECT_X 0
#define ELMC_FIELD_PEBBLE_UI_RECT_Y 1
#define ELMC_FIELD_PEBBLE_UI_TEXTOPTIONS_ALIGNMENT 0
#define ELMC_FIELD_PEBBLE_UI_TEXTOPTIONS_OVERFLOW 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_ANIMATEDBITMAP 0
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_DURATIONMS 5
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_FRAMECOUNT 4
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_HEIGHT 3
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDBITMAPINFO_WIDTH 2
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDVECTORINFO_ANIMATEDVECTOR 0
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_ANIMATEDVECTORINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_FONTINFO_FONT 0
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_FONTINFO_HEIGHT 2
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_FONTINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_HEIGHT 3
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_STATICBITMAP 0
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICBITMAPINFO_WIDTH 2
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICVECTORINFO_NAME 1
#define ELMC_FIELD_PEBBLE_UI_RESOURCES_STATICVECTORINFO_STATICVECTOR 0
#define ELMC_FIELD_PEBBLE_WATCHINFO_FIRMWAREVERSION_MAJOR 0
#define ELMC_FIELD_PEBBLE_WATCHINFO_FIRMWAREVERSION_MINOR 1
#define ELMC_FIELD_PEBBLE_WATCHINFO_FIRMWAREVERSION_PATCH 2

#define ELMC_RENDER_OP_CLEAR 2
#define ELMC_RENDER_OP_TEXT_INT_WITH_FONT 27
#define ELMC_BUTTON_UP 1
#define ELMC_BUTTON_SELECT 2
#define ELMC_BUTTON_DOWN 3
#define ELMC_BUTTON_EVENT_PRESSED 1
#define ELMC_BUTTON_EVENT_RELEASED 2
#define ELMC_BUTTON_EVENT_LONG_PRESSED 3
#define ELMC_SUBSCRIPTION_SECOND_CHANGE 1
#define ELMC_SUBSCRIPTION_ACCEL_TAP 16
#define ELMC_SUBSCRIPTION_BATTERY 32
#define ELMC_SUBSCRIPTION_CONNECTION 64
#define ELMC_SUBSCRIPTION_HOUR_CHANGE 1024
#define ELMC_SUBSCRIPTION_MINUTE_CHANGE 2048
#define ELMC_SUBSCRIPTION_FRAME_BASE 8192
#define ELMC_SUBSCRIPTION_BUTTON_RAW 16384
#define ELMC_SUBSCRIPTION_DAY_CHANGE 65536
#define ELMC_SUBSCRIPTION_MONTH_CHANGE 131072
#define ELMC_SUBSCRIPTION_YEAR_CHANGE 262144
#define ELMC_SUBSCRIPTION_ACCEL_DATA 32768
#define ELMC_SUBSCRIPTION_APP_FOCUS 524288
#define ELMC_SUBSCRIPTION_BACKLIGHT 16777216
#define ELMC_SUBSCRIPTION_COMPASS 1048576
#define ELMC_SUBSCRIPTION_DICTATION 2097152
#define ELMC_SUBSCRIPTION_ANIMATION_FINISHED 8388608
#define ELMC_SUBSCRIPTION_HEALTH 2147483648LL
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

static elmc_int_t elmc_fn_Main_parseHourFromTimeString_native(ElmcValue * const value);

static ElmcValue *elmc_fn_Main_parseHourFromTimeString(ElmcValue ** const args, const int argc);
RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_DataLog_tag(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Log_infoCode(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Log_warnCode(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Log_errorCode(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Pebble_Wakeup_cancel(ElmcValue **out, ElmcValue ** const args, const int argc);

static ElmcValue *elmc_partial_union_1(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
  (void)capture_count;
  ElmcValue *result = NULL;
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    ElmcValue *all_args[1] = {0};

    all_args[0] = (argc > 0) ? args[0] : NULL;
    ElmcValue *payload = elmc_build_constructor_payload(all_args, 1);
    ElmcValue *tag = captures[0] ? elmc_retain(captures[0]) : elmc_int_zero();
    Rc = elmc_tuple2_take(&result, tag, payload);
    CHECK_RC(Rc);
  CATCH_END
  return result;
}

static ElmcValue *elmc_fn_Main_parseHourFromTimeString(ElmcValue ** const args, const int argc) {
  /* Ownership policy: retain_arg, retain_result */

  ElmcValue *value = (argc > 0) ? args[0] : NULL;

  ElmcValue *out = NULL;
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    Rc = elmc_new_int(&out, elmc_fn_Main_parseHourFromTimeString_native(value));
    CHECK_RC(Rc);
  CATCH_END
  return out;
}

static elmc_int_t elmc_fn_Main_parseHourFromTimeString_native(ElmcValue * const value) {

  /* elm/core: String.toInt */

  /* elm/core: String.left */

  ElmcValue *tmp_1 = elmc_new_int_take(2);

  ElmcValue *tmp_2 = elmc_string_left(tmp_1, value);
  elmc_release(tmp_1);

  ElmcValue *tmp_3 = elmc_string_to_int(tmp_2);
  elmc_release(tmp_2);

  const elmc_int_t native_maybe_default_4 = elmc_maybe_with_default_int(0, tmp_3);
  elmc_release(tmp_3);

  return native_maybe_default_4;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[74] = {0};

  ElmcValue *launchContext = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *call_args_1[1] = { ELMC_RECORD_GET_INDEX(launchContext, ELMC_FIELD_PEBBLE_PLATFORM_LAUNCHCONTEXT_REASON) };
    Rc = elmc_fn_Pebble_Platform_launchReasonToInt(&owned[0], call_args_1, 1);
    CHECK_RC(Rc);

    const elmc_int_t native_i_3 = elmc_as_int(owned[0]);
    ;

    const elmc_int_t native_let_launchReasonValue_4 = native_i_3;

    ElmcValue *tmp_4_boxed_int = NULL;
    Rc = elmc_new_int(&tmp_4_boxed_int, native_let_launchReasonValue_4);
    CHECK_RC(Rc);

    Rc = elmc_new_string(&owned[1], "00:00");
    CHECK_RC(Rc);

    ElmcValue *rec_values_1[2] = { tmp_4_boxed_int, owned[1] };
    Rc = elmc_record_new_values_take(&owned[2], 2, rec_values_1);
    CHECK_RC(Rc);
    owned[1] = NULL;

    Rc = elmc_new_int(&owned[3], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);

    ElmcValue *tmp_5 = elmc_cmd1(ELMC_PEBBLE_CMD_TIMER_AFTER_MS, 1000);

    ElmcValue *tmp_6 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_GOTCURRENTDATETIME);

    ElmcValue *tmp_7 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_DATE_TIME, ELMC_PEBBLE_MSG_GOTCURRENTDATETIME);

    ElmcValue *tmp_8 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING, ELMC_PEBBLE_MSG_GOTTIME);

    ElmcValue *tmp_9 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H, ELMC_PEBBLE_MSG_GOTCLOCKSTYLE24H);

    ElmcValue *tmp_10 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET, ELMC_PEBBLE_MSG_GOTTIMEZONEISSET);

    ElmcValue *tmp_11 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_TIMEZONE, ELMC_PEBBLE_MSG_GOTTIMEZONE);

    ElmcValue *tmp_12 = elmc_cmd2(ELMC_PEBBLE_CMD_STORAGE_WRITE_INT, 7, 42);

    ElmcValue *tmp_13 = elmc_cmd2(ELMC_PEBBLE_CMD_STORAGE_READ_INT, 7, ELMC_PEBBLE_MSG_GOTSTOREDINT);

    ElmcValue *tmp_14 = elmc_cmd1(ELMC_PEBBLE_CMD_STORAGE_READ_MAX_SIZE, ELMC_PEBBLE_MSG_GOTMAXSIZE);

    Rc = elmc_new_int(&owned[4], ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[5], 8);
    CHECK_RC(Rc);
    Rc = elmc_new_string(&owned[6], "saved");
    CHECK_RC(Rc);

    owned[7] = elmc_int_zero();
    owned[8] = elmc_int_zero();

    Rc = elmc_tuple2_ints(&owned[9], 0, 0);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(&owned[10], owned[8], owned[9]);
    CHECK_RC(Rc);
    owned[8] = NULL;
    owned[9] = NULL;

    Rc = elmc_tuple2_take(&owned[11], owned[7], owned[10]);
    CHECK_RC(Rc);
    owned[7] = NULL;
    owned[10] = NULL;

    Rc = elmc_tuple2_take(&owned[12], owned[6], owned[11]);
    CHECK_RC(Rc);
    owned[6] = NULL;
    owned[11] = NULL;

    Rc = elmc_tuple2_take(&owned[13], owned[5], owned[12]);
    CHECK_RC(Rc);
    owned[5] = NULL;
    owned[12] = NULL;

    Rc = elmc_tuple2_take(&owned[14], owned[4], owned[13]);
    CHECK_RC(Rc);
    owned[4] = NULL;
    owned[13] = NULL;

    ElmcValue *tmp_16 = elmc_cmd2(ELMC_PEBBLE_CMD_STORAGE_READ_STRING, 8, ELMC_PEBBLE_MSG_GOTSTORAGESTRING);

    ElmcValue *tmp_17 = elmc_cmd1(ELMC_PEBBLE_CMD_STORAGE_DELETE, 7);

    ElmcValue *tmp_18 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_WATCH_MODEL, ELMC_PEBBLE_MSG_GOTWATCHMODEL);

    ElmcValue *tmp_19 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_WATCH_COLOR, ELMC_PEBBLE_MSG_GOTWATCHCOLOR);

    ElmcValue *tmp_20 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_FIRMWARE_VERSION, ELMC_PEBBLE_MSG_GOTFIRMWAREVERSION);

    ElmcValue *tmp_21 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_BATTERY_LEVEL, ELMC_PEBBLE_MSG_GOTBATTERYLEVEL);

    ElmcValue *tmp_22 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CONNECTION_STATUS, ELMC_PEBBLE_MSG_GOTCONNECTIONSTATUS);

    ElmcValue *tmp_23 = elmc_cmd2(ELMC_PEBBLE_CMD_HEALTH_VALUE, 1, ELMC_PEBBLE_MSG_GOTHEALTHVALUE);

    ElmcValue *tmp_24 = elmc_cmd2(ELMC_PEBBLE_CMD_HEALTH_SUM_TODAY, 1, ELMC_PEBBLE_MSG_GOTHEALTHSUMTODAY);

    ElmcValue *tmp_25 = elmc_cmd4(ELMC_PEBBLE_CMD_HEALTH_SUM, 3, 0, 3600, ELMC_PEBBLE_MSG_GOTHEALTHSUM);

    ElmcValue *tmp_26 = elmc_cmd4(ELMC_PEBBLE_CMD_HEALTH_ACCESSIBLE, 2, 0, 3600, ELMC_PEBBLE_MSG_GOTHEALTHACCESSIBLE);

    ElmcValue *tmp_27 = elmc_cmd1(ELMC_PEBBLE_CMD_BACKLIGHT, 0);

    ElmcValue *tmp_28 = elmc_cmd1(ELMC_PEBBLE_CMD_BACKLIGHT, 1);

    ElmcValue *tmp_29 = elmc_cmd1(ELMC_PEBBLE_CMD_BACKLIGHT, 2);

    Rc = elmc_new_int(&owned[15], ELMC_PEBBLE_CMD_VIBES_CANCEL);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[16], ELMC_PEBBLE_CMD_VIBES_SHORT_PULSE);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[17], ELMC_PEBBLE_CMD_VIBES_LONG_PULSE);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[18], ELMC_PEBBLE_CMD_VIBES_DOUBLE_PULSE);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[19], ELMC_PEBBLE_CMD_VIBES_CUSTOM_PATTERN);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[20], 100);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[21], 50);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[22], 100);
    CHECK_RC(Rc);
    ElmcValue *list_items_30[3] = { owned[20], owned[21], owned[22] };
    Rc = elmc_list_from_values_take(&owned[23], list_items_30, 3);
    CHECK_RC(Rc);
    owned[20] = NULL;
    owned[21] = NULL;
    owned[22] = NULL;

    owned[24] = elmc_int_zero();
    owned[25] = elmc_int_zero();
    owned[26] = elmc_int_zero();

    Rc = elmc_tuple2_ints(&owned[27], 0, 0);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(&owned[28], owned[26], owned[27]);
    CHECK_RC(Rc);
    owned[26] = NULL;
    owned[27] = NULL;

    Rc = elmc_tuple2_take(&owned[29], owned[25], owned[28]);
    CHECK_RC(Rc);
    owned[25] = NULL;
    owned[28] = NULL;

    Rc = elmc_tuple2_take(&owned[30], owned[24], owned[29]);
    CHECK_RC(Rc);
    owned[24] = NULL;
    owned[29] = NULL;

    Rc = elmc_tuple2_take(&owned[31], owned[23], owned[30]);
    CHECK_RC(Rc);
    owned[23] = NULL;
    owned[30] = NULL;

    Rc = elmc_tuple2_take(&owned[32], owned[19], owned[31]);
    CHECK_RC(Rc);
    owned[19] = NULL;
    owned[31] = NULL;

    Rc = elmc_new_int(&owned[33], ELMC_PEBBLE_CMD_DATA_LOG_BYTES);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[34], 42);
    CHECK_RC(Rc);

    ElmcValue *head_36 = NULL;
    Rc = elmc_fn_Pebble_DataLog_tag(&head_36, NULL, 0);
    CHECK_RC(Rc);
    ElmcValue *call_args_36[1] = { owned[34] };
    owned[35] = elmc_closure_call(head_36, call_args_36, 1);

    elmc_release(head_36);;

    Rc = elmc_new_int(&owned[36], 1);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[37], 2);
    CHECK_RC(Rc);
    Rc = elmc_new_int(&owned[38], 3);
    CHECK_RC(Rc);
    ElmcValue *list_items_40[3] = { owned[36], owned[37], owned[38] };
    Rc = elmc_list_from_values_take(&owned[39], list_items_40, 3);
    CHECK_RC(Rc);
    owned[36] = NULL;
    owned[37] = NULL;
    owned[38] = NULL;

    owned[40] = elmc_int_zero();
    owned[41] = elmc_int_zero();

    Rc = elmc_tuple2_ints(&owned[42], 0, 0);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(&owned[43], owned[41], owned[42]);
    CHECK_RC(Rc);
    owned[41] = NULL;
    owned[42] = NULL;

    Rc = elmc_tuple2_take(&owned[44], owned[40], owned[43]);
    CHECK_RC(Rc);
    owned[40] = NULL;
    owned[43] = NULL;

    Rc = elmc_tuple2_take(&owned[45], owned[39], owned[44]);
    CHECK_RC(Rc);
    owned[39] = NULL;
    owned[44] = NULL;

    Rc = elmc_tuple2_take(&owned[46], owned[35], owned[45]);
    CHECK_RC(Rc);
    owned[35] = NULL;
    owned[45] = NULL;

    Rc = elmc_tuple2_take(&owned[47], owned[33], owned[46]);
    CHECK_RC(Rc);
    owned[33] = NULL;
    owned[46] = NULL;

    Rc = elmc_new_int(&owned[48], ELMC_PEBBLE_CMD_DATA_LOG_INT32);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[49], 43);
    CHECK_RC(Rc);

    ElmcValue *head_51 = NULL;
    Rc = elmc_fn_Pebble_DataLog_tag(&head_51, NULL, 0);
    CHECK_RC(Rc);
    ElmcValue *call_args_51[1] = { owned[49] };
    owned[50] = elmc_closure_call(head_51, call_args_51, 1);

    elmc_release(head_51);;

    Rc = elmc_new_int(&owned[51], 9001);
    CHECK_RC(Rc);
    owned[52] = elmc_int_zero();
    owned[53] = elmc_int_zero();

    Rc = elmc_tuple2_ints(&owned[54], 0, 0);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(&owned[55], owned[53], owned[54]);
    CHECK_RC(Rc);
    owned[53] = NULL;
    owned[54] = NULL;

    Rc = elmc_tuple2_take(&owned[56], owned[52], owned[55]);
    CHECK_RC(Rc);
    owned[52] = NULL;
    owned[55] = NULL;

    Rc = elmc_tuple2_take(&owned[57], owned[51], owned[56]);
    CHECK_RC(Rc);
    owned[51] = NULL;
    owned[56] = NULL;

    Rc = elmc_tuple2_take(&owned[58], owned[50], owned[57]);
    CHECK_RC(Rc);
    owned[50] = NULL;
    owned[57] = NULL;

    Rc = elmc_tuple2_take(&owned[59], owned[48], owned[58]);
    CHECK_RC(Rc);
    owned[48] = NULL;
    owned[58] = NULL;

    ElmcValue *tmp_61 = elmc_cmd1(ELMC_PEBBLE_CMD_COMPASS_PEEK, ELMC_PEBBLE_MSG_GOTCOMPASSHEADING);

    Rc = elmc_new_int(&owned[60], ELMC_PEBBLE_CMD_DICTATION_START);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[61], ELMC_PEBBLE_CMD_DICTATION_STOP);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[62], 60);
    CHECK_RC(Rc);

    ElmcValue *head_64 = NULL;
    Rc = elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(&head_64, NULL, 0);
    CHECK_RC(Rc);
    ElmcValue *call_args_64[1] = { owned[62] };
    owned[63] = elmc_closure_call(head_64, call_args_64, 1);

    elmc_release(head_64);;

    Rc = elmc_new_int(&owned[64], 1);
    CHECK_RC(Rc);

    ElmcValue *head_66 = NULL;
    Rc = elmc_fn_Pebble_Wakeup_cancel(&head_66, NULL, 0);
    CHECK_RC(Rc);
    ElmcValue *call_args_66[1] = { owned[64] };
    owned[65] = elmc_closure_call(head_66, call_args_66, 1);

    elmc_release(head_66);;

    Rc = elmc_new_int(&owned[66], 101);
    CHECK_RC(Rc);

    ElmcValue *head_68 = NULL;
    Rc = elmc_fn_Pebble_Log_infoCode(&head_68, NULL, 0);
    CHECK_RC(Rc);
    ElmcValue *call_args_68[1] = { owned[66] };
    owned[67] = elmc_closure_call(head_68, call_args_68, 1);

    elmc_release(head_68);;

    Rc = elmc_new_int(&owned[68], 202);
    CHECK_RC(Rc);

    ElmcValue *head_70 = NULL;
    Rc = elmc_fn_Pebble_Log_warnCode(&head_70, NULL, 0);
    CHECK_RC(Rc);
    ElmcValue *call_args_70[1] = { owned[68] };
    owned[69] = elmc_closure_call(head_70, call_args_70, 1);

    elmc_release(head_70);;

    Rc = elmc_new_int(&owned[70], 303);
    CHECK_RC(Rc);

    ElmcValue *head_72 = NULL;
    Rc = elmc_fn_Pebble_Log_errorCode(&head_72, NULL, 0);
    CHECK_RC(Rc);
    ElmcValue *call_args_72[1] = { owned[70] };
    owned[71] = elmc_closure_call(head_72, call_args_72, 1);

    elmc_release(head_72);;

    ElmcValue *list_items_74[41] = { owned[3], tmp_5, tmp_6, tmp_7, tmp_8, tmp_9, tmp_10, tmp_11, tmp_12, tmp_13, tmp_14, owned[14], tmp_16, tmp_17, tmp_18, tmp_19, tmp_20, tmp_21, tmp_22, tmp_23, tmp_24, tmp_25, tmp_26, tmp_27, tmp_28, tmp_29, owned[15], owned[16], owned[17], owned[18], owned[32], owned[47], owned[59], tmp_61, owned[60], owned[61], owned[63], owned[65], owned[67], owned[69], owned[71] };
    Rc = elmc_list_from_values_take(&owned[72], list_items_74, 41);
    CHECK_RC(Rc);
    owned[3] = NULL;
    owned[14] = NULL;
    owned[15] = NULL;
    owned[16] = NULL;
    owned[17] = NULL;
    owned[18] = NULL;
    owned[32] = NULL;
    owned[47] = NULL;
    owned[59] = NULL;
    owned[60] = NULL;
    owned[61] = NULL;
    owned[63] = NULL;
    owned[65] = NULL;
    owned[67] = NULL;
    owned[69] = NULL;
    owned[71] = NULL;

    owned[73] = elmc_cmd_batch(owned[72]);

    Rc = elmc_tuple2_take(out, owned[2], owned[73]);
    CHECK_RC(Rc);
    owned[2] = NULL;
    owned[73] = NULL;

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[106] = {0};

  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));

    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_TICK: {

        Rc = elmc_new_int(&owned[0], ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_TICKS) + 1);
        CHECK_RC(Rc);

        ElmcValue *tmp_2 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[0]);

        ElmcValue *tmp_3 = elmc_cmd1(ELMC_PEBBLE_CMD_TIMER_AFTER_MS, 1000);

        Rc = elmc_tuple2_take(out, tmp_2, tmp_3);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_PEBBLE_MSG_BUTTONUP: {
        owned[1] = model ? elmc_retain(model) : elmc_int_zero();

        ElmcValue *tmp_4 = elmc_cmd2(ELMC_PEBBLE_CMD_STORAGE_WRITE_INT, 10, (ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_TICKS) + 1));

        Rc = elmc_tuple2_take(out, owned[1], tmp_4);
        CHECK_RC(Rc);
        owned[1] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_BUTTONSELECT: {
        owned[2] = model ? elmc_retain(model) : elmc_int_zero();

        ElmcValue *tmp_5 = elmc_cmd1(ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING, ELMC_PEBBLE_MSG_GOTTIME);

        Rc = elmc_tuple2_take(out, owned[2], tmp_5);
        CHECK_RC(Rc);
        owned[2] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_BUTTONDOWN: {
        owned[3] = model ? elmc_retain(model) : elmc_int_zero();

        ElmcValue *tmp_6 = elmc_cmd1(ELMC_PEBBLE_CMD_STORAGE_DELETE, 10);

        Rc = elmc_tuple2_take(out, owned[3], tmp_6);
        CHECK_RC(Rc);
        owned[3] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_BUTTONLONGUP: {
        owned[4] = model ? elmc_retain(model) : elmc_int_zero();

        Rc = elmc_new_int(&owned[5], 606);
        CHECK_RC(Rc);

        ElmcValue *head_7 = NULL;
        Rc = elmc_fn_Pebble_Log_infoCode(&head_7, NULL, 0);
        CHECK_RC(Rc);
        ElmcValue *call_args_7[1] = { owned[5] };
        owned[6] = elmc_closure_call(head_7, call_args_7, 1);

        elmc_release(head_7);;

        Rc = elmc_tuple2_take(out, owned[4], owned[6]);
        CHECK_RC(Rc);
        owned[4] = NULL;
        owned[6] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_BUTTONLONGSELECT: {
        owned[7] = model ? elmc_retain(model) : elmc_int_zero();

        Rc = elmc_new_int(&owned[8], 707);
        CHECK_RC(Rc);

        ElmcValue *head_10 = NULL;
        Rc = elmc_fn_Pebble_Log_warnCode(&head_10, NULL, 0);
        CHECK_RC(Rc);
        ElmcValue *call_args_10[1] = { owned[8] };
        owned[9] = elmc_closure_call(head_10, call_args_10, 1);

        elmc_release(head_10);;

        Rc = elmc_tuple2_take(out, owned[7], owned[9]);
        CHECK_RC(Rc);
        owned[7] = NULL;
        owned[9] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_BUTTONLONGDOWN: {
        owned[10] = model ? elmc_retain(model) : elmc_int_zero();

        Rc = elmc_new_int(&owned[11], 808);
        CHECK_RC(Rc);

        ElmcValue *head_13 = NULL;
        Rc = elmc_fn_Pebble_Log_errorCode(&head_13, NULL, 0);
        CHECK_RC(Rc);
        ElmcValue *call_args_13[1] = { owned[11] };
        owned[12] = elmc_closure_call(head_13, call_args_13, 1);

        elmc_release(head_13);;

        Rc = elmc_tuple2_take(out, owned[10], owned[12]);
        CHECK_RC(Rc);
        owned[10] = NULL;
        owned[12] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_ACCELTAP: {
        owned[13] = model ? elmc_retain(model) : elmc_int_zero();
        Rc = elmc_new_int(&owned[14], ELMC_PEBBLE_CMD_VIBES_SHORT_PULSE);
        CHECK_RC(Rc);

        Rc = elmc_tuple2_take(out, owned[13], owned[14]);
        CHECK_RC(Rc);
        owned[13] = NULL;
        owned[14] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_BATTERYCHANGED: {

        owned[15] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[16] = model ? elmc_retain(model) : elmc_int_zero();

        Rc = elmc_new_int(&owned[17], 404);
        CHECK_RC(Rc);

        ElmcValue *head_19 = NULL;
        Rc = elmc_fn_Pebble_Log_infoCode(&head_19, NULL, 0);
        CHECK_RC(Rc);
        ElmcValue *call_args_19[1] = { owned[17] };
        owned[18] = elmc_closure_call(head_19, call_args_19, 1);

        elmc_release(head_19);;

        Rc = elmc_tuple2_take(out, owned[16], owned[18]);
        CHECK_RC(Rc);
        owned[16] = NULL;
        owned[18] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_CONNECTIONCHANGED: {

        owned[19] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[20] = model ? elmc_retain(model) : elmc_int_zero();

        Rc = elmc_new_int(&owned[21], 505);
        CHECK_RC(Rc);

        ElmcValue *head_23 = NULL;
        Rc = elmc_fn_Pebble_Log_warnCode(&head_23, NULL, 0);
        CHECK_RC(Rc);
        ElmcValue *call_args_23[1] = { owned[21] };
        owned[22] = elmc_closure_call(head_23, call_args_23, 1);

        elmc_release(head_23);;

        Rc = elmc_tuple2_take(out, owned[20], owned[22]);
        CHECK_RC(Rc);
        owned[20] = NULL;
        owned[22] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_HOURCHANGED: {

        owned[23] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_25 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[23]);

        owned[24] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_25, owned[24]);
        CHECK_RC(Rc);
        owned[24] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_MINUTECHANGED: {

        owned[25] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_27 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[25]);

        owned[26] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_27, owned[26]);
        CHECK_RC(Rc);
        owned[26] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_DAYCHANGED: {

        owned[27] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_29 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[27]);

        owned[28] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_29, owned[28]);
        CHECK_RC(Rc);
        owned[28] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_MONTHCHANGED: {

        owned[29] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_31 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[29]);

        owned[30] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_31, owned[30]);
        CHECK_RC(Rc);
        owned[30] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_YEARCHANGED: {

        owned[31] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_33 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[31]);

        owned[32] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_33, owned[32]);
        CHECK_RC(Rc);
        owned[32] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTCURRENTDATETIME: {

        owned[33] = elmc_record_get_index(((ElmcTuple2 *)msg->payload)->second, 4 /* hour */);

        ElmcValue *tmp_35 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[33]);

        owned[34] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_35, owned[34]);
        CHECK_RC(Rc);
        owned[34] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTTIME: {

        owned[35] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_37 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_LATESTTIME, owned[35]);

        owned[36] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        const elmc_int_t native_call_38 = elmc_fn_Main_parseHourFromTimeString_native(owned[36]);

        ElmcValue *tmp_39 = NULL;
        Rc = elmc_new_int(&tmp_39, native_call_38);
        CHECK_RC(Rc);

        ElmcValue *tmp_40 = elmc_record_update_index_cow_drop(tmp_37, ELMC_FIELD_MAIN_MODEL_TICKS, tmp_39);

        elmc_release(tmp_39);

        owned[37] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_40, owned[37]);
        CHECK_RC(Rc);
        owned[37] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTSTOREDINT: {

        owned[38] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_41 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[38]);

        owned[39] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_41, owned[39]);
        CHECK_RC(Rc);
        owned[39] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTMAXSIZE: {

        owned[40] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_42 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[40]);

        owned[41] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_42, owned[41]);
        CHECK_RC(Rc);
        owned[41] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTSTORAGESTRING: {

        owned[42] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_44 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_LATESTTIME, owned[42]);

        owned[43] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_44, owned[43]);
        CHECK_RC(Rc);
        owned[43] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_FRAMETICK: {

        owned[44] = elmc_record_get_index(((ElmcTuple2 *)msg->payload)->second, ELMC_FIELD_PEBBLE_FRAME_FRAME_FRAME);

        ElmcValue *tmp_46 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[44]);

        owned[45] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_46, owned[45]);
        CHECK_RC(Rc);
        owned[45] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_UPPRESSED: {

        Rc = elmc_new_int(&owned[46], ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_TICKS) + 1);
        CHECK_RC(Rc);

        ElmcValue *tmp_48 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[46]);

        owned[47] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_48, owned[47]);
        CHECK_RC(Rc);
        owned[47] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_UPRELEASED: {
        owned[48] = model ? elmc_retain(model) : elmc_int_zero();
        owned[49] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[48], owned[49]);
        CHECK_RC(Rc);
        owned[48] = NULL;
        owned[49] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_ACCELDATA: {

        owned[50] = elmc_record_get_index(((ElmcTuple2 *)msg->payload)->second, 0 /* x */);

        owned[51] = elmc_record_get_index(((ElmcTuple2 *)msg->payload)->second, 1 /* y */);

        if ((owned[50] && owned[50]->tag == ELMC_TAG_FLOAT) || (owned[51] && owned[51]->tag == ELMC_TAG_FLOAT)) {
        Rc = elmc_new_float(&owned[52], elmc_as_float(owned[50]) + elmc_as_float(owned[51]));
        CHECK_RC(Rc);
        } else {
        Rc = elmc_new_int(&owned[52], elmc_as_int(owned[50]) + elmc_as_int(owned[51]));
        CHECK_RC(Rc);
        }

        owned[53] = elmc_record_get_index(((ElmcTuple2 *)msg->payload)->second, ELMC_FIELD_PEBBLE_ACCEL_SAMPLE_Z);

        if ((owned[52] && owned[52]->tag == ELMC_TAG_FLOAT) || (owned[53] && owned[53]->tag == ELMC_TAG_FLOAT)) {
        Rc = elmc_new_float(&owned[54], elmc_as_float(owned[52]) + elmc_as_float(owned[53]));
        CHECK_RC(Rc);
        } else {
        Rc = elmc_new_int(&owned[54], elmc_as_int(owned[52]) + elmc_as_int(owned[53]));
        CHECK_RC(Rc);
        }

        ElmcValue *tmp_56 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[54]);

        owned[55] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_56, owned[55]);
        CHECK_RC(Rc);
        owned[55] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTBATTERYLEVEL: {

        owned[56] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[57] = model ? elmc_retain(model) : elmc_int_zero();
        owned[58] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[57], owned[58]);
        CHECK_RC(Rc);
        owned[57] = NULL;
        owned[58] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTCONNECTIONSTATUS: {

        owned[59] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[60] = model ? elmc_retain(model) : elmc_int_zero();
        owned[61] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[60], owned[61]);
        CHECK_RC(Rc);
        owned[60] = NULL;
        owned[61] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTHEALTHVALUE: {

        owned[62] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_64 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[62]);

        owned[63] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_64, owned[63]);
        CHECK_RC(Rc);
        owned[63] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTHEALTHSUMTODAY: {

        owned[64] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_66 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[64]);

        owned[65] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_66, owned[65]);
        CHECK_RC(Rc);
        owned[65] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTHEALTHSUM: {

        owned[66] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();
        ElmcValue *tmp_68 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_TICKS, owned[66]);

        owned[67] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, tmp_68, owned[67]);
        CHECK_RC(Rc);
        owned[67] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTHEALTHACCESSIBLE: {

        owned[68] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[69] = model ? elmc_retain(model) : elmc_int_zero();
        owned[70] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[69], owned[70]);
        CHECK_RC(Rc);
        owned[69] = NULL;
        owned[70] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_HEALTHEVENT: {

        owned[71] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[72] = model ? elmc_retain(model) : elmc_int_zero();
        owned[73] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[72], owned[73]);
        CHECK_RC(Rc);
        owned[72] = NULL;
        owned[73] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_LIGHTCHANGED: {

        owned[74] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[75] = model ? elmc_retain(model) : elmc_int_zero();
        owned[76] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[75], owned[76]);
        CHECK_RC(Rc);
        owned[75] = NULL;
        owned[76] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_APPFOCUSCHANGED: {

        owned[77] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[78] = model ? elmc_retain(model) : elmc_int_zero();
        owned[79] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[78], owned[79]);
        CHECK_RC(Rc);
        owned[78] = NULL;
        owned[79] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_COMPASSCHANGED: {

        owned[80] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[81] = model ? elmc_retain(model) : elmc_int_zero();
        owned[82] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[81], owned[82]);
        CHECK_RC(Rc);
        owned[81] = NULL;
        owned[82] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTCOMPASSHEADING: {

        owned[83] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[84] = model ? elmc_retain(model) : elmc_int_zero();
        owned[85] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[84], owned[85]);
        CHECK_RC(Rc);
        owned[84] = NULL;
        owned[85] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_DICTATIONSTATUS: {

        owned[86] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[87] = model ? elmc_retain(model) : elmc_int_zero();
        owned[88] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[87], owned[88]);
        CHECK_RC(Rc);
        owned[87] = NULL;
        owned[88] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_DICTATIONRESULT: {

        owned[89] = ((ElmcTuple2 *)msg->payload)->second ? elmc_retain(((ElmcTuple2 *)msg->payload)->second) : elmc_int_zero();

        owned[90] = model ? elmc_retain(model) : elmc_int_zero();
        owned[91] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[90], owned[91]);
        CHECK_RC(Rc);
        owned[90] = NULL;
        owned[91] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_ANIMATIONFINISHED: {
        owned[92] = model ? elmc_retain(model) : elmc_int_zero();
        owned[93] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[92], owned[93]);
        CHECK_RC(Rc);
        owned[92] = NULL;
        owned[93] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTCLOCKSTYLE24H: {
        owned[94] = model ? elmc_retain(model) : elmc_int_zero();
        owned[95] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[94], owned[95]);
        CHECK_RC(Rc);
        owned[94] = NULL;
        owned[95] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTTIMEZONEISSET: {
        owned[96] = model ? elmc_retain(model) : elmc_int_zero();
        owned[97] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[96], owned[97]);
        CHECK_RC(Rc);
        owned[96] = NULL;
        owned[97] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTTIMEZONE: {
        owned[98] = model ? elmc_retain(model) : elmc_int_zero();
        owned[99] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[98], owned[99]);
        CHECK_RC(Rc);
        owned[98] = NULL;
        owned[99] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTWATCHMODEL: {
        owned[100] = model ? elmc_retain(model) : elmc_int_zero();
        owned[101] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[100], owned[101]);
        CHECK_RC(Rc);
        owned[100] = NULL;
        owned[101] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTWATCHCOLOR: {
        owned[102] = model ? elmc_retain(model) : elmc_int_zero();
        owned[103] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[102], owned[103]);
        CHECK_RC(Rc);
        owned[102] = NULL;
        owned[103] = NULL;

        break;
      }
      case ELMC_PEBBLE_MSG_GOTFIRMWAREVERSION: {
        owned[104] = model ? elmc_retain(model) : elmc_int_zero();
        owned[105] = elmc_int_zero();
        Rc = elmc_tuple2_take(out, owned[104], owned[105]);
        CHECK_RC(Rc);
        owned[104] = NULL;
        owned[105] = NULL;

        break;
      }

    }

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[1] = {0};

  ElmcValue *_unused_0 = (argc > 0) ? args[0] : NULL;
  (void)_unused_0;

  CATCH_BEGIN

    ElmcValue *tmp_1 = elmc_sub1(ELMC_SUBSCRIPTION_SECOND_CHANGE, ELMC_PEBBLE_MSG_TICK);

    ElmcValue *tmp_2 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_BUTTONUP);

    ElmcValue *tmp_3 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_SELECT, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_BUTTONSELECT);

    ElmcValue *tmp_4 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_DOWN, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_BUTTONDOWN);

    ElmcValue *tmp_5 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_LONG_PRESSED, ELMC_PEBBLE_MSG_BUTTONLONGUP);

    ElmcValue *tmp_6 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_SELECT, ELMC_BUTTON_EVENT_LONG_PRESSED, ELMC_PEBBLE_MSG_BUTTONLONGSELECT);

    ElmcValue *tmp_7 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_DOWN, ELMC_BUTTON_EVENT_LONG_PRESSED, ELMC_PEBBLE_MSG_BUTTONLONGDOWN);

    ElmcValue *tmp_8 = elmc_sub1(ELMC_SUBSCRIPTION_HOUR_CHANGE, ELMC_PEBBLE_MSG_HOURCHANGED);

    ElmcValue *tmp_9 = elmc_sub1(ELMC_SUBSCRIPTION_MINUTE_CHANGE, ELMC_PEBBLE_MSG_MINUTECHANGED);

    ElmcValue *tmp_10 = elmc_sub1(ELMC_SUBSCRIPTION_DAY_CHANGE, ELMC_PEBBLE_MSG_DAYCHANGED);

    ElmcValue *tmp_11 = elmc_sub1(ELMC_SUBSCRIPTION_MONTH_CHANGE, ELMC_PEBBLE_MSG_MONTHCHANGED);

    ElmcValue *tmp_12 = elmc_sub1(ELMC_SUBSCRIPTION_YEAR_CHANGE, ELMC_PEBBLE_MSG_YEARCHANGED);

    ElmcValue *tmp_13 = elmc_sub1(ELMC_SUBSCRIPTION_ACCEL_TAP, ELMC_PEBBLE_MSG_ACCELTAP);

    ElmcValue *tmp_14 = elmc_sub1(ELMC_SUBSCRIPTION_BATTERY, ELMC_PEBBLE_MSG_BATTERYCHANGED);

    ElmcValue *tmp_15 = elmc_sub1(ELMC_SUBSCRIPTION_CONNECTION, ELMC_PEBBLE_MSG_CONNECTIONCHANGED);

    ElmcValue *tmp_16 = elmc_sub1((ELMC_SUBSCRIPTION_FRAME_BASE + (33 << 16)), ELMC_PEBBLE_MSG_FRAMETICK);

    ElmcValue *tmp_17 = elmc_sub1((ELMC_SUBSCRIPTION_FRAME_BASE + (33 << 16)), ELMC_PEBBLE_MSG_FRAMETICK);

    ElmcValue *tmp_18 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, 1, ELMC_PEBBLE_MSG_UPPRESSED);

    ElmcValue *tmp_19 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, 2, ELMC_PEBBLE_MSG_UPRELEASED);

    ElmcValue *tmp_20 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_RELEASED, ELMC_PEBBLE_MSG_UPRELEASED);

    ElmcValue *tmp_21 = elmc_sub1(ELMC_SUBSCRIPTION_ACCEL_DATA, ELMC_PEBBLE_MSG_ACCELDATA);

    ElmcValue *tmp_22 = elmc_sub1(ELMC_SUBSCRIPTION_APP_FOCUS, ELMC_PEBBLE_MSG_APPFOCUSCHANGED);

    ElmcValue *tmp_23 = elmc_sub1(ELMC_SUBSCRIPTION_COMPASS, ELMC_PEBBLE_MSG_COMPASSCHANGED);

    ElmcValue *tmp_24 = elmc_sub1(ELMC_SUBSCRIPTION_DICTATION, ELMC_PEBBLE_MSG_DICTATIONSTATUS);

    ElmcValue *tmp_25 = elmc_sub1(ELMC_SUBSCRIPTION_DICTATION, ELMC_PEBBLE_MSG_DICTATIONRESULT);

    ElmcValue *tmp_26 = elmc_sub1(ELMC_SUBSCRIPTION_HEALTH, ELMC_PEBBLE_MSG_HEALTHEVENT);

    ElmcValue *tmp_27 = elmc_sub1(ELMC_SUBSCRIPTION_BACKLIGHT, ELMC_PEBBLE_MSG_LIGHTCHANGED);

    ElmcValue *tmp_28 = elmc_sub1(ELMC_SUBSCRIPTION_ANIMATION_FINISHED, ELMC_PEBBLE_MSG_ANIMATIONFINISHED);

    ElmcValue *list_items_29[28] = { tmp_1, tmp_2, tmp_3, tmp_4, tmp_5, tmp_6, tmp_7, tmp_8, tmp_9, tmp_10, tmp_11, tmp_12, tmp_13, tmp_14, tmp_15, tmp_16, tmp_17, tmp_18, tmp_19, tmp_20, tmp_21, tmp_22, tmp_23, tmp_24, tmp_25, tmp_26, tmp_27, tmp_28 };
    Rc = elmc_list_from_values_take(&owned[0], list_items_29, 28);
    CHECK_RC(Rc);

    *out = owned[0];
    owned[0] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static ElmcValue * elmc_fn_Main_main(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *tmp_1 = elmc_int_zero();
  return tmp_1;
}

static RC elmc_fn_Pebble_DataLog_tag(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};
  (void)args;
  (void)argc;

  CATCH_BEGIN

    Rc = elmc_new_int(&owned[0], 1);
    CHECK_RC(Rc);
    ElmcValue *cap_2[1] = { owned[0] };
    owned[1] = NULL;
    Rc = elmc_closure_new(&owned[1], elmc_partial_union_1, 1, 1, cap_2);
    CHECK_RC(Rc);

    *out = owned[1];
    owned[1] = NULL;
  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

static RC elmc_fn_Pebble_Log_infoCode(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  (void)args;
  (void)argc;

  ElmcValue *tmp_1 = elmc_int_zero();

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Pebble_Log_warnCode(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  (void)args;
  (void)argc;

  ElmcValue *tmp_1 = elmc_int_zero();

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Pebble_Log_errorCode(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  (void)args;
  (void)argc;

  ElmcValue *tmp_1 = elmc_int_zero();

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *launchReason = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (launchReason && (launchReason)->tag == ELMC_TAG_INT ? elmc_as_int(launchReason) : (launchReason && (launchReason)->tag == ELMC_TAG_TUPLE2 && (launchReason)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(launchReason)->payload)->first) : -1));

    elmc_int_t case_int_2;
    case_int_2 = 0;
    switch (case_msg_tag_1) {
      case ELMC_UNION_LAUNCHSYSTEM: {
        case_int_2 = 0;
        break;
      }
      case ELMC_UNION_LAUNCHUSER: {
        case_int_2 = 1;
        break;
      }
      case ELMC_UNION_LAUNCHPHONE: {
        case_int_2 = 2;
        break;
      }
      case ELMC_UNION_LAUNCHWAKEUP: {
        case_int_2 = 3;
        break;
      }
      case ELMC_UNION_LAUNCHWORKER: {
        case_int_2 = 4;
        break;
      }
      case ELMC_UNION_LAUNCHQUICKLAUNCH: {
        case_int_2 = 5;
        break;
      }
      case ELMC_UNION_LAUNCHTIMELINEACTION: {
        case_int_2 = 6;
        break;
      }
      case ELMC_UNION_LAUNCHSMARTSTRAP: {
        case_int_2 = 7;
        break;
      }
      case ELMC_UNION_LAUNCHUNKNOWN: {
        case_int_2 = -1;
        break;
      }

    }
    Rc = elmc_new_int(out, case_int_2);
    CHECK_RC(Rc);

  CATCH_END;

  return Rc;
}

static RC elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  (void)args;
  (void)argc;

  ElmcValue *tmp_1 = elmc_int_zero();

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Pebble_Wakeup_cancel(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  (void)args;
  (void)argc;

  ElmcValue *tmp_1 = elmc_int_zero();

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[6] = {0};

  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    owned[0] = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_LATESTTIME);

    const elmc_int_t native_call_2 = elmc_fn_Main_parseHourFromTimeString_native(owned[0]);
    ELMC_RELEASE(owned[0]);
    owned[0] = NULL;

    ElmcValue *tmp_3 = NULL;
    Rc = elmc_new_int(&tmp_3, native_call_2);
    CHECK_RC(Rc);

    /* elm/core: Basics.floor */

    /* elm/core: Maybe.withDefault */

    owned[1] = elmc_int_zero();
    /* elm/core: String.toFloat */

    Rc = elmc_new_string(&owned[2], "3.14");
    CHECK_RC(Rc);

    owned[3] = elmc_string_to_float(owned[2]);
    ELMC_RELEASE(owned[2]);
    owned[2] = NULL;

    owned[4] = elmc_maybe_with_default(owned[1], owned[3]);
    ELMC_RELEASE(owned[1]);
    owned[1] = NULL;
    ELMC_RELEASE(owned[3]);
    owned[3] = NULL;

    owned[5] = elmc_basics_floor(owned[4]);
    ELMC_RELEASE(owned[4]);
    owned[4] = NULL;

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CLEAR);
    scene_cmd.p0 = ELMC_COLOR_WHITE;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 24;
    scene_cmd.p3 = elmc_as_int(tmp_3);
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 48;
    scene_cmd.p3 = elmc_as_int(owned[5]);
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_INT_WITH_FONT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = 0;
    scene_cmd.p2 = 72;
    scene_cmd.p3 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_TICKS);
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    ELMC_RELEASE(owned[5]);
    owned[5] = NULL;

    elmc_release(tmp_3);

  CATCH_END;
  if (Rc != RC_SUCCESS) {
    elmc_release_array_lifo(owned, DIM(owned));
  }

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}
