#include "companion_protocol.h"

bool companion_protocol_encode_watch_to_phone(DictionaryIterator *iter, int32_t tag, int32_t value) {
  if (!iter) return false;
  switch (tag) {
    case 2:
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_REQUEST_TAG, 2);
      dict_write_int32(iter, COMPANION_PROTOCOL_KEY_REQUEST_VALUE, value);
      return true;
    default:
      return false;
  }
}

void companion_protocol_phone_to_watch_decoder_init(CompanionProtocolPhoneToWatchDecoder *decoder) {
  if (!decoder) return;
  decoder->saw_tag = false;
  decoder->saw_value = false;
  decoder->tag = 0;
  decoder->value = 0;
}

void companion_protocol_phone_to_watch_decoder_push_tuple(
    CompanionProtocolPhoneToWatchDecoder *decoder, const Tuple *tuple) {
  if (!decoder || !tuple) return;
  if (tuple->type != TUPLE_INT && tuple->type != TUPLE_UINT) return;

  if (tuple->key == COMPANION_PROTOCOL_KEY_RESPONSE_TAG) {
    decoder->tag = tuple->value->int32;
    decoder->saw_tag = true;
    return;
  }

  if (tuple->key == COMPANION_PROTOCOL_KEY_RESPONSE_VALUE) {
    decoder->value = tuple->value->int32;
    decoder->saw_value = true;
  }
}

bool companion_protocol_phone_to_watch_decoder_finish(
    const CompanionProtocolPhoneToWatchDecoder *decoder, CompanionProtocolPhoneToWatchMessage *out) {
  if (!decoder || !out) return false;
  if (!decoder->saw_tag || !decoder->saw_value) return false;

  switch (decoder->tag) {
    case 201:
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PROVIDE_TEMPERATURE;
      out->value = decoder->value;
      return true;
    default:
      out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN;
      out->value = decoder->value;
      return false;
  }
}
