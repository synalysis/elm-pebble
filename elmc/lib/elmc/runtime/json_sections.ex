defmodule Elmc.Runtime.JsonSections do
  @moduledoc false

  @spec runtime_header_declarations() :: String.t()
  def runtime_header_declarations do
    """
    /* --- Json.Decode --- */
    RC elmc_json_decode_value(ElmcValue **out, ElmcValue *decoder, ElmcValue *value);
    RC elmc_json_decode_string(ElmcValue **out, ElmcValue *decoder, ElmcValue *s);
    RC elmc_json_decode_string_decoder(ElmcValue **out);
    RC elmc_json_decode_int_decoder(ElmcValue **out);
    RC elmc_json_decode_float_decoder(ElmcValue **out);
    RC elmc_json_decode_bool_decoder(ElmcValue **out);
    RC elmc_json_decode_null(ElmcValue **out, ElmcValue *default_val);
    RC elmc_json_decode_nullable(ElmcValue **out, ElmcValue *decoder);
    RC elmc_json_decode_list(ElmcValue **out, ElmcValue *decoder);
    RC elmc_json_decode_array(ElmcValue **out, ElmcValue *decoder);
    RC elmc_json_decode_field(ElmcValue **out, ElmcValue *name, ElmcValue *decoder);
    RC elmc_json_decode_at(ElmcValue **out, ElmcValue *path, ElmcValue *decoder);
    RC elmc_json_decode_index(ElmcValue **out, ElmcValue *idx, ElmcValue *decoder);
    RC elmc_json_decode_map(ElmcValue **out, ElmcValue *f, ElmcValue *decoder);
    RC elmc_json_decode_map2(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2);
    RC elmc_json_decode_map3(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3);
    RC elmc_json_decode_map4(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4);
    RC elmc_json_decode_map5(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5);
    RC elmc_json_decode_map6(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6);
    RC elmc_json_decode_map7(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6, ElmcValue *d7);
    RC elmc_json_decode_map8(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6, ElmcValue *d7, ElmcValue *d8);
    RC elmc_json_decode_succeed(ElmcValue **out, ElmcValue *value);
    RC elmc_json_decode_fail(ElmcValue **out, ElmcValue *msg);
    RC elmc_json_decode_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *decoder);
    RC elmc_json_decode_one_of(ElmcValue **out, ElmcValue *decoders);
    RC elmc_json_decode_maybe(ElmcValue **out, ElmcValue *decoder);
    RC elmc_json_decode_lazy(ElmcValue **out, ElmcValue *thunk);
    RC elmc_json_decode_value_decoder(ElmcValue **out);
    RC elmc_json_decode_error_to_string(ElmcValue **out, ElmcValue *err);
    RC elmc_json_decode_key_value_pairs(ElmcValue **out, ElmcValue *decoder);
    RC elmc_json_decode_dict(ElmcValue **out, ElmcValue *decoder);

    /* --- Json.Encode --- */
    RC elmc_json_encode_string(ElmcValue **out, ElmcValue *s);
    RC elmc_json_encode_int(ElmcValue **out, ElmcValue *n);
    RC elmc_json_encode_float(ElmcValue **out, ElmcValue *f);
    RC elmc_json_encode_bool(ElmcValue **out, ElmcValue *b);
    RC elmc_json_encode_null(ElmcValue **out);
    RC elmc_json_encode_list(ElmcValue **out, ElmcValue *f, ElmcValue *items);
    RC elmc_json_encode_array(ElmcValue **out, ElmcValue *f, ElmcValue *items);
    RC elmc_json_encode_set(ElmcValue **out, ElmcValue *f, ElmcValue *items);
    RC elmc_json_encode_object(ElmcValue **out, ElmcValue *pairs);
    RC elmc_json_encode_add_field(ElmcValue **out, ElmcValue *key, ElmcValue *value, ElmcValue *obj);
    RC elmc_json_encode_add_entry(ElmcValue **out, ElmcValue *func, ElmcValue *value, ElmcValue *arr);
    RC elmc_json_encode_dict(ElmcValue **out, ElmcValue *key_fn, ElmcValue *val_fn, ElmcValue *dict);
    RC elmc_json_encode_encode(ElmcValue **out, ElmcValue *indent, ElmcValue *value);

    /* Internal Json parser/encoder structs (kept in header so pruned runtimes compile). */
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
    #define ELMC_JSON_DECODER_MAP7 114
    #define ELMC_JSON_DECODER_KEY_VALUE_PAIRS 115
    #define ELMC_JSON_DECODER_DICT 116
    #define ELMC_JSON_DECODER_NULLABLE 117
    /* Official elm/json `Error` declaration order. */
    #define ELMC_JSON_ERROR_FIELD 1
    #define ELMC_JSON_ERROR_INDEX 2
    #define ELMC_JSON_ERROR_ONE_OF 3
    #define ELMC_JSON_ERROR_FAILURE 4

    typedef enum {
      ELMC_JSON_NULL = 0,
      ELMC_JSON_BOOL = 1,
      ELMC_JSON_INT = 2,
      ELMC_JSON_FLOAT = 3,
      ELMC_JSON_STRING = 4,
      ELMC_JSON_ARRAY = 5,
      ELMC_JSON_OBJECT = 6
    } ElmcJsonKind;

    typedef struct ElmcJsonValue {
      ElmcJsonKind kind;
      int bool_value;
      int64_t int_value;
      double float_value;
      char *string_value;
      char *key;
      struct ElmcJsonValue *child;
      struct ElmcJsonValue *next;
    } ElmcJsonValue;

    typedef struct {
      char *data;
      size_t len;
      size_t cap;
    } ElmcJsonBuffer;

    typedef struct {
      const char *input;
      const char *at;
      const char *error;
    } ElmcJsonParser;
    """
  end

  @spec runtime_source_includes() :: String.t()
  def runtime_source_includes do
    ""
  end

  @json_float_numbers_config """
  #ifndef ELMC_JSON_FLOAT_NUMBERS
  #define ELMC_JSON_FLOAT_NUMBERS 1
  #endif
  """

  @spec json_float_numbers_config() :: String.t()
  def json_float_numbers_config, do: @json_float_numbers_config

  @spec runtime_source_impl() :: String.t()
  def runtime_source_impl do
    ~S"""
    /* ================================================================
       Standard Library – Json.Decode
       ================================================================ */

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

    static RC elmc_json_decoder_wrap(ElmcValue **out, int64_t tag, ElmcValue *payload) {
      ElmcValue *tag_value = NULL;
      RC rc = elmc_new_int(&tag_value, tag);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_tuple2(out, tag_value, payload ? payload : elmc_list_nil());
      elmc_release(tag_value);
      return rc;
    }

    static int elmc_json_is_ws(char c) {
      return c == ' ' || c == '\n' || c == '\r' || c == '\t';
    }

    static void elmc_json_skip_ws(ElmcJsonParser *parser) {
      while (parser && parser->at && elmc_json_is_ws(*parser->at)) parser->at++;
    }

    static void elmc_json_buf_init(ElmcJsonBuffer *buf) {
      buf->data = NULL;
      buf->len = 0;
      buf->cap = 0;
    }

    static void elmc_json_buf_free(ElmcJsonBuffer *buf) {
      if (buf && buf->data) free(buf->data);
      if (buf) {
        buf->data = NULL;
        buf->len = 0;
        buf->cap = 0;
      }
    }

    static int elmc_json_buf_reserve(ElmcJsonBuffer *buf, size_t needed) {
      if (needed <= buf->cap) return 1;
      size_t next = buf->cap ? buf->cap * 2 : 32;
      while (next < needed) next *= 2;
      char *data = (char *)elmc_realloc(buf->data, next, "json_buf");
      if (!data) return 0;
      buf->data = data;
      buf->cap = next;
      return 1;
    }

    static int elmc_json_buf_append_char(ElmcJsonBuffer *buf, char c) {
      if (!elmc_json_buf_reserve(buf, buf->len + 2)) return 0;
      buf->data[buf->len++] = c;
      buf->data[buf->len] = '\0';
      return 1;
    }

    static int elmc_json_buf_append_bytes(ElmcJsonBuffer *buf, const char *data, size_t len) {
      if (!elmc_json_buf_reserve(buf, buf->len + len + 1)) return 0;
      if (len > 0) memcpy(buf->data + buf->len, data, len);
      buf->len += len;
      buf->data[buf->len] = '\0';
      return 1;
    }

    static int elmc_json_buf_append_cstr(ElmcJsonBuffer *buf, const char *data) {
      return elmc_json_buf_append_bytes(buf, data ? data : "", data ? strlen(data) : 0);
    }

    static RC elmc_json_buf_to_string(ElmcValue **out, ElmcJsonBuffer *buf) {
      RC rc = elmc_new_string(out, buf->data ? buf->data : "");
      elmc_json_buf_free(buf);
      return rc;
    }

    static ElmcJsonValue *elmc_json_new_value(ElmcJsonKind kind) {
      ElmcJsonValue *value = (ElmcJsonValue *)elmc_malloc(sizeof(ElmcJsonValue), "json_value");
      if (!value) return NULL;
      memset(value, 0, sizeof(ElmcJsonValue));
      value->kind = kind;
      return value;
    }

    static void elmc_json_free_value(ElmcJsonValue *value) {
      while (value) {
        ElmcJsonValue *next = value->next;
        if (value->child) elmc_json_free_value(value->child);
        if (value->string_value) free(value->string_value);
        if (value->key) free(value->key);
        free(value);
        value = next;
      }
    }

    static int elmc_json_hex(char c) {
      if (c >= '0' && c <= '9') return c - '0';
      if (c >= 'a' && c <= 'f') return c - 'a' + 10;
      if (c >= 'A' && c <= 'F') return c - 'A' + 10;
      return -1;
    }

    static int elmc_json_append_utf8(ElmcJsonBuffer *buf, unsigned code) {
      if (code <= 0x7f) {
        return elmc_json_buf_append_char(buf, (char)code);
      } else if (code <= 0x7ff) {
        return elmc_json_buf_append_char(buf, (char)(0xc0 | (code >> 6))) &&
               elmc_json_buf_append_char(buf, (char)(0x80 | (code & 0x3f)));
      } else {
        return elmc_json_buf_append_char(buf, (char)(0xe0 | (code >> 12))) &&
               elmc_json_buf_append_char(buf, (char)(0x80 | ((code >> 6) & 0x3f))) &&
               elmc_json_buf_append_char(buf, (char)(0x80 | (code & 0x3f)));
      }
    }

    static char *elmc_json_parse_string_raw(ElmcJsonParser *parser) {
      if (!parser || *parser->at != '"') return NULL;
      parser->at++;
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      while (*parser->at && *parser->at != '"') {
        unsigned char c = (unsigned char)*parser->at++;
        if (c < 0x20) {
          parser->error = "Invalid string";
          elmc_json_buf_free(&buf);
          return NULL;
        }
        if (c != '\\') {
          if (!elmc_json_buf_append_char(&buf, (char)c)) {
            parser->error = "Out of memory";
            return NULL;
          }
          continue;
        }
        char esc = *parser->at++;
        switch (esc) {
          case '"': if (!elmc_json_buf_append_char(&buf, '"')) return NULL; break;
          case '\\': if (!elmc_json_buf_append_char(&buf, '\\')) return NULL; break;
          case '/': if (!elmc_json_buf_append_char(&buf, '/')) return NULL; break;
          case 'b': if (!elmc_json_buf_append_char(&buf, '\b')) return NULL; break;
          case 'f': if (!elmc_json_buf_append_char(&buf, '\f')) return NULL; break;
          case 'n': if (!elmc_json_buf_append_char(&buf, '\n')) return NULL; break;
          case 'r': if (!elmc_json_buf_append_char(&buf, '\r')) return NULL; break;
          case 't': if (!elmc_json_buf_append_char(&buf, '\t')) return NULL; break;
          case 'u': {
            unsigned code = 0;
            for (int i = 0; i < 4; i++) {
              int digit = elmc_json_hex(*parser->at++);
              if (digit < 0) {
                parser->error = "Invalid unicode escape";
                elmc_json_buf_free(&buf);
                return NULL;
              }
              code = (code << 4) | (unsigned)digit;
            }
            if (code >= 0xd800 && code <= 0xdfff) {
              parser->error = "Unsupported unicode surrogate";
              elmc_json_buf_free(&buf);
              return NULL;
            }
            if (!elmc_json_append_utf8(&buf, code)) return NULL;
            break;
          }
          default:
            parser->error = "Invalid string escape";
            elmc_json_buf_free(&buf);
            return NULL;
        }
      }
      if (*parser->at != '"') {
        parser->error = "Unterminated string";
        elmc_json_buf_free(&buf);
        return NULL;
      }
      parser->at++;
      if (!elmc_json_buf_append_char(&buf, '\0')) return NULL;
      buf.len -= 1;
      return buf.data;
    }

    static ElmcJsonValue *elmc_json_parse_value(ElmcJsonParser *parser, int depth);

    static ElmcJsonValue *elmc_json_parse_number(ElmcJsonParser *parser) {
      const char *p = parser->at;
      int sign = 1;
      if (*p == '-') { sign = -1; p++; }
      if (*p < '0' || *p > '9') {
        parser->error = "Invalid number";
        return NULL;
      }
      int64_t int_part = 0;
      #if ELMC_JSON_FLOAT_NUMBERS
      double number = 0.0;
      if (*p == '0') {
        p++;
        if (*p >= '0' && *p <= '9') {
          parser->error = "Invalid leading zero";
          return NULL;
        }
      } else {
        while (*p >= '0' && *p <= '9') {
          int digit = *p++ - '0';
          int_part = int_part * 10 + digit;
          number = number * 10.0 + (double)digit;
        }
      }
      int is_int = 1;
      if (*p == '.') {
        is_int = 0;
        p++;
        if (*p < '0' || *p > '9') {
          parser->error = "Invalid fraction";
          return NULL;
        }
        double place = 0.1;
        while (*p >= '0' && *p <= '9') {
          number += (double)(*p++ - '0') * place;
          place *= 0.1;
        }
      }
      if (*p == 'e' || *p == 'E') {
        is_int = 0;
        p++;
        int exp_sign = 1;
        if (*p == '-') { exp_sign = -1; p++; }
        else if (*p == '+') { p++; }
        if (*p < '0' || *p > '9') {
          parser->error = "Invalid exponent";
          return NULL;
        }
        int exp = 0;
        while (*p >= '0' && *p <= '9') {
          exp = exp * 10 + (*p++ - '0');
          if (exp > 308) exp = 308;
        }
        while (exp-- > 0) {
          if (exp_sign > 0) number *= 10.0;
          else number /= 10.0;
        }
      }
      parser->at = p;
      ElmcJsonValue *value = elmc_json_new_value(is_int ? ELMC_JSON_INT : ELMC_JSON_FLOAT);
      if (!value) {
        parser->error = "Out of memory";
        return NULL;
      }
      value->int_value = sign < 0 ? -int_part : int_part;
      value->float_value = (sign < 0 ? -number : number);
      return value;
      #else
      if (*p == '0') {
        p++;
        if (*p >= '0' && *p <= '9') {
          parser->error = "Invalid leading zero";
          return NULL;
        }
      } else {
        while (*p >= '0' && *p <= '9') {
          int digit = *p++ - '0';
          int_part = int_part * 10 + digit;
        }
      }
      if (*p == '.' || *p == 'e' || *p == 'E') {
        parser->error = "Float number not supported";
        return NULL;
      }
      parser->at = p;
      ElmcJsonValue *value = elmc_json_new_value(ELMC_JSON_INT);
      if (!value) {
        parser->error = "Out of memory";
        return NULL;
      }
      value->int_value = sign < 0 ? -int_part : int_part;
      return value;
      #endif
    }

    static int elmc_json_match_literal(ElmcJsonParser *parser, const char *literal) {
      size_t len = strlen(literal);
      if (strncmp(parser->at, literal, len) != 0) return 0;
      parser->at += len;
      return 1;
    }

    static ElmcJsonValue *elmc_json_parse_array(ElmcJsonParser *parser, int depth) {
      parser->at++;
      ElmcJsonValue *array = elmc_json_new_value(ELMC_JSON_ARRAY);
      if (!array) return NULL;
      ElmcJsonValue **tail = &array->child;
      elmc_json_skip_ws(parser);
      if (*parser->at == ']') {
        parser->at++;
        return array;
      }
      while (*parser->at) {
        ElmcJsonValue *child = elmc_json_parse_value(parser, depth + 1);
        if (!child) {
          elmc_json_free_value(array);
          return NULL;
        }
        *tail = child;
        tail = &child->next;
        elmc_json_skip_ws(parser);
        if (*parser->at == ']') {
          parser->at++;
          return array;
        }
        if (*parser->at != ',') {
          parser->error = "Expected array separator";
          elmc_json_free_value(array);
          return NULL;
        }
        parser->at++;
        elmc_json_skip_ws(parser);
      }
      parser->error = "Unterminated array";
      elmc_json_free_value(array);
      return NULL;
    }

    static ElmcJsonValue *elmc_json_parse_object(ElmcJsonParser *parser, int depth) {
      parser->at++;
      ElmcJsonValue *object = elmc_json_new_value(ELMC_JSON_OBJECT);
      if (!object) return NULL;
      ElmcJsonValue **tail = &object->child;
      elmc_json_skip_ws(parser);
      if (*parser->at == '}') {
        parser->at++;
        return object;
      }
      while (*parser->at) {
        char *key = elmc_json_parse_string_raw(parser);
        if (!key) {
          elmc_json_free_value(object);
          return NULL;
        }
        elmc_json_skip_ws(parser);
        if (*parser->at != ':') {
          free(key);
          parser->error = "Expected object colon";
          elmc_json_free_value(object);
          return NULL;
        }
        parser->at++;
        ElmcJsonValue *child = elmc_json_parse_value(parser, depth + 1);
        if (!child) {
          free(key);
          elmc_json_free_value(object);
          return NULL;
        }
        child->key = key;
        *tail = child;
        tail = &child->next;
        elmc_json_skip_ws(parser);
        if (*parser->at == '}') {
          parser->at++;
          return object;
        }
        if (*parser->at != ',') {
          parser->error = "Expected object separator";
          elmc_json_free_value(object);
          return NULL;
        }
        parser->at++;
        elmc_json_skip_ws(parser);
      }
      parser->error = "Unterminated object";
      elmc_json_free_value(object);
      return NULL;
    }

    static ElmcJsonValue *elmc_json_parse_value(ElmcJsonParser *parser, int depth) {
      if (depth > 64) {
        parser->error = "JSON nesting too deep";
        return NULL;
      }
      elmc_json_skip_ws(parser);
      if (*parser->at == '"') {
        ElmcJsonValue *value = elmc_json_new_value(ELMC_JSON_STRING);
        if (!value) return NULL;
        value->string_value = elmc_json_parse_string_raw(parser);
        if (!value->string_value) {
          free(value);
          return NULL;
        }
        return value;
      }
      if (*parser->at == '{') return elmc_json_parse_object(parser, depth);
      if (*parser->at == '[') return elmc_json_parse_array(parser, depth);
      if (*parser->at == '-' || (*parser->at >= '0' && *parser->at <= '9')) return elmc_json_parse_number(parser);
      if (elmc_json_match_literal(parser, "true")) {
        ElmcJsonValue *value = elmc_json_new_value(ELMC_JSON_BOOL);
        if (value) value->bool_value = 1;
        return value;
      }
      if (elmc_json_match_literal(parser, "false")) return elmc_json_new_value(ELMC_JSON_BOOL);
      if (elmc_json_match_literal(parser, "null")) return elmc_json_new_value(ELMC_JSON_NULL);
      parser->error = "Invalid JSON";
      return NULL;
    }

    static ElmcJsonValue *elmc_json_parse_document(const char *raw, const char **error_out) {
      if (!raw) {
        if (error_out) *error_out = "Invalid JSON";
        return NULL;
      }
      ElmcJsonParser parser = { raw, raw, NULL };
      ElmcJsonValue *value = elmc_json_parse_value(&parser, 0);
      if (!value) {
        if (error_out) *error_out = parser.error ? parser.error : "Invalid JSON";
        return NULL;
      }
      elmc_json_skip_ws(&parser);
      if (*parser.at != '\0') {
        elmc_json_free_value(value);
        if (error_out) *error_out = "Trailing JSON input";
        return NULL;
      }
      return value;
    }

    static ElmcJsonValue *elmc_json_object_get(const ElmcJsonValue *object, const char *key) {
      if (!object || object->kind != ELMC_JSON_OBJECT || !key) return NULL;
      ElmcJsonValue *child = object->child;
      while (child) {
        if (child->key && strcmp(child->key, key) == 0) return child;
        child = child->next;
      }
      return NULL;
    }

    static ElmcJsonValue *elmc_json_array_get(const ElmcJsonValue *array, int index) {
      if (!array || array->kind != ELMC_JSON_ARRAY || index < 0) return NULL;
      ElmcJsonValue *child = array->child;
      int i = 0;
      while (child) {
        if (i == index) return child;
        i++;
        child = child->next;
      }
      return NULL;
    }

    static int elmc_json_encode_value_to_buffer(const ElmcJsonValue *value, ElmcJsonBuffer *buf);

    static int elmc_json_encode_string_to_buffer(const char *raw, ElmcJsonBuffer *buf) {
      if (!elmc_json_buf_append_char(buf, '"')) return 0;
      const unsigned char *p = (const unsigned char *)(raw ? raw : "");
      while (*p) {
        unsigned char c = *p++;
        switch (c) {
          case '"': if (!elmc_json_buf_append_cstr(buf, "\\\"")) return 0; break;
          case '\\': if (!elmc_json_buf_append_cstr(buf, "\\\\")) return 0; break;
          case '\b': if (!elmc_json_buf_append_cstr(buf, "\\b")) return 0; break;
          case '\f': if (!elmc_json_buf_append_cstr(buf, "\\f")) return 0; break;
          case '\n': if (!elmc_json_buf_append_cstr(buf, "\\n")) return 0; break;
          case '\r': if (!elmc_json_buf_append_cstr(buf, "\\r")) return 0; break;
          case '\t': if (!elmc_json_buf_append_cstr(buf, "\\t")) return 0; break;
          default:
            if (c < 0x20) {
              char escape[7];
              snprintf(escape, sizeof(escape), "\\u%04x", c);
              if (!elmc_json_buf_append_cstr(buf, escape)) return 0;
            } else if (!elmc_json_buf_append_char(buf, (char)c)) {
              return 0;
            }
            break;
        }
      }
      return elmc_json_buf_append_char(buf, '"');
    }

    static int elmc_json_encode_value_to_buffer(const ElmcJsonValue *value, ElmcJsonBuffer *buf) {
      if (!value) return elmc_json_buf_append_cstr(buf, "null");
      char number[48];
      switch (value->kind) {
        case ELMC_JSON_NULL:
          return elmc_json_buf_append_cstr(buf, "null");
        case ELMC_JSON_BOOL:
          return elmc_json_buf_append_cstr(buf, value->bool_value ? "true" : "false");
        case ELMC_JSON_INT:
          snprintf(number, sizeof(number), "%lld", (long long)value->int_value);
          return elmc_json_buf_append_cstr(buf, number);
        #if ELMC_JSON_FLOAT_NUMBERS
        case ELMC_JSON_FLOAT:
          snprintf(number, sizeof(number), "%.17g", value->float_value);
          return elmc_json_buf_append_cstr(buf, number);
        #endif
        case ELMC_JSON_STRING:
          return elmc_json_encode_string_to_buffer(value->string_value, buf);
        case ELMC_JSON_ARRAY: {
          if (!elmc_json_buf_append_char(buf, '[')) return 0;
          ElmcJsonValue *child = value->child;
          int first = 1;
          while (child) {
            if (!first && !elmc_json_buf_append_char(buf, ',')) return 0;
            if (!elmc_json_encode_value_to_buffer(child, buf)) return 0;
            first = 0;
            child = child->next;
          }
          return elmc_json_buf_append_char(buf, ']');
        }
        case ELMC_JSON_OBJECT: {
          if (!elmc_json_buf_append_char(buf, '{')) return 0;
          ElmcJsonValue *child = value->child;
          int first = 1;
          while (child) {
            if (!first && !elmc_json_buf_append_char(buf, ',')) return 0;
            if (!elmc_json_encode_string_to_buffer(child->key, buf)) return 0;
            if (!elmc_json_buf_append_char(buf, ':')) return 0;
            if (!elmc_json_encode_value_to_buffer(child, buf)) return 0;
            first = 0;
            child = child->next;
          }
          return elmc_json_buf_append_char(buf, '}');
        }
        default:
          return elmc_json_buf_append_cstr(buf, "null");
      }
    }

    static int elmc_json_buf_append_indent(ElmcJsonBuffer *buf, int indent, int depth) {
      if (!elmc_json_buf_append_char(buf, '\n')) return 0;
      for (int i = 0; i < indent * depth; i++) {
        if (!elmc_json_buf_append_char(buf, ' ')) return 0;
      }
      return 1;
    }

    static int elmc_json_pretty_value_to_buffer(const ElmcJsonValue *value, ElmcJsonBuffer *buf, int indent, int depth) {
      if (!value) return elmc_json_buf_append_cstr(buf, "null");
      char number[48];
      switch (value->kind) {
        case ELMC_JSON_NULL:
          return elmc_json_buf_append_cstr(buf, "null");
        case ELMC_JSON_BOOL:
          return elmc_json_buf_append_cstr(buf, value->bool_value ? "true" : "false");
        case ELMC_JSON_INT:
          snprintf(number, sizeof(number), "%lld", (long long)value->int_value);
          return elmc_json_buf_append_cstr(buf, number);
        #if ELMC_JSON_FLOAT_NUMBERS
        case ELMC_JSON_FLOAT:
          snprintf(number, sizeof(number), "%.17g", value->float_value);
          return elmc_json_buf_append_cstr(buf, number);
        #endif
        case ELMC_JSON_STRING:
          return elmc_json_encode_string_to_buffer(value->string_value, buf);
        case ELMC_JSON_ARRAY: {
          if (!elmc_json_buf_append_char(buf, '[')) return 0;
          ElmcJsonValue *child = value->child;
          int first = 1;
          while (child) {
            if (!first && !elmc_json_buf_append_char(buf, ',')) return 0;
            if (!elmc_json_buf_append_indent(buf, indent, depth + 1)) return 0;
            if (!elmc_json_pretty_value_to_buffer(child, buf, indent, depth + 1)) return 0;
            first = 0;
            child = child->next;
          }
          if (!first && !elmc_json_buf_append_indent(buf, indent, depth)) return 0;
          return elmc_json_buf_append_char(buf, ']');
        }
        case ELMC_JSON_OBJECT: {
          if (!elmc_json_buf_append_char(buf, '{')) return 0;
          ElmcJsonValue *child = value->child;
          int first = 1;
          while (child) {
            if (!first && !elmc_json_buf_append_char(buf, ',')) return 0;
            if (!elmc_json_buf_append_indent(buf, indent, depth + 1)) return 0;
            if (!elmc_json_encode_string_to_buffer(child->key, buf)) return 0;
            /* Official JSON.stringify(..., null, indent) uses ": " after keys. */
            if (!elmc_json_buf_append_cstr(buf, ": ")) return 0;
            if (!elmc_json_pretty_value_to_buffer(child, buf, indent, depth + 1)) return 0;
            first = 0;
            child = child->next;
          }
          if (!first && !elmc_json_buf_append_indent(buf, indent, depth)) return 0;
          return elmc_json_buf_append_char(buf, '}');
        }
        default:
          return elmc_json_buf_append_cstr(buf, "null");
      }
    }

    static RC elmc_json_value_to_string(ElmcValue **out, const ElmcJsonValue *value) {
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_encode_value_to_buffer(value, &buf)) {
        elmc_json_buf_free(&buf);
        return elmc_new_string(out, "null");
      }
      return elmc_json_buf_to_string(out, &buf);
    }

    static RC elmc_json_error_ctor(ElmcValue **out, elmc_int_t tag, ElmcValue *payload) {
      ElmcValue *tagv = NULL;
      RC rc = elmc_new_int(&tagv, tag);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_tuple2(out, tagv, payload);
      elmc_release(tagv);
      return rc;
    }

    static RC elmc_json_pretty_text(ElmcValue **out, const ElmcJsonValue *node) {
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_pretty_value_to_buffer(node, &buf, 4, 0)) {
        elmc_json_buf_free(&buf);
        return elmc_new_string(out, "null");
      }
      return elmc_json_buf_to_string(out, &buf);
    }

    static RC elmc_json_make_failure(ElmcValue **out, const char *msg, const ElmcJsonValue *node) {
      ElmcValue *msgv = NULL;
      RC rc = elmc_new_string(&msgv, msg ? msg : "");
      if (rc != RC_SUCCESS) return rc;
      ElmcValue *jsonv = NULL;
      rc = elmc_json_pretty_text(&jsonv, node);
      if (rc != RC_SUCCESS) {
        elmc_release(msgv);
        return rc;
      }
      ElmcValue *pair = NULL;
      rc = elmc_tuple2(&pair, msgv, jsonv);
      elmc_release(msgv);
      elmc_release(jsonv);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_error_ctor(out, ELMC_JSON_ERROR_FAILURE, pair);
      elmc_release(pair);
      return rc;
    }

    static RC elmc_json_make_failure_raw_string(ElmcValue **out, const char *msg, const char *raw) {
      ElmcJsonValue node;
      memset(&node, 0, sizeof(node));
      node.kind = ELMC_JSON_STRING;
      node.string_value = (char *)(raw ? raw : "");
      return elmc_json_make_failure(out, msg, &node);
    }

    static RC elmc_json_take_error(ElmcValue **out, ElmcValue **error_out, ElmcValue *err) {
      *out = NULL;
      if (error_out) {
        if (*error_out) elmc_release(*error_out);
        *error_out = err;
      } else {
        elmc_release(err);
      }
      return RC_SUCCESS;
    }

    static RC elmc_json_failure_msg(
        ElmcValue **out,
        ElmcValue **error_out,
        const char *msg,
        const ElmcJsonValue *node) {
      ElmcValue *err = NULL;
      RC rc = elmc_json_make_failure(&err, msg, node);
      if (rc != RC_SUCCESS) return rc;
      return elmc_json_take_error(out, error_out, err);
    }

    static RC elmc_json_expecting(
        ElmcValue **out,
        ElmcValue **error_out,
        const char *type,
        const ElmcJsonValue *node) {
      char msg[96];
      snprintf(msg, sizeof(msg), "Expecting %s", type ? type : "a VALUE");
      return elmc_json_failure_msg(out, error_out, msg, node);
    }

    static RC elmc_json_wrap_field_error(ElmcValue **out, const char *name, ElmcValue *nested) {
      ElmcValue *namev = NULL;
      RC rc = elmc_new_string(&namev, name ? name : "");
      if (rc != RC_SUCCESS) return rc;
      ElmcValue *pair = NULL;
      rc = elmc_tuple2(&pair, namev, nested);
      elmc_release(namev);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_error_ctor(out, ELMC_JSON_ERROR_FIELD, pair);
      elmc_release(pair);
      return rc;
    }

    static RC elmc_json_wrap_index_error(ElmcValue **out, int index, ElmcValue *nested) {
      ElmcValue *idx = NULL;
      RC rc = elmc_new_int(&idx, index);
      if (rc != RC_SUCCESS) return rc;
      ElmcValue *pair = NULL;
      rc = elmc_tuple2(&pair, idx, nested);
      elmc_release(idx);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_error_ctor(out, ELMC_JSON_ERROR_INDEX, pair);
      elmc_release(pair);
      return rc;
    }

    static RC elmc_json_make_one_of(ElmcValue **out, ElmcValue *errors) {
      ElmcValue *list = errors ? errors : elmc_list_nil();
      return elmc_json_error_ctor(out, ELMC_JSON_ERROR_ONE_OF, list);
    }

    static int elmc_json_array_length(const ElmcJsonValue *node) {
      int n = 0;
      ElmcJsonValue *child = (node && node->kind == ELMC_JSON_ARRAY) ? node->child : NULL;
      while (child) {
        n++;
        child = child->next;
      }
      return n;
    }

    /* Decode miss: RC_SUCCESS + *out=NULL (+ optional structured Error).
       OOM / allocator failure: propagate RC_ERR_*. */
    static RC elmc_json_decode_miss(
        ElmcValue **out,
        ElmcValue **error_out,
        const char *msg,
        const ElmcJsonValue *node) {
      return elmc_json_failure_msg(out, error_out, msg, node);
    }

    static RC elmc_json_decode_with_value(ElmcValue **out, ElmcValue *decoder, const ElmcJsonValue *node, ElmcValue **error_out);

    static RC elmc_json_decode_map_with_value(ElmcValue **out, ElmcValue *payload, const ElmcJsonValue *node, ElmcValue **error_out) {
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
        return elmc_json_decode_miss(out, error_out, "Invalid map decoder", node);
      }
      ElmcTuple2 *tuple = (ElmcTuple2 *)payload->payload;
      ElmcValue *decoded = NULL;
      RC rc = elmc_json_decode_with_value(&decoded, tuple->second, node, error_out);
      if (rc != RC_SUCCESS) return rc;
      if (!decoded) {
        *out = NULL;
        return RC_SUCCESS;
      }
      ElmcValue *args[] = { decoded };
      ElmcValue *mapped = elmc_closure_call(tuple->first, args, 1);
      elmc_release(decoded);
      if (!mapped) {
        return elmc_json_decode_miss(out, error_out, "Failed to map decoded value", node);
      }
      *out = mapped;
      return RC_SUCCESS;
    }

    static int elmc_json_is_decoder_value(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return 0;
      ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
      return pair->first != NULL &&
             (pair->first->tag == ELMC_TAG_INT || pair->first->tag == ELMC_TAG_BOOL);
    }

    static int elmc_json_decode_collect_decoders(ElmcValue *cursor, ElmcValue **decoders, int max_count) {
      int count = 0;

      while (cursor && count < max_count) {
        if (cursor->tag != ELMC_TAG_TUPLE2 || cursor->payload == NULL) break;

        ElmcTuple2 *pair = (ElmcTuple2 *)cursor->payload;

        if (!elmc_json_is_decoder_value(pair->first)) break;

        decoders[count++] = pair->first;
        cursor = pair->second;

        if (elmc_json_is_decoder_value(cursor)) {
          decoders[count++] = cursor;
          break;
        }
      }

      return count;
    }

    static RC elmc_json_decode_mapn_with_value(
      ElmcValue **out,
      ElmcValue *payload,
      const ElmcJsonValue *node,
      int expected_count,
      ElmcValue **error_out
    ) {
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
        return elmc_json_decode_miss(out, error_out, "Invalid map decoder", node);
      }

      ElmcTuple2 *outer = (ElmcTuple2 *)payload->payload;
      ElmcValue *decoder_slots[8];
      int count = elmc_json_decode_collect_decoders(outer->second, decoder_slots, 8);

      if (count != expected_count) {
        return elmc_json_decode_miss(out, error_out, "Invalid map decoder", node);
      }

      ElmcValue *args[8];
      int i;

      for (i = 0; i < count; i++) {
        args[i] = NULL;
        RC rc = elmc_json_decode_with_value(&args[i], decoder_slots[i], node, error_out);
        if (rc != RC_SUCCESS) {
          for (int j = 0; j < i; j++) elmc_release(args[j]);
          return rc;
        }
        if (!args[i]) {
          for (int j = 0; j < i; j++) elmc_release(args[j]);
          *out = NULL;
          return RC_SUCCESS;
        }
      }

      ElmcValue *mapped = elmc_closure_call(outer->first, args, count);
      for (i = 0; i < count; i++) elmc_release(args[i]);
      if (!mapped) {
        return elmc_json_decode_miss(out, error_out, "Failed to map decoded value", node);
      }
      *out = mapped;
      return RC_SUCCESS;
    }

    static RC elmc_json_decode_map7_with_value(ElmcValue **out, ElmcValue *payload, const ElmcJsonValue *node, ElmcValue **error_out) {
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
        return elmc_json_decode_miss(out, error_out, "Invalid map decoder", node);
      }

      ElmcTuple2 *outer = (ElmcTuple2 *)payload->payload;
      ElmcValue *decoder_slots[8];
      int count = elmc_json_decode_collect_decoders(outer->second, decoder_slots, 8);

      if (count < 2 || count > 8) {
        return elmc_json_decode_miss(out, error_out, "Invalid map decoder", node);
      }

      return elmc_json_decode_mapn_with_value(out, payload, node, count, error_out);
    }

    static RC elmc_json_decode_map2_with_value(ElmcValue **out, ElmcValue *payload, const ElmcJsonValue *node, ElmcValue **error_out) {
      return elmc_json_decode_mapn_with_value(out, payload, node, 2, error_out);
    }

    static RC elmc_json_decode_key_value_pairs_with_value(
      ElmcValue **out,
      ElmcValue *decoder,
      const ElmcJsonValue *node,
      ElmcValue **error_out
    ) {
      if (!node || node->kind != ELMC_JSON_OBJECT) {
        return elmc_json_expecting(out, error_out, "an OBJECT", node);
      }

      ElmcValue *rev = elmc_list_nil();
      ElmcJsonValue *child = node->child;

      while (child) {
        ElmcValue *key = NULL;
        RC rc = elmc_new_string(&key, child->key ? child->key : "");
        if (rc != RC_SUCCESS) {
          elmc_release(rev);
          return rc;
        }
        ElmcValue *decoded = NULL;
        rc = elmc_json_decode_with_value(&decoded, decoder, child, error_out);
        if (rc != RC_SUCCESS) {
          elmc_release(rev);
          elmc_release(key);
          return rc;
        }
        if (!decoded) {
          elmc_release(rev);
          if (error_out && *error_out) {
            ElmcValue *wrapped = NULL;
            rc = elmc_json_wrap_field_error(&wrapped, child->key ? child->key : "", *error_out);
            if (rc != RC_SUCCESS) {
              elmc_release(key);
              return rc;
            }
            elmc_release(*error_out);
            *error_out = wrapped;
          }
          elmc_release(key);
          *out = NULL;
          return RC_SUCCESS;
        }

        ElmcValue *pair = NULL;
        rc = elmc_tuple2(&pair, key, decoded);
        elmc_release(key);
        elmc_release(decoded);
        if (rc != RC_SUCCESS) {
          elmc_release(rev);
          return rc;
        }

        ElmcValue *next = NULL;
        rc = elmc_list_cons(&next, pair, rev);
        elmc_release(pair);
        elmc_release(rev);
        if (rc != RC_SUCCESS) return rc;
        rev = next;
        child = child->next;
      }

      RC rc = elmc_list_reverse_into(out, rev);
      elmc_release(rev);
      return rc;
    }

    static RC elmc_json_decode_with_value(ElmcValue **out, ElmcValue *decoder, const ElmcJsonValue *node, ElmcValue **error_out) {
      int64_t tag = elmc_json_decoder_tag(decoder);
      ElmcValue *payload = elmc_json_decoder_payload(decoder);

      switch (tag) {
        case ELMC_JSON_DECODER_STRING:
          if (!node || node->kind != ELMC_JSON_STRING) {
            return elmc_json_expecting(out, error_out, "a STRING", node);
          }
          return elmc_new_string(out, node->string_value ? node->string_value : "");
        case ELMC_JSON_DECODER_INT:
          if (!node || node->kind != ELMC_JSON_INT) {
            return elmc_json_expecting(out, error_out, "an INT", node);
          }
          return elmc_new_int(out, node->int_value);
        #if ELMC_JSON_FLOAT_NUMBERS
        case ELMC_JSON_DECODER_FLOAT:
          if (!node || (node->kind != ELMC_JSON_INT && node->kind != ELMC_JSON_FLOAT)) {
            return elmc_json_expecting(out, error_out, "a FLOAT", node);
          }
          return elmc_new_float(out, node->kind == ELMC_JSON_INT ? (double)node->int_value : node->float_value);
        #endif
        case ELMC_JSON_DECODER_BOOL:
          if (!node || node->kind != ELMC_JSON_BOOL) {
            return elmc_json_expecting(out, error_out, "a BOOL", node);
          }
          *out = elmc_bool(node->bool_value);
          return RC_SUCCESS;
        case ELMC_JSON_DECODER_VALUE:
          return elmc_json_value_to_string(out, node);
        case ELMC_JSON_DECODER_FIELD: {
          const char *field_name = NULL;
          if (payload && payload->tag == ELMC_TAG_TUPLE2 && payload->payload) {
            ElmcTuple2 *field_tuple = (ElmcTuple2 *)payload->payload;
            if (field_tuple->first && field_tuple->first->tag == ELMC_TAG_STRING &&
                field_tuple->first->payload) {
              field_name = (const char *)field_tuple->first->payload;
            }
          }
          if (!field_name) {
            return elmc_json_decode_miss(out, error_out, "Invalid field decoder", node);
          }
          if (!node || node->kind != ELMC_JSON_OBJECT || !elmc_json_object_get(node, field_name)) {
            char msg[256];
            snprintf(msg, sizeof(msg), "Expecting an OBJECT with a field named `%s`", field_name);
            return elmc_json_failure_msg(out, error_out, msg, node);
          }
          ElmcTuple2 *field_tuple = (ElmcTuple2 *)payload->payload;
          ElmcValue *decoded = NULL;
          RC rc = elmc_json_decode_with_value(&decoded, field_tuple->second,
                                             elmc_json_object_get(node, field_name), error_out);
          if (rc != RC_SUCCESS) return rc;
          if (decoded) {
            *out = decoded;
            return RC_SUCCESS;
          }
          if (error_out && *error_out) {
            ElmcValue *wrapped = NULL;
            rc = elmc_json_wrap_field_error(&wrapped, field_name, *error_out);
            if (rc != RC_SUCCESS) return rc;
            elmc_release(*error_out);
            *error_out = wrapped;
          }
          *out = NULL;
          return RC_SUCCESS;
        }
        case ELMC_JSON_DECODER_INDEX: {
          if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
            return elmc_json_decode_miss(out, error_out, "Invalid index decoder", node);
          }
          if (!node || node->kind != ELMC_JSON_ARRAY) {
            return elmc_json_expecting(out, error_out, "an ARRAY", node);
          }
          ElmcTuple2 *index_tuple = (ElmcTuple2 *)payload->payload;
          int idx = (int)elmc_as_int(index_tuple->first);
          ElmcJsonValue *child = elmc_json_array_get(node, idx);
          if (!child) {
            char msg[160];
            snprintf(msg, sizeof(msg),
                     "Expecting a LONGER array. Need index %d but only see %d entries",
                     idx, elmc_json_array_length(node));
            return elmc_json_failure_msg(out, error_out, msg, node);
          }
          ElmcValue *decoded = NULL;
          RC rc = elmc_json_decode_with_value(&decoded, index_tuple->second, child, error_out);
          if (rc != RC_SUCCESS) return rc;
          if (decoded) {
            *out = decoded;
            return RC_SUCCESS;
          }
          if (error_out && *error_out) {
            ElmcValue *wrapped = NULL;
            rc = elmc_json_wrap_index_error(&wrapped, idx, *error_out);
            if (rc != RC_SUCCESS) return rc;
            elmc_release(*error_out);
            *error_out = wrapped;
          }
          *out = NULL;
          return RC_SUCCESS;
        }
        case ELMC_JSON_DECODER_LIST:
        case ELMC_JSON_DECODER_ARRAY:
          if (!payload || !node || node->kind != ELMC_JSON_ARRAY) {
            return elmc_json_expecting(
                out, error_out, tag == ELMC_JSON_DECODER_LIST ? "a LIST" : "an ARRAY", node);
          } else {
            ElmcValue *rev = elmc_list_nil();
            ElmcJsonValue *child = node->child;
            int index = 0;
            while (child) {
              ElmcValue *decoded = NULL;
              RC rc = elmc_json_decode_with_value(&decoded, payload, child, error_out);
              if (rc != RC_SUCCESS) {
                elmc_release(rev);
                return rc;
              }
              if (!decoded) {
                elmc_release(rev);
                if (error_out && *error_out) {
                  ElmcValue *wrapped = NULL;
                  rc = elmc_json_wrap_index_error(&wrapped, index, *error_out);
                  if (rc != RC_SUCCESS) return rc;
                  elmc_release(*error_out);
                  *error_out = wrapped;
                }
                *out = NULL;
                return RC_SUCCESS;
              }
              ElmcValue *next = NULL;
              rc = elmc_list_cons(&next, decoded, rev);
              elmc_release(decoded);
              elmc_release(rev);
              if (rc != RC_SUCCESS) return rc;
              rev = next;
              child = child->next;
              index++;
            }
            RC rc = elmc_list_reverse_into(out, rev);
            elmc_release(rev);
            return rc;
          }
        case ELMC_JSON_DECODER_NULL:
          if (node && node->kind == ELMC_JSON_NULL) {
            *out = payload ? elmc_retain(payload) : elmc_list_nil();
            return RC_SUCCESS;
          }
          return elmc_json_expecting(out, error_out, "null", node);
        case ELMC_JSON_DECODER_MAYBE: {
          ElmcValue *decoded = NULL;
          RC rc = elmc_json_decode_with_value(&decoded, payload, node, NULL);
          if (rc != RC_SUCCESS) return rc;
          if (!decoded) {
            *out = elmc_maybe_nothing();
            return RC_SUCCESS;
          }
          rc = elmc_maybe_just(out, decoded);
          elmc_release(decoded);
          return rc;
        }
        case ELMC_JSON_DECODER_NULLABLE: {
          /* Official: oneOf [null Nothing, map Just decoder] */
          if (node && node->kind == ELMC_JSON_NULL) {
            *out = elmc_maybe_nothing();
            return RC_SUCCESS;
          }
          ElmcValue *decoded = NULL;
          RC rc = elmc_json_decode_with_value(&decoded, payload, node, error_out);
          if (rc != RC_SUCCESS) return rc;
          if (!decoded) {
            *out = NULL;
            return RC_SUCCESS;
          }
          rc = elmc_maybe_just(out, decoded);
          elmc_release(decoded);
          return rc;
        }
        case ELMC_JSON_DECODER_ONE_OF:
          if (!payload || payload->tag != ELMC_TAG_LIST) {
            return elmc_json_decode_miss(out, error_out, "Invalid oneOf decoder", node);
          } else {
            ElmcValue *errors = elmc_list_nil();
            ElmcValue *cursor = payload;
            while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
              ElmcCons *cons = (ElmcCons *)cursor->payload;
              ElmcValue *decoded = NULL;
              ElmcValue *step_err = NULL;
              RC rc = elmc_json_decode_with_value(&decoded, cons->head, node, &step_err);
              if (rc != RC_SUCCESS) {
                elmc_release(errors);
                elmc_release(step_err);
                return rc;
              }
              if (decoded) {
                elmc_release(errors);
                elmc_release(step_err);
                *out = decoded;
                return RC_SUCCESS;
              }
              if (!step_err) {
                rc = elmc_json_make_failure(&step_err, "Decode failed", node);
                if (rc != RC_SUCCESS) {
                  elmc_release(errors);
                  return rc;
                }
              }
              ElmcValue *next = NULL;
              rc = elmc_list_cons(&next, step_err, errors);
              elmc_release(step_err);
              elmc_release(errors);
              if (rc != RC_SUCCESS) return rc;
              errors = next;
              cursor = cons->tail;
            }
            ElmcValue *fwd = NULL;
            RC rc = elmc_list_reverse_into(&fwd, errors);
            elmc_release(errors);
            if (rc != RC_SUCCESS) return rc;
            ElmcValue *one = NULL;
            rc = elmc_json_make_one_of(&one, fwd);
            elmc_release(fwd);
            if (rc != RC_SUCCESS) return rc;
            return elmc_json_take_error(out, error_out, one);
          }
        case ELMC_JSON_DECODER_SUCCEED:
          *out = payload ? elmc_retain(payload) : elmc_list_nil();
          return RC_SUCCESS;
        case ELMC_JSON_DECODER_FAIL: {
          const char *msg =
            (payload && payload->tag == ELMC_TAG_STRING && payload->payload)
              ? (const char *)payload->payload
              : "";
          return elmc_json_failure_msg(out, error_out, msg, node);
        }
        case ELMC_JSON_DECODER_MAP:
          return elmc_json_decode_map_with_value(out, payload, node, error_out);
        case ELMC_JSON_DECODER_MAP2:
          return elmc_json_decode_map2_with_value(out, payload, node, error_out);
        case ELMC_JSON_DECODER_MAP7:
          return elmc_json_decode_map7_with_value(out, payload, node, error_out);
        case ELMC_JSON_DECODER_KEY_VALUE_PAIRS:
          if (!payload) {
            return elmc_json_decode_miss(out, error_out, "Invalid keyValuePairs decoder", node);
          }
          return elmc_json_decode_key_value_pairs_with_value(out, payload, node, error_out);
        case ELMC_JSON_DECODER_DICT:
          if (!payload) {
            return elmc_json_decode_miss(out, error_out, "Invalid dict decoder", node);
          } else {
            ElmcValue *pairs = NULL;
            RC rc = elmc_json_decode_key_value_pairs_with_value(&pairs, payload, node, error_out);
            if (rc != RC_SUCCESS) return rc;
            if (!pairs) {
              *out = NULL;
              return RC_SUCCESS;
            }
            rc = elmc_dict_from_list(out, pairs);
            elmc_release(pairs);
            return rc;
          }
        case ELMC_JSON_DECODER_AND_THEN:
          if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
            return elmc_json_decode_miss(out, error_out, "Invalid andThen decoder", node);
          } else {
            ElmcTuple2 *and_then_tuple = (ElmcTuple2 *)payload->payload;
            ElmcValue *step = NULL;
            RC rc = elmc_json_decode_with_value(&step, and_then_tuple->second, node, error_out);
            if (rc != RC_SUCCESS) return rc;
            if (!step) {
              *out = NULL;
              return RC_SUCCESS;
            }
            ElmcValue *args[] = { step };
            ElmcValue *next_decoder = elmc_closure_call(and_then_tuple->first, args, 1);
            elmc_release(step);
            if (!next_decoder) {
              return elmc_json_decode_miss(out, error_out, "Failed to resolve andThen decoder", node);
            }
            rc = elmc_json_decode_with_value(out, next_decoder, node, error_out);
            elmc_release(next_decoder);
            return rc;
          }
        default:
          return elmc_json_decode_miss(out, error_out, "Unsupported decoder", node);
      }
    }

    RC elmc_json_decode_value(ElmcValue **out, ElmcValue *decoder, ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_STRING || value->payload == NULL) {
        ElmcValue *err = NULL;
        RC rc = elmc_json_make_failure_raw_string(&err, "Expected JSON string value", "");
        if (rc != RC_SUCCESS) return rc;
        rc = elmc_result_err(out, err);
        elmc_release(err);
        return rc;
      }
      const char *raw = (const char *)value->payload;
      const char *parse_error = "Invalid JSON";
      ElmcJsonValue *parsed = elmc_json_parse_document(raw, &parse_error);
      if (!parsed) {
        char msg[320];
        snprintf(msg, sizeof(msg), "This is not valid JSON! %s",
                 parse_error ? parse_error : "Invalid JSON");
        ElmcValue *err = NULL;
        RC rc = elmc_json_make_failure_raw_string(&err, msg, raw);
        if (rc != RC_SUCCESS) return rc;
        rc = elmc_result_err(out, err);
        elmc_release(err);
        return rc;
      }
      ElmcValue *decode_error = NULL;
      ElmcValue *decoded = NULL;
      RC rc = elmc_json_decode_with_value(&decoded, decoder, parsed, &decode_error);
      if (rc != RC_SUCCESS) {
        elmc_json_free_value(parsed);
        elmc_release(decode_error);
        return rc;
      }
      if (!decoded) {
        if (!decode_error) {
          rc = elmc_json_make_failure(&decode_error, "Decode failed", parsed);
        }
        elmc_json_free_value(parsed);
        if (rc != RC_SUCCESS) {
          elmc_release(decode_error);
          return rc;
        }
        rc = elmc_result_err(out, decode_error);
        elmc_release(decode_error);
        return rc;
      }
      elmc_json_free_value(parsed);
      elmc_release(decode_error);
      rc = elmc_result_ok(out, decoded);
      elmc_release(decoded);
      return rc;
    }

    RC elmc_json_decode_string(ElmcValue **out, ElmcValue *decoder, ElmcValue *s) {
      return elmc_json_decode_value(out, decoder, s);
    }

    RC elmc_json_decode_string_decoder(ElmcValue **out) {
      return elmc_new_int(out, ELMC_JSON_DECODER_STRING);
    }

    RC elmc_json_decode_int_decoder(ElmcValue **out) {
      return elmc_new_int(out, ELMC_JSON_DECODER_INT);
    }

    #if ELMC_JSON_FLOAT_NUMBERS
    RC elmc_json_decode_float_decoder(ElmcValue **out) {
      return elmc_new_int(out, ELMC_JSON_DECODER_FLOAT);
    }
    #endif

    RC elmc_json_decode_bool_decoder(ElmcValue **out) {
      return elmc_new_int(out, ELMC_JSON_DECODER_BOOL);
    }

    RC elmc_json_decode_null(ElmcValue **out, ElmcValue *default_val) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_NULL, default_val);
    }

    RC elmc_json_decode_nullable(ElmcValue **out, ElmcValue *decoder) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_NULLABLE, decoder);
    }

    RC elmc_json_decode_list(ElmcValue **out, ElmcValue *decoder) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_LIST, decoder);
    }

    RC elmc_json_decode_array(ElmcValue **out, ElmcValue *decoder) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_ARRAY, decoder);
    }

    RC elmc_json_decode_field(ElmcValue **out, ElmcValue *name, ElmcValue *decoder) {
      ElmcValue *payload = NULL;
      RC rc = elmc_tuple2(&payload, name, decoder);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_FIELD, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_at(ElmcValue **out, ElmcValue *path, ElmcValue *decoder) {
      if (!path) {
        *out = elmc_retain(decoder);
        return RC_SUCCESS;
      }
      ElmcValue *reversed = NULL;
      RC rc = elmc_list_reverse_into(&reversed, path);
      if (rc != RC_SUCCESS) return rc;
      ElmcValue *current = elmc_retain(decoder);
      ElmcValue *cursor = reversed;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *next = NULL;
        rc = elmc_json_decode_field(&next, node->head, current);
        elmc_release(current);
        if (rc != RC_SUCCESS) {
          elmc_release(reversed);
          return rc;
        }
        current = next;
        cursor = node->tail;
      }
      elmc_release(reversed);
      *out = current;
      return RC_SUCCESS;
    }

    RC elmc_json_decode_index(ElmcValue **out, ElmcValue *idx, ElmcValue *decoder) {
      ElmcValue *payload = NULL;
      RC rc = elmc_tuple2(&payload, idx, decoder);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_INDEX, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_map(ElmcValue **out, ElmcValue *f, ElmcValue *decoder) {
      ElmcValue *payload = NULL;
      RC rc = elmc_tuple2(&payload, f, decoder);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_MAP, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_map2(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2) {
      ElmcValue *pair = NULL;
      RC rc = elmc_tuple2(&pair, d1, d2);
      if (rc != RC_SUCCESS) return rc;
      ElmcValue *payload = NULL;
      rc = elmc_tuple2(&payload, f, pair);
      elmc_release(pair);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_MAP2, payload);
      elmc_release(payload);
      return rc;
    }

    static RC elmc_json_decode_map_build_payload(ElmcValue **out, ElmcValue *f, ElmcValue **decoders, int count) {
      ElmcValue *tail = NULL;
      int i;

      if (!f || count < 2 || count > 8) return RC_ERR_INVALID_ARG;

      RC rc = elmc_tuple2(&tail, decoders[count - 2], decoders[count - 1]);
      if (rc != RC_SUCCESS) return rc;

      for (i = count - 3; i >= 0; i--) {
        ElmcValue *next = NULL;
        rc = elmc_tuple2(&next, decoders[i], tail);
        elmc_release(tail);
        if (rc != RC_SUCCESS) return rc;
        tail = next;
      }

      rc = elmc_tuple2(out, f, tail);
      elmc_release(tail);
      return rc;
    }

    RC elmc_json_decode_map3(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3) {
      ElmcValue *decoders[] = {d1, d2, d3};
      ElmcValue *payload = NULL;
      RC rc = elmc_json_decode_map_build_payload(&payload, f, decoders, 3);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_MAP7, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_map4(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4) {
      ElmcValue *decoders[] = {d1, d2, d3, d4};
      ElmcValue *payload = NULL;
      RC rc = elmc_json_decode_map_build_payload(&payload, f, decoders, 4);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_MAP7, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_map5(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5) {
      ElmcValue *decoders[] = {d1, d2, d3, d4, d5};
      ElmcValue *payload = NULL;
      RC rc = elmc_json_decode_map_build_payload(&payload, f, decoders, 5);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_MAP7, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_map6(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6) {
      ElmcValue *decoders[] = {d1, d2, d3, d4, d5, d6};
      ElmcValue *payload = NULL;
      RC rc = elmc_json_decode_map_build_payload(&payload, f, decoders, 6);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_MAP7, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_map7(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6, ElmcValue *d7) {
      ElmcValue *decoders[] = {d1, d2, d3, d4, d5, d6, d7};
      ElmcValue *payload = NULL;
      RC rc = elmc_json_decode_map_build_payload(&payload, f, decoders, 7);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_MAP7, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_map8(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6, ElmcValue *d7, ElmcValue *d8) {
      ElmcValue *decoders[] = {d1, d2, d3, d4, d5, d6, d7, d8};
      ElmcValue *payload = NULL;
      RC rc = elmc_json_decode_map_build_payload(&payload, f, decoders, 8);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_MAP7, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_succeed(ElmcValue **out, ElmcValue *value) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_SUCCEED, value);
    }

    RC elmc_json_decode_fail(ElmcValue **out, ElmcValue *msg) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_FAIL, msg);
    }

    RC elmc_json_decode_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *decoder) {
      ElmcValue *payload = NULL;
      RC rc = elmc_tuple2(&payload, f, decoder);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_AND_THEN, payload);
      elmc_release(payload);
      return rc;
    }

    RC elmc_json_decode_one_of(ElmcValue **out, ElmcValue *decoders) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_ONE_OF, decoders);
    }

    RC elmc_json_decode_maybe(ElmcValue **out, ElmcValue *decoder) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_MAYBE, decoder);
    }

    RC elmc_json_decode_lazy(ElmcValue **out, ElmcValue *thunk) {
      if (!thunk || thunk->tag != ELMC_TAG_CLOSURE) {
        return elmc_new_int(out, 0);
      }
      ElmcValue *forced = NULL;
      RC rc = elmc_closure_call_rc(&forced, thunk, NULL, 0);
      if (rc != RC_SUCCESS) {
        elmc_release(forced);
        return rc;
      }
      if (forced) {
        *out = forced;
        return RC_SUCCESS;
      }
      return elmc_new_int(out, 0);
    }

    RC elmc_json_decode_value_decoder(ElmcValue **out) {
      return elmc_new_int(out, ELMC_JSON_DECODER_VALUE);
    }

    /* Official elm/json `errorToStringHelp`. Context is a stack of
       `.field` / `['x']` / `[i]` fragments joined newest-first. */
    static int elmc_json_error_is_simple_field(const char *name) {
      if (!name || !name[0]) return 0;
      unsigned char first = (unsigned char)name[0];
      if (!((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z'))) return 0;
      const char *p;
      for (p = name + 1; *p; p++) {
        unsigned char ch = (unsigned char)*p;
        if (!((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
              (ch >= '0' && ch <= '9'))) {
          return 0;
        }
      }
      return 1;
    }

    static const char *elmc_json_error_ctor_short(ElmcValue *err) {
      if (!err || err->tag != ELMC_TAG_TUPLE2 || !err->payload) return NULL;
      ElmcTuple2 *pair = (ElmcTuple2 *)err->payload;
      const char *name = elmc_debug_union_ctor_name(elmc_as_int(pair->first));
      if (!name) return NULL;
      const char *dot = strrchr(name, '.');
      return dot ? dot + 1 : name;
    }

    static int elmc_json_error_named(const char *name, const char *want) {
      return name && want && strcmp(name, want) == 0;
    }

    static int elmc_json_error_looks_nested(ElmcValue *value) {
      if (!value) return 0;
      if (value->tag == ELMC_TAG_LIST) return 1;
      if (value->tag == ELMC_TAG_TUPLE2 && value->payload) {
        ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
        return pair->first && pair->first->tag == ELMC_TAG_INT;
      }
      return 0;
    }

    /* Official elm/json Error shapes when the debug ctor table is missing or
       shares small tag ints with app unions. */
    static const char *elmc_json_error_kind(ElmcValue *err) {
      const char *named = elmc_json_error_ctor_short(err);
      if (elmc_json_error_named(named, "Field") || elmc_json_error_named(named, "Index") ||
          elmc_json_error_named(named, "OneOf") || elmc_json_error_named(named, "Failure")) {
        return named;
      }
      if (!err || err->tag != ELMC_TAG_TUPLE2 || !err->payload) return named;
      ElmcValue *payload = ((ElmcTuple2 *)err->payload)->second;
      if (payload && payload->tag == ELMC_TAG_LIST) return "OneOf";
      if (payload && payload->tag == ELMC_TAG_TUPLE2 && payload->payload) {
        ElmcTuple2 *inner = (ElmcTuple2 *)payload->payload;
        if (inner->first && inner->first->tag == ELMC_TAG_STRING &&
            elmc_json_error_looks_nested(inner->second)) {
          return "Field";
        }
        if (inner->first && inner->first->tag == ELMC_TAG_INT &&
            elmc_json_error_looks_nested(inner->second)) {
          return "Index";
        }
        if (inner->first && inner->first->tag == ELMC_TAG_STRING) return "Failure";
      }
      if (payload && payload->tag == ELMC_TAG_STRING) return "Failure";
      return named;
    }

    static int elmc_json_error_indent_cstr(ElmcJsonBuffer *buf, const char *src) {
      const char *p = src ? src : "";
      while (*p) {
        if (*p == '\n') {
          if (!elmc_json_buf_append_cstr(buf, "\n    ")) return 0;
          p++;
        } else if (!elmc_json_buf_append_char(buf, *p++)) {
          return 0;
        }
      }
      return 1;
    }

    static RC elmc_json_error_to_string_help(ElmcValue **out, ElmcValue *err, const char *context);

    static RC elmc_json_error_one_of_help(ElmcValue **out, ElmcValue *errors, const char *context) {
      ElmcValue *items[32];
      int n = 0;
      ElmcValue *cursor = errors;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload && n < 32) {
        ElmcCons *cons = (ElmcCons *)cursor->payload;
        items[n++] = cons->head;
        cursor = cons->tail;
      }
      if (n == 0) {
        char buf[256];
        if (!context || !context[0]) {
          snprintf(buf, sizeof(buf), "Ran into a Json.Decode.oneOf with no possibilities!");
        } else {
          snprintf(buf, sizeof(buf),
                   "Ran into a Json.Decode.oneOf with no possibilities at json%s", context);
        }
        return elmc_new_string(out, buf);
      }
      if (n == 1) {
        return elmc_json_error_to_string_help(out, items[0], context);
      }
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!context || !context[0]) {
        if (!elmc_json_buf_append_cstr(&buf, "Json.Decode.oneOf")) {
          elmc_json_buf_free(&buf);
          return RC_ERR_OUT_OF_MEMORY;
        }
      } else {
        if (!elmc_json_buf_append_cstr(&buf, "The Json.Decode.oneOf at json") ||
            !elmc_json_buf_append_cstr(&buf, context)) {
          elmc_json_buf_free(&buf);
          return RC_ERR_OUT_OF_MEMORY;
        }
      }
      char intro_tail[64];
      snprintf(intro_tail, sizeof(intro_tail), " failed in the following %d ways:", n);
      if (!elmc_json_buf_append_cstr(&buf, intro_tail)) {
        elmc_json_buf_free(&buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      int i;
      for (i = 0; i < n; i++) {
        ElmcValue *inner = NULL;
        RC rc = elmc_json_error_to_string_help(&inner, items[i], "");
        if (rc != RC_SUCCESS) {
          elmc_json_buf_free(&buf);
          return rc;
        }
        const char *text =
          (inner && inner->tag == ELMC_TAG_STRING && inner->payload)
            ? (const char *)inner->payload
            : "";
        char head[32];
        snprintf(head, sizeof(head), "\n\n\n\n(%d) ", i + 1);
        int ok = elmc_json_buf_append_cstr(&buf, head) && elmc_json_error_indent_cstr(&buf, text);
        elmc_release(inner);
        if (!ok) {
          elmc_json_buf_free(&buf);
          return RC_ERR_OUT_OF_MEMORY;
        }
      }
      return elmc_json_buf_to_string(out, &buf);
    }

    static RC elmc_json_error_to_string_help(
        ElmcValue **out,
        ElmcValue *err,
        const char *context) {
      if (err && err->tag == ELMC_TAG_STRING && err->payload) {
        *out = elmc_retain(err);
        return RC_SUCCESS;
      }
      const char *ctor = elmc_json_error_kind(err);
      if (ctor && err && err->tag == ELMC_TAG_TUPLE2 && err->payload) {
        ElmcTuple2 *pair = (ElmcTuple2 *)err->payload;
        ElmcValue *payload = pair->second;
        if (strcmp(ctor, "Field") == 0 && payload && payload->tag == ELMC_TAG_TUPLE2 &&
            payload->payload) {
          ElmcTuple2 *field_pair = (ElmcTuple2 *)payload->payload;
          const char *name =
            (field_pair->first && field_pair->first->tag == ELMC_TAG_STRING &&
             field_pair->first->payload)
              ? (const char *)field_pair->first->payload
              : "";
          char next[256];
          if (elmc_json_error_is_simple_field(name)) {
            snprintf(next, sizeof(next), "%s.%s", context ? context : "", name);
          } else {
            snprintf(next, sizeof(next), "%s['%s']", context ? context : "", name);
          }
          return elmc_json_error_to_string_help(out, field_pair->second, next);
        }
        if (strcmp(ctor, "Index") == 0 && payload && payload->tag == ELMC_TAG_TUPLE2 &&
            payload->payload) {
          ElmcTuple2 *index_pair = (ElmcTuple2 *)payload->payload;
          char next[256];
          snprintf(next, sizeof(next), "%s[%lld]", context ? context : "",
                   (long long)elmc_as_int(index_pair->first));
          return elmc_json_error_to_string_help(out, index_pair->second, next);
        }
        if (strcmp(ctor, "OneOf") == 0) {
          return elmc_json_error_one_of_help(out, payload, context);
        }
        if (strcmp(ctor, "Failure") == 0) {
          const char *msg = "Json.Decode.Error";
          const char *json_text = "null";
          if (payload && payload->tag == ELMC_TAG_TUPLE2 && payload->payload) {
            ElmcTuple2 *fail_pair = (ElmcTuple2 *)payload->payload;
            if (fail_pair->first && fail_pair->first->tag == ELMC_TAG_STRING &&
                fail_pair->first->payload) {
              msg = (const char *)fail_pair->first->payload;
            }
            if (fail_pair->second && fail_pair->second->tag == ELMC_TAG_STRING &&
                fail_pair->second->payload) {
              json_text = (const char *)fail_pair->second->payload;
            }
          } else if (payload && payload->tag == ELMC_TAG_STRING && payload->payload) {
            msg = (const char *)payload->payload;
          }
          /* Official: introduction ++ indent (Encode.encode 4 json) ++ "\n\n" ++ msg */
          ElmcJsonBuffer buf;
          elmc_json_buf_init(&buf);
          int ok;
          if (!context || !context[0]) {
            ok = elmc_json_buf_append_cstr(&buf, "Problem with the given value:\n\n");
          } else {
            ok = elmc_json_buf_append_cstr(&buf, "Problem with the value at json") &&
                 elmc_json_buf_append_cstr(&buf, context) &&
                 elmc_json_buf_append_cstr(&buf, ":\n\n    ");
          }
          ok = ok && elmc_json_error_indent_cstr(&buf, json_text) &&
               elmc_json_buf_append_cstr(&buf, "\n\n") &&
               elmc_json_buf_append_cstr(&buf, msg);
          if (!ok) {
            elmc_json_buf_free(&buf);
            return RC_ERR_OUT_OF_MEMORY;
          }
          return elmc_json_buf_to_string(out, &buf);
        }
      }
      return elmc_new_string(out, "Json.Decode.Error");
    }

    RC elmc_json_decode_error_to_string(ElmcValue **out, ElmcValue *err) {
      return elmc_json_error_to_string_help(out, err, "");
    }

    RC elmc_json_decode_key_value_pairs(ElmcValue **out, ElmcValue *decoder) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_KEY_VALUE_PAIRS, decoder);
    }

    RC elmc_json_decode_dict(ElmcValue **out, ElmcValue *decoder) {
      return elmc_json_decoder_wrap(out, ELMC_JSON_DECODER_DICT, decoder);
    }

    /* ================================================================
       Standard Library – Json.Encode
       ================================================================ */

    static int elmc_json_encoded_to_buffer(ElmcValue *value, ElmcJsonBuffer *buf) {
      if (!value) return elmc_json_buf_append_cstr(buf, "null");
      if (value->tag == ELMC_TAG_STRING && value->payload != NULL) {
        const char *raw = (const char *)value->payload;
        const char *parse_error = NULL;
        ElmcJsonValue *parsed = elmc_json_parse_document(raw, &parse_error);
        if (parsed) {
          int ok = elmc_json_encode_value_to_buffer(parsed, buf);
          elmc_json_free_value(parsed);
          return ok;
        }
        return elmc_json_encode_string_to_buffer(raw, buf);
      }
      if (value->tag == ELMC_TAG_INT) {
        char number[32];
        snprintf(number, sizeof(number), "%lld", (long long)elmc_as_int(value));
        return elmc_json_buf_append_cstr(buf, number);
      }
      #if ELMC_JSON_FLOAT_NUMBERS
      if (value->tag == ELMC_TAG_FLOAT) {
        char number[48];
        snprintf(number, sizeof(number), "%.17g", elmc_as_float(value));
        return elmc_json_buf_append_cstr(buf, number);
      }
      #endif
      if (value->tag == ELMC_TAG_BOOL) return elmc_json_buf_append_cstr(buf, elmc_as_int(value) ? "true" : "false");
      if (value->tag == ELMC_TAG_LIST) {
        if (!elmc_json_buf_append_char(buf, '[')) return 0;
        ElmcValue *cursor = value;
        int first = 1;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (!first && !elmc_json_buf_append_char(buf, ',')) return 0;
          if (!elmc_json_encoded_to_buffer(node->head, buf)) return 0;
          first = 0;
          cursor = node->tail;
        }
        return elmc_json_buf_append_char(buf, ']');
      }
      return elmc_json_buf_append_cstr(buf, "null");
    }

    RC elmc_json_encode_string(ElmcValue **out, ElmcValue *s) {
      const char *raw = (s && s->tag == ELMC_TAG_STRING && s->payload) ? (const char *)s->payload : "";
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_encode_string_to_buffer(raw, &buf)) {
        elmc_json_buf_free(&buf);
        return elmc_new_string(out, "\"\"");
      }
      return elmc_json_buf_to_string(out, &buf);
    }

    RC elmc_json_encode_int(ElmcValue **out, ElmcValue *n) {
      return elmc_string_from_int(out, n);
    }

    #if ELMC_JSON_FLOAT_NUMBERS
    RC elmc_json_encode_float(ElmcValue **out, ElmcValue *f) {
      return elmc_string_from_float(out, f);
    }
    #endif

    RC elmc_json_encode_bool(ElmcValue **out, ElmcValue *b) {
      return elmc_new_string(out, elmc_as_int(b) ? "true" : "false");
    }

    RC elmc_json_encode_null(ElmcValue **out) {
      return elmc_new_string(out, "null");
    }

    RC elmc_json_encode_list(ElmcValue **out, ElmcValue *f, ElmcValue *items) {
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_buf_append_char(&buf, '[')) {
        elmc_json_buf_free(&buf);
        return elmc_new_string(out, "[]");
      }
      ElmcValue *owned_items = NULL;
      ElmcValue *cursor = items;
      if (cursor && cursor->tag != ELMC_TAG_LIST) {
        if (elmc_list_materialize_cons(&owned_items, cursor) != RC_SUCCESS) {
          elmc_json_buf_free(&buf);
          return elmc_new_string(out, "[]");
        }
        cursor = owned_items;
      }
      int first = 1;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[] = { node->head };
        ElmcValue *mapped = NULL;
        if (elmc_closure_call_rc(&mapped, f, args, 1) != RC_SUCCESS) {
          elmc_release(mapped);
          if (owned_items) elmc_release(owned_items);
          elmc_json_buf_free(&buf);
          return RC_ERR_OUT_OF_MEMORY;
        }
        if (!first) elmc_json_buf_append_char(&buf, ',');
        elmc_json_encoded_to_buffer(mapped, &buf);
        first = 0;
        if (mapped) elmc_release(mapped);
        cursor = node->tail;
      }
      if (owned_items) elmc_release(owned_items);
      elmc_json_buf_append_char(&buf, ']');
      return elmc_json_buf_to_string(out, &buf);
    }

    RC elmc_json_encode_array(ElmcValue **out, ElmcValue *f, ElmcValue *items) {
      return elmc_json_encode_list(out, f, items);
    }

    RC elmc_json_encode_set(ElmcValue **out, ElmcValue *f, ElmcValue *items) {
      return elmc_json_encode_list(out, f, items);
    }

    RC elmc_json_encode_object(ElmcValue **out, ElmcValue *pairs) {
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_buf_append_char(&buf, '{')) {
        elmc_json_buf_free(&buf);
        return elmc_new_string(out, "{}");
      }
      ElmcValue *cursor = pairs;
      int first = 1;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *entry = node->head;
        if (entry && entry->tag == ELMC_TAG_TUPLE2 && entry->payload != NULL) {
          ElmcTuple2 *tuple = (ElmcTuple2 *)entry->payload;
          const char *key = (tuple->first && tuple->first->tag == ELMC_TAG_STRING && tuple->first->payload)
                              ? (const char *)tuple->first->payload
                              : NULL;
          if (key) {
            if (!first) elmc_json_buf_append_char(&buf, ',');
            elmc_json_encode_string_to_buffer(key, &buf);
            elmc_json_buf_append_char(&buf, ':');
            elmc_json_encoded_to_buffer(tuple->second, &buf);
            first = 0;
          }
        }
        cursor = node->tail;
      }
      elmc_json_buf_append_char(&buf, '}');
      return elmc_json_buf_to_string(out, &buf);
    }

    RC elmc_json_encode_add_field(ElmcValue **out, ElmcValue *key, ElmcValue *value, ElmcValue *obj) {
      ElmcValue *pair = NULL;
      RC rc = elmc_tuple2(&pair, key, value);
      if (rc != RC_SUCCESS) return rc;
      rc = elmc_list_cons(out, pair, obj);
      elmc_release(pair);
      return rc;
    }

    RC elmc_json_encode_add_entry(ElmcValue **out, ElmcValue *func, ElmcValue *value, ElmcValue *arr) {
      ElmcValue *args[] = { value };
      ElmcValue *encoded = NULL;
      RC rc = elmc_closure_call_rc(&encoded, func, args, 1);
      if (rc != RC_SUCCESS) {
        elmc_release(encoded);
        return rc;
      }
      rc = elmc_list_cons(out, encoded, arr);
      elmc_release(encoded);
      return rc;
    }

    RC elmc_json_encode_dict(ElmcValue **out, ElmcValue *key_fn, ElmcValue *val_fn, ElmcValue *dict) {
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_buf_append_char(&buf, '{')) {
        elmc_json_buf_free(&buf);
        return elmc_new_string(out, "{}");
      }
      ElmcValue *cursor = dict;
      int first = 1;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *entry = node->head;
        if (entry && entry->tag == ELMC_TAG_TUPLE2 && entry->payload != NULL) {
          ElmcTuple2 *tuple = (ElmcTuple2 *)entry->payload;
          ElmcValue *key_args[] = { tuple->first };
          ElmcValue *val_args[] = { tuple->second };
          ElmcValue *key_text = NULL;
          ElmcValue *val_enc = NULL;
          if (elmc_closure_call_rc(&key_text, key_fn, key_args, 1) != RC_SUCCESS) {
            elmc_release(key_text);
            elmc_json_buf_free(&buf);
            return RC_ERR_OUT_OF_MEMORY;
          }
          if (elmc_closure_call_rc(&val_enc, val_fn, val_args, 1) != RC_SUCCESS) {
            elmc_release(key_text);
            elmc_release(val_enc);
            elmc_json_buf_free(&buf);
            return RC_ERR_OUT_OF_MEMORY;
          }
          const char *key = (key_text && key_text->tag == ELMC_TAG_STRING && key_text->payload)
                              ? (const char *)key_text->payload
                              : NULL;
          if (key) {
            if (!first) elmc_json_buf_append_char(&buf, ',');
            elmc_json_encode_string_to_buffer(key, &buf);
            elmc_json_buf_append_char(&buf, ':');
            elmc_json_encoded_to_buffer(val_enc, &buf);
            first = 0;
          }
          elmc_release(key_text);
          elmc_release(val_enc);
        }
        cursor = node->tail;
      }
      elmc_json_buf_append_char(&buf, '}');
      return elmc_json_buf_to_string(out, &buf);
    }

    RC elmc_json_encode_encode(ElmcValue **out, ElmcValue *indent, ElmcValue *value) {
      int spaces = (int)elmc_as_int(indent);
      if (spaces <= 0) {
        if (value && value->tag == ELMC_TAG_STRING && value->payload) {
          *out = elmc_retain(value);
          return RC_SUCCESS;
        }
      }
      if (value && value->tag == ELMC_TAG_STRING && value->payload) {
        const char *raw = (const char *)value->payload;
        const char *parse_error = NULL;
        ElmcJsonValue *parsed = elmc_json_parse_document(raw, &parse_error);
        if (parsed) {
          ElmcJsonBuffer buf;
          elmc_json_buf_init(&buf);
          int ok = spaces > 0
            ? elmc_json_pretty_value_to_buffer(parsed, &buf, spaces, 0)
            : elmc_json_encode_value_to_buffer(parsed, &buf);
          elmc_json_free_value(parsed);
          if (!ok) {
            elmc_json_buf_free(&buf);
            return elmc_new_string(out, "null");
          }
          return elmc_json_buf_to_string(out, &buf);
        }
      }
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_encoded_to_buffer(value, &buf)) {
        elmc_json_buf_free(&buf);
        return elmc_new_string(out, "null");
      }
      return elmc_json_buf_to_string(out, &buf);
    }
    """
  end
end
