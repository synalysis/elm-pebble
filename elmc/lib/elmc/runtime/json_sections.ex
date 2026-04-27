defmodule Elmc.Runtime.JsonSections do
  @moduledoc false

  @spec runtime_header_declarations() :: String.t()
  def runtime_header_declarations do
    """
    /* --- Json.Decode --- */
    ElmcValue *elmc_json_decode_value(ElmcValue *decoder, ElmcValue *value);
    ElmcValue *elmc_json_decode_string(ElmcValue *decoder, ElmcValue *s);
    ElmcValue *elmc_json_decode_string_decoder(void);
    ElmcValue *elmc_json_decode_int_decoder(void);
    ElmcValue *elmc_json_decode_float_decoder(void);
    ElmcValue *elmc_json_decode_bool_decoder(void);
    ElmcValue *elmc_json_decode_null(ElmcValue *default_val);
    ElmcValue *elmc_json_decode_nullable(ElmcValue *decoder);
    ElmcValue *elmc_json_decode_list(ElmcValue *decoder);
    ElmcValue *elmc_json_decode_array(ElmcValue *decoder);
    ElmcValue *elmc_json_decode_field(ElmcValue *name, ElmcValue *decoder);
    ElmcValue *elmc_json_decode_at(ElmcValue *path, ElmcValue *decoder);
    ElmcValue *elmc_json_decode_index(ElmcValue *idx, ElmcValue *decoder);
    ElmcValue *elmc_json_decode_map(ElmcValue *f, ElmcValue *decoder);
    ElmcValue *elmc_json_decode_map2(ElmcValue *f, ElmcValue *d1, ElmcValue *d2);
    ElmcValue *elmc_json_decode_map3(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3);
    ElmcValue *elmc_json_decode_map4(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4);
    ElmcValue *elmc_json_decode_map5(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5);
    ElmcValue *elmc_json_decode_succeed(ElmcValue *value);
    ElmcValue *elmc_json_decode_fail(ElmcValue *msg);
    ElmcValue *elmc_json_decode_and_then(ElmcValue *f, ElmcValue *decoder);
    ElmcValue *elmc_json_decode_one_of(ElmcValue *decoders);
    ElmcValue *elmc_json_decode_maybe(ElmcValue *decoder);
    ElmcValue *elmc_json_decode_lazy(ElmcValue *thunk);
    ElmcValue *elmc_json_decode_value_decoder(void);
    ElmcValue *elmc_json_decode_error_to_string(ElmcValue *err);
    ElmcValue *elmc_json_decode_key_value_pairs(ElmcValue *decoder);
    ElmcValue *elmc_json_decode_dict(ElmcValue *decoder);

    /* --- Json.Encode --- */
    ElmcValue *elmc_json_encode_string(ElmcValue *s);
    ElmcValue *elmc_json_encode_int(ElmcValue *n);
    ElmcValue *elmc_json_encode_float(ElmcValue *f);
    ElmcValue *elmc_json_encode_bool(ElmcValue *b);
    ElmcValue *elmc_json_encode_null(void);
    ElmcValue *elmc_json_encode_list(ElmcValue *f, ElmcValue *items);
    ElmcValue *elmc_json_encode_array(ElmcValue *f, ElmcValue *items);
    ElmcValue *elmc_json_encode_set(ElmcValue *f, ElmcValue *items);
    ElmcValue *elmc_json_encode_object(ElmcValue *pairs);
    ElmcValue *elmc_json_encode_dict(ElmcValue *key_fn, ElmcValue *val_fn, ElmcValue *dict);
    ElmcValue *elmc_json_encode_encode(ElmcValue *indent, ElmcValue *value);
    """
  end

  @spec runtime_source_includes() :: String.t()
  def runtime_source_includes do
    """
    #if defined(ELMC_USE_CJSON)
    #if defined(__has_include)
    #if __has_include("cJSON.h")
    #include "cJSON.h"
    #elif __has_include(<cjson/cJSON.h>)
    #include <cjson/cJSON.h>
    #else
    #undef ELMC_USE_CJSON
    #endif
    #else
    #include "cJSON.h"
    #endif
    #endif
    """
  end

  @spec runtime_source_impl() :: String.t()
  def runtime_source_impl do
    """
    /* ================================================================
       Standard Library – Json.Decode
       ================================================================ */

    #define ELMC_JSON_DECODER_STRING 1
    #define ELMC_JSON_DECODER_INT 2
    #define ELMC_JSON_DECODER_FLOAT 3
    #define ELMC_JSON_DECODER_BOOL 4
    #define ELMC_JSON_DECODER_VALUE 5
    #define ELMC_JSON_DECODER_FIELD 102
    #define ELMC_JSON_DECODER_INDEX 103
    #define ELMC_JSON_DECODER_LIST 104
    #define ELMC_JSON_DECODER_ARRAY 105
    #define ELMC_JSON_DECODER_NULL 106
    #define ELMC_JSON_DECODER_MAYBE 107
    #define ELMC_JSON_DECODER_ONE_OF 108
    #define ELMC_JSON_DECODER_SUCCEED 109
    #define ELMC_JSON_DECODER_FAIL 110
    #define ELMC_JSON_DECODER_MAP 111
    #define ELMC_JSON_DECODER_MAP2 112
    #define ELMC_JSON_DECODER_AND_THEN 113

    #if defined(__GNUC__) || defined(__clang__)
    #define ELMC_MAYBE_UNUSED __attribute__((unused))
    #else
    #define ELMC_MAYBE_UNUSED
    #endif

    static ELMC_MAYBE_UNUSED int64_t elmc_json_decoder_tag(ElmcValue *decoder) {
      if (!decoder) return 0;
      if (decoder->tag == ELMC_TAG_INT || decoder->tag == ELMC_TAG_BOOL) {
        return elmc_as_int(decoder);
      }
      if (decoder->tag == ELMC_TAG_TUPLE2 && decoder->payload != NULL) {
        ElmcTuple2 *tuple = (ElmcTuple2 *)decoder->payload;
        if (tuple->first && (tuple->first->tag == ELMC_TAG_INT || tuple->first->tag == ELMC_TAG_BOOL)) {
          return elmc_as_int(tuple->first);
        }
      }
      return 0;
    }

    static ELMC_MAYBE_UNUSED ElmcValue *elmc_json_decoder_payload(ElmcValue *decoder) {
      if (!decoder || decoder->tag != ELMC_TAG_TUPLE2 || decoder->payload == NULL) return NULL;
      ElmcTuple2 *tuple = (ElmcTuple2 *)decoder->payload;
      return tuple->second;
    }

    static ElmcValue *elmc_json_decoder_wrap(int64_t tag, ElmcValue *payload) {
      ElmcValue *tag_value = elmc_new_int(tag);
      if (!tag_value) return NULL;
      ElmcValue *wrapped = elmc_tuple2(tag_value, payload ? payload : elmc_list_nil());
      elmc_release(tag_value);
      return wrapped;
    }

    #if defined(ELMC_USE_CJSON)
    static ElmcValue *elmc_json_value_from_cjson(const cJSON *node) {
      if (!node) return elmc_new_string("null");
      char *printed = cJSON_PrintUnformatted((cJSON *)node);
      if (!printed) return elmc_new_string("null");
      ElmcValue *out = elmc_new_string(printed);
      free(printed);
      return out;
    }

    static ElmcValue *elmc_json_decode_with_cjson(ElmcValue *decoder, const cJSON *node, const char **error_out);

    static ElmcValue *elmc_json_decode_map_with_cjson(ElmcValue *payload, const cJSON *node, const char **error_out) {
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
        if (error_out) *error_out = "Invalid map decoder";
        return NULL;
      }
      ElmcTuple2 *tuple = (ElmcTuple2 *)payload->payload;
      ElmcValue *f = tuple->first;
      ElmcValue *inner = tuple->second;
      if (!f || !inner) {
        if (error_out) *error_out = "Invalid map decoder";
        return NULL;
      }
      ElmcValue *decoded = elmc_json_decode_with_cjson(inner, node, error_out);
      if (!decoded) return NULL;
      ElmcValue *args[] = { decoded };
      ElmcValue *mapped = elmc_closure_call(f, args, 1);
      elmc_release(decoded);
      if (!mapped && error_out) *error_out = "Failed to map decoded value";
      return mapped;
    }

    static ElmcValue *elmc_json_decode_map2_with_cjson(ElmcValue *payload, const cJSON *node, const char **error_out) {
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
        if (error_out) *error_out = "Invalid map2 decoder";
        return NULL;
      }
      ElmcTuple2 *outer = (ElmcTuple2 *)payload->payload;
      ElmcValue *f = outer->first;
      ElmcValue *rest = outer->second;
      if (!f || !rest || rest->tag != ELMC_TAG_TUPLE2 || rest->payload == NULL) {
        if (error_out) *error_out = "Invalid map2 decoder";
        return NULL;
      }
      ElmcTuple2 *inner = (ElmcTuple2 *)rest->payload;
      ElmcValue *d1 = inner->first;
      ElmcValue *d2 = inner->second;
      if (!d1 || !d2) {
        if (error_out) *error_out = "Invalid map2 decoder";
        return NULL;
      }
      ElmcValue *v1 = elmc_json_decode_with_cjson(d1, node, error_out);
      if (!v1) return NULL;
      ElmcValue *v2 = elmc_json_decode_with_cjson(d2, node, error_out);
      if (!v2) {
        elmc_release(v1);
        return NULL;
      }
      ElmcValue *args[] = { v1, v2 };
      ElmcValue *mapped = elmc_closure_call(f, args, 2);
      elmc_release(v1);
      elmc_release(v2);
      if (!mapped && error_out) *error_out = "Failed to map2 decoded value";
      return mapped;
    }

    static ElmcValue *elmc_json_decode_with_cjson(ElmcValue *decoder, const cJSON *node, const char **error_out) {
      int64_t tag = elmc_json_decoder_tag(decoder);
      ElmcValue *payload = elmc_json_decoder_payload(decoder);

      switch (tag) {
        case ELMC_JSON_DECODER_STRING:
          if (!cJSON_IsString(node)) {
            if (error_out) *error_out = "Expected STRING";
            return NULL;
          }
          return elmc_new_string(node->valuestring ? node->valuestring : "");
        case ELMC_JSON_DECODER_INT:
          if (!cJSON_IsNumber(node)) {
            if (error_out) *error_out = "Expected INT";
            return NULL;
          }
          {
            int64_t as_int = (int64_t)node->valuedouble;
            if ((double)as_int != node->valuedouble) {
              if (error_out) *error_out = "Expected INT";
              return NULL;
            }
            return elmc_new_int(as_int);
          }
        case ELMC_JSON_DECODER_FLOAT:
          if (!cJSON_IsNumber(node)) {
            if (error_out) *error_out = "Expected FLOAT";
            return NULL;
          }
          return elmc_new_float(node->valuedouble);
        case ELMC_JSON_DECODER_BOOL:
          if (!cJSON_IsBool(node)) {
            if (error_out) *error_out = "Expected BOOL";
            return NULL;
          }
          return elmc_new_bool(cJSON_IsTrue(node));
        case ELMC_JSON_DECODER_VALUE:
          return elmc_json_value_from_cjson(node);
        case ELMC_JSON_DECODER_FIELD:
          if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL || !cJSON_IsObject(node)) {
            if (error_out) *error_out = "Expected OBJECT field";
            return NULL;
          } else {
            ElmcTuple2 *field_tuple = (ElmcTuple2 *)payload->payload;
            const char *field_name =
              (field_tuple->first && field_tuple->first->tag == ELMC_TAG_STRING && field_tuple->first->payload)
                ? (const char *)field_tuple->first->payload
                : NULL;
            if (!field_name) {
              if (error_out) *error_out = "Invalid field decoder";
              return NULL;
            }
            cJSON *child = cJSON_GetObjectItemCaseSensitive((cJSON *)node, field_name);
            if (!child) {
              if (error_out) *error_out = "Missing field";
              return NULL;
            }
            return elmc_json_decode_with_cjson(field_tuple->second, child, error_out);
          }
        case ELMC_JSON_DECODER_INDEX:
          if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL || !cJSON_IsArray(node)) {
            if (error_out) *error_out = "Expected ARRAY index";
            return NULL;
          } else {
            ElmcTuple2 *index_tuple = (ElmcTuple2 *)payload->payload;
            int idx = (int)elmc_as_int(index_tuple->first);
            cJSON *child = cJSON_GetArrayItem((cJSON *)node, idx);
            if (!child) {
              if (error_out) *error_out = "Index out of range";
              return NULL;
            }
            return elmc_json_decode_with_cjson(index_tuple->second, child, error_out);
          }
        case ELMC_JSON_DECODER_LIST:
        case ELMC_JSON_DECODER_ARRAY:
          if (!payload || !cJSON_IsArray(node)) {
            if (error_out) *error_out = "Expected ARRAY";
            return NULL;
          } else {
            ElmcValue *rev = elmc_list_nil();
            if (!rev) {
              if (error_out) *error_out = "Out of memory";
              return NULL;
            }
            cJSON *child = NULL;
            cJSON_ArrayForEach(child, (cJSON *)node) {
              ElmcValue *decoded = elmc_json_decode_with_cjson(payload, child, error_out);
              if (!decoded) {
                elmc_release(rev);
                return NULL;
              }
              ElmcValue *next = elmc_list_cons(decoded, rev);
              elmc_release(decoded);
              elmc_release(rev);
              rev = next;
            }
            ElmcValue *out = elmc_list_reverse_copy(rev);
            elmc_release(rev);
            return out;
          }
        case ELMC_JSON_DECODER_NULL:
          if (cJSON_IsNull(node)) return payload ? elmc_retain(payload) : elmc_list_nil();
          if (error_out) *error_out = "Expected NULL";
          return NULL;
        case ELMC_JSON_DECODER_MAYBE: {
          ElmcValue *decoded = elmc_json_decode_with_cjson(payload, node, NULL);
          if (!decoded) return elmc_maybe_nothing();
          ElmcValue *out = elmc_maybe_just(decoded);
          elmc_release(decoded);
          return out;
        }
        case ELMC_JSON_DECODER_ONE_OF:
          if (!payload || payload->tag != ELMC_TAG_LIST) {
            if (error_out) *error_out = "Invalid oneOf decoder";
            return NULL;
          } else {
            ElmcValue *cursor = payload;
            while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
              ElmcCons *cons = (ElmcCons *)cursor->payload;
              ElmcValue *decoded = elmc_json_decode_with_cjson(cons->head, node, NULL);
              if (decoded) return decoded;
              cursor = cons->tail;
            }
            if (error_out) *error_out = "oneOf failed";
            return NULL;
          }
        case ELMC_JSON_DECODER_SUCCEED:
          return payload ? elmc_retain(payload) : elmc_list_nil();
        case ELMC_JSON_DECODER_FAIL:
          if (error_out) *error_out = "Decoder forced failure";
          return NULL;
        case ELMC_JSON_DECODER_MAP:
          return elmc_json_decode_map_with_cjson(payload, node, error_out);
        case ELMC_JSON_DECODER_MAP2:
          return elmc_json_decode_map2_with_cjson(payload, node, error_out);
        case ELMC_JSON_DECODER_AND_THEN:
          if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
            if (error_out) *error_out = "Invalid andThen decoder";
            return NULL;
          } else {
            ElmcTuple2 *and_then_tuple = (ElmcTuple2 *)payload->payload;
            ElmcValue *step = elmc_json_decode_with_cjson(and_then_tuple->second, node, error_out);
            if (!step) return NULL;
            ElmcValue *args[] = { step };
            ElmcValue *next_decoder = elmc_closure_call(and_then_tuple->first, args, 1);
            elmc_release(step);
            if (!next_decoder) {
              if (error_out) *error_out = "Failed to resolve andThen decoder";
              return NULL;
            }
            ElmcValue *decoded = elmc_json_decode_with_cjson(next_decoder, node, error_out);
            elmc_release(next_decoder);
            return decoded;
          }
        default:
          if (error_out) *error_out = "Unsupported decoder";
          return NULL;
      }
    }
    #endif

    ElmcValue *elmc_json_decode_value(ElmcValue *decoder, ElmcValue *value) {
    #if defined(ELMC_USE_CJSON)
      if (!value || value->tag != ELMC_TAG_STRING || value->payload == NULL) {
        return elmc_result_err(elmc_new_string("Expected JSON string value"));
      }
      const char *raw = (const char *)value->payload;
      const char *parse_end = NULL;
      cJSON *parsed = cJSON_ParseWithOpts(raw, &parse_end, 1);
      if (!parsed) {
        return elmc_result_err(elmc_new_string("Invalid JSON"));
      }
      const char *decode_error = "Decode failed";
      ElmcValue *decoded = elmc_json_decode_with_cjson(decoder, parsed, &decode_error);
      cJSON_Delete(parsed);
      if (!decoded) return elmc_result_err(elmc_new_string(decode_error ? decode_error : "Decode failed"));
      ElmcValue *ok = elmc_result_ok(decoded);
      elmc_release(decoded);
      return ok;
    #else
      (void)decoder;
      (void)value;
      return elmc_result_err(elmc_new_string("Json.Decode requires cJSON"));
    #endif
    }

    ElmcValue *elmc_json_decode_string(ElmcValue *decoder, ElmcValue *s) {
      return elmc_json_decode_value(decoder, s);
    }

    ElmcValue *elmc_json_decode_string_decoder(void) {
      return elmc_new_int(ELMC_JSON_DECODER_STRING);
    }

    ElmcValue *elmc_json_decode_int_decoder(void) {
      return elmc_new_int(ELMC_JSON_DECODER_INT);
    }

    ElmcValue *elmc_json_decode_float_decoder(void) {
      return elmc_new_int(ELMC_JSON_DECODER_FLOAT);
    }

    ElmcValue *elmc_json_decode_bool_decoder(void) {
      return elmc_new_int(ELMC_JSON_DECODER_BOOL);
    }

    ElmcValue *elmc_json_decode_null(ElmcValue *default_val) {
      return elmc_json_decoder_wrap(ELMC_JSON_DECODER_NULL, default_val);
    }

    ElmcValue *elmc_json_decode_nullable(ElmcValue *decoder) {
      return elmc_json_decode_maybe(decoder);
    }

    ElmcValue *elmc_json_decode_list(ElmcValue *decoder) {
      return elmc_json_decoder_wrap(ELMC_JSON_DECODER_LIST, decoder);
    }

    ElmcValue *elmc_json_decode_array(ElmcValue *decoder) {
      return elmc_json_decoder_wrap(ELMC_JSON_DECODER_ARRAY, decoder);
    }

    ElmcValue *elmc_json_decode_field(ElmcValue *name, ElmcValue *decoder) {
      ElmcValue *payload = elmc_tuple2(name, decoder);
      if (!payload) return NULL;
      ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_FIELD, payload);
      elmc_release(payload);
      return wrapped;
    }

    ElmcValue *elmc_json_decode_at(ElmcValue *path, ElmcValue *decoder) {
      if (!path) return elmc_retain(decoder);
      ElmcValue *reversed = elmc_list_reverse_copy(path);
      ElmcValue *current = elmc_retain(decoder);
      ElmcValue *cursor = reversed;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *next = elmc_json_decode_field(node->head, current);
        elmc_release(current);
        current = next;
        cursor = node->tail;
      }
      elmc_release(reversed);
      return current;
    }

    ElmcValue *elmc_json_decode_index(ElmcValue *idx, ElmcValue *decoder) {
      ElmcValue *payload = elmc_tuple2(idx, decoder);
      if (!payload) return NULL;
      ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_INDEX, payload);
      elmc_release(payload);
      return wrapped;
    }

    ElmcValue *elmc_json_decode_map(ElmcValue *f, ElmcValue *decoder) {
      ElmcValue *payload = elmc_tuple2(f, decoder);
      if (!payload) return NULL;
      ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAP, payload);
      elmc_release(payload);
      return wrapped;
    }

    ElmcValue *elmc_json_decode_map2(ElmcValue *f, ElmcValue *d1, ElmcValue *d2) {
      ElmcValue *pair = elmc_tuple2(d1, d2);
      if (!pair) return NULL;
      ElmcValue *payload = elmc_tuple2(f, pair);
      elmc_release(pair);
      if (!payload) return NULL;
      ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAP2, payload);
      elmc_release(payload);
      return wrapped;
    }

    ElmcValue *elmc_json_decode_map3(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3) {
      (void)f; (void)d1; (void)d2; (void)d3;
      return elmc_result_err(elmc_new_string("Json.Decode.map3 not implemented in C runtime"));
    }

    ElmcValue *elmc_json_decode_map4(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4) {
      (void)f; (void)d1; (void)d2; (void)d3; (void)d4;
      return elmc_result_err(elmc_new_string("Json.Decode.map4 not implemented in C runtime"));
    }

    ElmcValue *elmc_json_decode_map5(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5) {
      (void)f; (void)d1; (void)d2; (void)d3; (void)d4; (void)d5;
      return elmc_result_err(elmc_new_string("Json.Decode.map5 not implemented in C runtime"));
    }

    ElmcValue *elmc_json_decode_succeed(ElmcValue *value) {
      return elmc_json_decoder_wrap(ELMC_JSON_DECODER_SUCCEED, value);
    }

    ElmcValue *elmc_json_decode_fail(ElmcValue *msg) {
      return elmc_json_decoder_wrap(ELMC_JSON_DECODER_FAIL, msg);
    }

    ElmcValue *elmc_json_decode_and_then(ElmcValue *f, ElmcValue *decoder) {
      ElmcValue *payload = elmc_tuple2(f, decoder);
      if (!payload) return NULL;
      ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_AND_THEN, payload);
      elmc_release(payload);
      return wrapped;
    }

    ElmcValue *elmc_json_decode_one_of(ElmcValue *decoders) {
      return elmc_json_decoder_wrap(ELMC_JSON_DECODER_ONE_OF, decoders);
    }

    ElmcValue *elmc_json_decode_maybe(ElmcValue *decoder) {
      return elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAYBE, decoder);
    }

    ElmcValue *elmc_json_decode_lazy(ElmcValue *thunk) {
      (void)thunk;
      return elmc_new_int(0);
    }

    ElmcValue *elmc_json_decode_value_decoder(void) {
      return elmc_new_int(ELMC_JSON_DECODER_VALUE);
    }

    ElmcValue *elmc_json_decode_error_to_string(ElmcValue *err) {
      (void)err;
      return elmc_new_string("Json.Decode.Error");
    }

    ElmcValue *elmc_json_decode_key_value_pairs(ElmcValue *decoder) {
      (void)decoder;
      return elmc_new_int(0);
    }

    ElmcValue *elmc_json_decode_dict(ElmcValue *decoder) {
      (void)decoder;
      return elmc_new_int(0);
    }

    /* ================================================================
       Standard Library – Json.Encode
       ================================================================ */

    #if defined(ELMC_USE_CJSON)
    static cJSON *elmc_json_encoded_to_cjson(ElmcValue *value) {
      if (!value) return cJSON_CreateNull();
      if (value->tag == ELMC_TAG_STRING && value->payload != NULL) {
        const char *raw = (const char *)value->payload;
        const char *parse_end = NULL;
        cJSON *parsed = cJSON_ParseWithOpts(raw, &parse_end, 1);
        if (parsed) return parsed;
        return cJSON_CreateString(raw);
      }
      if (value->tag == ELMC_TAG_INT) return cJSON_CreateNumber((double)elmc_as_int(value));
      if (value->tag == ELMC_TAG_FLOAT) return cJSON_CreateNumber(elmc_as_float(value));
      if (value->tag == ELMC_TAG_BOOL) return cJSON_CreateBool(elmc_as_int(value) ? 1 : 0);
      if (value->tag == ELMC_TAG_LIST) {
        cJSON *arr = cJSON_CreateArray();
        if (!arr) return NULL;
        ElmcValue *cursor = value;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          cJSON *child = elmc_json_encoded_to_cjson(node->head);
          if (!child) child = cJSON_CreateNull();
          cJSON_AddItemToArray(arr, child);
          cursor = node->tail;
        }
        return arr;
      }
      return cJSON_CreateNull();
    }

    static ElmcValue *elmc_json_print_value(cJSON *value, int pretty) {
      if (!value) return elmc_new_string("null");
      char *rendered = pretty ? cJSON_Print(value) : cJSON_PrintUnformatted(value);
      if (!rendered) return elmc_new_string("null");
      ElmcValue *out = elmc_new_string(rendered);
      free(rendered);
      return out;
    }
    #endif

    ElmcValue *elmc_json_encode_string(ElmcValue *s) {
    #if defined(ELMC_USE_CJSON)
      const char *raw = (s && s->tag == ELMC_TAG_STRING && s->payload) ? (const char *)s->payload : "";
      cJSON *json = cJSON_CreateString(raw);
      if (!json) return elmc_new_string("\"\"");
      ElmcValue *out = elmc_json_print_value(json, 0);
      cJSON_Delete(json);
      return out;
    #else
      if (!s) return elmc_new_string("");
      return elmc_retain(s);
    #endif
    }

    ElmcValue *elmc_json_encode_int(ElmcValue *n) {
      return elmc_string_from_int(n);
    }

    ElmcValue *elmc_json_encode_float(ElmcValue *f) {
      return elmc_string_from_float(f);
    }

    ElmcValue *elmc_json_encode_bool(ElmcValue *b) {
      return elmc_new_string(elmc_as_int(b) ? "true" : "false");
    }

    ElmcValue *elmc_json_encode_null(void) {
      return elmc_new_string("null");
    }

    ElmcValue *elmc_json_encode_list(ElmcValue *f, ElmcValue *items) {
    #if defined(ELMC_USE_CJSON)
      cJSON *arr = cJSON_CreateArray();
      if (!arr) return elmc_new_string("[]");
      ElmcValue *cursor = items;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[] = { node->head };
        ElmcValue *mapped = elmc_closure_call(f, args, 1);
        cJSON *child = elmc_json_encoded_to_cjson(mapped);
        if (!child) child = cJSON_CreateNull();
        cJSON_AddItemToArray(arr, child);
        if (mapped) elmc_release(mapped);
        cursor = node->tail;
      }
      ElmcValue *out = elmc_json_print_value(arr, 0);
      cJSON_Delete(arr);
      return out;
    #else
      (void)f; (void)items;
      return elmc_new_string("[]");
    #endif
    }

    ElmcValue *elmc_json_encode_array(ElmcValue *f, ElmcValue *items) {
      (void)f; (void)items;
      return elmc_new_string("[]");
    }

    ElmcValue *elmc_json_encode_set(ElmcValue *f, ElmcValue *items) {
      (void)f; (void)items;
      return elmc_new_string("[]");
    }

    ElmcValue *elmc_json_encode_object(ElmcValue *pairs) {
    #if defined(ELMC_USE_CJSON)
      cJSON *obj = cJSON_CreateObject();
      if (!obj) return elmc_new_string("{}");
      ElmcValue *cursor = pairs;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *entry = node->head;
        if (entry && entry->tag == ELMC_TAG_TUPLE2 && entry->payload != NULL) {
          ElmcTuple2 *tuple = (ElmcTuple2 *)entry->payload;
          const char *key = (tuple->first && tuple->first->tag == ELMC_TAG_STRING && tuple->first->payload)
                              ? (const char *)tuple->first->payload
                              : NULL;
          if (key) {
            cJSON *child = elmc_json_encoded_to_cjson(tuple->second);
            if (!child) child = cJSON_CreateNull();
            cJSON_AddItemToObject(obj, key, child);
          }
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_json_print_value(obj, 0);
      cJSON_Delete(obj);
      return out;
    #else
      (void)pairs;
      return elmc_new_string("{}");
    #endif
    }

    ElmcValue *elmc_json_encode_dict(ElmcValue *key_fn, ElmcValue *val_fn, ElmcValue *dict) {
    #if defined(ELMC_USE_CJSON)
      cJSON *obj = cJSON_CreateObject();
      if (!obj) return elmc_new_string("{}");
      ElmcValue *cursor = dict;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *entry = node->head;
        if (entry && entry->tag == ELMC_TAG_TUPLE2 && entry->payload != NULL) {
          ElmcTuple2 *tuple = (ElmcTuple2 *)entry->payload;
          ElmcValue *key_args[] = { tuple->first };
          ElmcValue *val_args[] = { tuple->second };
          ElmcValue *key_text = elmc_closure_call(key_fn, key_args, 1);
          ElmcValue *val_enc = elmc_closure_call(val_fn, val_args, 1);
          const char *key = (key_text && key_text->tag == ELMC_TAG_STRING && key_text->payload)
                              ? (const char *)key_text->payload
                              : NULL;
          if (key) {
            cJSON *child = elmc_json_encoded_to_cjson(val_enc);
            if (!child) child = cJSON_CreateNull();
            cJSON_AddItemToObject(obj, key, child);
          }
          if (key_text) elmc_release(key_text);
          if (val_enc) elmc_release(val_enc);
        }
        cursor = node->tail;
      }
      ElmcValue *out = elmc_json_print_value(obj, 0);
      cJSON_Delete(obj);
      return out;
    #else
      (void)key_fn; (void)val_fn; (void)dict;
      return elmc_new_string("{}");
    #endif
    }

    ElmcValue *elmc_json_encode_encode(ElmcValue *indent, ElmcValue *value) {
    #if defined(ELMC_USE_CJSON)
      int pretty = elmc_as_int(indent) > 0;
      cJSON *json = elmc_json_encoded_to_cjson(value);
      if (!json) return elmc_new_string("null");
      ElmcValue *out = elmc_json_print_value(json, pretty);
      cJSON_Delete(json);
      return out;
    #else
      (void)indent;
      if (!value) return elmc_new_string("null");
      if (value->tag == ELMC_TAG_STRING) return elmc_retain(value);
      return elmc_debug_to_string(value);
    #endif
    }
    """
  end
end
