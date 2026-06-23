#ifndef COMPANION_PROTOCOL_H
#define COMPANION_PROTOCOL_H

#include <pebble.h>
#include <stdbool.h>
#include <stdint.h>
#include "../elmc/c/elmc_pebble.h"

#define COMPANION_PROTOCOL_KEY_MESSAGE_TAG 10
#define COMPANION_PROTOCOL_KEY_SEND_COLOR_FIELD1 11
#define COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_TAG 12
#define COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_VALUE 13
#define COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_X 14
#define COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_Y 15
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_COUNT 16
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_0 17
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_1 18
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_2 19
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_3 20
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_4 21
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_5 22
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_6 23
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_7 24
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_8 25
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_9 26
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_10 27
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_11 28
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_12 29
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_13 30
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_14 31
#define COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_15 32
#define COMPANION_PROTOCOL_KEY_ECHO_COLOR_FIELD1 33
#define COMPANION_PROTOCOL_KEY_ECHO_MEASURE_FIELD1_TAG 34
#define COMPANION_PROTOCOL_KEY_ECHO_MEASURE_FIELD1_VALUE 35
#define COMPANION_PROTOCOL_KEY_ECHO_POINT_FIELD1_X 36
#define COMPANION_PROTOCOL_KEY_ECHO_POINT_FIELD1_Y 37
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_COUNT 38
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_0 39
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_1 40
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_2 41
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_3 42
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_4 43
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_5 44
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_6 45
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_7 46
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_8 47
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_9 48
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_10 49
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_11 50
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_12 51
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_13 52
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_14 53
#define COMPANION_PROTOCOL_KEY_ECHO_COUNTS_FIELD1_15 54
#define COMPANION_PROTOCOL_KEY_PUSH_BOOL_FIELD1 55
#define COMPANION_PROTOCOL_KEY_PUSH_STRING_FIELD1 56
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_COUNT 57
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_0_X 58
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_0_Y 59
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_1_X 60
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_1_Y 61
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_2_X 62
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_2_Y 63
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_3_X 64
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_3_Y 65
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_4_X 66
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_4_Y 67
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_5_X 68
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_5_Y 69
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_6_X 70
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_6_Y 71
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_7_X 72
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_7_Y 73
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_8_X 74
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_8_Y 75
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_9_X 76
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_9_Y 77
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_10_X 78
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_10_Y 79
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_11_X 80
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_11_Y 81
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_12_X 82
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_12_Y 83
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_13_X 84
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_13_Y 85
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_14_X 86
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_14_Y 87
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_15_X 88
#define COMPANION_PROTOCOL_KEY_PUSH_POINTS_FIELD1_15_Y 89
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_COUNT 90
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_0 91
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_0 92
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_1 93
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_1 94
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_2 95
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_2 96
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_3 97
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_3 98
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_4 99
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_4 100
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_5 101
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_5 102
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_6 103
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_6 104
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_7 105
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_7 106
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_8 107
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_8 108
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_9 109
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_9 110
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_10 111
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_10 112
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_11 113
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_11 114
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_12 115
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_12 116
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_13 117
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_13 118
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_14 119
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_14 120
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_KEY_15 121
#define COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_VAL_15 122
#define COMPANION_PROTOCOL_ENUM_COLOR_RED 1
#define COMPANION_PROTOCOL_ENUM_COLOR_GREEN 2
#define COMPANION_PROTOCOL_ENUM_COLOR_BLUE 3
#define COMPANION_PROTOCOL_TAG_PING 2
#define COMPANION_PROTOCOL_TAG_SEND_COLOR 3
#define COMPANION_PROTOCOL_TAG_SEND_MEASURE 4
#define COMPANION_PROTOCOL_TAG_SEND_POINT 5
#define COMPANION_PROTOCOL_TAG_SEND_COUNTS 6
#define COMPANION_PROTOCOL_TAG_REQUEST_PHONE_EXTRAS 7
#define COMPANION_PROTOCOL_TAG_PONG 201
#define COMPANION_PROTOCOL_TAG_ECHO_COLOR 202
#define COMPANION_PROTOCOL_TAG_ECHO_MEASURE 203
#define COMPANION_PROTOCOL_TAG_ECHO_POINT 204
#define COMPANION_PROTOCOL_TAG_ECHO_COUNTS 205
#define COMPANION_PROTOCOL_TAG_PUSH_BOOL 206
#define COMPANION_PROTOCOL_TAG_PUSH_STRING 207
#define COMPANION_PROTOCOL_TAG_PUSH_POINTS 208
#define COMPANION_PROTOCOL_TAG_PUSH_LABELS 209

