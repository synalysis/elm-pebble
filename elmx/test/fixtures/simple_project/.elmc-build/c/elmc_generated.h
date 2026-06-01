#ifndef ELMC_GENERATED_H
#define ELMC_GENERATED_H

#include "../runtime/elmc_runtime.h"
#include "../ports/elmc_ports.h"

ElmcValue *elmc_fn_Main_helper(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_advanced(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_counterOf(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_temperatureOf(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_requestWeather(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_requestSystemInfo(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_handleAppMsg(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_handlePlatformMsg(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_view(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_statusDraw(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_counterDraw(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_temperatureValue(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Ui_path(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Ui_rotationToPebbleAngle(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Companion_Internal_encodeLocationCode(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Companion_Internal_watchToPhoneTag(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Companion_Internal_watchToPhoneValue(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Companion_Watch_sendWatchToPhone(ElmcValue ** const args, const int argc);
#define ELMC_HAVE_DIRECT_COMMANDS_MAIN_COUNTERDRAW 1
int elmc_fn_Main_counterDraw_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds);
int elmc_fn_Main_counterDraw_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip);

#define ELMC_HAVE_DIRECT_COMMANDS_MAIN_STATUSDRAW 1
int elmc_fn_Main_statusDraw_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds);
int elmc_fn_Main_statusDraw_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip);

#define ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW 1
int elmc_fn_Main_view_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds);
int elmc_fn_Main_view_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip);


#endif
