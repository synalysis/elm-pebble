#ifndef ELMC_GENERATED_H
#define ELMC_GENERATED_H

#include "../runtime/elmc_runtime.h"
#include "../ports/elmc_ports.h"

ElmcValue *elmc_fn_Main_parseHourFromTimeString(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_subscriptions(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthValue(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthSumToday(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthSum(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Elm_Kernel_PebbleWatch_healthAccessible(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Accel_defaultConfig(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Health_value(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Health_sumToday(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Health_sum(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Health_accessible(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Health_metricToInt(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Light_interaction(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Light_disable(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Light_enable(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Log_infoCode(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Log_warnCode(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Log_errorCode(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Platform_launchReasonToInt(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Wakeup_scheduleAfterSeconds(ElmcValue ** const args, const int argc);
ElmcValue *elmc_fn_Pebble_Wakeup_cancel(ElmcValue ** const args, const int argc);
#define ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW 1
int elmc_fn_Main_view_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds);
int elmc_fn_Main_view_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip);


#endif