#define COMPANION_PROTOCOL_MAX_FIELDS 1
#define COMPANION_PROTOCOL_LIST_MAX_ELEMENTS 16
#define COMPANION_PROTOCOL_LIST_WIRE_OFFSET 1
#define ELMC_COMPANION_SIMULATOR_WEATHER 0
#define ELMC_COMPANION_PROTOCOL_HAS_UNION_PAYLOADS 1

typedef enum {
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN = 0,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PONG,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_COLOR,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_MEASURE,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_POINT,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_ECHO_COUNTS,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_BOOL,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_STRING,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_POINTS,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PUSH_LABELS,
} CompanionProtocolPhoneToWatchKind;

typedef struct {
  int32_t wire_send_color_field1;
  int32_t wire_send_measure_field1_tag;
  int32_t wire_send_measure_field1_value;
  int32_t wire_send_point_field1_x;
  int32_t wire_send_point_field1_y;
  int32_t wire_send_counts_field1_count;
  int32_t wire_send_counts_field1_0;
  int32_t wire_send_counts_field1_1;
  int32_t wire_send_counts_field1_2;
  int32_t wire_send_counts_field1_3;
  int32_t wire_send_counts_field1_4;
  int32_t wire_send_counts_field1_5;
  int32_t wire_send_counts_field1_6;
  int32_t wire_send_counts_field1_7;
  int32_t wire_send_counts_field1_8;
  int32_t wire_send_counts_field1_9;
  int32_t wire_send_counts_field1_10;
  int32_t wire_send_counts_field1_11;
  int32_t wire_send_counts_field1_12;
  int32_t wire_send_counts_field1_13;
  int32_t wire_send_counts_field1_14;
  int32_t wire_send_counts_field1_15;
  int32_t wire_echo_color_field1;
  int32_t wire_echo_measure_field1_tag;
  int32_t wire_echo_measure_field1_value;
  int32_t wire_echo_point_field1_x;
  int32_t wire_echo_point_field1_y;
  int32_t wire_echo_counts_field1_count;
  int32_t wire_echo_counts_field1_0;
  int32_t wire_echo_counts_field1_1;
  int32_t wire_echo_counts_field1_2;
  int32_t wire_echo_counts_field1_3;
  int32_t wire_echo_counts_field1_4;
  int32_t wire_echo_counts_field1_5;
  int32_t wire_echo_counts_field1_6;
  int32_t wire_echo_counts_field1_7;
  int32_t wire_echo_counts_field1_8;
  int32_t wire_echo_counts_field1_9;
  int32_t wire_echo_counts_field1_10;
  int32_t wire_echo_counts_field1_11;
  int32_t wire_echo_counts_field1_12;
  int32_t wire_echo_counts_field1_13;
  int32_t wire_echo_counts_field1_14;
  int32_t wire_echo_counts_field1_15;
  bool wire_push_bool_field1;
  char wire_push_string_field1[64];
  int32_t wire_push_points_field1_count;
  int32_t wire_push_points_field1_0_x;
  int32_t wire_push_points_field1_0_y;
  int32_t wire_push_points_field1_1_x;
  int32_t wire_push_points_field1_1_y;
  int32_t wire_push_points_field1_2_x;
  int32_t wire_push_points_field1_2_y;
  int32_t wire_push_points_field1_3_x;
  int32_t wire_push_points_field1_3_y;
  int32_t wire_push_points_field1_4_x;
  int32_t wire_push_points_field1_4_y;
  int32_t wire_push_points_field1_5_x;
  int32_t wire_push_points_field1_5_y;
  int32_t wire_push_points_field1_6_x;
  int32_t wire_push_points_field1_6_y;
  int32_t wire_push_points_field1_7_x;
  int32_t wire_push_points_field1_7_y;
  int32_t wire_push_points_field1_8_x;
  int32_t wire_push_points_field1_8_y;
  int32_t wire_push_points_field1_9_x;
  int32_t wire_push_points_field1_9_y;
  int32_t wire_push_points_field1_10_x;
  int32_t wire_push_points_field1_10_y;
  int32_t wire_push_points_field1_11_x;
  int32_t wire_push_points_field1_11_y;
  int32_t wire_push_points_field1_12_x;
  int32_t wire_push_points_field1_12_y;
  int32_t wire_push_points_field1_13_x;
  int32_t wire_push_points_field1_13_y;
  int32_t wire_push_points_field1_14_x;
  int32_t wire_push_points_field1_14_y;
  int32_t wire_push_points_field1_15_x;
  int32_t wire_push_points_field1_15_y;
  int32_t wire_push_labels_field1_count;
  char wire_push_labels_field1_key_0[64];
  int32_t wire_push_labels_field1_val_0;
  char wire_push_labels_field1_key_1[64];
  int32_t wire_push_labels_field1_val_1;
  char wire_push_labels_field1_key_2[64];
  int32_t wire_push_labels_field1_val_2;
  char wire_push_labels_field1_key_3[64];
  int32_t wire_push_labels_field1_val_3;
  char wire_push_labels_field1_key_4[64];
  int32_t wire_push_labels_field1_val_4;
  char wire_push_labels_field1_key_5[64];
  int32_t wire_push_labels_field1_val_5;
  char wire_push_labels_field1_key_6[64];
  int32_t wire_push_labels_field1_val_6;
  char wire_push_labels_field1_key_7[64];
  int32_t wire_push_labels_field1_val_7;
  char wire_push_labels_field1_key_8[64];
  int32_t wire_push_labels_field1_val_8;
  char wire_push_labels_field1_key_9[64];
  int32_t wire_push_labels_field1_val_9;
  char wire_push_labels_field1_key_10[64];
  int32_t wire_push_labels_field1_val_10;
  char wire_push_labels_field1_key_11[64];
  int32_t wire_push_labels_field1_val_11;
  char wire_push_labels_field1_key_12[64];
  int32_t wire_push_labels_field1_val_12;
  char wire_push_labels_field1_key_13[64];
  int32_t wire_push_labels_field1_val_13;
  char wire_push_labels_field1_key_14[64];
  int32_t wire_push_labels_field1_val_14;
  char wire_push_labels_field1_key_15[64];
  int32_t wire_push_labels_field1_val_15;
} CompanionProtocolPhoneToWatchWire;

