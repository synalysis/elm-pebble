#ifndef ELMC_PORTS_H
#define ELMC_PORTS_H

#include "../runtime/elmc_runtime.h"

typedef struct {
  ElmcPortCallback callback;
  void *context;
} ElmcIncomingRegistration;

int register_incoming_port(const char *port_name, ElmcPortCallback callback, void *context);
int send_outgoing_port(const char *port_name, ElmcValue *payload);
void elmc_ports_reset(void);

#endif
