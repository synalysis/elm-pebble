#include "companion_protocol.h"
#include <string.h>

static ElmcValue *companion_protocol_box_int(int32_t value) {
  ElmcValue *boxed = NULL;
  if (elmc_new_int(&boxed, value) != RC_SUCCESS) return NULL;
  return boxed;
}

static ElmcValue *companion_protocol_box_bool(int value) {
  ElmcValue *boxed = NULL;
  if (elmc_new_bool(&boxed, value) != RC_SUCCESS) return NULL;
  return boxed;
}

static ElmcValue *companion_protocol_box_string(const char *value) {
  ElmcValue *boxed = NULL;
  if (elmc_new_string(&boxed, value) != RC_SUCCESS) return NULL;
  return boxed;
}

static ElmcValue *companion_protocol_tuple2_take(ElmcValue *left, ElmcValue *right) {
  ElmcValue *tuple = NULL;
  if (elmc_tuple2_take(&tuple, left, right) != RC_SUCCESS) return NULL;
  return tuple;
}

static ElmcValue *companion_protocol_box_int_list(const int32_t *values, int32_t count) {
  ElmcValue *list = NULL;
  if (elmc_list_from_int_array(&list, values, count) != RC_SUCCESS) return NULL;
  return list;
}


static int32_t companion_protocol_runtime_tag_COLOR(int32_t wire_code) {
  switch (wire_code) {
    case 1: return 1;
    case 2: return 2;
    case 3: return 3;
    default: return 0;
  }
}


static int32_t companion_protocol_runtime_tag_MEASURE(int32_t wire_code) {
  switch (wire_code) {
    case 1: return 1;
    case 2: return 2;
    default: return 0;
  }
}


static int32_t companion_protocol_wire_code_COLOR(int32_t runtime_tag) {
  switch (runtime_tag) {
    case 1: return 1;
    case 2: return 2;
    case 3: return 3;
    default: return 0;
  }
}


static int32_t companion_protocol_wire_code_MEASURE(int32_t runtime_tag) {
  switch (runtime_tag) {
    case 1: return 1;
    case 2: return 2;
    default: return 0;
  }
}


static elmc_int_t companion_protocol_value_int(ElmcValue *value) {
  return value ? elmc_as_int(value) : 0;
}


static ElmcValue *companion_protocol_new_union_value(int32_t runtime_tag, int32_t value) {
  ElmcValue *tag_value = companion_protocol_box_int(runtime_tag);
  ElmcValue *payload_value = companion_protocol_box_int(value);
  if (!tag_value || !payload_value) {
    if (tag_value) elmc_release(tag_value);
    if (payload_value) elmc_release(payload_value);
    return NULL;
  }

  return companion_protocol_tuple2_take(tag_value, payload_value);
}


static ElmcValue *companion_protocol_new_phone_to_watch_message(int32_t tag, ElmcValue *payload) {
  if (!payload) return NULL;
  ElmcValue *tag_value = companion_protocol_box_int(tag);
  if (!tag_value) return NULL;

  return companion_protocol_tuple2_take(tag_value, payload);
}


static int32_t companion_protocol_decode_list_wire_int(int32_t wire) {
  return wire - COMPANION_PROTOCOL_LIST_WIRE_OFFSET;
}

static int32_t companion_protocol_decode_list_wire_count(int32_t wire) {
  int32_t count = wire - COMPANION_PROTOCOL_LIST_WIRE_OFFSET;
  return count < 0 ? 0 : count;
}


static ElmcValue *companion_protocol_build_echo_point_field1(const CompanionProtocolPhoneToWatchMessage *message) {

ElmcValue *v_field_0 = companion_protocol_box_int(message->wire.wire_echo_point_field1_x);
if (!v_field_0) return NULL;


ElmcValue *v_field_1 = companion_protocol_box_int(message->wire.wire_echo_point_field1_y);
if (!v_field_1) return NULL;
const char *v_names[] = { "x", "y" };
ElmcValue *v_values[] = { v_field_0, v_field_1 };
ElmcValue *v_out = NULL;
if (elmc_record_new_take(&v_out, 2, v_names, v_values) != RC_SUCCESS) return NULL;

  return v_out;
}


static ElmcValue *companion_protocol_build_push_points_field1(const CompanionProtocolPhoneToWatchMessage *message) {
    int32_t v_count = message->wire.wire_push_points_field1_count;
    if (v_count < 0) v_count = 0;
    if (v_count > 16) v_count = 16;
    /* Zero-init: elmc_tuple2_take / list builders release *out when non-NULL. */
    ElmcValue *v_items[16] = {0};
  if (v_count > 0) {

ElmcValue *v_item_0_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_0_x);
if (!v_item_0_field_0) return NULL;


ElmcValue *v_item_0_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_0_y);
if (!v_item_0_field_1) return NULL;
const char *v_item_0_names[] = { "x", "y" };
ElmcValue *v_item_0_values[] = { v_item_0_field_0, v_item_0_field_1 };
ElmcValue *v_item_0_out = NULL;
if (elmc_record_new_take(&v_item_0_out, 2, v_item_0_names, v_item_0_values) != RC_SUCCESS) return NULL;

  v_items[0] = v_item_0_out;
  if (!v_items[0]) return NULL;
}

if (v_count > 1) {

ElmcValue *v_item_1_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_1_x);
if (!v_item_1_field_0) return NULL;


ElmcValue *v_item_1_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_1_y);
if (!v_item_1_field_1) return NULL;
const char *v_item_1_names[] = { "x", "y" };
ElmcValue *v_item_1_values[] = { v_item_1_field_0, v_item_1_field_1 };
ElmcValue *v_item_1_out = NULL;
if (elmc_record_new_take(&v_item_1_out, 2, v_item_1_names, v_item_1_values) != RC_SUCCESS) return NULL;

  v_items[1] = v_item_1_out;
  if (!v_items[1]) return NULL;
}

if (v_count > 2) {

ElmcValue *v_item_2_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_2_x);
if (!v_item_2_field_0) return NULL;


ElmcValue *v_item_2_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_2_y);
if (!v_item_2_field_1) return NULL;
const char *v_item_2_names[] = { "x", "y" };
ElmcValue *v_item_2_values[] = { v_item_2_field_0, v_item_2_field_1 };
ElmcValue *v_item_2_out = NULL;
if (elmc_record_new_take(&v_item_2_out, 2, v_item_2_names, v_item_2_values) != RC_SUCCESS) return NULL;

  v_items[2] = v_item_2_out;
  if (!v_items[2]) return NULL;
}

if (v_count > 3) {

ElmcValue *v_item_3_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_3_x);
if (!v_item_3_field_0) return NULL;


ElmcValue *v_item_3_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_3_y);
if (!v_item_3_field_1) return NULL;
const char *v_item_3_names[] = { "x", "y" };
ElmcValue *v_item_3_values[] = { v_item_3_field_0, v_item_3_field_1 };
ElmcValue *v_item_3_out = NULL;
if (elmc_record_new_take(&v_item_3_out, 2, v_item_3_names, v_item_3_values) != RC_SUCCESS) return NULL;

  v_items[3] = v_item_3_out;
  if (!v_items[3]) return NULL;
}

if (v_count > 4) {

ElmcValue *v_item_4_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_4_x);
if (!v_item_4_field_0) return NULL;


