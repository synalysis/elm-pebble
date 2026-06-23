defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.BitmapSequenceInstances do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_BITMAP_SEQUENCE_AT
    #ifdef ELMC_PEBBLE_PLATFORM
    #define ELMC_BITMAP_SEQUENCE_MAX_INSTANCES 8

    typedef struct {
      int32_t animation_id;
      uint32_t resource_id;
      int16_t origin_x;
      int16_t origin_y;
      int64_t started_at_ms;
      uint32_t duration_ms;
      uint16_t play_count;
      GBitmapSequence *sequence;
      uint8_t active;
      uint8_t seen_this_frame;
      uint8_t finished_pending;
    } ElmcBitmapSequenceInstance;

    static ElmcBitmapSequenceInstance s_bitmap_sequence_instances[ELMC_BITMAP_SEQUENCE_MAX_INSTANCES];
    static AppTimer *s_bitmap_sequence_timer = NULL;
    static uint32_t s_failed_bitmap_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;

    static void bitmap_sequence_timer_callback(void *data);

    static void bitmap_sequence_normalize_play_count(GBitmapSequence *sequence) {
      if (!sequence) {
        return;
      }

      if (gbitmap_sequence_get_play_count(sequence) == 0) {
        gbitmap_sequence_set_play_count(sequence, PLAY_COUNT_INFINITE);
      }
    }

    static uint32_t bitmap_sequence_total_duration_ms(GBitmapSequence *sequence) {
      if (!sequence) {
        return 0;
      }

      uint16_t frame_count = gbitmap_sequence_get_total_num_frames(sequence);
      if (frame_count == 0) {
        return 0;
      }

      GSize size = gbitmap_sequence_get_bitmap_size(sequence);
      if (size.w <= 0 || size.h <= 0) {
        return 0;
      }

      GBitmap *scratch = gbitmap_create_blank(size, GBitmapFormat8Bit);
      if (!scratch) {
        return 0;
      }

      gbitmap_sequence_restart(sequence);
      uint32_t total_ms = 0;
      uint32_t delay_ms = 0;

      for (uint16_t frame = 0; frame < frame_count; frame++) {
        if (!gbitmap_sequence_update_bitmap_next_frame(sequence, scratch, &delay_ms)) {
          break;
        }
        total_ms += delay_ms;
      }

      gbitmap_destroy(scratch);
      gbitmap_sequence_restart(sequence);
      return total_ms;
    }

    static GBitmapSequence *bitmap_sequence_create(uint32_t resource_id) {
      if (resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING) {
        return NULL;
      }
      if (resource_id == s_failed_bitmap_sequence_resource_id) {
        return NULL;
      }

      GBitmapSequence *sequence = gbitmap_sequence_create_with_resource(resource_id);
      if (!sequence) {
        s_failed_bitmap_sequence_resource_id = resource_id;
        APP_LOG(APP_LOG_LEVEL_WARNING, "bitmap sequence load failed resource_id=%lu",
                (unsigned long)resource_id);
        return NULL;
      }

      bitmap_sequence_normalize_play_count(sequence);
      return sequence;
    }

    static void bitmap_sequence_instance_release(ElmcBitmapSequenceInstance *inst) {
      if (!inst) {
        return;
      }

      if (inst->sequence) {
        gbitmap_sequence_destroy(inst->sequence);
        inst->sequence = NULL;
      }
    }

    static ElmcBitmapSequenceInstance *bitmap_sequence_instance_find(int32_t animation_id) {
      for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
        if (inst->active && inst->animation_id == animation_id) {
          return inst;
        }
      }
      return NULL;
    }

    static ElmcBitmapSequenceInstance *bitmap_sequence_instance_alloc(int32_t animation_id) {
      ElmcBitmapSequenceInstance *existing = bitmap_sequence_instance_find(animation_id);
      if (existing) {
        return existing;
      }

      for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
        if (!inst->active) {
          memset(inst, 0, sizeof(*inst));
          inst->animation_id = animation_id;
          inst->active = 1;
          inst->started_at_ms = elmc_sequence_monotonic_ms();
          return inst;
        }
      }

      return NULL;
    }

    static bool bitmap_sequence_seek_elapsed(
        GBitmapSequence *sequence,
        GBitmap *bitmap,
        uint32_t elapsed_ms,
        uint32_t total_duration_ms,
        uint16_t play_count) {
      if (!sequence || !bitmap) {
        return false;
      }

      gbitmap_sequence_restart(sequence);
      bitmap_sequence_normalize_play_count(sequence);

      if (total_duration_ms > 0) {
        if (elmc_sequence_play_loops(play_count)) {
          elapsed_ms = elapsed_ms % total_duration_ms;
        } else if (play_count > 0) {
          uint32_t max_elapsed = total_duration_ms * (uint32_t)play_count;
          if (elapsed_ms >= max_elapsed) {
            return false;
          }
        }
      }

      uint32_t accumulated = 0;
      while (true) {
        uint32_t delay_ms = 0;
        if (!gbitmap_sequence_update_bitmap_next_frame(sequence, bitmap, &delay_ms)) {
          return accumulated <= elapsed_ms;
        }

        if (delay_ms == 0) {
          delay_ms = 1;
        }

        if (accumulated + delay_ms > elapsed_ms) {
          return true;
        }

        accumulated += delay_ms;
      }
    }

    static bool bitmap_sequence_instance_animating(ElmcBitmapSequenceInstance *inst) {
      if (!inst) {
        return false;
      }

      if (elmc_sequence_play_loops(inst->play_count) && inst->duration_ms > 0) {
        return true;
      }

      if (inst->play_count > 0 && inst->duration_ms > 0) {
        uint32_t elapsed = (uint32_t)(elmc_sequence_monotonic_ms() - inst->started_at_ms);
        return elapsed < inst->duration_ms * (uint32_t)inst->play_count;
      }

      return false;
    }

    static void bitmap_sequence_schedule_timer_if_needed(bool animating) {
      if (animating && !s_bitmap_sequence_timer) {
        s_bitmap_sequence_timer = app_timer_register(33, bitmap_sequence_timer_callback, NULL);
      } else if (!animating && s_bitmap_sequence_timer) {
        app_timer_cancel(s_bitmap_sequence_timer);
        s_bitmap_sequence_timer = NULL;
      }
    }

    static void bitmap_sequence_flush_finished(ElmcPebbleApp *app) {
      if (!app) {
        return;
      }

      for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
        if (!inst->finished_pending) {
          continue;
        }

        int rc = elmc_pebble_dispatch_animation_finished(app, inst->animation_id);
        if (rc == 0) {
          elmc_pebble_after_worker_dispatch();
        }
        inst->finished_pending = 0;
        bitmap_sequence_instance_release(inst);
        inst->active = 0;
      }
    }

    static void bitmap_sequence_timer_callback(void *data) {
      (void)data;
      s_bitmap_sequence_timer = NULL;
      bool any_animating = false;

      for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
        if (!inst->active) {
          continue;
        }

        if (!inst->sequence) {
          inst->active = 0;
          continue;
        }

        if (bitmap_sequence_instance_animating(inst)) {
          any_animating = true;
        } else {
          inst->finished_pending = 1;
          inst->active = 0;
        }
      }

      bitmap_sequence_flush_finished(s_sequence_playback_app);
      if (s_sequence_playback_app) {
        elmc_pebble_invalidate_scene(s_sequence_playback_app);
      }
      elmc_pebble_schedule_layer_redraw();
      bitmap_sequence_schedule_timer_if_needed(any_animating);
    }

    void elmc_bitmap_sequence_frame_begin(void) {
      for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
        if (s_bitmap_sequence_instances[i].active) {
          s_bitmap_sequence_instances[i].seen_this_frame = 0;
        }
      }
    }

    void elmc_bitmap_sequence_draw_at(
        GContext *ctx,
        ElmcPebbleApp *app,
        int32_t animation_id,
        uint32_t resource_id,
        int16_t x,
        int16_t y) {
      if (!ctx || animation_id <= 0) {
        return;
      }

      elmc_sequence_track_app(app);

      ElmcBitmapSequenceInstance *inst = bitmap_sequence_instance_alloc(animation_id);
      if (!inst) {
        return;
      }

      bool fresh = inst->resource_id == 0;
      bool resource_changed = inst->resource_id != 0 && inst->resource_id != resource_id;

      if (fresh || resource_changed || !inst->sequence) {
        bitmap_sequence_instance_release(inst);
        inst->sequence = bitmap_sequence_create(resource_id);
        if (!inst->sequence) {
          inst->active = 0;
          return;
        }
        inst->started_at_ms = elmc_sequence_monotonic_ms();
        inst->duration_ms = bitmap_sequence_total_duration_ms(inst->sequence);
        inst->play_count = gbitmap_sequence_get_play_count(inst->sequence);
        if (inst->duration_ms == 0) {
          APP_LOG(APP_LOG_LEVEL_WARNING, "bitmap sequence has no playable frames resource_id=%lu",
                  (unsigned long)resource_id);
        }
      }

      inst->resource_id = resource_id;
      inst->origin_x = x;
      inst->origin_y = y;
      inst->seen_this_frame = 1;

      GSize size = gbitmap_sequence_get_bitmap_size(inst->sequence);
      if (size.w <= 0 || size.h <= 0) {
        return;
      }

      GBitmap *frame = gbitmap_create_blank(size, GBitmapFormat8Bit);
      if (!frame) {
        return;
      }

      uint32_t elapsed = (uint32_t)(elmc_sequence_monotonic_ms() - inst->started_at_ms);
      bool has_frame = bitmap_sequence_seek_elapsed(
          inst->sequence,
          frame,
          elapsed,
          inst->duration_ms,
          inst->play_count);

      if (has_frame) {
        graphics_draw_bitmap_in_rect(ctx, frame, GRect(x, y, size.w, size.h));
      }

      gbitmap_destroy(frame);

      bool animating = bitmap_sequence_instance_animating(inst);
      if (!animating) {
        inst->finished_pending = 1;
        inst->active = 0;
      }

      bitmap_sequence_schedule_timer_if_needed(animating);
    }

    void elmc_bitmap_sequence_frame_end(ElmcPebbleApp *app) {
      elmc_sequence_track_app(app);
      bool any_animating = false;

      for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcBitmapSequenceInstance *inst = &s_bitmap_sequence_instances[i];
        if (!inst->active) {
          continue;
        }

        if (!inst->seen_this_frame) {
          inst->active = 0;
          bitmap_sequence_instance_release(inst);
          continue;
        }

        if (bitmap_sequence_instance_animating(inst)) {
          any_animating = true;
        } else {
          inst->finished_pending = 1;
          inst->active = 0;
        }
      }

      bitmap_sequence_flush_finished(app);
      bitmap_sequence_schedule_timer_if_needed(any_animating);
    }

    void elmc_bitmap_sequence_deinit(void) {
      if (s_bitmap_sequence_timer) {
        app_timer_cancel(s_bitmap_sequence_timer);
        s_bitmap_sequence_timer = NULL;
      }

      for (int i = 0; i < ELMC_BITMAP_SEQUENCE_MAX_INSTANCES; i++) {
        bitmap_sequence_instance_release(&s_bitmap_sequence_instances[i]);
      }

      memset(s_bitmap_sequence_instances, 0, sizeof(s_bitmap_sequence_instances));
      s_failed_bitmap_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
    }
    #else
    void elmc_bitmap_sequence_frame_begin(void) {
    }

    void elmc_bitmap_sequence_draw_at(
        GContext *ctx,
        ElmcPebbleApp *app,
        int32_t animation_id,
        uint32_t resource_id,
        int16_t x,
        int16_t y) {
      (void)ctx;
      (void)app;
      (void)animation_id;
      (void)resource_id;
      (void)x;
      (void)y;
    }

    void elmc_bitmap_sequence_frame_end(ElmcPebbleApp *app) {
      (void)app;
    }

    void elmc_bitmap_sequence_deinit(void) {
    }
    #endif
    #endif
    """
  end

  @spec header_decls() :: Types.c_source()
  def header_decls do
    """
    void elmc_bitmap_sequence_frame_begin(void);
    void elmc_bitmap_sequence_draw_at(GContext *ctx, ElmcPebbleApp *app, int32_t animation_id, uint32_t resource_id, int16_t x, int16_t y);
    void elmc_bitmap_sequence_frame_end(ElmcPebbleApp *app);
    void elmc_bitmap_sequence_deinit(void);
    """
  end
end
