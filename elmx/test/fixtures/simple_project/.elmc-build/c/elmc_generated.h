#ifndef ELMC_GENERATED_H
#define ELMC_GENERATED_H

#include "../runtime/elmc_runtime.h"
#include "../ports/elmc_ports.h"
RC elmc_fn_Main_init(ElmcValue **out, ElmcValue *launchContext);
RC elmc_fn_Main_update(ElmcValue **out, ElmcValue *msg, ElmcValue *model);
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue *_unused_0);
RC elmc_fn_Main_view(ElmcValue **out, ElmcValue *model);

#define ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW 1


#endif