ElmcValue *v_item_4_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_4_y);
if (!v_item_4_field_1) return NULL;
const char *v_item_4_names[] = { "x", "y" };
ElmcValue *v_item_4_values[] = { v_item_4_field_0, v_item_4_field_1 };
ElmcValue *v_item_4_out = NULL;
if (elmc_record_new_take(&v_item_4_out, 2, v_item_4_names, v_item_4_values) != RC_SUCCESS) return NULL;

  v_items[4] = v_item_4_out;
  if (!v_items[4]) return NULL;
}

if (v_count > 5) {

ElmcValue *v_item_5_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_5_x);
if (!v_item_5_field_0) return NULL;


ElmcValue *v_item_5_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_5_y);
if (!v_item_5_field_1) return NULL;
const char *v_item_5_names[] = { "x", "y" };
ElmcValue *v_item_5_values[] = { v_item_5_field_0, v_item_5_field_1 };
ElmcValue *v_item_5_out = NULL;
if (elmc_record_new_take(&v_item_5_out, 2, v_item_5_names, v_item_5_values) != RC_SUCCESS) return NULL;

  v_items[5] = v_item_5_out;
  if (!v_items[5]) return NULL;
}

if (v_count > 6) {

ElmcValue *v_item_6_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_6_x);
if (!v_item_6_field_0) return NULL;


ElmcValue *v_item_6_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_6_y);
if (!v_item_6_field_1) return NULL;
const char *v_item_6_names[] = { "x", "y" };
ElmcValue *v_item_6_values[] = { v_item_6_field_0, v_item_6_field_1 };
ElmcValue *v_item_6_out = NULL;
if (elmc_record_new_take(&v_item_6_out, 2, v_item_6_names, v_item_6_values) != RC_SUCCESS) return NULL;

  v_items[6] = v_item_6_out;
  if (!v_items[6]) return NULL;
}

if (v_count > 7) {

ElmcValue *v_item_7_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_7_x);
if (!v_item_7_field_0) return NULL;


ElmcValue *v_item_7_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_7_y);
if (!v_item_7_field_1) return NULL;
const char *v_item_7_names[] = { "x", "y" };
ElmcValue *v_item_7_values[] = { v_item_7_field_0, v_item_7_field_1 };
ElmcValue *v_item_7_out = NULL;
if (elmc_record_new_take(&v_item_7_out, 2, v_item_7_names, v_item_7_values) != RC_SUCCESS) return NULL;

  v_items[7] = v_item_7_out;
  if (!v_items[7]) return NULL;
}

if (v_count > 8) {

ElmcValue *v_item_8_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_8_x);
if (!v_item_8_field_0) return NULL;


ElmcValue *v_item_8_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_8_y);
if (!v_item_8_field_1) return NULL;
const char *v_item_8_names[] = { "x", "y" };
ElmcValue *v_item_8_values[] = { v_item_8_field_0, v_item_8_field_1 };
ElmcValue *v_item_8_out = NULL;
if (elmc_record_new_take(&v_item_8_out, 2, v_item_8_names, v_item_8_values) != RC_SUCCESS) return NULL;

  v_items[8] = v_item_8_out;
  if (!v_items[8]) return NULL;
}

if (v_count > 9) {

ElmcValue *v_item_9_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_9_x);
if (!v_item_9_field_0) return NULL;


ElmcValue *v_item_9_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_9_y);
if (!v_item_9_field_1) return NULL;
const char *v_item_9_names[] = { "x", "y" };
ElmcValue *v_item_9_values[] = { v_item_9_field_0, v_item_9_field_1 };
ElmcValue *v_item_9_out = NULL;
if (elmc_record_new_take(&v_item_9_out, 2, v_item_9_names, v_item_9_values) != RC_SUCCESS) return NULL;

  v_items[9] = v_item_9_out;
  if (!v_items[9]) return NULL;
}

if (v_count > 10) {

ElmcValue *v_item_10_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_10_x);
if (!v_item_10_field_0) return NULL;


ElmcValue *v_item_10_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_10_y);
if (!v_item_10_field_1) return NULL;
const char *v_item_10_names[] = { "x", "y" };
ElmcValue *v_item_10_values[] = { v_item_10_field_0, v_item_10_field_1 };
ElmcValue *v_item_10_out = NULL;
if (elmc_record_new_take(&v_item_10_out, 2, v_item_10_names, v_item_10_values) != RC_SUCCESS) return NULL;

  v_items[10] = v_item_10_out;
  if (!v_items[10]) return NULL;
}

if (v_count > 11) {

ElmcValue *v_item_11_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_11_x);
if (!v_item_11_field_0) return NULL;


ElmcValue *v_item_11_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_11_y);
if (!v_item_11_field_1) return NULL;
const char *v_item_11_names[] = { "x", "y" };
ElmcValue *v_item_11_values[] = { v_item_11_field_0, v_item_11_field_1 };
ElmcValue *v_item_11_out = NULL;
if (elmc_record_new_take(&v_item_11_out, 2, v_item_11_names, v_item_11_values) != RC_SUCCESS) return NULL;

  v_items[11] = v_item_11_out;
  if (!v_items[11]) return NULL;
}

if (v_count > 12) {

ElmcValue *v_item_12_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_12_x);
if (!v_item_12_field_0) return NULL;


ElmcValue *v_item_12_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_12_y);
if (!v_item_12_field_1) return NULL;
const char *v_item_12_names[] = { "x", "y" };
ElmcValue *v_item_12_values[] = { v_item_12_field_0, v_item_12_field_1 };
ElmcValue *v_item_12_out = NULL;
if (elmc_record_new_take(&v_item_12_out, 2, v_item_12_names, v_item_12_values) != RC_SUCCESS) return NULL;

  v_items[12] = v_item_12_out;
  if (!v_items[12]) return NULL;
}

if (v_count > 13) {

ElmcValue *v_item_13_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_13_x);
if (!v_item_13_field_0) return NULL;


ElmcValue *v_item_13_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_13_y);
if (!v_item_13_field_1) return NULL;
const char *v_item_13_names[] = { "x", "y" };
ElmcValue *v_item_13_values[] = { v_item_13_field_0, v_item_13_field_1 };
ElmcValue *v_item_13_out = NULL;
if (elmc_record_new_take(&v_item_13_out, 2, v_item_13_names, v_item_13_values) != RC_SUCCESS) return NULL;

  v_items[13] = v_item_13_out;
  if (!v_items[13]) return NULL;
}

if (v_count > 14) {

ElmcValue *v_item_14_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_14_x);
if (!v_item_14_field_0) return NULL;


ElmcValue *v_item_14_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_14_y);
if (!v_item_14_field_1) return NULL;
const char *v_item_14_names[] = { "x", "y" };
ElmcValue *v_item_14_values[] = { v_item_14_field_0, v_item_14_field_1 };
ElmcValue *v_item_14_out = NULL;
if (elmc_record_new_take(&v_item_14_out, 2, v_item_14_names, v_item_14_values) != RC_SUCCESS) return NULL;

  v_items[14] = v_item_14_out;
  if (!v_items[14]) return NULL;
}

if (v_count > 15) {

ElmcValue *v_item_15_field_0 = companion_protocol_box_int(message->wire.wire_push_points_field1_15_x);
if (!v_item_15_field_0) return NULL;


ElmcValue *v_item_15_field_1 = companion_protocol_box_int(message->wire.wire_push_points_field1_15_y);
if (!v_item_15_field_1) return NULL;
const char *v_item_15_names[] = { "x", "y" };
ElmcValue *v_item_15_values[] = { v_item_15_field_0, v_item_15_field_1 };
ElmcValue *v_item_15_out = NULL;
if (elmc_record_new_take(&v_item_15_out, 2, v_item_15_names, v_item_15_values) != RC_SUCCESS) return NULL;

  v_items[15] = v_item_15_out;
  if (!v_items[15]) return NULL;
}

