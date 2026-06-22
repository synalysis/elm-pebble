defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.VectorSequenceInstances do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT
    #define ELMC_VECTOR_SEQUENCE_MAX_INSTANCES 8

    typedef struct {
      int32_t animation_id;
      uint32_t resource_id;
      int16_t origin_x;
      int16_t origin_y;
      int64_t started_at_ms;
      uint32_t duration_ms;
      uint16_t play_count;
      uint8_t active;
      uint8_t seen_this_frame;
      uint8_t finished_pending;
    } ElmcVectorSequenceInstance;

    static ElmcVectorSequenceInstance s_vector_sequence_instances[ELMC_VECTOR_SEQUENCE_MAX_INSTANCES];
    static AppTimer *s_vector_sequence_timer = NULL;
    static uint32_t s_cached_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
    static uint32_t s_failed_vector_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
    static uint32_t s_cached_vector_sequence_duration_ms = 0;
    static GDrawCommandSequence *s_cached_sequence = NULL;

    static void vector_sequence_timer_callback(void *data);
    static void vector_sequence_flush_finished(ElmcPebbleApp *app);

    static void vector_sequence_cache_clear(void) {
      if (s_cached_sequence) {
        gdraw_command_sequence_destroy(s_cached_sequence);
        s_cached_sequence = NULL;
      }
      s_cached_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
      s_failed_vector_sequence_resource_id = ELM_PEBBLE_RESOURCE_ID_MISSING;
      s_cached_vector_sequence_duration_ms = 0;
    }

    static uint32_t vector_sequence_total_duration_ms(GDrawCommandSequence *sequence) {
      if (!sequence) {
        return 0;
      }

      uint32_t frame_count = gdraw_command_sequence_get_num_frames(sequence);
      if (frame_count == 0) {
        return 0;
      }

      uint32_t total_ms = 0;
      for (uint32_t index = 0; index < frame_count; index++) {
        GDrawCommandFrame *frame = gdraw_command_sequence_get_frame_by_index(sequence, index);
        if (!frame) {
          continue;
        }
        total_ms += gdraw_command_frame_get_duration(frame);
      }

      return total_ms;
    }

    static uint32_t vector_sequence_playable_duration_ms(GDrawCommandSequence *sequence) {
      if (!sequence) {
        return 0;
      }

      uint32_t total_ms = gdraw_command_sequence_get_total_duration(sequence);
      if (total_ms > 0) {
        return total_ms;
      }

      return vector_sequence_total_duration_ms(sequence);
    }

    static GDrawCommandFrame *vector_sequence_frame_at_elapsed(
        GDrawCommandSequence *sequence,
        uint32_t elapsed_ms,
        uint32_t total_duration_ms,
        uint16_t play_count) {
      if (!sequence) {
        return NULL;
      }

      uint32_t frame_count = gdraw_command_sequence_get_num_frames(sequence);
      if (frame_count == 0) {
        return NULL;
      }

      if (total_duration_ms == 0) {
        total_duration_ms = vector_sequence_playable_duration_ms(sequence);
      }

      if (total_duration_ms > 0) {
        if (elmc_sequence_play_loops(play_count)) {
          elapsed_ms = elapsed_ms % total_duration_ms;
        } else if (play_count > 0) {
          uint32_t max_elapsed = total_duration_ms * (uint32_t)play_count;
          if (elapsed_ms >= max_elapsed) {
            elapsed_ms = max_elapsed > 0 ? max_elapsed - 1 : 0;
          }
        }

        uint32_t remaining = elapsed_ms;
        for (uint32_t index = 0; index < frame_count; index++) {
          GDrawCommandFrame *frame = gdraw_command_sequence_get_frame_by_index(sequence, index);
          if (!frame) {
            continue;
          }
          uint32_t frame_duration = gdraw_command_frame_get_duration(frame);
          if (frame_duration == 0) {
            frame_duration = total_duration_ms / frame_count;
            if (frame_duration == 0) {
              frame_duration = 100;
            }
          }
          if (remaining < frame_duration || index + 1 == frame_count) {
            return frame;
          }
          remaining -= frame_duration;
        }
      }

      return gdraw_command_sequence_get_frame_by_index(sequence, frame_count - 1);
    }

    static GDrawCommandSequence *vector_sequence_cached(uint32_t resource_id) {
      if (resource_id == ELM_PEBBLE_RESOURCE_ID_MISSING) {
        return NULL;
      }
      if (resource_id == s_failed_vector_sequence_resource_id) {
        return NULL;
      }
      if (s_cached_sequence && s_cached_sequence_resource_id == resource_id) {
        return s_cached_sequence;
      }
      vector_sequence_cache_clear();
      s_cached_sequence_resource_id = resource_id;
      s_cached_sequence = gdraw_command_sequence_create_with_resource(resource_id);
      if (!s_cached_sequence) {
        s_failed_vector_sequence_resource_id = resource_id;
        APP_LOG(APP_LOG_LEVEL_WARNING, "vector sequence load failed resource_id=%lu", (unsigned long)resource_id);
        return NULL;
      }

      s_cached_vector_sequence_duration_ms = vector_sequence_playable_duration_ms(s_cached_sequence);
      if (s_cached_vector_sequence_duration_ms == 0) {
        APP_LOG(APP_LOG_LEVEL_WARNING, "vector sequence has no playable frames resource_id=%lu",
                (unsigned long)resource_id);
      }
      return s_cached_sequence;
    }

    static ElmcVectorSequenceInstance *vector_sequence_instance_find(int32_t animation_id) {
      for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
        if (inst->active && inst->animation_id == animation_id) {
          return inst;
        }
      }
      return NULL;
    }

    static ElmcVectorSequenceInstance *vector_sequence_instance_alloc(int32_t animation_id) {
      ElmcVectorSequenceInstance *existing = vector_sequence_instance_find(animation_id);
      if (existing) {
        return existing;
      }

      for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
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

    static bool vector_sequence_instance_animating(
        ElmcVectorSequenceInstance *inst,
        GDrawCommandSequence *sequence,
        uint32_t total_duration_ms) {
      if (!inst || !sequence) {
        return false;
      }

      uint32_t play_count = inst->play_count;
      if (elmc_sequence_play_loops(play_count) && total_duration_ms > 0) {
        return true;
      }

      if (play_count > 0 && total_duration_ms > 0) {
        uint32_t elapsed = (uint32_t)(elmc_sequence_monotonic_ms() - inst->started_at_ms);
        return elapsed < total_duration_ms * (uint32_t)play_count;
      }

      return false;
    }

    static void vector_sequence_schedule_timer_if_needed(bool animating) {
      if (animating && !s_vector_sequence_timer) {
        s_vector_sequence_timer = app_timer_register(33, vector_sequence_timer_callback, NULL);
      } else if (!animating && s_vector_sequence_timer) {
        app_timer_cancel(s_vector_sequence_timer);
        s_vector_sequence_timer = NULL;
      }
    }

    static void vector_sequence_timer_callback(void *data) {
      (void)data;
      s_vector_sequence_timer = NULL;
      bool any_animating = false;

      for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
        if (!inst->active) {
          continue;
        }

        GDrawCommandSequence *sequence = vector_sequence_cached(inst->resource_id);
        if (!sequence) {
          inst->active = 0;
          continue;
        }

        if (vector_sequence_instance_animating(inst, sequence, inst->duration_ms)) {
          any_animating = true;
        } else {
          inst->finished_pending = 1;
          inst->active = 0;
        }
      }

      vector_sequence_flush_finished(s_sequence_playback_app);
      if (s_sequence_playback_app) {
        elmc_pebble_invalidate_scene(s_sequence_playback_app);
      }
      elmc_pebble_schedule_layer_redraw();
      vector_sequence_schedule_timer_if_needed(any_animating);
    }

    static void vector_sequence_flush_finished(ElmcPebbleApp *app) {
      if (!app) {
        return;
      }

      for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
        if (!inst->finished_pending) {
          continue;
        }

        int rc = elmc_pebble_dispatch_animation_finished(app, inst->animation_id);
        if (rc == 0) {
          elmc_pebble_after_worker_dispatch();
        }
        inst->finished_pending = 0;
        inst->active = 0;
      }
    }

    void elmc_vector_sequence_frame_begin(void) {
      for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
        if (s_vector_sequence_instances[i].active) {
          s_vector_sequence_instances[i].seen_this_frame = 0;
        }
      }
    }

    void elmc_vector_sequence_draw_at(
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

      GDrawCommandSequence *sequence = vector_sequence_cached(resource_id);
      if (!sequence) {
        return;
      }

      ElmcVectorSequenceInstance *inst = vector_sequence_instance_alloc(animation_id);
      if (!inst) {
        return;
      }

      bool fresh = inst->resource_id == 0;
      inst->resource_id = resource_id;
      inst->origin_x = x;
      inst->origin_y = y;
      inst->seen_this_frame = 1;
      inst->play_count = gdraw_command_sequence_get_play_count(sequence);
      inst->duration_ms = vector_sequence_playable_duration_ms(sequence);
      if (inst->duration_ms == 0 && s_cached_vector_sequence_duration_ms > 0) {
        inst->duration_ms = s_cached_vector_sequence_duration_ms;
      }

      if (fresh) {
        inst->started_at_ms = elmc_sequence_monotonic_ms();
      }

      uint32_t elapsed = (uint32_t)(elmc_sequence_monotonic_ms() - inst->started_at_ms);
      uint32_t total_duration = inst->duration_ms;
      GDrawCommandFrame *frame =
          vector_sequence_frame_at_elapsed(sequence, elapsed, total_duration, inst->play_count);
      if (frame) {
        gdraw_command_frame_draw(ctx, sequence, frame, GPoint(x, y));
      }

      bool animating = vector_sequence_instance_animating(inst, sequence, total_duration);
      if (!animating) {
        inst->finished_pending = 1;
        inst->active = 0;
      }

      vector_sequence_schedule_timer_if_needed(animating);
    }

    void elmc_vector_sequence_frame_end(ElmcPebbleApp *app) {
      elmc_sequence_track_app(app);
      bool any_animating = false;

      for (int i = 0; i < ELMC_VECTOR_SEQUENCE_MAX_INSTANCES; i++) {
        ElmcVectorSequenceInstance *inst = &s_vector_sequence_instances[i];
        if (!inst->active) {
          continue;
        }

        if (!inst->seen_this_frame) {
          inst->active = 0;
          continue;
        }

        GDrawCommandSequence *sequence = vector_sequence_cached(inst->resource_id);
        if (!sequence) {
          inst->active = 0;
          continue;
        }

        if (vector_sequence_instance_animating(inst, sequence, inst->duration_ms)) {
          any_animating = true;
        } else {
          inst->finished_pending = 1;
          inst->active = 0;
        }
      }

      vector_sequence_flush_finished(app);
      vector_sequence_schedule_timer_if_needed(any_animating);
    }

    void elmc_vector_sequence_deinit(void) {
      if (s_vector_sequence_timer) {
        app_timer_cancel(s_vector_sequence_timer);
        s_vector_sequence_timer = NULL;
      }
      vector_sequence_cache_clear();
      memset(s_vector_sequence_instances, 0, sizeof(s_vector_sequence_instances));
    }
    #endif
    """
  end

  @spec header_decls() :: Types.c_source()
  def header_decls do
    """
    void elmc_vector_sequence_frame_begin(void);
    void elmc_vector_sequence_draw_at(GContext *ctx, ElmcPebbleApp *app, int32_t animation_id, uint32_t resource_id, int16_t x, int16_t y);
    void elmc_vector_sequence_frame_end(ElmcPebbleApp *app);
    void elmc_vector_sequence_deinit(void);
    int elmc_pebble_dispatch_animation_finished(ElmcPebbleApp *app, int animation_id);
    """
  end
end
