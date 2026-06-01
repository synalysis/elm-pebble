#include "elmc_generated.h"
#include <stdio.h>

static void on_outgoing(ElmcValue *value, void *context) {
  (void)context;
  printf("port callback value=%lld\n", (long long)elmc_as_int(value));
}

int main(void) {
  register_incoming_port("demo", on_outgoing, NULL);
  ElmcValue *payload = elmc_new_int(7);
  send_outgoing_port("demo", payload);
  elmc_release(payload);
  return 0;
}