ElmcValue *v_out = NULL;
if (elmc_list_from_values_take(&v_out, v_items, v_count) != RC_SUCCESS) return NULL;

  return v_out;
}


static ElmcValue *companion_protocol_build_push_labels_field1(const CompanionProtocolPhoneToWatchMessage *message) {
    int32_t v_count = message->wire.wire_push_labels_field1_count;
    if (v_count < 0) v_count = 0;
    if (v_count > 16) v_count = 16;
    /* Zero-init: elmc_tuple2_take releases *out when non-NULL (uninitialized = crash). */
    ElmcValue *v_pairs[16] = {0};
  if (v_count > 0) {
  ElmcValue *v_key_0 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_0);

  ElmcValue *v_value_0 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_0);
  if (!v_key_0 || !v_value_0) return NULL;
  if (elmc_tuple2_take(&v_pairs[0], v_key_0, v_value_0) != RC_SUCCESS) return NULL;
}

if (v_count > 1) {
  ElmcValue *v_key_1 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_1);

  ElmcValue *v_value_1 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_1);
  if (!v_key_1 || !v_value_1) return NULL;
  if (elmc_tuple2_take(&v_pairs[1], v_key_1, v_value_1) != RC_SUCCESS) return NULL;
}

if (v_count > 2) {
  ElmcValue *v_key_2 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_2);

  ElmcValue *v_value_2 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_2);
  if (!v_key_2 || !v_value_2) return NULL;
  if (elmc_tuple2_take(&v_pairs[2], v_key_2, v_value_2) != RC_SUCCESS) return NULL;
}

if (v_count > 3) {
  ElmcValue *v_key_3 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_3);

  ElmcValue *v_value_3 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_3);
  if (!v_key_3 || !v_value_3) return NULL;
  if (elmc_tuple2_take(&v_pairs[3], v_key_3, v_value_3) != RC_SUCCESS) return NULL;
}

if (v_count > 4) {
  ElmcValue *v_key_4 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_4);

  ElmcValue *v_value_4 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_4);
  if (!v_key_4 || !v_value_4) return NULL;
  if (elmc_tuple2_take(&v_pairs[4], v_key_4, v_value_4) != RC_SUCCESS) return NULL;
}

if (v_count > 5) {
  ElmcValue *v_key_5 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_5);

  ElmcValue *v_value_5 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_5);
  if (!v_key_5 || !v_value_5) return NULL;
  if (elmc_tuple2_take(&v_pairs[5], v_key_5, v_value_5) != RC_SUCCESS) return NULL;
}

if (v_count > 6) {
  ElmcValue *v_key_6 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_6);

  ElmcValue *v_value_6 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_6);
  if (!v_key_6 || !v_value_6) return NULL;
  if (elmc_tuple2_take(&v_pairs[6], v_key_6, v_value_6) != RC_SUCCESS) return NULL;
}

if (v_count > 7) {
  ElmcValue *v_key_7 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_7);

  ElmcValue *v_value_7 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_7);
  if (!v_key_7 || !v_value_7) return NULL;
  if (elmc_tuple2_take(&v_pairs[7], v_key_7, v_value_7) != RC_SUCCESS) return NULL;
}

if (v_count > 8) {
  ElmcValue *v_key_8 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_8);

  ElmcValue *v_value_8 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_8);
  if (!v_key_8 || !v_value_8) return NULL;
  if (elmc_tuple2_take(&v_pairs[8], v_key_8, v_value_8) != RC_SUCCESS) return NULL;
}

if (v_count > 9) {
  ElmcValue *v_key_9 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_9);

  ElmcValue *v_value_9 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_9);
  if (!v_key_9 || !v_value_9) return NULL;
  if (elmc_tuple2_take(&v_pairs[9], v_key_9, v_value_9) != RC_SUCCESS) return NULL;
}

if (v_count > 10) {
  ElmcValue *v_key_10 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_10);

  ElmcValue *v_value_10 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_10);
  if (!v_key_10 || !v_value_10) return NULL;
  if (elmc_tuple2_take(&v_pairs[10], v_key_10, v_value_10) != RC_SUCCESS) return NULL;
}

if (v_count > 11) {
  ElmcValue *v_key_11 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_11);

  ElmcValue *v_value_11 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_11);
  if (!v_key_11 || !v_value_11) return NULL;
  if (elmc_tuple2_take(&v_pairs[11], v_key_11, v_value_11) != RC_SUCCESS) return NULL;
}

if (v_count > 12) {
  ElmcValue *v_key_12 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_12);

  ElmcValue *v_value_12 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_12);
  if (!v_key_12 || !v_value_12) return NULL;
  if (elmc_tuple2_take(&v_pairs[12], v_key_12, v_value_12) != RC_SUCCESS) return NULL;
}

if (v_count > 13) {
  ElmcValue *v_key_13 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_13);

  ElmcValue *v_value_13 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_13);
  if (!v_key_13 || !v_value_13) return NULL;
  if (elmc_tuple2_take(&v_pairs[13], v_key_13, v_value_13) != RC_SUCCESS) return NULL;
}

if (v_count > 14) {
  ElmcValue *v_key_14 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_14);

  ElmcValue *v_value_14 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_14);
  if (!v_key_14 || !v_value_14) return NULL;
  if (elmc_tuple2_take(&v_pairs[14], v_key_14, v_value_14) != RC_SUCCESS) return NULL;
}

if (v_count > 15) {
  ElmcValue *v_key_15 = companion_protocol_box_string(message->wire.wire_push_labels_field1_key_15);

  ElmcValue *v_value_15 = companion_protocol_box_int(message->wire.wire_push_labels_field1_val_15);
  if (!v_key_15 || !v_value_15) return NULL;
  if (elmc_tuple2_take(&v_pairs[15], v_key_15, v_value_15) != RC_SUCCESS) return NULL;
}

    ElmcValue *v_pair_list = NULL;
    if (elmc_list_from_values_take(&v_pair_list, v_pairs, v_count) != RC_SUCCESS) return NULL;
    ElmcValue *v_dict = NULL;
    if (elmc_dict_from_list(&v_dict, v_pair_list) != RC_SUCCESS) {
      elmc_release(v_pair_list);
      return NULL;
    }
    elmc_release(v_pair_list);

  return v_dict;
}


bool companion_protocol_encode_watch_to_phone(DictionaryIterator *iter, int32_t tag, int32_t value) {
  if (!iter) return false;
  switch (tag) {
    case COMPANION_PROTOCOL_TAG_PING:
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_PING);

      return true;

    case COMPANION_PROTOCOL_TAG_SEND_COLOR:
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_SEND_COLOR);
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_COLOR_FIELD1, value);
      return true;

    case COMPANION_PROTOCOL_TAG_SEND_MEASURE:
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_SEND_MEASURE);
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_TAG, value);
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_VALUE, 0);

      return true;

    case COMPANION_PROTOCOL_TAG_SEND_POINT:
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_SEND_POINT);

      return true;

    case COMPANION_PROTOCOL_TAG_SEND_COUNTS:
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_SEND_COUNTS);

      return true;

    case COMPANION_PROTOCOL_TAG_REQUEST_PHONE_EXTRAS:
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_REQUEST_PHONE_EXTRAS);

      return true;

    default:
      return false;
  }
}

