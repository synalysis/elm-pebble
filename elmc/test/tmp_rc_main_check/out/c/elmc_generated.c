#include "elmc_generated.h"
#include "elmc_pebble.h"
#include <stdbool.h>
#include <stdio.h>

#if defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wunused-function"
#endif

#define ELMC_UNION_BESTLOADED 5
#define ELMC_UNION_DOWN 4
#define ELMC_UNION_DOWNPRESSED 4
#define ELMC_UNION_LEFT 1
#define ELMC_UNION_LEFTPRESSED 1
#define ELMC_UNION_MAIN_BESTLOADED 5
#define ELMC_UNION_MAIN_DOWN 4
#define ELMC_UNION_MAIN_DOWNPRESSED 4
#define ELMC_UNION_MAIN_LEFT 1
#define ELMC_UNION_MAIN_LEFTPRESSED 1
#define ELMC_UNION_MAIN_RANDOMGENERATED 6
#define ELMC_UNION_MAIN_RIGHT 2
#define ELMC_UNION_MAIN_RIGHTPRESSED 2
#define ELMC_UNION_MAIN_UP 3
#define ELMC_UNION_MAIN_UPPRESSED 3
#define ELMC_UNION_RANDOMGENERATED 6
#define ELMC_UNION_RIGHT 2
#define ELMC_UNION_RIGHTPRESSED 2
#define ELMC_UNION_UP 3
#define ELMC_UNION_UPPRESSED 3

#define ELMC_FIELD_MAIN_BOARDLAYOUT_CELL 0
#define ELMC_FIELD_MAIN_BOARDLAYOUT_GAP 1
#define ELMC_FIELD_MAIN_BOARDLAYOUT_X 2
#define ELMC_FIELD_MAIN_BOARDLAYOUT_Y 3
#define ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS 0
#define ELMC_FIELD_MAIN_COLLAPSERESULT_SCORE 1
#define ELMC_FIELD_MAIN_MODEL_BEST 0
#define ELMC_FIELD_MAIN_MODEL_CELLS 1
#define ELMC_FIELD_MAIN_MODEL_DISPLAYSHAPE 2
#define ELMC_FIELD_MAIN_MODEL_SCORE 3
#define ELMC_FIELD_MAIN_MODEL_SCREENH 4
#define ELMC_FIELD_MAIN_MODEL_SCREENW 5
#define ELMC_FIELD_MAIN_MODEL_SEED 6
#define ELMC_FIELD_MAIN_MODEL_TURN 7

#define ELMC_RENDER_OP_CLEAR 2
#define ELMC_RENDER_OP_RECT 5
#define ELMC_RENDER_OP_PUSH_CONTEXT 10
#define ELMC_RENDER_OP_POP_CONTEXT 11
#define ELMC_RENDER_OP_STROKE_COLOR 14
#define ELMC_RENDER_OP_TEXT_COLOR 16
#define ELMC_RENDER_OP_TEXT 29
#define ELMC_BUTTON_BACK 0
#define ELMC_BUTTON_UP 1
#define ELMC_BUTTON_SELECT 2
#define ELMC_BUTTON_DOWN 3
#define ELMC_BUTTON_EVENT_PRESSED 1
#define ELMC_SUBSCRIPTION_BUTTON_RAW 16384
#define ELMC_TEXT_ALIGN_CENTER 1
#define ELMC_TEXT_OVERFLOW_WORD_WRAP 0
#define ELMC_TEXT_OVERFLOW_SHIFT 2
#define ELMC_COLOR_BLACK 192
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

