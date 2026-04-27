#ifndef COMPANION_PROTOCOL_H
#define COMPANION_PROTOCOL_H

#include <pebble.h>
#include <stdbool.h>
#include <stdint.h>

#define COMPANION_PROTOCOL_KEY_REQUEST_TAG 10
#define COMPANION_PROTOCOL_KEY_REQUEST_VALUE 11
#define COMPANION_PROTOCOL_KEY_RESPONSE_TAG 12
#define COMPANION_PROTOCOL_KEY_RESPONSE_VALUE 13

#define COMPANION_PROTOCOL_WATCH_TO_PHONE_TAG_REQUEST_WEATHER 2

#define COMPANION_PROTOCOL_PHONE_TO_WATCH_TAG_PROVIDE_TEMPERATURE 201

#define COMPANION_PROTOCOL_LOCATION_BERLIN 1
#define COMPANION_PROTOCOL_LOCATION_ZURICH 2
#define COMPANION_PROTOCOL_LOCATION_NEW_YORK 3

typedef enum {
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN = 0,
  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PROVIDE_TEMPERATURE,
} CompanionProtocolPhoneToWatchKind;

typedef struct {
  CompanionProtocolPhoneToWatchKind kind;
  int32_t value;
} CompanionProtocolPhoneToWatchMessage;

typedef struct {
  bool saw_tag;
  bool saw_value;
  int32_t tag;
  int32_t value;
} CompanionProtocolPhoneToWatchDecoder;

bool companion_protocol_encode_watch_to_phone(DictionaryIterator *iter, int32_t tag, int32_t value);
void companion_protocol_phone_to_watch_decoder_init(CompanionProtocolPhoneToWatchDecoder *decoder);
void companion_protocol_phone_to_watch_decoder_push_tuple(
    CompanionProtocolPhoneToWatchDecoder *decoder, const Tuple *tuple);
bool companion_protocol_phone_to_watch_decoder_finish(
    const CompanionProtocolPhoneToWatchDecoder *decoder, CompanionProtocolPhoneToWatchMessage *out);

#endif