bool companion_protocol_encode_watch_to_phone_value(DictionaryIterator *iter, ElmcValue *message) {
  if (!iter || !message) return false;
  switch ((int32_t)elmc_union_tag_as_int(message)) {
    case 1: {
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_PING);
      return true;
    }

    case 2: {
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_SEND_COLOR);
      ElmcValue *m3_arg1 = elmc_union_payload(message);
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_COLOR_FIELD1, companion_protocol_wire_code_COLOR((int32_t)elmc_union_tag_as_int(m3_arg1)));
      return true;
    }

    case 3: {
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_SEND_MEASURE);
      ElmcValue *m4_arg1 = elmc_union_payload(message);
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_TAG, companion_protocol_wire_code_MEASURE((int32_t)elmc_union_tag_as_int(m4_arg1)));
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_VALUE, (int32_t)elmc_union_payload_int(m4_arg1));
      return true;
    }

    case 4: {
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_SEND_POINT);
      ElmcValue *m5_arg1 = elmc_union_payload(message);
      {
        ElmcValue *m5_a1_record = m5_arg1;
        {
          ElmcValue *m5_a1_x = elmc_record_get_index(m5_a1_record, 0);
          dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_X, (int32_t)companion_protocol_value_int(m5_a1_x));
          elmc_release(m5_a1_x);
        }
        {
          ElmcValue *m5_a1_y = elmc_record_get_index(m5_a1_record, 1);
          dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_Y, (int32_t)companion_protocol_value_int(m5_a1_y));
          elmc_release(m5_a1_y);
        }
      }
      return true;
    }

    case 5: {
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_SEND_COUNTS);
      ElmcValue *m6_arg1 = elmc_union_payload(message);
      {
        static const uint32_t m6_a1_keys[16] = { COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_0, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_1, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_2, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_3, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_4, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_5, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_6, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_7, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_8, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_9, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_10, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_11, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_12, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_13, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_14, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_15 };
        ElmcValue *m6_a1_list = m6_arg1;
        int32_t m6_a1_n = (int32_t)elmc_list_length_native(m6_a1_list);
        if (m6_a1_n > 16) m6_a1_n = 16;
        dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_COUNT, m6_a1_n + 1);
        for (int32_t m6_a1_i = 0; m6_a1_i < m6_a1_n; m6_a1_i++) {
          dict_write_int32(iter, m6_a1_keys[m6_a1_i], (int32_t)elmc_list_nth_int_default(m6_a1_list, m6_a1_i, 0) + 1);
        }
      }
      return true;
    }

    case 6: {
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_REQUEST_PHONE_EXTRAS);
      return true;
    }
    default:
      return false;
  }
}


void companion_protocol_phone_to_watch_decoder_init(CompanionProtocolPhoneToWatchDecoder *decoder) {
  if (!decoder) return;
  memset(decoder, 0, sizeof(*decoder));
  decoder->saw_tag = false;
  decoder->tag = 0;
  memset(&decoder->message, 0, sizeof(decoder->message));
  memset(decoder->saw_fields, 0, sizeof(decoder->saw_fields));
  memset(decoder->saw_union_value_fields, 0, sizeof(decoder->saw_union_value_fields));
  memset(decoder->saw_list_counts, 0, sizeof(decoder->saw_list_counts));
  memset(decoder->saw_list_elements, 0, sizeof(decoder->saw_list_elements));

}

