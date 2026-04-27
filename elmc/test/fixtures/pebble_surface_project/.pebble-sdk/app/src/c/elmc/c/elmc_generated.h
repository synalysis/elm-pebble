#ifndef ELMC_GENERATED_H
#define ELMC_GENERATED_H

#include "../runtime/elmc_runtime.h"
#include "../ports/elmc_ports.h"

ElmcValue *elmc_fn_Main_parseHourFromTimeString(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Main_init(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Main_update(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Main_subscriptions(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Main_view(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Main_main(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_none(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_timerAfter(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_storageWriteInt(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_storageReadInt(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_storageDelete(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_companionSend(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_backlight(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getCurrentTimeString(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getClockStyle24h(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getTimezoneIsSet(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getTimezone(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getWatchModel(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getFirmwareVersion(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_getColor(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_logInfoCode(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_logWarnCode(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_logErrorCode(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_wakeupScheduleAfterSeconds(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_wakeupCancel(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_vibesCancel(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_vibesShortPulse(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_vibesLongPulse(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_vibesDoublePulse(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onTick(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onButtonUp(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onButtonSelect(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onButtonDown(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onAccelTap(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onBatteryChange(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_onConnectionChange(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_batch(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_AppMessage_sendIntPair(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Cmd_none(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Cmd_timerAfter(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Cmd_companionSend(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Events_onTick(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Events_onButtonUp(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Events_onButtonSelect(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Events_onButtonDown(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Events_onAccelTap(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Events_batch(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Light_interaction(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Light_disable(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Light_enable(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Log_infoCode(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Log_warnCode(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Log_errorCode(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Platform_worker(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Storage_writeInt(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Storage_readInt(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Storage_delete(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_System_onBatteryChange(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_System_onConnectionChange(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Time_currentTimeString(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Time_clockStyle24h(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Time_timezoneIsSet(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Time_timezone(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Ui_windowStack(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Ui_window(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Ui_canvasLayer(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Ui_textInt(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Ui_clear(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Vibes_cancel(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Vibes_shortPulse(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Vibes_longPulse(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Vibes_doublePulse(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_Wakeup_cancel(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_WatchInfo_getModel(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_WatchInfo_getFirmwareVersion(ElmcValue **args, int argc);
ElmcValue *elmc_fn_Pebble_WatchInfo_getColor(ElmcValue **args, int argc);

#endif