typedef struct {
  CompanionProtocolPhoneToWatchKind kind;
  int32_t int_fields[COMPANION_PROTOCOL_MAX_FIELDS];
  CompanionProtocolPhoneToWatchWire wire;
  int32_t list_counts[COMPANION_PROTOCOL_MAX_FIELDS];
  int32_t list_values[COMPANION_PROTOCOL_MAX_FIELDS][COMPANION_PROTOCOL_LIST_MAX_ELEMENTS];
  int32_t union_value_fields[COMPANION_PROTOCOL_MAX_FIELDS];
  bool bool_fields[COMPANION_PROTOCOL_MAX_FIELDS];
  char string_fields[COMPANION_PROTOCOL_MAX_FIELDS][64];
} CompanionProtocolPhoneToWatchMessage;

typedef struct {
  bool saw_tag;
  int32_t tag;
  CompanionProtocolPhoneToWatchMessage message;
  bool saw_fields[COMPANION_PROTOCOL_MAX_FIELDS];
  bool saw_union_value_fields[COMPANION_PROTOCOL_MAX_FIELDS];
  bool saw_list_counts[COMPANION_PROTOCOL_MAX_FIELDS];
  bool saw_list_elements[COMPANION_PROTOCOL_MAX_FIELDS][COMPANION_PROTOCOL_LIST_MAX_ELEMENTS];
  bool saw_wire_send_color_field1;
  bool saw_wire_send_measure_field1_tag;
  bool saw_wire_send_measure_field1_value;
  bool saw_wire_send_point_field1_x;
  bool saw_wire_send_point_field1_y;
  bool saw_wire_send_counts_field1_count;
  bool saw_wire_send_counts_field1_0;
  bool saw_wire_send_counts_field1_1;
  bool saw_wire_send_counts_field1_2;
  bool saw_wire_send_counts_field1_3;
  bool saw_wire_send_counts_field1_4;
  bool saw_wire_send_counts_field1_5;
  bool saw_wire_send_counts_field1_6;
  bool saw_wire_send_counts_field1_7;
  bool saw_wire_send_counts_field1_8;
  bool saw_wire_send_counts_field1_9;
  bool saw_wire_send_counts_field1_10;
  bool saw_wire_send_counts_field1_11;
  bool saw_wire_send_counts_field1_12;
  bool saw_wire_send_counts_field1_13;
  bool saw_wire_send_counts_field1_14;
  bool saw_wire_send_counts_field1_15;
  bool saw_wire_echo_color_field1;
  bool saw_wire_echo_measure_field1_tag;
  bool saw_wire_echo_measure_field1_value;
  bool saw_wire_echo_point_field1_x;
  bool saw_wire_echo_point_field1_y;
  bool saw_wire_echo_counts_field1_count;
  bool saw_wire_echo_counts_field1_0;
  bool saw_wire_echo_counts_field1_1;
  bool saw_wire_echo_counts_field1_2;
  bool saw_wire_echo_counts_field1_3;
  bool saw_wire_echo_counts_field1_4;
  bool saw_wire_echo_counts_field1_5;
  bool saw_wire_echo_counts_field1_6;
  bool saw_wire_echo_counts_field1_7;
  bool saw_wire_echo_counts_field1_8;
  bool saw_wire_echo_counts_field1_9;
  bool saw_wire_echo_counts_field1_10;
  bool saw_wire_echo_counts_field1_11;
  bool saw_wire_echo_counts_field1_12;
  bool saw_wire_echo_counts_field1_13;
  bool saw_wire_echo_counts_field1_14;
  bool saw_wire_echo_counts_field1_15;
  bool saw_wire_push_bool_field1;
  bool saw_wire_push_string_field1;
  bool saw_wire_push_points_field1_count;
  bool saw_wire_push_points_field1_0_x;
  bool saw_wire_push_points_field1_0_y;
  bool saw_wire_push_points_field1_1_x;
  bool saw_wire_push_points_field1_1_y;
  bool saw_wire_push_points_field1_2_x;
  bool saw_wire_push_points_field1_2_y;
  bool saw_wire_push_points_field1_3_x;
  bool saw_wire_push_points_field1_3_y;
  bool saw_wire_push_points_field1_4_x;
  bool saw_wire_push_points_field1_4_y;
  bool saw_wire_push_points_field1_5_x;
  bool saw_wire_push_points_field1_5_y;
  bool saw_wire_push_points_field1_6_x;
  bool saw_wire_push_points_field1_6_y;
  bool saw_wire_push_points_field1_7_x;
  bool saw_wire_push_points_field1_7_y;
  bool saw_wire_push_points_field1_8_x;
  bool saw_wire_push_points_field1_8_y;
  bool saw_wire_push_points_field1_9_x;
  bool saw_wire_push_points_field1_9_y;
  bool saw_wire_push_points_field1_10_x;
  bool saw_wire_push_points_field1_10_y;
  bool saw_wire_push_points_field1_11_x;
  bool saw_wire_push_points_field1_11_y;
  bool saw_wire_push_points_field1_12_x;
  bool saw_wire_push_points_field1_12_y;
  bool saw_wire_push_points_field1_13_x;
  bool saw_wire_push_points_field1_13_y;
  bool saw_wire_push_points_field1_14_x;
  bool saw_wire_push_points_field1_14_y;
  bool saw_wire_push_points_field1_15_x;
  bool saw_wire_push_points_field1_15_y;
  bool saw_wire_push_labels_field1_count;
  bool saw_wire_push_labels_field1_key_0;
  bool saw_wire_push_labels_field1_val_0;
  bool saw_wire_push_labels_field1_key_1;
  bool saw_wire_push_labels_field1_val_1;
  bool saw_wire_push_labels_field1_key_2;
  bool saw_wire_push_labels_field1_val_2;
  bool saw_wire_push_labels_field1_key_3;
  bool saw_wire_push_labels_field1_val_3;
  bool saw_wire_push_labels_field1_key_4;
  bool saw_wire_push_labels_field1_val_4;
  bool saw_wire_push_labels_field1_key_5;
  bool saw_wire_push_labels_field1_val_5;
  bool saw_wire_push_labels_field1_key_6;
  bool saw_wire_push_labels_field1_val_6;
  bool saw_wire_push_labels_field1_key_7;
  bool saw_wire_push_labels_field1_val_7;
  bool saw_wire_push_labels_field1_key_8;
  bool saw_wire_push_labels_field1_val_8;
  bool saw_wire_push_labels_field1_key_9;
  bool saw_wire_push_labels_field1_val_9;
  bool saw_wire_push_labels_field1_key_10;
  bool saw_wire_push_labels_field1_val_10;
  bool saw_wire_push_labels_field1_key_11;
  bool saw_wire_push_labels_field1_val_11;
  bool saw_wire_push_labels_field1_key_12;
  bool saw_wire_push_labels_field1_val_12;
  bool saw_wire_push_labels_field1_key_13;
  bool saw_wire_push_labels_field1_val_13;
  bool saw_wire_push_labels_field1_key_14;
  bool saw_wire_push_labels_field1_val_14;
  bool saw_wire_push_labels_field1_key_15;
  bool saw_wire_push_labels_field1_val_15;
} CompanionProtocolPhoneToWatchDecoder;

bool companion_protocol_encode_watch_to_phone(DictionaryIterator *iter, int32_t tag, int32_t value);
void companion_protocol_phone_to_watch_decoder_init(CompanionProtocolPhoneToWatchDecoder *decoder);
void companion_protocol_phone_to_watch_decoder_push_tuple(
    CompanionProtocolPhoneToWatchDecoder *decoder, const Tuple *tuple);
bool companion_protocol_phone_to_watch_decoder_finish(
    CompanionProtocolPhoneToWatchDecoder *decoder, CompanionProtocolPhoneToWatchMessage *out);
int companion_protocol_dispatch_phone_to_watch(
    ElmcPebbleApp *app, const CompanionProtocolPhoneToWatchMessage *message);

#endif