void companion_protocol_phone_to_watch_decoder_push_tuple(
    CompanionProtocolPhoneToWatchDecoder *decoder, const Tuple *tuple) {
  if (!decoder || !tuple) return;

  if (tuple->key == COMPANION_PROTOCOL_KEY_MESSAGE_TAG &&
      (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT)) {
    decoder->tag = tuple->value->int32;
    decoder->saw_tag = true;
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COLOR_FIELD1) {
    decoder->saw_fields[0] = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.int_fields[0] = tuple->value->int32;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_MEASURE_FIELD1_TAG) {
    decoder->saw_fields[0] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.int_fields[0] = tuple->value->int32;
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_MEASURE_FIELD1_VALUE) {
    decoder->saw_union_value_fields[0] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.union_value_fields[0] = tuple->value->int32;
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_COUNT) {
    decoder->saw_list_counts[0] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_counts[0] =
          companion_protocol_decode_list_wire_count(tuple->value->int32);
    }
    return;
  }
  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_0) {
    decoder->saw_list_elements[0][0] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][0] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_1) {
    decoder->saw_list_elements[0][1] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][1] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_2) {
    decoder->saw_list_elements[0][2] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][2] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_3) {
    decoder->saw_list_elements[0][3] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][3] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_4) {
    decoder->saw_list_elements[0][4] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][4] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_5) {
    decoder->saw_list_elements[0][5] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][5] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_6) {
    decoder->saw_list_elements[0][6] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][6] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_7) {
    decoder->saw_list_elements[0][7] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][7] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_8) {
    decoder->saw_list_elements[0][8] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][8] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_9) {
    decoder->saw_list_elements[0][9] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][9] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_10) {
    decoder->saw_list_elements[0][10] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][10] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_11) {
    decoder->saw_list_elements[0][11] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][11] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_12) {
    decoder->saw_list_elements[0][12] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][12] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_13) {
    decoder->saw_list_elements[0][13] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][13] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_14) {
    decoder->saw_list_elements[0][14] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][14] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_15) {
    decoder->saw_list_elements[0][15] = true;
    if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
      decoder->message.list_values[0][15] =
          companion_protocol_decode_list_wire_int(tuple->value->int32);
    }
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_BOOL_FIELD1) {
    decoder->saw_fields[0] = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.bool_fields[0] = tuple->value->int32 == 1;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_STRING_FIELD1) {
    decoder->saw_fields[0] = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.string_fields[0], tuple->value->cstring, 63);
    decoder->message.string_fields[0][63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COLOR_FIELD1) {
    decoder->saw_wire_send_color_field1 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_color_field1 = tuple->value->int32;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_TAG) {
    decoder->saw_wire_send_measure_field1_tag = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_measure_field1_tag = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_measure_field1_tag < 0) decoder->message.wire.wire_send_measure_field1_tag = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_VALUE) {
    decoder->saw_wire_send_measure_field1_value = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_measure_field1_value = tuple->value->int32;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_X) {
    decoder->saw_wire_send_point_field1_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_point_field1_x = tuple->value->int32;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_Y) {
    decoder->saw_wire_send_point_field1_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_point_field1_y = tuple->value->int32;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_COUNT) {
    decoder->saw_wire_send_counts_field1_count = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_count = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_count < 0) decoder->message.wire.wire_send_counts_field1_count = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_0) {
    decoder->saw_wire_send_counts_field1_0 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_0 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_0 < 0) decoder->message.wire.wire_send_counts_field1_0 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_1) {
    decoder->saw_wire_send_counts_field1_1 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_1 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_1 < 0) decoder->message.wire.wire_send_counts_field1_1 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_2) {
    decoder->saw_wire_send_counts_field1_2 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_2 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_2 < 0) decoder->message.wire.wire_send_counts_field1_2 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_3) {
    decoder->saw_wire_send_counts_field1_3 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_3 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_3 < 0) decoder->message.wire.wire_send_counts_field1_3 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_4) {
    decoder->saw_wire_send_counts_field1_4 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_4 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_4 < 0) decoder->message.wire.wire_send_counts_field1_4 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_5) {
    decoder->saw_wire_send_counts_field1_5 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_5 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_5 < 0) decoder->message.wire.wire_send_counts_field1_5 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_6) {
    decoder->saw_wire_send_counts_field1_6 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_6 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_6 < 0) decoder->message.wire.wire_send_counts_field1_6 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_7) {
    decoder->saw_wire_send_counts_field1_7 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_7 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_7 < 0) decoder->message.wire.wire_send_counts_field1_7 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_8) {
    decoder->saw_wire_send_counts_field1_8 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_8 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_8 < 0) decoder->message.wire.wire_send_counts_field1_8 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_9) {
    decoder->saw_wire_send_counts_field1_9 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_9 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_9 < 0) decoder->message.wire.wire_send_counts_field1_9 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_10) {
    decoder->saw_wire_send_counts_field1_10 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_10 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_10 < 0) decoder->message.wire.wire_send_counts_field1_10 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_11) {
    decoder->saw_wire_send_counts_field1_11 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_11 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_11 < 0) decoder->message.wire.wire_send_counts_field1_11 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_12) {
    decoder->saw_wire_send_counts_field1_12 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_12 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_12 < 0) decoder->message.wire.wire_send_counts_field1_12 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_13) {
    decoder->saw_wire_send_counts_field1_13 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_13 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_13 < 0) decoder->message.wire.wire_send_counts_field1_13 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_14) {
    decoder->saw_wire_send_counts_field1_14 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_14 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_14 < 0) decoder->message.wire.wire_send_counts_field1_14 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_15) {
    decoder->saw_wire_send_counts_field1_15 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_send_counts_field1_15 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_send_counts_field1_15 < 0) decoder->message.wire.wire_send_counts_field1_15 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COLOR_FIELD1) {
    decoder->saw_wire_echo_color_field1 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_color_field1 = tuple->value->int32;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_MEASURE_FIELD1_TAG) {
    decoder->saw_wire_echo_measure_field1_tag = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_measure_field1_tag = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_measure_field1_tag < 0) decoder->message.wire.wire_echo_measure_field1_tag = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_MEASURE_FIELD1_VALUE) {
    decoder->saw_wire_echo_measure_field1_value = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_measure_field1_value = tuple->value->int32;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_POINT_FIELD1_X) {
    decoder->saw_wire_echo_point_field1_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_point_field1_x = tuple->value->int32;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_POINT_FIELD1_Y) {
    decoder->saw_wire_echo_point_field1_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_point_field1_y = tuple->value->int32;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_COUNT) {
    decoder->saw_wire_echo_counts_field1_count = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_count = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_count < 0) decoder->message.wire.wire_echo_counts_field1_count = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_0) {
    decoder->saw_wire_echo_counts_field1_0 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_0 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_0 < 0) decoder->message.wire.wire_echo_counts_field1_0 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_1) {
    decoder->saw_wire_echo_counts_field1_1 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_1 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_1 < 0) decoder->message.wire.wire_echo_counts_field1_1 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_2) {
    decoder->saw_wire_echo_counts_field1_2 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_2 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_2 < 0) decoder->message.wire.wire_echo_counts_field1_2 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_3) {
    decoder->saw_wire_echo_counts_field1_3 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_3 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_3 < 0) decoder->message.wire.wire_echo_counts_field1_3 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_4) {
    decoder->saw_wire_echo_counts_field1_4 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_4 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_4 < 0) decoder->message.wire.wire_echo_counts_field1_4 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_5) {
    decoder->saw_wire_echo_counts_field1_5 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_5 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_5 < 0) decoder->message.wire.wire_echo_counts_field1_5 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_6) {
    decoder->saw_wire_echo_counts_field1_6 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_6 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_6 < 0) decoder->message.wire.wire_echo_counts_field1_6 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_7) {
    decoder->saw_wire_echo_counts_field1_7 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_7 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_7 < 0) decoder->message.wire.wire_echo_counts_field1_7 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_8) {
    decoder->saw_wire_echo_counts_field1_8 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_8 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_8 < 0) decoder->message.wire.wire_echo_counts_field1_8 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_9) {
    decoder->saw_wire_echo_counts_field1_9 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_9 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_9 < 0) decoder->message.wire.wire_echo_counts_field1_9 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_10) {
    decoder->saw_wire_echo_counts_field1_10 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_10 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_10 < 0) decoder->message.wire.wire_echo_counts_field1_10 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_11) {
    decoder->saw_wire_echo_counts_field1_11 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_11 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_11 < 0) decoder->message.wire.wire_echo_counts_field1_11 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_12) {
    decoder->saw_wire_echo_counts_field1_12 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_12 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_12 < 0) decoder->message.wire.wire_echo_counts_field1_12 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_13) {
    decoder->saw_wire_echo_counts_field1_13 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_13 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_13 < 0) decoder->message.wire.wire_echo_counts_field1_13 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_14) {
    decoder->saw_wire_echo_counts_field1_14 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_14 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_14 < 0) decoder->message.wire.wire_echo_counts_field1_14 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_15) {
    decoder->saw_wire_echo_counts_field1_15 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_echo_counts_field1_15 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_echo_counts_field1_15 < 0) decoder->message.wire.wire_echo_counts_field1_15 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_BOOL_FIELD1) {
    decoder->saw_wire_push_bool_field1 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_bool_field1 = tuple->value->int32 == 1;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_STRING_FIELD1) {
    decoder->saw_wire_push_string_field1 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_string_field1, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_string_field1[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_COUNT) {
    decoder->saw_wire_push_points_field1_count = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_count = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_count < 0) decoder->message.wire.wire_push_points_field1_count = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_0_X) {
    decoder->saw_wire_push_points_field1_0_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_0_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_0_x < 0) decoder->message.wire.wire_push_points_field1_0_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_0_Y) {
    decoder->saw_wire_push_points_field1_0_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_0_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_0_y < 0) decoder->message.wire.wire_push_points_field1_0_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_1_X) {
    decoder->saw_wire_push_points_field1_1_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_1_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_1_x < 0) decoder->message.wire.wire_push_points_field1_1_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_1_Y) {
    decoder->saw_wire_push_points_field1_1_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_1_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_1_y < 0) decoder->message.wire.wire_push_points_field1_1_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_2_X) {
    decoder->saw_wire_push_points_field1_2_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_2_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_2_x < 0) decoder->message.wire.wire_push_points_field1_2_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_2_Y) {
    decoder->saw_wire_push_points_field1_2_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_2_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_2_y < 0) decoder->message.wire.wire_push_points_field1_2_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_3_X) {
    decoder->saw_wire_push_points_field1_3_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_3_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_3_x < 0) decoder->message.wire.wire_push_points_field1_3_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_3_Y) {
    decoder->saw_wire_push_points_field1_3_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_3_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_3_y < 0) decoder->message.wire.wire_push_points_field1_3_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_4_X) {
    decoder->saw_wire_push_points_field1_4_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_4_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_4_x < 0) decoder->message.wire.wire_push_points_field1_4_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_4_Y) {
    decoder->saw_wire_push_points_field1_4_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_4_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_4_y < 0) decoder->message.wire.wire_push_points_field1_4_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_5_X) {
    decoder->saw_wire_push_points_field1_5_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_5_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_5_x < 0) decoder->message.wire.wire_push_points_field1_5_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_5_Y) {
    decoder->saw_wire_push_points_field1_5_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_5_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_5_y < 0) decoder->message.wire.wire_push_points_field1_5_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_6_X) {
    decoder->saw_wire_push_points_field1_6_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_6_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_6_x < 0) decoder->message.wire.wire_push_points_field1_6_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_6_Y) {
    decoder->saw_wire_push_points_field1_6_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_6_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_6_y < 0) decoder->message.wire.wire_push_points_field1_6_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_7_X) {
    decoder->saw_wire_push_points_field1_7_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_7_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_7_x < 0) decoder->message.wire.wire_push_points_field1_7_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_7_Y) {
    decoder->saw_wire_push_points_field1_7_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_7_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_7_y < 0) decoder->message.wire.wire_push_points_field1_7_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_8_X) {
    decoder->saw_wire_push_points_field1_8_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_8_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_8_x < 0) decoder->message.wire.wire_push_points_field1_8_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_8_Y) {
    decoder->saw_wire_push_points_field1_8_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_8_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_8_y < 0) decoder->message.wire.wire_push_points_field1_8_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_9_X) {
    decoder->saw_wire_push_points_field1_9_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_9_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_9_x < 0) decoder->message.wire.wire_push_points_field1_9_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_9_Y) {
    decoder->saw_wire_push_points_field1_9_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_9_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_9_y < 0) decoder->message.wire.wire_push_points_field1_9_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_10_X) {
    decoder->saw_wire_push_points_field1_10_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_10_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_10_x < 0) decoder->message.wire.wire_push_points_field1_10_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_10_Y) {
    decoder->saw_wire_push_points_field1_10_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_10_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_10_y < 0) decoder->message.wire.wire_push_points_field1_10_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_11_X) {
    decoder->saw_wire_push_points_field1_11_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_11_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_11_x < 0) decoder->message.wire.wire_push_points_field1_11_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_11_Y) {
    decoder->saw_wire_push_points_field1_11_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_11_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_11_y < 0) decoder->message.wire.wire_push_points_field1_11_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_12_X) {
    decoder->saw_wire_push_points_field1_12_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_12_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_12_x < 0) decoder->message.wire.wire_push_points_field1_12_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_12_Y) {
    decoder->saw_wire_push_points_field1_12_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_12_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_12_y < 0) decoder->message.wire.wire_push_points_field1_12_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_13_X) {
    decoder->saw_wire_push_points_field1_13_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_13_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_13_x < 0) decoder->message.wire.wire_push_points_field1_13_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_13_Y) {
    decoder->saw_wire_push_points_field1_13_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_13_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_13_y < 0) decoder->message.wire.wire_push_points_field1_13_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_14_X) {
    decoder->saw_wire_push_points_field1_14_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_14_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_14_x < 0) decoder->message.wire.wire_push_points_field1_14_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_14_Y) {
    decoder->saw_wire_push_points_field1_14_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_14_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_14_y < 0) decoder->message.wire.wire_push_points_field1_14_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_15_X) {
    decoder->saw_wire_push_points_field1_15_x = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_15_x = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_15_x < 0) decoder->message.wire.wire_push_points_field1_15_x = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_15_Y) {
    decoder->saw_wire_push_points_field1_15_y = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_points_field1_15_y = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_points_field1_15_y < 0) decoder->message.wire.wire_push_points_field1_15_y = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_COUNT) {
    decoder->saw_wire_push_labels_field1_count = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_count = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_count < 0) decoder->message.wire.wire_push_labels_field1_count = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_0) {
    decoder->saw_wire_push_labels_field1_key_0 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_0, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_0[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_0) {
    decoder->saw_wire_push_labels_field1_val_0 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_0 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_0 < 0) decoder->message.wire.wire_push_labels_field1_val_0 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_1) {
    decoder->saw_wire_push_labels_field1_key_1 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_1, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_1[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_1) {
    decoder->saw_wire_push_labels_field1_val_1 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_1 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_1 < 0) decoder->message.wire.wire_push_labels_field1_val_1 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_2) {
    decoder->saw_wire_push_labels_field1_key_2 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_2, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_2[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_2) {
    decoder->saw_wire_push_labels_field1_val_2 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_2 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_2 < 0) decoder->message.wire.wire_push_labels_field1_val_2 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_3) {
    decoder->saw_wire_push_labels_field1_key_3 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_3, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_3[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_3) {
    decoder->saw_wire_push_labels_field1_val_3 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_3 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_3 < 0) decoder->message.wire.wire_push_labels_field1_val_3 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_4) {
    decoder->saw_wire_push_labels_field1_key_4 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_4, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_4[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_4) {
    decoder->saw_wire_push_labels_field1_val_4 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_4 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_4 < 0) decoder->message.wire.wire_push_labels_field1_val_4 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_5) {
    decoder->saw_wire_push_labels_field1_key_5 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_5, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_5[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_5) {
    decoder->saw_wire_push_labels_field1_val_5 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_5 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_5 < 0) decoder->message.wire.wire_push_labels_field1_val_5 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_6) {
    decoder->saw_wire_push_labels_field1_key_6 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_6, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_6[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_6) {
    decoder->saw_wire_push_labels_field1_val_6 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_6 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_6 < 0) decoder->message.wire.wire_push_labels_field1_val_6 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_7) {
    decoder->saw_wire_push_labels_field1_key_7 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_7, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_7[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_7) {
    decoder->saw_wire_push_labels_field1_val_7 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_7 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_7 < 0) decoder->message.wire.wire_push_labels_field1_val_7 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_8) {
    decoder->saw_wire_push_labels_field1_key_8 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_8, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_8[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_8) {
    decoder->saw_wire_push_labels_field1_val_8 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_8 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_8 < 0) decoder->message.wire.wire_push_labels_field1_val_8 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_9) {
    decoder->saw_wire_push_labels_field1_key_9 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_9, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_9[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_9) {
    decoder->saw_wire_push_labels_field1_val_9 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_9 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_9 < 0) decoder->message.wire.wire_push_labels_field1_val_9 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_10) {
    decoder->saw_wire_push_labels_field1_key_10 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_10, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_10[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_10) {
    decoder->saw_wire_push_labels_field1_val_10 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_10 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_10 < 0) decoder->message.wire.wire_push_labels_field1_val_10 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_11) {
    decoder->saw_wire_push_labels_field1_key_11 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_11, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_11[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_11) {
    decoder->saw_wire_push_labels_field1_val_11 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_11 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_11 < 0) decoder->message.wire.wire_push_labels_field1_val_11 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_12) {
    decoder->saw_wire_push_labels_field1_key_12 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_12, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_12[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_12) {
    decoder->saw_wire_push_labels_field1_val_12 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_12 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_12 < 0) decoder->message.wire.wire_push_labels_field1_val_12 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_13) {
    decoder->saw_wire_push_labels_field1_key_13 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_13, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_13[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_13) {
    decoder->saw_wire_push_labels_field1_val_13 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_13 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_13 < 0) decoder->message.wire.wire_push_labels_field1_val_13 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_14) {
    decoder->saw_wire_push_labels_field1_key_14 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_14, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_14[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_14) {
    decoder->saw_wire_push_labels_field1_val_14 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_14 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_14 < 0) decoder->message.wire.wire_push_labels_field1_val_14 = 0;
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_15) {
    decoder->saw_wire_push_labels_field1_key_15 = true;
  if (tuple->type == TUPLE_CSTRING) {
    strncpy(decoder->message.wire.wire_push_labels_field1_key_15, tuple->value->cstring, 63);
    decoder->message.wire.wire_push_labels_field1_key_15[63] = '\0';
  }

    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_15) {
    decoder->saw_wire_push_labels_field1_val_15 = true;
  if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
    decoder->message.wire.wire_push_labels_field1_val_15 = tuple->value->int32 - 1;
    if (decoder->message.wire.wire_push_labels_field1_val_15 < 0) decoder->message.wire.wire_push_labels_field1_val_15 = 0;
  }

    return;
  }

}

