#include "elmc_generated.h"
#include "elmc_pebble.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#if defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-variable"
#endif

const char *elmc_debug_union_ctor_name(elmc_int_t tag) {
  switch (tag) {

    default: return NULL;
  }
}

#define ELMC_FIELD_MAIN_LAYOUT_CX 0
#define ELMC_FIELD_MAIN_LAYOUT_CY 1
#define ELMC_FIELD_MAIN_LAYOUT_RADIUS 2
#define ELMC_FIELD_MAIN_TICKSPEC_LABEL 2
#define ELMC_FIELD_MAIN_TICKSPEC_SIZE 1
#define ELMC_FIELD_MAIN_TICKSPEC_VALUE 0

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

static ElmcValue *elmc_fn_Main_main(ElmcValue ** const args, const int argc);
RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_view(ElmcValue **out, ElmcValue ** const args, const int argc);

static ElmcValue * elmc_fn_Main_main(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  (void)args;
  (void)argc;
  ElmcValue *tmp_1 = elmc_int_zero();
  return tmp_1;
}

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};

  ElmcValue *_unused_0 = (argc > 0) ? args[0] : NULL;
  (void)_unused_0;

  CATCH_BEGIN

    ElmcValue *rec_values_1[1] = {  };
    Rc = elmc_record_new_values_take(&owned[0], 0, rec_values_1);
    CHECK_RC(Rc);

    Rc = elmc_new_int(&owned[1], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(out, owned[0], owned[1]);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;

  CATCH_END;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;
  ElmcValue *owned[2] = {0};

  ElmcValue *_unused_0 = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;
  (void)_unused_0;

  CATCH_BEGIN

    owned[0] = model ? elmc_retain(model) : elmc_int_zero();
    Rc = elmc_new_int(&owned[1], ELMC_PEBBLE_CMD_NONE);
    CHECK_RC(Rc);

    Rc = elmc_tuple2_take(out, owned[0], owned[1]);
    CHECK_RC(Rc);
    owned[0] = NULL;
    owned[1] = NULL;

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

  owned[0] = elmc_int_zero();

  *out = owned[0];
  owned[0] = NULL;

  elmc_release_array_lifo(owned, DIM(owned));
  return Rc;
}

RC elmc_fn_Main_view(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *_unused_0 = (argc > 0) ? args[0] : NULL;
  (void)_unused_0;

  // #region agent log
  elmc_agent_generated_probe(0xED998100);
  // #endregion

  ElmcValue *tmp_1 = elmc_int_zero();

  // #region agent log
  if (!tmp_1) {
    elmc_agent_generated_probe(0xED998113);
  } else if (tmp_1->tag == ELMC_TAG_TUPLE2) {
    elmc_agent_generated_probe(0xED998111);
  } else if (tmp_1->tag == ELMC_TAG_LIST) {
    elmc_agent_generated_probe(0xED998112);
  } else {
    elmc_agent_generated_probe(0xED998110);
  }

  // #endregion

  *out = tmp_1;

  return Rc;
}