static elmc_int_t elmc_fn_Main_advanceSeed_native(const elmc_int_t seed);
static elmc_int_t elmc_fn_Main_randomIndex_native(const elmc_int_t maxExclusive, const elmc_int_t seed);
static elmc_int_t elmc_fn_Main_countEmpty_native(ElmcValue * const cells);
static elmc_int_t elmc_fn_Main_nthEmptyIndex_native(ElmcValue * const target, ElmcValue * const cells);
static elmc_int_t elmc_fn_Main_nthEmptyIndexHelp_native(const elmc_int_t target, const elmc_int_t index, ElmcValue * const cells);
static ElmcValue *elmc_fn_Main_rowAt_native(const elmc_int_t row, ElmcValue * const cells);

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_emptyBoard(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_moveBoard(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_initialBoard(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_collapseRows(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_collapseRow(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_merge(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_spawnTileWithSeed(ElmcValue **out, ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_advanceSeed(ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_randomIndex(ElmcValue **out, ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_countEmpty(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_nthEmptyIndex(ElmcValue ** const args, const int argc);
static ElmcValue *elmc_fn_Main_nthEmptyIndexHelp(ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_setCell(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_orient(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_restore(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_rowAt(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_reverseRows(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_transpose(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_listAt(ElmcValue **out, ElmcValue ** const args, const int argc);
RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue ** const args, const int argc);
static RC elmc_fn_Main_main(ElmcValue **out, ElmcValue ** const args, const int argc);

RC elmc_fn_Main_init(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *context = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *tmp_1_boxed_int = elmc_new_int_take(0);

    ElmcValue *tmp_2 = ({ ElmcValue *__z = NULL; RC __call_rc = elmc_fn_Main_emptyBoard(&__z, NULL, 0); if (__call_rc != RC_SUCCESS) { ELMC_RC_LOG_FAIL(__call_rc, "elmc_fn_Main_emptyBoard", "zero-arg call failed"); __z = NULL; } __z; })
    ;
    ElmcValue *tmp_3_screen = elmc_record_get(context, "screen");

    ElmcValue *tmp_4_shape = elmc_record_get(tmp_3_screen, "shape");

    ElmcValue *tmp_5_height = elmc_record_get(tmp_3_screen, "height");

    ElmcValue *tmp_6_width = elmc_record_get(tmp_3_screen, "width");

    elmc_release(tmp_3_screen);
    ElmcValue *rec_values_7[8] = { tmp_1_boxed_int, tmp_2, tmp_4_shape, elmc_retain(tmp_1_boxed_int), tmp_5_height, tmp_6_width, elmc_retain(tmp_1_boxed_int), elmc_retain(tmp_1_boxed_int) };
    ElmcValue *tmp_7 = NULL;
    Rc = elmc_record_new_values_take(&tmp_7, 8, rec_values_7);
    CHECK_RC(Rc);

    ElmcValue *tmp_8 = elmc_cmd2(ELMC_PEBBLE_CMD_STORAGE_READ_STRING, 2048, ELMC_PEBBLE_MSG_BESTLOADED);

    ElmcValue *tmp_9 = elmc_cmd1(ELMC_PEBBLE_CMD_RANDOM_GENERATE, ELMC_PEBBLE_MSG_RANDOMGENERATED);

    ElmcValue *tmp_10 = elmc_cmd1(ELMC_PEBBLE_CMD_BACKLIGHT, 2);

    ElmcValue *list_items_11[3] = { tmp_8, tmp_9, tmp_10 };
    ElmcValue *tmp_11 = NULL;
    Rc = elmc_list_from_values_take(&tmp_11, list_items_11, 3);
    CHECK_RC(Rc);

    ElmcValue *tmp_12 = NULL;
    Rc = elmc_tuple2_take(&tmp_12, tmp_7, tmp_11);
    CHECK_RC(Rc);

    *out = tmp_12;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_emptyBoard(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  (void)args;
  (void)argc;

  ElmcValue *tmp_1;
  {
    enum { ELMC_ZERO_N = 16 };
    static struct {
      ElmcValue value;
      ElmcCons cons;
    } elmc_zero_list_tmp_1_cells[ELMC_ZERO_N];
    static int elmc_zero_list_tmp_1_ready = 0;
    while (elmc_zero_list_tmp_1_ready < ELMC_ZERO_N) {
      int i = elmc_zero_list_tmp_1_ready++;
      ElmcCons *cell_cons = &elmc_zero_list_tmp_1_cells[i].cons;
      ElmcValue *cell_value = &elmc_zero_list_tmp_1_cells[i].value;
      cell_cons->head = elmc_int_zero();
      cell_cons->tail = (i == 0) ? elmc_list_nil() : &elmc_zero_list_tmp_1_cells[i - 1].value;
      cell_value->rc = ELMC_RC_IMMORTAL;
      cell_value->tag = ELMC_TAG_LIST;
      cell_value->payload = cell_cons;
      cell_value->scalar = ELMC_LIST_CELL_SCALAR;
    }
    tmp_1 = &elmc_zero_list_tmp_1_cells[ELMC_ZERO_N - 1].value;
  }

  *out = tmp_1;

  return Rc;
}

RC elmc_fn_Main_update(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *msg = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (msg && (msg)->tag == ELMC_TAG_INT ? elmc_as_int(msg) : (msg && (msg)->tag == ELMC_TAG_TUPLE2 && (msg)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(msg)->payload)->first) : -1));
    ElmcValue *tmp_1;
    switch (case_msg_tag_1) {
      case ELMC_PEBBLE_MSG_LEFTPRESSED: {

        ElmcValue *tmp_2 = NULL;
        Rc = elmc_new_int(&tmp_2, ELMC_UNION_LEFT);
        CHECK_RC(Rc);

        ElmcValue *call_args_3[2] = { tmp_2, model };
        Rc = elmc_fn_Main_moveBoard(&tmp_1, call_args_3, 2);
        CHECK_RC(Rc);

        elmc_release(tmp_2);

        break;
      }
      case ELMC_PEBBLE_MSG_RIGHTPRESSED: {

        ElmcValue *tmp_4 = NULL;
        Rc = elmc_new_int(&tmp_4, ELMC_UNION_RIGHT);
        CHECK_RC(Rc);

        ElmcValue *call_args_5[2] = { tmp_4, model };
        Rc = elmc_fn_Main_moveBoard(&tmp_1, call_args_5, 2);
        CHECK_RC(Rc);

        elmc_release(tmp_4);

        break;
      }
      case ELMC_PEBBLE_MSG_UPPRESSED: {

        ElmcValue *tmp_6 = NULL;
        Rc = elmc_new_int(&tmp_6, ELMC_UNION_UP);
        CHECK_RC(Rc);

        ElmcValue *call_args_7[2] = { tmp_6, model };
        Rc = elmc_fn_Main_moveBoard(&tmp_1, call_args_7, 2);
        CHECK_RC(Rc);

        elmc_release(tmp_6);

        break;
      }
      case ELMC_PEBBLE_MSG_DOWNPRESSED: {

        ElmcValue *tmp_8 = NULL;
        Rc = elmc_new_int(&tmp_8, ELMC_UNION_DOWN);
        CHECK_RC(Rc);

        ElmcValue *call_args_9[2] = { tmp_8, model };
        Rc = elmc_fn_Main_moveBoard(&tmp_1, call_args_9, 2);
        CHECK_RC(Rc);

        elmc_release(tmp_8);

        break;
      }
      case ELMC_PEBBLE_MSG_BESTLOADED: {

        ElmcValue *tmp_10 = elmc_int_zero();

        ElmcValue *tmp_11 = elmc_string_to_int(((ElmcTuple2 *)msg->payload)->second);

        ElmcValue *tmp_12 = elmc_maybe_with_default(tmp_10, tmp_11);
        elmc_release(tmp_10);
        elmc_release(tmp_11);

        ElmcValue *tmp_13 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_BEST, tmp_12);

        elmc_release(tmp_12);

        ElmcValue *tmp_14 = elmc_int_zero();
        ElmcValue *tmp_15 = NULL;
        Rc = elmc_tuple2_take(&tmp_15, tmp_13, tmp_14);
        CHECK_RC(Rc);

        tmp_1 = tmp_15;
        break;
      }
      case ELMC_PEBBLE_MSG_RANDOMGENERATED: {

        ElmcValue *call_args_16[1] = { ((ElmcTuple2 *)msg->payload)->second };
        Rc = elmc_fn_Main_initialBoard(&tmp_1, call_args_16, 1);
        CHECK_RC(Rc);

        ElmcValue *tmp_17 = elmc_tuple_first(tmp_1);

        ElmcValue *tmp_18 = elmc_tuple_second(tmp_1);

        ElmcValue *tmp_19 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_CELLS, tmp_17);

        ElmcValue *tmp_20 = elmc_record_update_index_cow(tmp_19, ELMC_FIELD_MAIN_MODEL_SEED, tmp_18);

        ElmcValue *tmp_21 = elmc_int_zero();
        ElmcValue *tmp_22 = NULL;
        Rc = elmc_tuple2_take(&tmp_22, tmp_20, tmp_21);
        CHECK_RC(Rc);

        elmc_release(tmp_18);

        elmc_release(tmp_17);

        elmc_release(tmp_1);

        tmp_1 = tmp_22;
        break;
      }
      default:
        tmp_1 = elmc_int_zero();
        break;

    }

    *out = tmp_1;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_moveBoard(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *direction = (argc > 0) ? args[0] : NULL;
  ElmcValue *model = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    ElmcValue *call_args_1[2] = { direction, ELMC_RECORD_GET_INDEX(model, ELMC_FIELD_MAIN_MODEL_CELLS) };
    ElmcValue *tmp_1;
    Rc = elmc_fn_Main_orient(&tmp_1, call_args_1, 2);
    CHECK_RC(Rc);

    ElmcValue *call_args_2[1] = { tmp_1 };
    ElmcValue *tmp_2;
    Rc = elmc_fn_Main_collapseRows(&tmp_2, call_args_2, 1);
    CHECK_RC(Rc);

    ElmcValue *call_args_3[2] = { direction, ELMC_RECORD_GET_INDEX(tmp_2, ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS) };
    ElmcValue *tmp_3;
    Rc = elmc_fn_Main_restore(&tmp_3, call_args_3, 2);
    CHECK_RC(Rc);

    ElmcValue *tmp_4 = tmp_3 ? elmc_retain(tmp_3) : elmc_int_zero();

    ElmcValue *tmp_5 = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_CELLS);

    const bool native_cmp_6 = elmc_list_equal_int(tmp_4, tmp_5);
    elmc_release(tmp_4);
    elmc_release(tmp_5);

    ElmcValue *tmp_7 = NULL;
    if (native_cmp_6) {
      ElmcValue *tmp_9 = model ? elmc_retain(model) : elmc_int_zero();
      ElmcValue *tmp_10 = elmc_int_zero();
      ElmcValue *tmp_11 = NULL;
      Rc = elmc_tuple2_take(&tmp_11, tmp_9, tmp_10);
      CHECK_RC(Rc);

      tmp_7 = tmp_11;
    } else {
      ElmcValue *call_args_12[2] = { ELMC_RECORD_GET_INDEX(model, ELMC_FIELD_MAIN_MODEL_SEED), tmp_3 };
      ElmcValue *tmp_12;
      Rc = elmc_fn_Main_spawnTileWithSeed(&tmp_12, call_args_12, 2);
      CHECK_RC(Rc);

      ElmcValue *tmp_13 = elmc_tuple_first(tmp_12);

      ElmcValue *tmp_14 = elmc_tuple_second(tmp_12);

      ElmcValue *tmp_15 = NULL;
      Rc = elmc_new_int(&tmp_15, (ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_SCORE) + ELMC_RECORD_GET_INDEX_INT(tmp_2, ELMC_FIELD_MAIN_COLLAPSERESULT_SCORE)));
      CHECK_RC(Rc);

      const elmc_int_t native_max_left_16 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_BEST);
      const elmc_int_t native_max_right_16 = elmc_as_int(tmp_15);
      const elmc_int_t native_max_16 = (native_max_left_16 >= native_max_right_16) ? native_max_left_16 : native_max_right_16;
      ElmcValue *tmp_17 = NULL;
      Rc = elmc_new_int(&tmp_17, native_max_16);
      CHECK_RC(Rc);

      ElmcValue *tmp_18 = NULL;
      if ((elmc_as_int(tmp_17) > ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_BEST))) {
        char native_string_buf_20[32];
        snprintf(native_string_buf_20, sizeof(native_string_buf_20), "%lld", (long long)elmc_as_int(tmp_17));
        const char *native_string_20 = native_string_buf_20;
        tmp_18 = elmc_cmd1_string(ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING, 2048, native_string_20);
      } else {
        tmp_18 = elmc_int_zero();
      }

      ElmcValue *tmp_23 = elmc_record_update_index(model, ELMC_FIELD_MAIN_MODEL_BEST, tmp_17);

      ElmcValue *tmp_24 = elmc_record_update_index_cow(tmp_23, ELMC_FIELD_MAIN_MODEL_CELLS, tmp_13);

      ElmcValue *tmp_25 = elmc_record_update_index_cow(tmp_24, ELMC_FIELD_MAIN_MODEL_SCORE, tmp_15);

      ElmcValue *tmp_26 = elmc_record_update_index_cow(tmp_25, ELMC_FIELD_MAIN_MODEL_SEED, tmp_14);

      ElmcValue *tmp_27 = NULL;
      Rc = elmc_new_int(&tmp_27, ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_TURN) + 1);
      CHECK_RC(Rc);

      ElmcValue *tmp_28 = elmc_record_update_index_cow(tmp_26, ELMC_FIELD_MAIN_MODEL_TURN, tmp_27);

      elmc_release(tmp_27);

      ElmcValue *tmp_29 = tmp_18 ? elmc_retain(tmp_18) : elmc_int_zero();
      ElmcValue *tmp_30 = NULL;
      Rc = elmc_tuple2_take(&tmp_30, tmp_28, tmp_29);
      CHECK_RC(Rc);

      elmc_release(tmp_18);

      elmc_release(tmp_17);

      elmc_release(tmp_15);

      elmc_release(tmp_14);

      elmc_release(tmp_13);

      elmc_release(tmp_12);

      tmp_7 = tmp_30;
    }
    elmc_release(tmp_3);

    elmc_release(tmp_2);

    elmc_release(tmp_1);

    *out = tmp_7;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_initialBoard(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *seed = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *tmp_1 = ({ ElmcValue *__z = NULL; RC __call_rc = elmc_fn_Main_emptyBoard(&__z, NULL, 0); if (__call_rc != RC_SUCCESS) { ELMC_RC_LOG_FAIL(__call_rc, "elmc_fn_Main_emptyBoard", "zero-arg call failed"); __z = NULL; } __z; })
    ;

    ElmcValue *call_args_2[2] = { seed, tmp_1 };
    ElmcValue *tmp_2;
    Rc = elmc_fn_Main_spawnTileWithSeed(&tmp_2, call_args_2, 2);
    CHECK_RC(Rc);

    elmc_release(tmp_1);

    ElmcValue *tmp_3 = elmc_tuple_first(tmp_2);

    ElmcValue *tmp_4 = elmc_tuple_second(tmp_2);

    ElmcValue *call_args_5[2] = { tmp_4, tmp_3 };
    ElmcValue *tmp_5;
    Rc = elmc_fn_Main_spawnTileWithSeed(&tmp_5, call_args_5, 2);
    CHECK_RC(Rc);

    elmc_release(tmp_4);

    elmc_release(tmp_3);

    elmc_release(tmp_2);

    *out = tmp_5;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_collapseRows(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *cells = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *tmp_1 = elmc_fn_Main_rowAt_native(0, cells);

    ElmcValue *call_args_2[1] = { tmp_1 };
    ElmcValue *tmp_2;
    Rc = elmc_fn_Main_collapseRow(&tmp_2, call_args_2, 1);
    CHECK_RC(Rc);

    elmc_release(tmp_1);

    ElmcValue *tmp_3 = elmc_fn_Main_rowAt_native(1, cells);

    ElmcValue *call_args_4[1] = { tmp_3 };
    ElmcValue *tmp_4;
    Rc = elmc_fn_Main_collapseRow(&tmp_4, call_args_4, 1);
    CHECK_RC(Rc);

    elmc_release(tmp_3);

    ElmcValue *tmp_5 = elmc_fn_Main_rowAt_native(2, cells);

    ElmcValue *call_args_6[1] = { tmp_5 };
    ElmcValue *tmp_6;
    Rc = elmc_fn_Main_collapseRow(&tmp_6, call_args_6, 1);
    CHECK_RC(Rc);

    elmc_release(tmp_5);

    ElmcValue *tmp_7 = elmc_fn_Main_rowAt_native(3, cells);

    ElmcValue *call_args_8[1] = { tmp_7 };
    ElmcValue *tmp_8;
    Rc = elmc_fn_Main_collapseRow(&tmp_8, call_args_8, 1);
    CHECK_RC(Rc);

    elmc_release(tmp_7);

    ElmcValue *tmp_9_cells = elmc_record_get_index(tmp_2, ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS);

    ElmcValue *tmp_10_cells = elmc_record_get_index(tmp_4, ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS);

    ElmcValue *tmp_11_cells = elmc_record_get_index(tmp_6, ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS);

    ElmcValue *tmp_12_cells = elmc_record_get_index(tmp_8, ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS);

    ElmcValue *list_concat_segments_13[4] = { tmp_9_cells, tmp_10_cells, tmp_11_cells, tmp_12_cells };
    ElmcValue *tmp_13 = NULL;
    Rc = elmc_list_concat_array(&tmp_13, list_concat_segments_13, 4);
    CHECK_RC(Rc);
    elmc_release(tmp_9_cells);
    elmc_release(tmp_10_cells);
    elmc_release(tmp_11_cells);
    elmc_release(tmp_12_cells);

    ElmcValue *tmp_14_boxed_int = elmc_new_int_take((((ELMC_RECORD_GET_INDEX_INT(tmp_2, ELMC_FIELD_MAIN_COLLAPSERESULT_SCORE) + ELMC_RECORD_GET_INDEX_INT(tmp_4, ELMC_FIELD_MAIN_COLLAPSERESULT_SCORE)) + ELMC_RECORD_GET_INDEX_INT(tmp_6, ELMC_FIELD_MAIN_COLLAPSERESULT_SCORE)) + ELMC_RECORD_GET_INDEX_INT(tmp_8, ELMC_FIELD_MAIN_COLLAPSERESULT_SCORE)));

    ElmcValue *rec_values_15[2] = { tmp_13, tmp_14_boxed_int };
    ElmcValue *tmp_15 = NULL;
    Rc = elmc_record_new_values_take(&tmp_15, 2, rec_values_15);
    CHECK_RC(Rc);

    elmc_release(tmp_8);

    elmc_release(tmp_6);

    elmc_release(tmp_4);

    elmc_release(tmp_2);

    *out = tmp_15;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_collapseRow(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *row = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *tmp_1 = row ? elmc_retain(row) : elmc_int_zero();
    ElmcValue *list_fwd_head_2 = elmc_list_nil();
    ElmcValue **list_fwd_tail_2 = &list_fwd_head_2;

    // List.filter

    ElmcValue *list_filter_cursor_2 = tmp_1;
    while (list_filter_cursor_2 && list_filter_cursor_2->tag == ELMC_TAG_LIST && list_filter_cursor_2->payload != NULL) {
      ElmcCons *list_filter_node_2 = (ElmcCons *)list_filter_cursor_2->payload;
      ElmcValue *list_filter_head_2 = list_filter_node_2->head;

      if ((0 != elmc_as_int(list_filter_head_2))) {
        ElmcValue *list_fwd_cell_2 = NULL;
        Rc = elmc_list_cons(&list_fwd_cell_2, list_filter_head_2, elmc_list_nil());
        CHECK_RC(Rc);
        *list_fwd_tail_2 = list_fwd_cell_2;
        list_fwd_tail_2 = &((ElmcCons *)list_fwd_cell_2->payload)->tail;

      }
      list_filter_cursor_2 = list_filter_node_2->tail;
    }
    ElmcValue *tmp_3 = list_fwd_head_2;

    elmc_release(tmp_1);

    ElmcValue *call_args_4[1] = { tmp_3 };
    ElmcValue *tmp_4;
    Rc = elmc_fn_Main_merge(&tmp_4, call_args_4, 1);
    CHECK_RC(Rc);

    elmc_release(tmp_3);

    ElmcValue *tmp_5_cells = elmc_record_get_index(tmp_4, ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS);

    // List.length
    elmc_int_t list_length_count_6 = 0;
    ElmcValue *list_length_cursor_6 = tmp_5_cells;
    while (list_length_cursor_6 && list_length_cursor_6->tag == ELMC_TAG_LIST && list_length_cursor_6->payload != NULL) {
      ElmcCons *list_length_node_6 = (ElmcCons *)list_length_cursor_6->payload;
      list_length_count_6++;
      list_length_cursor_6 = list_length_node_6->tail;
    }

    elmc_release(tmp_5_cells);

    // List.repeat
    ElmcValue *list_repeat_acc_6 = elmc_list_nil();
    for (elmc_int_t list_repeat_i_6 = 0; list_repeat_i_6 < (4 - list_length_count_6); list_repeat_i_6++) {
      ElmcValue *list_repeat_cons_6 = NULL;
      Rc = elmc_list_cons(&list_repeat_cons_6, elmc_int_zero(), list_repeat_acc_6);
      CHECK_RC(Rc);
      elmc_release(list_repeat_acc_6);
      list_repeat_acc_6 = list_repeat_cons_6;
    }
    if (!list_repeat_acc_6)
      list_repeat_acc_6 = elmc_list_nil();

    ElmcValue *tmp_6 = elmc_append(ELMC_RECORD_GET_INDEX(tmp_4, ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS), list_repeat_acc_6);
    elmc_release(list_repeat_acc_6);

    ElmcValue *tmp_7_boxed_int = elmc_new_int_take(ELMC_RECORD_GET_INDEX_INT(tmp_4, ELMC_FIELD_MAIN_COLLAPSERESULT_SCORE));

    ElmcValue *rec_values_8[2] = { tmp_6, tmp_7_boxed_int };
    ElmcValue *tmp_8 = NULL;
    Rc = elmc_record_new_values_take(&tmp_8, 2, rec_values_8);
    CHECK_RC(Rc);

    elmc_release(tmp_4);

    *out = tmp_8;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_merge(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *values = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *tmp_1 = NULL;

    if (values && values->tag == ELMC_TAG_LIST && values->payload != NULL && (1) && (((ElmcCons *)values->payload)->tail && ((ElmcCons *)values->payload)->tail->tag == ELMC_TAG_LIST && ((ElmcCons *)values->payload)->tail->payload != NULL && (1) && (1))) {
      ElmcValue *tmp_3 = NULL;
      if ((elmc_as_int(((ElmcCons *)values->payload)->head) == elmc_as_int(((ElmcCons *)((ElmcCons *)values->payload)->tail->payload)->head))) {
        ElmcValue *call_args_5[1] = { ((ElmcCons *)((ElmcCons *)values->payload)->tail->payload)->tail };
        ElmcValue *tmp_5;
        Rc = elmc_fn_Main_merge(&tmp_5, call_args_5, 1);
        CHECK_RC(Rc);

        ElmcValue *tmp_6 = NULL;
        Rc = elmc_new_int(&tmp_6, (elmc_as_int(((ElmcCons *)values->payload)->head) + elmc_as_int(((ElmcCons *)((ElmcCons *)values->payload)->tail->payload)->head)));
        CHECK_RC(Rc);

        ElmcValue *tmp_7_cells = elmc_record_get_index(tmp_5, ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS);

        ElmcValue *tmp_8 = NULL;
        Rc = elmc_list_cons(&tmp_8, tmp_6, tmp_7_cells);
        CHECK_RC(Rc);
        elmc_release(tmp_7_cells);

        ElmcValue *tmp_9_boxed_int = elmc_new_int_take((elmc_as_int(tmp_6) + ELMC_RECORD_GET_INDEX_INT(tmp_5, ELMC_FIELD_MAIN_COLLAPSERESULT_SCORE)));

        ElmcValue *rec_values_10[2] = { tmp_8, tmp_9_boxed_int };
        ElmcValue *tmp_10 = NULL;
        Rc = elmc_record_new_values_take(&tmp_10, 2, rec_values_10);
        CHECK_RC(Rc);

        elmc_release(tmp_6);

        elmc_release(tmp_5);

        tmp_3 = tmp_10;
      } else {
        ElmcValue *tmp_11 = ((ElmcCons *)((ElmcCons *)values->payload)->tail->payload)->tail ? elmc_list_copy_take(((ElmcCons *)((ElmcCons *)values->payload)->tail->payload)->tail) : elmc_int_zero();
        ElmcValue *tmp_12 = elmc_list_cons_take(((ElmcCons *)((ElmcCons *)values->payload)->tail->payload)->head, tmp_11);

        ElmcValue *call_args_13[1] = { tmp_12 };
        ElmcValue *tmp_13;
        Rc = elmc_fn_Main_merge(&tmp_13, call_args_13, 1);
        CHECK_RC(Rc);

        elmc_release(tmp_12);

        ElmcValue *tmp_14_cells = elmc_record_get_index(tmp_13, ELMC_FIELD_MAIN_COLLAPSERESULT_CELLS);

        ElmcValue *tmp_15 = NULL;
        Rc = elmc_list_cons(&tmp_15, ((ElmcCons *)values->payload)->head, tmp_14_cells);
        CHECK_RC(Rc);
        elmc_release(tmp_14_cells);

        ElmcValue *tmp_16_boxed_int = elmc_new_int_take(ELMC_RECORD_GET_INDEX_INT(tmp_13, ELMC_FIELD_MAIN_COLLAPSERESULT_SCORE));

        ElmcValue *rec_values_17[2] = { tmp_15, tmp_16_boxed_int };
        ElmcValue *tmp_17 = NULL;
        Rc = elmc_record_new_values_take(&tmp_17, 2, rec_values_17);
        CHECK_RC(Rc);

        elmc_release(tmp_13);

        tmp_3 = tmp_17;
      }

      tmp_1 = tmp_3;

    } else {
      ElmcValue *tmp_18 = values ? elmc_list_copy_take(values) : elmc_int_zero();
      ElmcValue *tmp_19_boxed_int = elmc_new_int_take(0);

      ElmcValue *rec_values_20[2] = { tmp_18, tmp_19_boxed_int };
      ElmcValue *tmp_20 = NULL;
      Rc = elmc_record_new_values_take(&tmp_20, 2, rec_values_20);
      CHECK_RC(Rc);

      tmp_1 = tmp_20;
    }

    *out = tmp_1;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_spawnTileWithSeed(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *seed = (argc > 0) ? args[0] : NULL;
  ElmcValue *cells = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const elmc_int_t native_call_1 = elmc_fn_Main_countEmpty_native(cells);

    const elmc_int_t native_let_emptyCount_2 = native_call_1;

    elmc_int_t native_mod_2 = ((elmc_as_int(seed) * 16807) + 11) % 2147483647;
    if (native_mod_2 < 0)
      native_mod_2 += 2147483647;
    // inlined Main.advanceSeed

    const elmc_int_t native_let_seedAfterChoice_3 = native_mod_2;

    elmc_int_t native_mod_3 = ((native_let_seedAfterChoice_3 * 16807) + 11) % 2147483647;
    if (native_mod_3 < 0)
      native_mod_3 += 2147483647;
    // inlined Main.advanceSeed

    const elmc_int_t native_let_seedAfterTile_4 = native_mod_3;

    bool native_bool_if_4;
    if ((native_let_emptyCount_2 < 0)) {

      native_bool_if_4 = true;
    } else {

      native_bool_if_4 = (native_let_emptyCount_2 == 0);
    }

    elmc_int_t native_if_6;
    if (native_bool_if_4) {

      native_if_6 = 0;
    } else {

      const elmc_int_t native_mod_base_5 = native_let_emptyCount_2;
      elmc_int_t native_mod_5 = 0;
      if (native_mod_base_5 != 0) {
        native_mod_5 = native_let_seedAfterChoice_3 % native_mod_base_5;
        if (native_mod_5 < 0)
          native_mod_5 += (native_mod_base_5 < 0 ? -native_mod_base_5 : native_mod_base_5);
      }

      native_if_6 = native_mod_5;
    }
    // inlined Main.randomIndex

    const elmc_int_t native_call_7 = elmc_fn_Main_nthEmptyIndexHelp_native(native_if_6, 0, cells);

    // inlined Main.nthEmptyIndex
    ElmcValue *tmp_8 = NULL;
    Rc = elmc_new_int(&tmp_8, native_call_7);
    CHECK_RC(Rc);

    bool native_bool_if_9;
    if ((10 < 0)) {

      native_bool_if_9 = true;
    } else {

      native_bool_if_9 = (10 == 0);
    }

    elmc_int_t native_if_11;
    if (native_bool_if_9) {

      native_if_11 = 0;
    } else {

      elmc_int_t native_mod_10 = native_let_seedAfterTile_4 % 10;
      if (native_mod_10 < 0)
        native_mod_10 += 10;

      native_if_11 = native_mod_10;
    }
    // inlined Main.randomIndex

    elmc_int_t native_if_12;
    if ((native_if_11 == 0)) {

      native_if_12 = 4;
    } else {

      native_if_12 = 2;
    }
    ElmcValue *tmp_13 = NULL;
    Rc = elmc_new_int(&tmp_13, native_if_12);
    CHECK_RC(Rc);

    ElmcValue *tmp_14 = NULL;
    if ((native_let_emptyCount_2 == 0)) {
      ElmcValue *tmp_16 = cells ? elmc_retain(cells) : elmc_int_zero();
      ElmcValue *tmp_17 = NULL;
      Rc = elmc_new_int(&tmp_17, native_let_seedAfterTile_4);
      CHECK_RC(Rc);

      ElmcValue *tmp_18 = NULL;
      Rc = elmc_tuple2_take(&tmp_18, tmp_16, tmp_17);
      CHECK_RC(Rc);

      tmp_14 = tmp_18;
    } else {
      ElmcValue *call_args_19[3] = { tmp_8, tmp_13, cells };
      ElmcValue *tmp_19;
      Rc = elmc_fn_Main_setCell(&tmp_19, call_args_19, 3);
      CHECK_RC(Rc);

      ElmcValue *tmp_20 = NULL;
      Rc = elmc_new_int(&tmp_20, native_let_seedAfterTile_4);
      CHECK_RC(Rc);

      ElmcValue *tmp_21 = NULL;
      Rc = elmc_tuple2_take(&tmp_21, tmp_19, tmp_20);
      CHECK_RC(Rc);

      tmp_14 = tmp_21;
    }
    elmc_release(tmp_13);

    elmc_release(tmp_8);

    *out = tmp_14;
  CATCH_END;

  return Rc;
}

static ElmcValue *elmc_fn_Main_advanceSeed(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  elmc_int_t seed = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;

  return elmc_new_int_take(elmc_fn_Main_advanceSeed_native(seed));
}

static elmc_int_t elmc_fn_Main_advanceSeed_native(const elmc_int_t seed) {

  elmc_int_t native_mod_1 = ((seed * 16807) + 11) % 2147483647;
  if (native_mod_1 < 0)
    native_mod_1 += 2147483647;

  return native_mod_1;
}

static RC elmc_fn_Main_randomIndex(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  elmc_int_t maxExclusive = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  elmc_int_t seed = (argc > 1 && args[1]) ? elmc_as_int(args[1]) : 0;

  *out = elmc_new_int_take(elmc_fn_Main_randomIndex_native(maxExclusive, seed));
  return RC_SUCCESS;

}

static elmc_int_t elmc_fn_Main_randomIndex_native(const elmc_int_t maxExclusive, const elmc_int_t seed) {

  bool native_bool_if_1;
  if ((maxExclusive < 0)) {

    native_bool_if_1 = true;
  } else {

    native_bool_if_1 = (maxExclusive == 0);
  }

  elmc_int_t native_if_3;
  if (native_bool_if_1) {

    native_if_3 = 0;
  } else {

    const elmc_int_t native_mod_base_2 = maxExclusive;
    elmc_int_t native_mod_2 = 0;
    if (native_mod_base_2 != 0) {
      native_mod_2 = seed % native_mod_base_2;
      if (native_mod_2 < 0)
        native_mod_2 += (native_mod_base_2 < 0 ? -native_mod_base_2 : native_mod_base_2);
    }

    native_if_3 = native_mod_2;
  }

  return native_if_3;
}

static ElmcValue *elmc_fn_Main_countEmpty(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  ElmcValue *cells = (argc > 0) ? args[0] : NULL;

  return elmc_new_int_take(elmc_fn_Main_countEmpty_native(cells));
}

static elmc_int_t elmc_fn_Main_countEmpty_native(ElmcValue * const cells) {

  elmc_int_t list_reduce_acc_518 = 0;
  ElmcValue *list_reduce_cursor_518 = cells;
  while (list_reduce_cursor_518 && list_reduce_cursor_518->tag == ELMC_TAG_LIST && list_reduce_cursor_518->payload != NULL) {
    ElmcCons *list_reduce_node_518 = (ElmcCons *)list_reduce_cursor_518->payload;
    const elmc_int_t list_reduce_head_518 = elmc_as_int(list_reduce_node_518->head);

    elmc_int_t native_if_1;
    if ((list_reduce_head_518 == 0)) {

      native_if_1 = 1;
    } else {

      native_if_1 = 0;
    }

    list_reduce_acc_518 += native_if_1;
    list_reduce_cursor_518 = list_reduce_node_518->tail;
  }

  return list_reduce_acc_518;
}

static ElmcValue *elmc_fn_Main_nthEmptyIndex(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  ElmcValue *target = (argc > 0) ? args[0] : NULL;
  ElmcValue *cells = (argc > 1) ? args[1] : NULL;

  return elmc_new_int_take(elmc_fn_Main_nthEmptyIndex_native(target, cells));
}

static elmc_int_t elmc_fn_Main_nthEmptyIndex_native(ElmcValue * const target, ElmcValue * const cells) {

  const elmc_int_t native_call_1 = elmc_fn_Main_nthEmptyIndexHelp_native(elmc_as_int(target), 0, cells);

  return native_call_1;
}

static ElmcValue *elmc_fn_Main_nthEmptyIndexHelp(ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  elmc_int_t target = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  elmc_int_t index = (argc > 1 && args[1]) ? elmc_as_int(args[1]) : 0;
  ElmcValue *cells = (argc > 2) ? args[2] : NULL;

  return elmc_new_int_take(elmc_fn_Main_nthEmptyIndexHelp_native(target, index, cells));
}

static elmc_int_t elmc_fn_Main_nthEmptyIndexHelp_native(const elmc_int_t target, const elmc_int_t index, ElmcValue * const cells) {

  elmc_int_t list_search_target_582 = target;
  elmc_int_t list_search_index_582 = index;
  elmc_int_t list_search_result_582 = -1;
  ElmcValue *list_search_cursor_582 = cells;
  while (list_search_cursor_582 && list_search_cursor_582->tag == ELMC_TAG_LIST && list_search_cursor_582->payload != NULL) {
    ElmcCons *list_search_node_582 = (ElmcCons *)list_search_cursor_582->payload;
    const elmc_int_t list_search_head_582 = elmc_as_int(list_search_node_582->head);
    if ((list_search_head_582 == 0)) {
      if ((list_search_target_582 == 0)) {
        list_search_result_582 = list_search_index_582;
        break;
      }
      list_search_target_582--;
    }
    list_search_index_582++;
    list_search_cursor_582 = list_search_node_582->tail;
  }

  return list_search_result_582;
}

static RC elmc_fn_Main_setCell(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *index = (argc > 0) ? args[0] : NULL;
  ElmcValue *newValue = (argc > 1) ? args[1] : NULL;
  ElmcValue *cells = (argc > 2) ? args[2] : NULL;

  ElmcValue *tmp_1 = elmc_list_replace_nth_int(cells, elmc_as_int(index), elmc_as_int(newValue));

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Main_orient(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *direction = (argc > 0) ? args[0] : NULL;
  ElmcValue *cells = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (direction && (direction)->tag == ELMC_TAG_INT ? elmc_as_int(direction) : (direction && (direction)->tag == ELMC_TAG_TUPLE2 && (direction)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(direction)->payload)->first) : -1));
    ElmcValue *tmp_1;
    switch (case_msg_tag_1) {
      case ELMC_UNION_LEFT: {
        tmp_1 = cells ? elmc_retain(cells) : elmc_int_zero();
        break;
      }
      case ELMC_UNION_RIGHT: {

        ElmcValue *call_args_3[1] = { cells };
        Rc = elmc_fn_Main_reverseRows(&tmp_1, call_args_3, 1);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_UNION_UP: {

        ElmcValue *call_args_4[1] = { cells };
        Rc = elmc_fn_Main_transpose(&tmp_1, call_args_4, 1);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_UNION_DOWN: {

        ElmcValue *call_args_5[1] = { cells };
        ElmcValue *tmp_5;
        Rc = elmc_fn_Main_transpose(&tmp_5, call_args_5, 1);
        CHECK_RC(Rc);

        ElmcValue *call_args_6[1] = { tmp_5 };
        Rc = elmc_fn_Main_reverseRows(&tmp_1, call_args_6, 1);
        CHECK_RC(Rc);

        elmc_release(tmp_5);

        break;
      }
      default:
        tmp_1 = elmc_int_zero();
        break;

    }

    *out = tmp_1;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_restore(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *direction = (argc > 0) ? args[0] : NULL;
  ElmcValue *cells = (argc > 1) ? args[1] : NULL;

  CATCH_BEGIN

    const int case_msg_tag_1 = (direction && (direction)->tag == ELMC_TAG_INT ? elmc_as_int(direction) : (direction && (direction)->tag == ELMC_TAG_TUPLE2 && (direction)->payload != NULL ? elmc_as_int(((ElmcTuple2 *)(direction)->payload)->first) : -1));
    ElmcValue *tmp_1;
    switch (case_msg_tag_1) {
      case ELMC_UNION_LEFT: {
        tmp_1 = cells ? elmc_retain(cells) : elmc_int_zero();
        break;
      }
      case ELMC_UNION_RIGHT: {

        ElmcValue *call_args_3[1] = { cells };
        Rc = elmc_fn_Main_reverseRows(&tmp_1, call_args_3, 1);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_UNION_UP: {

        ElmcValue *call_args_4[1] = { cells };
        Rc = elmc_fn_Main_transpose(&tmp_1, call_args_4, 1);
        CHECK_RC(Rc);

        break;
      }
      case ELMC_UNION_DOWN: {

        ElmcValue *call_args_5[1] = { cells };
        ElmcValue *tmp_5;
        Rc = elmc_fn_Main_reverseRows(&tmp_5, call_args_5, 1);
        CHECK_RC(Rc);

        ElmcValue *call_args_6[1] = { tmp_5 };
        Rc = elmc_fn_Main_transpose(&tmp_1, call_args_6, 1);
        CHECK_RC(Rc);

        elmc_release(tmp_5);

        break;
      }
      default:
        tmp_1 = elmc_int_zero();
        break;

    }

    *out = tmp_1;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_rowAt(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  elmc_int_t row = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;
  ElmcValue *cells = (argc > 1) ? args[1] : NULL;

  ElmcValue *tmp_result = elmc_fn_Main_rowAt_native(row, cells);
  *out = tmp_result;
  return RC_SUCCESS;

}

static ElmcValue *elmc_fn_Main_rowAt_native(const elmc_int_t row, ElmcValue * const cells) {

  ElmcValue *tmp_1 = elmc_list_drop_int_take((row * 4), cells);

  ElmcValue *tmp_2 = elmc_list_take_int_take(4, tmp_1);
  elmc_release(tmp_1);

  return tmp_2;
}

static RC elmc_fn_Main_reverseRows(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *cells = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    ElmcValue *tmp_1 = elmc_fn_Main_rowAt_native(0, cells);

    ElmcValue *tmp_2 = NULL;
    Rc = elmc_list_reverse(&tmp_2, tmp_1);
    CHECK_RC(Rc);
    elmc_release(tmp_1);

    ElmcValue *tmp_3 = elmc_fn_Main_rowAt_native(1, cells);

    ElmcValue *tmp_4 = NULL;
    Rc = elmc_list_reverse(&tmp_4, tmp_3);
    CHECK_RC(Rc);
    elmc_release(tmp_3);

    ElmcValue *tmp_5 = elmc_fn_Main_rowAt_native(2, cells);

    ElmcValue *tmp_6 = NULL;
    Rc = elmc_list_reverse(&tmp_6, tmp_5);
    CHECK_RC(Rc);
    elmc_release(tmp_5);

    ElmcValue *tmp_7 = elmc_fn_Main_rowAt_native(3, cells);

    ElmcValue *tmp_8 = NULL;
    Rc = elmc_list_reverse(&tmp_8, tmp_7);
    CHECK_RC(Rc);
    elmc_release(tmp_7);

    ElmcValue *list_concat_segments_9[4] = { tmp_2, tmp_4, tmp_6, tmp_8 };
    ElmcValue *tmp_9 = NULL;
    Rc = elmc_list_concat_array(&tmp_9, list_concat_segments_9, 4);
    CHECK_RC(Rc);
    elmc_release(tmp_2);
    elmc_release(tmp_4);
    elmc_release(tmp_6);
    elmc_release(tmp_8);

    *out = tmp_9;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_transpose(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *cells = (argc > 0) ? args[0] : NULL;

  CATCH_BEGIN

    static const elmc_int_t list_int_values_1[16] = { 0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15 };
    ElmcValue *tmp_1 = NULL;
    Rc = elmc_list_from_int_array(&tmp_1, list_int_values_1, 16);
    CHECK_RC(Rc);

    ElmcValue *list_fwd_head_2 = elmc_list_nil();
    ElmcValue **list_fwd_tail_2 = &list_fwd_head_2;

    // List.map

    ElmcValue *list_map_cursor_2 = tmp_1;
    while (list_map_cursor_2 && list_map_cursor_2->tag == ELMC_TAG_LIST && list_map_cursor_2->payload != NULL) {
      ElmcCons *list_map_node_2 = (ElmcCons *)list_map_cursor_2->payload;
      ElmcValue *list_map_head_2 = list_map_node_2->head;

      ElmcValue *call_args_3[2] = { list_map_head_2, cells };
      ElmcValue *tmp_3;
      Rc = elmc_fn_Main_listAt(&tmp_3, call_args_3, 2);
      CHECK_RC(Rc);

      const elmc_int_t native_maybe_default_4 = elmc_maybe_with_default_int(0, tmp_3);
      elmc_release(tmp_3);

      ElmcValue *list_map_item_2 = NULL;
      Rc = elmc_new_int(&list_map_item_2, native_maybe_default_4);
      CHECK_RC(Rc);
      ElmcValue *list_fwd_cell_2 = NULL;
      Rc = elmc_list_cons(&list_fwd_cell_2, list_map_item_2, elmc_list_nil());
      CHECK_RC(Rc);
      *list_fwd_tail_2 = list_fwd_cell_2;
      list_fwd_tail_2 = &((ElmcCons *)list_fwd_cell_2->payload)->tail;

      list_map_cursor_2 = list_map_node_2->tail;
    }
    ElmcValue *tmp_2 = list_fwd_head_2;

    elmc_release(tmp_1);

    *out = tmp_2;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_listAt(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, retain_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *index = (argc > 0) ? args[0] : NULL;
  ElmcValue *values = (argc > 1) ? args[1] : NULL;

  ElmcValue *tmp_1 = NULL;
  if ((elmc_as_int(index) < 0)) {
    tmp_1 = elmc_maybe_nothing();
  } else {
    tmp_1 = elmc_list_nth_maybe(values, index);
  }

  *out = tmp_1;

  return Rc;
}

RC elmc_fn_Main_subscriptions(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  ElmcValue *_unused_0 = (argc > 0) ? args[0] : NULL;
  (void)_unused_0;

  CATCH_BEGIN

    ElmcValue *tmp_1 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_BACK, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_LEFTPRESSED);

    ElmcValue *tmp_2 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_UP, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_UPPRESSED);

    ElmcValue *tmp_3 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_DOWN, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_DOWNPRESSED);

    ElmcValue *tmp_4 = elmc_sub3(ELMC_SUBSCRIPTION_BUTTON_RAW, ELMC_BUTTON_SELECT, ELMC_BUTTON_EVENT_PRESSED, ELMC_PEBBLE_MSG_RIGHTPRESSED);

    ElmcValue *list_items_5[4] = { tmp_1, tmp_2, tmp_3, tmp_4 };
    ElmcValue *tmp_5 = NULL;
    Rc = elmc_list_from_values_take(&tmp_5, list_items_5, 4);
    CHECK_RC(Rc);

    *out = tmp_5;
  CATCH_END;

  return Rc;
}

static RC elmc_fn_Main_main(ElmcValue **out, ElmcValue ** const args, const int argc) {
  /* Ownership policy: borrow_arg, borrow_result */
  RC Rc = RC_SUCCESS;

  (void)args;
  (void)argc;

  ElmcValue *tmp_1 = elmc_int_zero();

  *out = tmp_1;

  return Rc;
}

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Main_drawCell_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);
static RC elmc_fn_Main_drawCell_commands_append_native(ElmcValue * const layout, const elmc_int_t index, const elmc_int_t value, ElmcSceneWriter * const writer);

static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *model = (argc > 0) ? args[0] : NULL;

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    ElmcValue *native_union_subject_1 = ELMC_RECORD_GET_INDEX(model, ELMC_FIELD_MAIN_MODEL_DISPLAYSHAPE);
    const bool native_b_1 = (native_union_subject_1) && (((native_union_subject_1)->tag == ELMC_TAG_INT && elmc_as_int(native_union_subject_1) == 2) || ((native_union_subject_1)->tag == ELMC_TAG_TUPLE2 && (native_union_subject_1)->payload != NULL && elmc_as_int(((ElmcTuple2 *)(native_union_subject_1)->payload)->first) == 2));
    const elmc_int_t native_min_left_3 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_SCREENW);
    const elmc_int_t native_min_right_3 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_SCREENH);
    const elmc_int_t native_min_3 = (native_min_left_3 <= native_min_right_3) ? native_min_left_3 : native_min_right_3;
    const elmc_int_t direct_native_record_branch__then_y_2 = ((ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_SCREENH) - ((((((native_min_3 * 2) / 3) - (2 * 3)) / 4) * 4) + (2 * 3))) / 2);
    const elmc_int_t direct_native_record_branch__then_x_3 = ((ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_SCREENW) - ((((((native_min_3 * 2) / 3) - (2 * 3)) / 4) * 4) + (2 * 3))) / 2);
    const elmc_int_t direct_native_record_branch__then_gap_3 = 2;
    const elmc_int_t direct_native_record_branch__then_cell_3 = ((((native_min_3 * 2) / 3) - (2 * 3)) / 4);
    const elmc_int_t direct_native_record_branch__else_y_3 = 26;
    const elmc_int_t direct_native_record_branch__else_x_3 = ((native_min_3 - ((((((native_min_3 - (12 * 2)) - (3 * 2)) - (3 * 3)) / 4) * 4) + (3 * 3))) / 2);
    const elmc_int_t direct_native_record_branch__else_gap_3 = 3;
    const elmc_int_t direct_native_record_branch__else_cell_3 = ((((native_min_3 - (12 * 2)) - (3 * 2)) - (3 * 3)) / 4);
    const elmc_int_t direct_native_record_layout_cell_4 = (native_b_1) ? direct_native_record_branch__then_cell_3 : direct_native_record_branch__else_cell_3;
    const elmc_int_t direct_native_record_layout_gap_5 = (native_b_1) ? direct_native_record_branch__then_gap_3 : direct_native_record_branch__else_gap_3;
    const elmc_int_t direct_native_record_layout_x_6 = (native_b_1) ? direct_native_record_branch__then_x_3 : direct_native_record_branch__else_x_3;
    const elmc_int_t direct_native_record_layout_y_7 = (native_b_1) ? direct_native_record_branch__then_y_2 : direct_native_record_branch__else_y_3;

    const elmc_int_t direct_native_let_textOptions_8 = (ELMC_TEXT_ALIGN_CENTER + (ELMC_TEXT_OVERFLOW_WORD_WRAP * (1 << ELMC_TEXT_OVERFLOW_SHIFT)));

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CLEAR);
    scene_cmd.p0 = ELMC_COLOR_WHITE;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    if (native_b_1) {

      const elmc_int_t native_min_left_10 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_SCREENW);
      const elmc_int_t native_min_right_10 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_SCREENH);
      const elmc_int_t native_min_10 = (native_min_left_10 <= native_min_right_10) ? native_min_left_10 : native_min_right_10;

      const elmc_int_t direct_native_let_textW_11 = ((native_min_10 * 4) / 9);

      const elmc_int_t direct_native_let_textX_12 = ((ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_SCREENW) - direct_native_let_textW_11) / 2);

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = direct_native_let_textX_12;
      scene_cmd.p2 = 10;
      scene_cmd.p3 = direct_native_let_textW_11;
      scene_cmd.p4 = 14;
      scene_cmd.p5 = direct_native_let_textOptions_8;
      {
        scene_cmd.text[0] = '2';
        scene_cmd.text[1] = '0';
        scene_cmd.text[2] = '4';
        scene_cmd.text[3] = '8';
        scene_cmd.text[4] = '\0';
      }

      if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
        Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
        break;
      }

      char native_string_buf_13[32];
      snprintf(native_string_buf_13, sizeof(native_string_buf_13), "%lld", (long long)ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_BEST));
      const char *native_string_13 = native_string_buf_13;

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = direct_native_let_textX_12;
      scene_cmd.p2 = (ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_SCREENH) - 24);
      scene_cmd.p3 = direct_native_let_textW_11;
      scene_cmd.p4 = 14;
      scene_cmd.p5 = direct_native_let_textOptions_8;
      {
        scene_cmd.text[0] = 'B';
        scene_cmd.text[1] = 'e';
        scene_cmd.text[2] = 's';
        scene_cmd.text[3] = 't';
        scene_cmd.text[4] = ' ';
        int direct_text_i = 5;
        const char *direct_text_right = native_string_13;
        int direct_text_right_i = 0;
        while (direct_text_right && direct_text_right[direct_text_right_i] && direct_text_i < 63) {
          scene_cmd.text[direct_text_i] = direct_text_right[direct_text_right_i];
          direct_text_i++;
          direct_text_right_i++;
        }
        scene_cmd.text[direct_text_i] = '\0';
      }

      if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
        Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
        break;
      }

    } else {

      char native_string_buf_14[32];
      snprintf(native_string_buf_14, sizeof(native_string_buf_14), "%lld", (long long)ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_BEST));
      const char *native_string_14 = native_string_buf_14;

      elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT);
      scene_cmd.p0 = 1;
      scene_cmd.p1 = 4;
      scene_cmd.p2 = 4;
      scene_cmd.p3 = 132;
      scene_cmd.p4 = 16;
      scene_cmd.p5 = direct_native_let_textOptions_8;
      {
        scene_cmd.text[0] = '2';
        scene_cmd.text[1] = '0';
        scene_cmd.text[2] = '4';
        scene_cmd.text[3] = '8';
        scene_cmd.text[4] = ' ';
        scene_cmd.text[5] = ' ';
        scene_cmd.text[6] = 'B';
        scene_cmd.text[7] = 'e';
        scene_cmd.text[8] = 's';
        scene_cmd.text[9] = 't';
        scene_cmd.text[10] = ' ';
        int direct_text_i = 11;
        const char *direct_text_right = native_string_14;
        int direct_text_right_i = 0;
        while (direct_text_right && direct_text_right[direct_text_right_i] && direct_text_i < 63) {
          scene_cmd.text[direct_text_i] = direct_text_right[direct_text_right_i];
          direct_text_i++;
          direct_text_right_i++;
        }
        scene_cmd.text[direct_text_i] = '\0';
      }

      if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
        Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
        break;
      }

    }

    ElmcValue *tmp_15 = elmc_record_get_index(model, ELMC_FIELD_MAIN_MODEL_CELLS);

    ElmcValue *direct_cursor_15 = tmp_15;
    elmc_int_t direct_index_15 = 0;
    while (Rc == RC_SUCCESS && direct_cursor_15 && direct_cursor_15->tag == ELMC_TAG_LIST && direct_cursor_15->payload != NULL) {
      ElmcCons *direct_node_15 = (ElmcCons *)direct_cursor_15->payload;
      RC direct_rc_15 = elmc_fn_Main_drawCell_commands_append_native(direct_index_15, elmc_as_int(direct_node_15->head), writer);
      if (direct_rc_15 != RC_SUCCESS) {
        Rc = direct_rc_15;
        elmc_release(tmp_15);

        break;
      }
      direct_index_15++;
      direct_cursor_15 = direct_node_15->tail;
    }
    elmc_release(tmp_15);

  CATCH_END;

  return Rc;

}

