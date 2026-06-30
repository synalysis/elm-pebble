#include "elmc_generated.h"
#include <stdio.h>

static void on_outgoing(ElmcValue *value, void *context) {
  (void)context;
  printf("port callback value=%lld\n", (long long)elmc_as_int(value));
}

int main(void) {
  RC Rc = RC_SUCCESS;
  CATCH_BEGIN
    register_incoming_port("demo", on_outgoing, NULL);
    ElmcValue *payload = NULL;
    Rc = elmc_new_int(&payload, 7);
    CHECK_RC(Rc);
    send_outgoing_port("demo", payload);
    elmc_release(payload);
  CATCH_END
  return (int)Rc;
}
