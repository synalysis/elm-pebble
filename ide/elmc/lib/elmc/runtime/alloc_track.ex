defmodule Elmc.Runtime.AllocTrack do
  @moduledoc """
  Host/test malloc registry for `elmc_malloc` / `elmc_free`.

  Enable with `-DELMC_ALLOC_TRACK=1` when compiling a harness (not PBW builds).
  Each successful `elmc_malloc` records pointer, size, `__func__`, and `__FILE__:__LINE__`.
  Call `elmc_alloc_track_dump_live(stderr)` or `elmc_alloc_track_check_balanced()` at checkpoints.

  Pairs with `ELMC_RC_TRACK` (`Elmc.Runtime.RcTrack`), which tracks `ElmcValue` retain/release.
  """

  @spec header_declarations() :: String.t()
  def header_declarations do
    """
    #ifndef ELMC_ALLOC_TRACK
    #define ELMC_ALLOC_TRACK 0
    #endif

    #if ELMC_ALLOC_TRACK
    #include <stdio.h>
    void elmc_alloc_track_reset(void);
    uint32_t elmc_alloc_track_live_count(void);
    int elmc_alloc_track_check_balanced(void);
    void elmc_alloc_track_dump_live(FILE *out);
    void elmc_alloc_track_dump_since(uint32_t min_id, FILE *out);
    uint32_t elmc_alloc_track_next_alloc_id(void);
    #endif

    #ifndef ELMC_ALLOC_TRACE
    #define ELMC_ALLOC_TRACE 0
    #endif

    #if ELMC_ALLOC_TRACK && !ELMC_ALLOC_TRACE
    #undef ELMC_ALLOC_TRACE
    #define ELMC_ALLOC_TRACE 1
    #endif

    #if ELMC_ALLOC_TRACK
    #define elmc_free(ptr) elmc_free_impl((ptr), __func__, __FILE__, __LINE__)
    #else
    #define elmc_free(ptr) free(ptr)
    #endif

    void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line);
    void *elmc_calloc_impl(size_t nmemb, size_t size, const char *context, const char *file, int line);
    #if ELMC_ALLOC_TRACE
    #define elmc_malloc(size, context) elmc_malloc_impl((size), (context), __FILE__, __LINE__)
    #define elmc_calloc(nmemb, size, context) elmc_calloc_impl((nmemb), (size), (context), __FILE__, __LINE__)
    #else
    #define elmc_malloc(size, context) elmc_malloc_impl((size), (context), NULL, 0)
    #define elmc_calloc(nmemb, size, context) elmc_calloc_impl((nmemb), (size), (context), NULL, 0)
    #endif
    """
  end

  @spec register_hook() :: String.t()
  def register_hook do
    """
    #if ELMC_ALLOC_TRACK
    static void elmc_alloc_track_register(void *ptr, size_t size, const char *context, const char *file, int line);
    static void elmc_free_impl(void *ptr, const char *context, const char *file, int line);
    #endif
    """
  end

  @spec source_impl() :: String.t()
  def source_impl do
    """
    #if ELMC_ALLOC_TRACK

    #ifndef ELMC_ALLOC_TRACK_MAX
    #define ELMC_ALLOC_TRACK_MAX 32768
    #endif

    typedef struct ElmcAllocTrackEntry {
      void *ptr;
      size_t size;
      uint32_t id;
      const char *context;
      const char *file;
      int line;
    } ElmcAllocTrackEntry;

    static ElmcAllocTrackEntry ELMC_ALLOC_TRACK_ENTRIES[ELMC_ALLOC_TRACK_MAX];
    static uint32_t ELMC_ALLOC_TRACK_COUNT = 0;
    static uint32_t ELMC_ALLOC_TRACK_NEXT_ID = 1;

    static ElmcAllocTrackEntry *elmc_alloc_track_find(void *ptr) {
      if (!ptr) return NULL;
      for (uint32_t i = 0; i < ELMC_ALLOC_TRACK_COUNT; i++) {
        if (ELMC_ALLOC_TRACK_ENTRIES[i].ptr == ptr) return &ELMC_ALLOC_TRACK_ENTRIES[i];
      }
      return NULL;
    }

    static void elmc_alloc_track_register(void *ptr, size_t size, const char *context, const char *file, int line) {
      if (!ptr) return;
      if (ELMC_ALLOC_TRACK_COUNT >= ELMC_ALLOC_TRACK_MAX) return;
      ElmcAllocTrackEntry *entry = &ELMC_ALLOC_TRACK_ENTRIES[ELMC_ALLOC_TRACK_COUNT++];
      entry->ptr = ptr;
      entry->size = size;
      entry->id = ELMC_ALLOC_TRACK_NEXT_ID++;
      entry->context = context ? context : "malloc";
      entry->file = file;
      entry->line = line;
    }

    static void elmc_alloc_track_unregister(void *ptr) {
      if (!ptr) return;
      ElmcAllocTrackEntry *entry = elmc_alloc_track_find(ptr);
      if (!entry) return;
      uint32_t i = (uint32_t)(entry - ELMC_ALLOC_TRACK_ENTRIES);
      ELMC_ALLOC_TRACK_COUNT -= 1;
      if (i < ELMC_ALLOC_TRACK_COUNT) {
        ELMC_ALLOC_TRACK_ENTRIES[i] = ELMC_ALLOC_TRACK_ENTRIES[ELMC_ALLOC_TRACK_COUNT];
      }
    }

    void elmc_alloc_track_reset(void) {
      ELMC_ALLOC_TRACK_COUNT = 0;
      ELMC_ALLOC_TRACK_NEXT_ID = 1;
    }

    uint32_t elmc_alloc_track_live_count(void) {
      return ELMC_ALLOC_TRACK_COUNT;
    }

    uint32_t elmc_alloc_track_next_alloc_id(void) {
      return ELMC_ALLOC_TRACK_NEXT_ID;
    }

    void elmc_alloc_track_dump_since(uint32_t min_id, FILE *out) {
      if (!out) out = stderr;
      for (uint32_t i = 0; i < ELMC_ALLOC_TRACK_COUNT; i++) {
        ElmcAllocTrackEntry *entry = &ELMC_ALLOC_TRACK_ENTRIES[i];
        if (entry->id < min_id) continue;
        const char *file = entry->file ? entry->file : "?";
        fprintf(out,
                "    +malloc #%u size=%lu %s:%d (%s)\\n",
                entry->id,
                (unsigned long)entry->size,
                file,
                entry->line,
                entry->context ? entry->context : "malloc");
      }
    }

    void elmc_alloc_track_dump_live(FILE *out) {
      if (!out) out = stderr;
      fprintf(out, "elmc alloc track: %u live malloc(s)\\n", ELMC_ALLOC_TRACK_COUNT);
      for (uint32_t i = 0; i < ELMC_ALLOC_TRACK_COUNT; i++) {
        ElmcAllocTrackEntry *entry = &ELMC_ALLOC_TRACK_ENTRIES[i];
        const char *file = entry->file ? entry->file : "?";
        fprintf(out,
                "  #%u %p size=%lu %s:%d (%s)\\n",
                entry->id,
                entry->ptr,
                (unsigned long)entry->size,
                file,
                entry->line,
                entry->context ? entry->context : "malloc");
      }
    }

    int elmc_alloc_track_check_balanced(void) {
      if (ELMC_ALLOC_TRACK_COUNT == 0) return 1;
      elmc_alloc_track_dump_live(stderr);
      return 0;
    }

    static void elmc_free_impl(void *ptr, const char *context, const char *file, int line) {
      (void)context;
      (void)file;
      (void)line;
      if (!ptr) return;
      elmc_alloc_track_unregister(ptr);
      free(ptr);
    }

    #endif
    """
  end
end
