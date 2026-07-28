defmodule Elmc.Runtime.WebPlatform do
  @moduledoc false

  @doc "RC declarations for web/platform helpers (host provides real WASM imports)."
  def runtime_header_declarations do
    """
    RC elmc_string_chop_end(ElmcValue **out, ElmcValue *str, ElmcValue *suffix);
    RC elmc_string_chop_start(ElmcValue **out, ElmcValue *str, ElmcValue *prefix);
    RC elmc_string_chop_forward_slashes(ElmcValue **out, ElmcValue *str);
    RC elmc_url_percent_encode(ElmcValue **out, ElmcValue *segment);
    RC elmc_url_percent_decode(ElmcValue **out, ElmcValue *segment);
    RC elmc_url_from_string(ElmcValue **out, ElmcValue *url);
    RC elmc_http_empty_body(ElmcValue **out, ElmcValue *req);
    RC elmc_http_pair(ElmcValue **out, ElmcValue *key, ElmcValue *value);
    RC elmc_http_to_data_view(ElmcValue **out, ElmcValue *body);
    RC elmc_http_expect(ElmcValue **out, ElmcValue *to_msg, ElmcValue *decoder, ElmcValue *req);
    RC elmc_http_command(ElmcValue **out, ElmcValue *req);
    RC elmc_http_cancel(ElmcValue **out, ElmcValue *tracker);
    RC elmc_backend_task_http_get_json(ElmcValue **out, ElmcValue *url, ElmcValue *expect);
    RC elmc_backend_task_http_get(ElmcValue **out, ElmcValue *url, ElmcValue *expect);
    RC elmc_backend_task_http_get_with_options(ElmcValue **out, ElmcValue *url, ElmcValue *options, ElmcValue *expect);
    RC elmc_backend_task_http_expect_json(ElmcValue **out, ElmcValue *decoder);
    RC elmc_backend_task_http_expect_string(ElmcValue **out);
    RC elmc_backend_task_http_expect_whatever(ElmcValue **out);
    RC elmc_backend_task_http_expect_bytes(ElmcValue **out);
    RC elmc_backend_task_http_with_metadata(ElmcValue **out, ElmcValue *expect);
    RC elmc_backend_task_http_empty_body(ElmcValue **out);
    RC elmc_backend_task_http_string_body(ElmcValue **out, ElmcValue *body);
    RC elmc_backend_task_http_json_body(ElmcValue **out, ElmcValue *value);
    RC elmc_backend_task_http_bytes_body(ElmcValue **out, ElmcValue *bytes);
    RC elmc_bytes_encode_sequence(ElmcValue **out, ElmcValue *list);
    RC elmc_backend_task_http_request(ElmcValue **out, ElmcValue *req);
    RC elmc_backend_task_http_post(ElmcValue **out, ElmcValue *url, ElmcValue *body, ElmcValue *expect);
    RC elmc_file_download_task(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content);
    RC elmc_file_select(ElmcValue **out, ElmcValue *to_msg, ElmcValue *accept);
    RC elmc_file_download(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content);
    RC elmc_random_generate(ElmcValue **out, ElmcValue *to_msg, ElmcValue *generator);
    RC elmc_regex_from_string(ElmcValue **out, ElmcValue *pattern);
    RC elmc_regex_find(ElmcValue **out, ElmcValue *regex, ElmcValue *str);
    RC elmc_regex_contains(ElmcValue **out, ElmcValue *regex, ElmcValue *str);
    RC elmc_regex_replace(ElmcValue **out, ElmcValue *regex, ElmcValue *replacement, ElmcValue *str);
    RC elmc_time_here(ElmcValue **out);
    RC elmc_browser_get_viewport(ElmcValue **out);
    """
  end

  def runtime_source_impl do
    """
    static const char *elmc_web_cstr(ElmcValue *value) {
      if (value && value->tag == ELMC_TAG_STRING && value->payload) {
        return (const char *)value->payload;
      }
      return "";
    }

    static int elmc_web_ends_with(const char *str, const char *suffix) {
      size_t sl = strlen(str);
      size_t su = strlen(suffix);
      if (su == 0 || su > sl) return 0;
      return memcmp(str + (sl - su), suffix, su) == 0;
    }

    static int elmc_web_starts_with(const char *str, const char *prefix) {
      size_t pl = strlen(prefix);
      return pl == 0 || strncmp(str, prefix, pl) == 0;
    }

    RC elmc_string_chop_end(ElmcValue **out, ElmcValue *str, ElmcValue *suffix) {
      const char *s = elmc_web_cstr(str);
      const char *suf = elmc_web_cstr(suffix);
      if (suf[0] && elmc_web_ends_with(s, suf)) {
        size_t keep = strlen(s) - strlen(suf);
        char *buf = (char *)elmc_malloc(keep + 1, __func__);
        if (!buf) return RC_ERR_OUT_OF_MEMORY;
        memcpy(buf, s, keep);
        buf[keep] = '\\0';
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
        if (!allocated) {
          elmc_free(buf);
          return RC_ERR_OUT_OF_MEMORY;
        }
        *out = allocated;
        return RC_SUCCESS;
      }
      *out = str ? elmc_retain(str) : NULL;
      if (!*out) return elmc_new_string(out, "");
      return RC_SUCCESS;
    }

    RC elmc_string_chop_start(ElmcValue **out, ElmcValue *str, ElmcValue *prefix) {
      const char *s = elmc_web_cstr(str);
      const char *pre = elmc_web_cstr(prefix);
      if (pre[0] && elmc_web_starts_with(s, pre)) {
        return elmc_new_string(out, s + strlen(pre));
      }
      *out = str ? elmc_retain(str) : NULL;
      if (!*out) return elmc_new_string(out, "");
      return RC_SUCCESS;
    }

    RC elmc_string_chop_forward_slashes(ElmcValue **out, ElmcValue *str) {
      const char *s = elmc_web_cstr(str);
      size_t len = strlen(s);
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return RC_ERR_OUT_OF_MEMORY;
      size_t j = 0;
      for (size_t i = 0; i < len; i++) {
        char c = s[i] == '\\\\' ? '/' : s[i];
        if (c == '/' && j > 0 && buf[j - 1] == '/') continue;
        buf[j++] = c;
      }
      buf[j] = '\\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      *out = allocated;
      return RC_SUCCESS;
    }

    static int elmc_url_is_unreserved(unsigned char c) {
      return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
             c == '-' || c == '_' || c == '.' || c == '~';
    }

    RC elmc_url_percent_encode(ElmcValue **out, ElmcValue *segment) {
      const char *s = elmc_web_cstr(segment);
      size_t len = strlen(s);
      char *buf = (char *)elmc_malloc(len * 3 + 1, __func__);
      if (!buf) return RC_ERR_OUT_OF_MEMORY;
      size_t j = 0;
      static const char *hex = "0123456789ABCDEF";
      for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        if (elmc_url_is_unreserved(c)) {
          buf[j++] = (char)c;
        } else {
          buf[j++] = '%';
          buf[j++] = hex[c >> 4];
          buf[j++] = hex[c & 15];
        }
      }
      buf[j] = '\\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      *out = allocated;
      return RC_SUCCESS;
    }

    static int elmc_url_hex_value(char c) {
      if (c >= '0' && c <= '9') return c - '0';
      if (c >= 'A' && c <= 'F') return c - 'A' + 10;
      if (c >= 'a' && c <= 'f') return c - 'a' + 10;
      return -1;
    }

    RC elmc_url_percent_decode(ElmcValue **out, ElmcValue *segment) {
      const char *s = elmc_web_cstr(segment);
      size_t len = strlen(s);
      char *buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) return RC_ERR_OUT_OF_MEMORY;
      size_t j = 0;
      for (size_t i = 0; i < len; i++) {
        if (s[i] == '%' && i + 2 < len) {
          int hi = elmc_url_hex_value(s[i + 1]);
          int lo = elmc_url_hex_value(s[i + 2]);
          if (hi >= 0 && lo >= 0) {
            buf[j++] = (char)((hi << 4) | lo);
            i += 2;
            continue;
          }
        }
        buf[j++] = s[i] == '+' ? ' ' : s[i];
      }
      buf[j] = '\\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      if (!allocated) {
        elmc_free(buf);
        return RC_ERR_OUT_OF_MEMORY;
      }
      *out = allocated;
      return RC_SUCCESS;
    }

    /* Host/WASM provides a richer Url record; C retains the input string. */
    RC elmc_url_from_string(ElmcValue **out, ElmcValue *url) {
      if (url) {
        *out = elmc_retain(url);
        return RC_SUCCESS;
      }
      return elmc_new_string(out, "");
    }

    static RC elmc_web_unsupported(ElmcValue **out) {
      *out = NULL;
      return RC_ERR_UNSUPPORTED;
    }

    RC elmc_http_empty_body(ElmcValue **out, ElmcValue *req) {
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_pair(ElmcValue **out, ElmcValue *key, ElmcValue *value) {
      (void)key;
      (void)value;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_to_data_view(ElmcValue **out, ElmcValue *body) {
      (void)body;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_expect(ElmcValue **out, ElmcValue *to_msg, ElmcValue *decoder, ElmcValue *req) {
      (void)to_msg;
      (void)decoder;
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_command(ElmcValue **out, ElmcValue *req) {
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_http_cancel(ElmcValue **out, ElmcValue *tracker) {
      (void)tracker;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_get_json(ElmcValue **out, ElmcValue *url, ElmcValue *expect) {
      (void)url;
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_get(ElmcValue **out, ElmcValue *url, ElmcValue *expect) {
      (void)url;
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_get_with_options(ElmcValue **out, ElmcValue *url, ElmcValue *options, ElmcValue *expect) {
      (void)url;
      (void)options;
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_expect_json(ElmcValue **out, ElmcValue *decoder) {
      (void)decoder;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_expect_string(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_backend_task_http_expect_whatever(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_backend_task_http_expect_bytes(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_backend_task_http_with_metadata(ElmcValue **out, ElmcValue *expect) {
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_empty_body(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_backend_task_http_string_body(ElmcValue **out, ElmcValue *body) {
      (void)body;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_json_body(ElmcValue **out, ElmcValue *value) {
      (void)value;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_bytes_body(ElmcValue **out, ElmcValue *bytes) {
      (void)bytes;
      return elmc_web_unsupported(out);
    }
    RC elmc_bytes_encode_sequence(ElmcValue **out, ElmcValue *list) {
      (void)list;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_request(ElmcValue **out, ElmcValue *req) {
      (void)req;
      return elmc_web_unsupported(out);
    }
    RC elmc_backend_task_http_post(ElmcValue **out, ElmcValue *url, ElmcValue *body, ElmcValue *expect) {
      (void)url;
      (void)body;
      (void)expect;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_download_task(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content) {
      (void)name;
      (void)mime;
      (void)content;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_select(ElmcValue **out, ElmcValue *to_msg, ElmcValue *accept) {
      (void)to_msg;
      (void)accept;
      return elmc_web_unsupported(out);
    }
    RC elmc_file_download(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content) {
      (void)name;
      (void)mime;
      (void)content;
      return elmc_web_unsupported(out);
    }
    RC elmc_random_generate(ElmcValue **out, ElmcValue *to_msg, ElmcValue *generator) {
      (void)to_msg;
      (void)generator;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_from_string(ElmcValue **out, ElmcValue *pattern) {
      (void)pattern;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_find(ElmcValue **out, ElmcValue *regex, ElmcValue *str) {
      (void)regex;
      (void)str;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_contains(ElmcValue **out, ElmcValue *regex, ElmcValue *str) {
      (void)regex;
      (void)str;
      return elmc_web_unsupported(out);
    }
    RC elmc_regex_replace(ElmcValue **out, ElmcValue *regex, ElmcValue *replacement, ElmcValue *str) {
      (void)regex;
      (void)replacement;
      (void)str;
      return elmc_web_unsupported(out);
    }
    RC elmc_time_here(ElmcValue **out) { return elmc_web_unsupported(out); }
    RC elmc_browser_get_viewport(ElmcValue **out) { return elmc_web_unsupported(out); }
    """
  end
end