RC elmc_fn_Main_view_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_view_commands_append(args, argc, writer);
}

static RC elmc_fn_Main_drawCell_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  ElmcValue *layout = (argc > 0) ? args[0] : NULL;
  elmc_int_t index = (argc > 1 && args[1]) ? elmc_as_int(args[1]) : 0;
  elmc_int_t value = (argc > 2 && args[2]) ? elmc_as_int(args[2]) : 0;

  return elmc_fn_Main_drawCell_commands_append_native(layout, index, value, writer);
}

static RC elmc_fn_Main_drawCell_commands_append_native(ElmcValue * const layout, const elmc_int_t index, const elmc_int_t value, ElmcSceneWriter * const writer) {

  if (!writer)
    return RC_ERR_INVALID_ARG;
  RC Rc = RC_SUCCESS;
  static ElmcPebbleDrawCmd scene_cmd;

  CATCH_BEGIN

    elmc_int_t native_mod_1 = index % 4;
    if (native_mod_1 < 0)
      native_mod_1 += 4;

    const elmc_int_t direct_native_let_x_2 = (ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_X) + (native_mod_1 * (ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_CELL) + ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_GAP))));

    const elmc_int_t direct_native_let_y_3 = (ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_Y) + ((index / 4) * (ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_CELL) + ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_GAP))));

    ElmcValue *tmp_4 = NULL;
    if ((value == 0)) {
      Rc = elmc_new_string(&tmp_4, ".");
      CHECK_RC(Rc);
    } else {
      ElmcValue *tmp_6 = NULL;
      Rc = elmc_string_from_native_int(&tmp_6, value);
      CHECK_RC(Rc);

      tmp_4 = tmp_6;
    }

    const elmc_int_t direct_native_let_textY_7 = (direct_native_let_y_3 + ((ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_CELL) - 18) / 2));

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_PUSH_CONTEXT);

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_STROKE_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT_COLOR);
    scene_cmd.p0 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_RECT);
    scene_cmd.p0 = direct_native_let_x_2;
    scene_cmd.p1 = direct_native_let_y_3;
    scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_CELL);
    scene_cmd.p3 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_CELL);
    scene_cmd.p4 = ELMC_COLOR_BLACK;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    ElmcValue *tmp_12 = tmp_4 ? elmc_retain(tmp_4) : elmc_int_zero();
    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_TEXT);
    scene_cmd.p0 = 1;
    scene_cmd.p1 = direct_native_let_x_2;
    scene_cmd.p2 = direct_native_let_textY_7;
    scene_cmd.p3 = ELMC_RECORD_GET_INDEX_INT(layout, ELMC_FIELD_MAIN_BOARDLAYOUT_CELL);
    scene_cmd.p4 = 18;
    scene_cmd.p5 = (ELMC_TEXT_ALIGN_CENTER + (ELMC_TEXT_OVERFLOW_WORD_WRAP * (1 << ELMC_TEXT_OVERFLOW_SHIFT)));
    if (tmp_12 && tmp_12->tag == ELMC_TAG_STRING && tmp_12->payload) {
      const char *direct_text = (const char *)tmp_12->payload;
      int direct_text_i = 0;
      while (direct_text[direct_text_i] && direct_text_i < 63) {
        scene_cmd.text[direct_text_i] = direct_text[direct_text_i];
        direct_text_i++;
      }
      scene_cmd.text[direct_text_i] = '\0';

    }

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }
    elmc_release(tmp_12);

    elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_POP_CONTEXT);

    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
      Rc = RC_ERR_SCENE_BUFFER_OVERFLOW;
      break;
    }

    elmc_release(tmp_4);

  CATCH_END;

  return Rc;

}

RC elmc_fn_Main_drawCell_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
  return elmc_fn_Main_drawCell_commands_append(args, argc, writer);
}