bool companion_protocol_phone_to_watch_decoder_finish(
    CompanionProtocolPhoneToWatchDecoder *decoder, CompanionProtocolPhoneToWatchMessage *out) {
  if (!decoder || !out || !decoder->saw_tag) return false;

  switch (decoder->tag) {
    case COMPANION_PROTOCOL_TAG_PONG:
      if (!(true)) return false;
      *out = decoder->message;
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PONG;
      return true;

    case COMPANION_PROTOCOL_TAG_ECHO_COLOR:
      if (!decoder->saw_fields[0]) {
        decoder->saw_fields[0] = true;
        decoder->message.int_fields[0] = 1;
      }
      if (!(decoder->saw_fields[0])) return false;
      *out = decoder->message;
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_COLOR;
      return true;

    case COMPANION_PROTOCOL_TAG_ECHO_MEASURE:
      if (!decoder->saw_fields[0]) {
        decoder->saw_fields[0] = true;
        decoder->message.int_fields[0] = 1;
      }
      if (!decoder->saw_union_value_fields[0]) {
        decoder->saw_union_value_fields[0] = true;
        decoder->message.union_value_fields[0] = 0;
      }
      if (!(decoder->saw_fields[0] && decoder->saw_union_value_fields[0])) return false;
      *out = decoder->message;
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_MEASURE;
      return true;

    case COMPANION_PROTOCOL_TAG_ECHO_POINT:
      if (!decoder->saw_wire_echo_point_field1_x) {
        decoder->message.wire.wire_echo_point_field1_x = 0;
      }

      if (!decoder->saw_wire_echo_point_field1_y) {
        decoder->message.wire.wire_echo_point_field1_y = 0;
      }
      if (!(true)) return false;
      *out = decoder->message;
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_POINT;
      return true;

    case COMPANION_PROTOCOL_TAG_ECHO_COUNTS:
      if (!decoder->saw_list_counts[0]) {
        decoder->saw_list_counts[0] = true;
        decoder->message.list_counts[0] = 0;
      }
      if (!decoder->saw_list_elements[0][0]) {
        decoder->saw_list_elements[0][0] = true;
        decoder->message.list_values[0][0] = 0;
      }

      if (!decoder->saw_list_elements[0][1]) {
        decoder->saw_list_elements[0][1] = true;
        decoder->message.list_values[0][1] = 0;
      }

      if (!decoder->saw_list_elements[0][2]) {
        decoder->saw_list_elements[0][2] = true;
        decoder->message.list_values[0][2] = 0;
      }

      if (!decoder->saw_list_elements[0][3]) {
        decoder->saw_list_elements[0][3] = true;
        decoder->message.list_values[0][3] = 0;
      }

      if (!decoder->saw_list_elements[0][4]) {
        decoder->saw_list_elements[0][4] = true;
        decoder->message.list_values[0][4] = 0;
      }

      if (!decoder->saw_list_elements[0][5]) {
        decoder->saw_list_elements[0][5] = true;
        decoder->message.list_values[0][5] = 0;
      }

      if (!decoder->saw_list_elements[0][6]) {
        decoder->saw_list_elements[0][6] = true;
        decoder->message.list_values[0][6] = 0;
      }

      if (!decoder->saw_list_elements[0][7]) {
        decoder->saw_list_elements[0][7] = true;
        decoder->message.list_values[0][7] = 0;
      }

      if (!decoder->saw_list_elements[0][8]) {
        decoder->saw_list_elements[0][8] = true;
        decoder->message.list_values[0][8] = 0;
      }

      if (!decoder->saw_list_elements[0][9]) {
        decoder->saw_list_elements[0][9] = true;
        decoder->message.list_values[0][9] = 0;
      }

      if (!decoder->saw_list_elements[0][10]) {
        decoder->saw_list_elements[0][10] = true;
        decoder->message.list_values[0][10] = 0;
      }

      if (!decoder->saw_list_elements[0][11]) {
        decoder->saw_list_elements[0][11] = true;
        decoder->message.list_values[0][11] = 0;
      }

      if (!decoder->saw_list_elements[0][12]) {
        decoder->saw_list_elements[0][12] = true;
        decoder->message.list_values[0][12] = 0;
      }

      if (!decoder->saw_list_elements[0][13]) {
        decoder->saw_list_elements[0][13] = true;
        decoder->message.list_values[0][13] = 0;
      }

      if (!decoder->saw_list_elements[0][14]) {
        decoder->saw_list_elements[0][14] = true;
        decoder->message.list_values[0][14] = 0;
      }

      if (!decoder->saw_list_elements[0][15]) {
        decoder->saw_list_elements[0][15] = true;
        decoder->message.list_values[0][15] = 0;
      }

      if (!(decoder->saw_list_counts[0])) return false;
      *out = decoder->message;
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_COUNTS;
      return true;

    case COMPANION_PROTOCOL_TAG_PUSH_BOOL:
      if (!decoder->saw_fields[0]) {
        decoder->saw_fields[0] = true;
        decoder->message.bool_fields[0] = false;
      }
      if (!(decoder->saw_fields[0])) return false;
      *out = decoder->message;
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_BOOL;
      return true;

    case COMPANION_PROTOCOL_TAG_PUSH_STRING:
      if (!(decoder->saw_fields[0])) return false;
      *out = decoder->message;
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_STRING;
      return true;

    case COMPANION_PROTOCOL_TAG_PUSH_POINTS:
      if (!decoder->saw_wire_push_points_field1_count) {
        decoder->message.wire.wire_push_points_field1_count = 0;
      }

      if (!decoder->saw_wire_push_points_field1_0_x) {
        decoder->message.wire.wire_push_points_field1_0_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_0_y) {
        decoder->message.wire.wire_push_points_field1_0_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_1_x) {
        decoder->message.wire.wire_push_points_field1_1_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_1_y) {
        decoder->message.wire.wire_push_points_field1_1_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_2_x) {
        decoder->message.wire.wire_push_points_field1_2_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_2_y) {
        decoder->message.wire.wire_push_points_field1_2_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_3_x) {
        decoder->message.wire.wire_push_points_field1_3_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_3_y) {
        decoder->message.wire.wire_push_points_field1_3_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_4_x) {
        decoder->message.wire.wire_push_points_field1_4_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_4_y) {
        decoder->message.wire.wire_push_points_field1_4_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_5_x) {
        decoder->message.wire.wire_push_points_field1_5_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_5_y) {
        decoder->message.wire.wire_push_points_field1_5_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_6_x) {
        decoder->message.wire.wire_push_points_field1_6_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_6_y) {
        decoder->message.wire.wire_push_points_field1_6_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_7_x) {
        decoder->message.wire.wire_push_points_field1_7_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_7_y) {
        decoder->message.wire.wire_push_points_field1_7_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_8_x) {
        decoder->message.wire.wire_push_points_field1_8_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_8_y) {
        decoder->message.wire.wire_push_points_field1_8_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_9_x) {
        decoder->message.wire.wire_push_points_field1_9_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_9_y) {
        decoder->message.wire.wire_push_points_field1_9_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_10_x) {
        decoder->message.wire.wire_push_points_field1_10_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_10_y) {
        decoder->message.wire.wire_push_points_field1_10_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_11_x) {
        decoder->message.wire.wire_push_points_field1_11_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_11_y) {
        decoder->message.wire.wire_push_points_field1_11_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_12_x) {
        decoder->message.wire.wire_push_points_field1_12_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_12_y) {
        decoder->message.wire.wire_push_points_field1_12_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_13_x) {
        decoder->message.wire.wire_push_points_field1_13_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_13_y) {
        decoder->message.wire.wire_push_points_field1_13_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_14_x) {
        decoder->message.wire.wire_push_points_field1_14_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_14_y) {
        decoder->message.wire.wire_push_points_field1_14_y = 0;
      }

      if (!decoder->saw_wire_push_points_field1_15_x) {
        decoder->message.wire.wire_push_points_field1_15_x = 0;
      }

      if (!decoder->saw_wire_push_points_field1_15_y) {
        decoder->message.wire.wire_push_points_field1_15_y = 0;
      }
      if (!(true)) return false;
      *out = decoder->message;
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_POINTS;
      return true;

    case COMPANION_PROTOCOL_TAG_PUSH_LABELS:
      if (!decoder->saw_wire_push_labels_field1_count) {
        decoder->message.wire.wire_push_labels_field1_count = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_0) {
        decoder->message.wire.wire_push_labels_field1_key_0[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_0) {
        decoder->message.wire.wire_push_labels_field1_val_0 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_1) {
        decoder->message.wire.wire_push_labels_field1_key_1[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_1) {
        decoder->message.wire.wire_push_labels_field1_val_1 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_2) {
        decoder->message.wire.wire_push_labels_field1_key_2[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_2) {
        decoder->message.wire.wire_push_labels_field1_val_2 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_3) {
        decoder->message.wire.wire_push_labels_field1_key_3[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_3) {
        decoder->message.wire.wire_push_labels_field1_val_3 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_4) {
        decoder->message.wire.wire_push_labels_field1_key_4[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_4) {
        decoder->message.wire.wire_push_labels_field1_val_4 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_5) {
        decoder->message.wire.wire_push_labels_field1_key_5[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_5) {
        decoder->message.wire.wire_push_labels_field1_val_5 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_6) {
        decoder->message.wire.wire_push_labels_field1_key_6[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_6) {
        decoder->message.wire.wire_push_labels_field1_val_6 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_7) {
        decoder->message.wire.wire_push_labels_field1_key_7[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_7) {
        decoder->message.wire.wire_push_labels_field1_val_7 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_8) {
        decoder->message.wire.wire_push_labels_field1_key_8[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_8) {
        decoder->message.wire.wire_push_labels_field1_val_8 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_9) {
        decoder->message.wire.wire_push_labels_field1_key_9[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_9) {
        decoder->message.wire.wire_push_labels_field1_val_9 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_10) {
        decoder->message.wire.wire_push_labels_field1_key_10[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_10) {
        decoder->message.wire.wire_push_labels_field1_val_10 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_11) {
        decoder->message.wire.wire_push_labels_field1_key_11[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_11) {
        decoder->message.wire.wire_push_labels_field1_val_11 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_12) {
        decoder->message.wire.wire_push_labels_field1_key_12[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_12) {
        decoder->message.wire.wire_push_labels_field1_val_12 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_13) {
        decoder->message.wire.wire_push_labels_field1_key_13[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_13) {
        decoder->message.wire.wire_push_labels_field1_val_13 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_14) {
        decoder->message.wire.wire_push_labels_field1_key_14[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_14) {
        decoder->message.wire.wire_push_labels_field1_val_14 = 0;
      }

      if (!decoder->saw_wire_push_labels_field1_key_15) {
        decoder->message.wire.wire_push_labels_field1_key_15[0] = '\0';
      }

      if (!decoder->saw_wire_push_labels_field1_val_15) {
        decoder->message.wire.wire_push_labels_field1_val_15 = 0;
      }
      if (!(true)) return false;
      *out = decoder->message;
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_LABELS;
      return true;

    default:
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN;
      return false;
  }
}

int companion_protocol_dispatch_phone_to_watch(
    ElmcPebbleApp *app, const CompanionProtocolPhoneToWatchMessage *message) {
  if (!app || !message) return -1;

  switch (message->kind) {
    case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PONG: {
      if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      ElmcValue *payload = companion_protocol_box_int(1);
      if (!payload) return -2;
      int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, payload);
      elmc_release(payload);
      return rc;
    }

    case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_COLOR: {
      if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      const int64_t payload_values[] = { companion_protocol_runtime_tag_COLOR(message->int_fields[0]) };
      return elmc_pebble_dispatch_tag_int_values(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, 2, 1, payload_values);
    }

    case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_MEASURE: {
      if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      ElmcValue *payload = companion_protocol_new_union_value(companion_protocol_runtime_tag_MEASURE(message->int_fields[0]), message->union_value_fields[0]);
      if (!payload) return -2;
      ElmcValue *phone_to_watch = companion_protocol_new_phone_to_watch_message(3, payload);
      if (!phone_to_watch) {
        elmc_release(payload);
        return -2;
      }
      int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, phone_to_watch);
      elmc_release(phone_to_watch);
      return rc;
    }

    case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_POINT: {
      if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      ElmcValue *payload = companion_protocol_build_echo_point_field1(message);
      if (!payload) return -2;
      ElmcValue *phone_to_watch = companion_protocol_new_phone_to_watch_message(4, payload);
      if (!phone_to_watch) {
        elmc_release(payload);
        return -2;
      }
      int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, phone_to_watch);
      elmc_release(phone_to_watch);
      return rc;
    }

    case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_COUNTS: {
      if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      ElmcValue *payload = companion_protocol_box_int_list(message->list_values[0], message->list_counts[0]);
      if (!payload) return -2;
      ElmcValue *phone_to_watch = companion_protocol_new_phone_to_watch_message(5, payload);
      if (!phone_to_watch) {
        elmc_release(payload);
        return -2;
      }
      int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, phone_to_watch);
      elmc_release(phone_to_watch);
      return rc;
    }

    case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_BOOL: {
      if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      ElmcValue *payload = companion_protocol_box_bool(message->bool_fields[0] ? 1 : 0);
      if (!payload) return -2;
      ElmcValue *phone_to_watch = companion_protocol_new_phone_to_watch_message(6, payload);
      if (!phone_to_watch) {
        elmc_release(payload);
        return -2;
      }
      int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, phone_to_watch);
      elmc_release(phone_to_watch);
      return rc;
    }

    case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_STRING: {
      if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      ElmcValue *payload = companion_protocol_box_string(message->string_fields[0]);
      if (!payload) return -2;
      ElmcValue *phone_to_watch = companion_protocol_new_phone_to_watch_message(7, payload);
      if (!phone_to_watch) {
        elmc_release(payload);
        return -2;
      }
      int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, phone_to_watch);
      elmc_release(phone_to_watch);
      return rc;
    }

    case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_POINTS: {
      if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      ElmcValue *payload = companion_protocol_build_push_points_field1(message);
      if (!payload) return -2;
      ElmcValue *phone_to_watch = companion_protocol_new_phone_to_watch_message(8, payload);
      if (!phone_to_watch) {
        elmc_release(payload);
        return -2;
      }
      int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, phone_to_watch);
      elmc_release(phone_to_watch);
      return rc;
    }

    case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_LABELS: {
      if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      ElmcValue *payload = companion_protocol_build_push_labels_field1(message);
      if (!payload) return -2;
      ElmcValue *phone_to_watch = companion_protocol_new_phone_to_watch_message(9, payload);
      if (!phone_to_watch) {
        elmc_release(payload);
        return -2;
      }
      int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, phone_to_watch);
      elmc_release(phone_to_watch);
      return rc;
    }

    default:
      return -6;
  }
}
