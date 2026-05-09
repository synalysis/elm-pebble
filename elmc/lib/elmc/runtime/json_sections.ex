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
    ""
  end

  @spec runtime_source_impl() :: String.t()
  def runtime_source_impl do
    ~S"""
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
      char *data = (char *)realloc(buf->data, next);
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

    static ElmcValue *elmc_json_buf_to_string(ElmcJsonBuffer *buf) {
      ElmcValue *out = elmc_new_string(buf->data ? buf->data : "");
      elmc_json_buf_free(buf);
      return out;
    }

    static ElmcJsonValue *elmc_json_new_value(ElmcJsonKind kind) {
      ElmcJsonValue *value = (ElmcJsonValue *)malloc(sizeof(ElmcJsonValue));
      if (!value) return NULL;
      value->kind = kind;
      value->bool_value = 0;
      value->int_value = 0;
      value->float_value = 0.0;
      value->string_value = NULL;
      value->key = NULL;
      value->child = NULL;
      value->next = NULL;
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
        case ELMC_JSON_FLOAT:
          snprintf(number, sizeof(number), "%.17g", value->float_value);
          return elmc_json_buf_append_cstr(buf, number);
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

    static ElmcValue *elmc_json_value_to_string(const ElmcJsonValue *value) {
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_encode_value_to_buffer(value, &buf)) {
        elmc_json_buf_free(&buf);
        return elmc_new_string("null");
      }
      return elmc_json_buf_to_string(&buf);
    }

    static ElmcValue *elmc_json_decode_with_value(ElmcValue *decoder, const ElmcJsonValue *node, const char **error_out);

    static ElmcValue *elmc_json_decode_map_with_value(ElmcValue *payload, const ElmcJsonValue *node, const char **error_out) {
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
        if (error_out) *error_out = "Invalid map decoder";
        return NULL;
      }
      ElmcTuple2 *tuple = (ElmcTuple2 *)payload->payload;
      ElmcValue *decoded = elmc_json_decode_with_value(tuple->second, node, error_out);
      if (!decoded) return NULL;
      ElmcValue *args[] = { decoded };
      ElmcValue *mapped = elmc_closure_call(tuple->first, args, 1);
      elmc_release(decoded);
      if (!mapped && error_out) *error_out = "Failed to map decoded value";
      return mapped;
    }

    static ElmcValue *elmc_json_decode_map2_with_value(ElmcValue *payload, const ElmcJsonValue *node, const char **error_out) {
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
        if (error_out) *error_out = "Invalid map2 decoder";
        return NULL;
      }
      ElmcTuple2 *outer = (ElmcTuple2 *)payload->payload;
      if (!outer->second || outer->second->tag != ELMC_TAG_TUPLE2 || outer->second->payload == NULL) {
        if (error_out) *error_out = "Invalid map2 decoder";
        return NULL;
      }
      ElmcTuple2 *inner = (ElmcTuple2 *)outer->second->payload;
      ElmcValue *v1 = elmc_json_decode_with_value(inner->first, node, error_out);
      if (!v1) return NULL;
      ElmcValue *v2 = elmc_json_decode_with_value(inner->second, node, error_out);
      if (!v2) {
        elmc_release(v1);
        return NULL;
      }
      ElmcValue *args[] = { v1, v2 };
      ElmcValue *mapped = elmc_closure_call(outer->first, args, 2);
      elmc_release(v1);
      elmc_release(v2);
      if (!mapped && error_out) *error_out = "Failed to map2 decoded value";
      return mapped;
    }

    static ElmcValue *elmc_json_decode_with_value(ElmcValue *decoder, const ElmcJsonValue *node, const char **error_out) {
      int64_t tag = elmc_json_decoder_tag(decoder);
      ElmcValue *payload = elmc_json_decoder_payload(decoder);

      switch (tag) {
        case ELMC_JSON_DECODER_STRING:
          if (!node || node->kind != ELMC_JSON_STRING) {
            if (error_out) *error_out = "Expected STRING";
            return NULL;
          }
          return elmc_new_string(node->string_value ? node->string_value : "");
        case ELMC_JSON_DECODER_INT:
          if (!node || node->kind != ELMC_JSON_INT) {
            if (error_out) *error_out = "Expected INT";
            return NULL;
          }
          return elmc_new_int(node->int_value);
        case ELMC_JSON_DECODER_FLOAT:
          if (!node || (node->kind != ELMC_JSON_INT && node->kind != ELMC_JSON_FLOAT)) {
            if (error_out) *error_out = "Expected FLOAT";
            return NULL;
          }
          return elmc_new_float(node->kind == ELMC_JSON_INT ? (double)node->int_value : node->float_value);
        case ELMC_JSON_DECODER_BOOL:
          if (!node || node->kind != ELMC_JSON_BOOL) {
            if (error_out) *error_out = "Expected BOOL";
            return NULL;
          }
          return elmc_new_bool(node->bool_value);
        case ELMC_JSON_DECODER_VALUE:
          return elmc_json_value_to_string(node);
        case ELMC_JSON_DECODER_FIELD:
          if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL || !node || node->kind != ELMC_JSON_OBJECT) {
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
            ElmcJsonValue *child = elmc_json_object_get(node, field_name);
            if (!child) {
              if (error_out) *error_out = "Missing field";
              return NULL;
            }
            return elmc_json_decode_with_value(field_tuple->second, child, error_out);
          }
        case ELMC_JSON_DECODER_INDEX:
          if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL || !node || node->kind != ELMC_JSON_ARRAY) {
            if (error_out) *error_out = "Expected ARRAY index";
            return NULL;
          } else {
            ElmcTuple2 *index_tuple = (ElmcTuple2 *)payload->payload;
            int idx = (int)elmc_as_int(index_tuple->first);
            ElmcJsonValue *child = elmc_json_array_get(node, idx);
            if (!child) {
              if (error_out) *error_out = "Index out of range";
              return NULL;
            }
            return elmc_json_decode_with_value(index_tuple->second, child, error_out);
          }
        case ELMC_JSON_DECODER_LIST:
        case ELMC_JSON_DECODER_ARRAY:
          if (!payload || !node || node->kind != ELMC_JSON_ARRAY) {
            if (error_out) *error_out = "Expected ARRAY";
            return NULL;
          } else {
            ElmcValue *rev = elmc_list_nil();
            if (!rev) {
              if (error_out) *error_out = "Out of memory";
              return NULL;
            }
            ElmcJsonValue *child = node->child;
            while (child) {
              ElmcValue *decoded = elmc_json_decode_with_value(payload, child, error_out);
              if (!decoded) {
                elmc_release(rev);
                return NULL;
              }
              ElmcValue *next = elmc_list_cons(decoded, rev);
              elmc_release(decoded);
              elmc_release(rev);
              rev = next;
              child = child->next;
            }
            ElmcValue *out = elmc_list_reverse_copy(rev);
            elmc_release(rev);
            return out;
          }
        case ELMC_JSON_DECODER_NULL:
          if (node && node->kind == ELMC_JSON_NULL) return payload ? elmc_retain(payload) : elmc_list_nil();
          if (error_out) *error_out = "Expected NULL";
          return NULL;
        case ELMC_JSON_DECODER_MAYBE: {
          ElmcValue *decoded = elmc_json_decode_with_value(payload, node, NULL);
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
              ElmcValue *decoded = elmc_json_decode_with_value(cons->head, node, NULL);
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
          return elmc_json_decode_map_with_value(payload, node, error_out);
        case ELMC_JSON_DECODER_MAP2:
          return elmc_json_decode_map2_with_value(payload, node, error_out);
        case ELMC_JSON_DECODER_AND_THEN:
          if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
            if (error_out) *error_out = "Invalid andThen decoder";
            return NULL;
          } else {
            ElmcTuple2 *and_then_tuple = (ElmcTuple2 *)payload->payload;
            ElmcValue *step = elmc_json_decode_with_value(and_then_tuple->second, node, error_out);
            if (!step) return NULL;
            ElmcValue *args[] = { step };
            ElmcValue *next_decoder = elmc_closure_call(and_then_tuple->first, args, 1);
            elmc_release(step);
            if (!next_decoder) {
              if (error_out) *error_out = "Failed to resolve andThen decoder";
              return NULL;
            }
            ElmcValue *decoded = elmc_json_decode_with_value(next_decoder, node, error_out);
            elmc_release(next_decoder);
            return decoded;
          }
        default:
          if (error_out) *error_out = "Unsupported decoder";
          return NULL;
      }
    }

    ElmcValue *elmc_json_decode_value(ElmcValue *decoder, ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_STRING || value->payload == NULL) {
        return elmc_result_err(elmc_new_string("Expected JSON string value"));
      }
      const char *raw = (const char *)value->payload;
      const char *parse_error = "Invalid JSON";
      ElmcJsonValue *parsed = elmc_json_parse_document(raw, &parse_error);
      if (!parsed) {
        return elmc_result_err(elmc_new_string(parse_error ? parse_error : "Invalid JSON"));
      }
      const char *decode_error = "Decode failed";
      ElmcValue *decoded = elmc_json_decode_with_value(decoder, parsed, &decode_error);
      elmc_json_free_value(parsed);
      if (!decoded) return elmc_result_err(elmc_new_string(decode_error ? decode_error : "Decode failed"));
      ElmcValue *ok = elmc_result_ok(decoded);
      elmc_release(decoded);
      return ok;
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
      if (value->tag == ELMC_TAG_FLOAT) {
        char number[48];
        snprintf(number, sizeof(number), "%.17g", elmc_as_float(value));
        return elmc_json_buf_append_cstr(buf, number);
      }
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

    ElmcValue *elmc_json_encode_string(ElmcValue *s) {
      const char *raw = (s && s->tag == ELMC_TAG_STRING && s->payload) ? (const char *)s->payload : "";
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_encode_string_to_buffer(raw, &buf)) {
        elmc_json_buf_free(&buf);
        return elmc_new_string("\"\"");
      }
      return elmc_json_buf_to_string(&buf);
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
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_buf_append_char(&buf, '[')) return elmc_new_string("[]");
      ElmcValue *cursor = items;
      int first = 1;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *args[] = { node->head };
        ElmcValue *mapped = elmc_closure_call(f, args, 1);
        if (!first) elmc_json_buf_append_char(&buf, ',');
        elmc_json_encoded_to_buffer(mapped, &buf);
        first = 0;
        if (mapped) elmc_release(mapped);
        cursor = node->tail;
      }
      elmc_json_buf_append_char(&buf, ']');
      return elmc_json_buf_to_string(&buf);
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
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_buf_append_char(&buf, '{')) return elmc_new_string("{}");
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
      return elmc_json_buf_to_string(&buf);
    }

    ElmcValue *elmc_json_encode_dict(ElmcValue *key_fn, ElmcValue *val_fn, ElmcValue *dict) {
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_buf_append_char(&buf, '{')) return elmc_new_string("{}");
      ElmcValue *cursor = dict;
      int first = 1;
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
            if (!first) elmc_json_buf_append_char(&buf, ',');
            elmc_json_encode_string_to_buffer(key, &buf);
            elmc_json_buf_append_char(&buf, ':');
            elmc_json_encoded_to_buffer(val_enc, &buf);
            first = 0;
          }
          if (key_text) elmc_release(key_text);
          if (val_enc) elmc_release(val_enc);
        }
        cursor = node->tail;
      }
      elmc_json_buf_append_char(&buf, '}');
      return elmc_json_buf_to_string(&buf);
    }

    ElmcValue *elmc_json_encode_encode(ElmcValue *indent, ElmcValue *value) {
      (void)indent;
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      if (!elmc_json_encoded_to_buffer(value, &buf)) {
        elmc_json_buf_free(&buf);
        return elmc_new_string("null");
      }
      return elmc_json_buf_to_string(&buf);
    }
    """
  end
end
