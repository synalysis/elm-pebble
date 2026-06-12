defmodule Elmc.Runtime.RcCodes do
  @moduledoc """
  Canonical RC (return-code) enum entries for generated C runtime headers.
  """

  @type entry :: %{
          id: atom(),
          c_name: String.t(),
          severity: :logged
        }

  @entries [
    %{id: :success, c_name: "RC_SUCCESS", severity: :logged},
    %{id: :out_of_memory, c_name: "RC_ERR_OUT_OF_MEMORY", severity: :logged},
    %{id: :invalid_arg, c_name: "RC_ERR_INVALID_ARG", severity: :logged},
    %{id: :unsupported, c_name: "RC_ERR_UNSUPPORTED", severity: :logged},
    %{id: :missing_callback, c_name: "RC_ERR_MISSING_CALLBACK", severity: :logged},
    %{id: :malformed_tuple, c_name: "RC_ERR_MALFORMED_TUPLE", severity: :logged},
    %{id: :malformed_cmd, c_name: "RC_ERR_MALFORMED_CMD", severity: :logged},
    %{id: :malformed_view, c_name: "RC_ERR_MALFORMED_VIEW", severity: :logged},
    %{id: :malformed_sub, c_name: "RC_ERR_MALFORMED_SUB", severity: :logged},
    %{id: :scene_buffer_overflow, c_name: "RC_ERR_SCENE_BUFFER_OVERFLOW", severity: :logged},
    %{id: :scene_decode, c_name: "RC_ERR_SCENE_DECODE", severity: :logged},
    %{id: :scene_depth_limit, c_name: "RC_ERR_SCENE_DEPTH_LIMIT", severity: :logged},
    %{id: :render_abort, c_name: "RC_ERR_RENDER_ABORT", severity: :logged},
    %{id: :persist_write_int, c_name: "RC_ERR_PERSIST_WRITE_INT", severity: :logged},
    %{id: :persist_read_int, c_name: "RC_ERR_PERSIST_READ_INT", severity: :logged},
    %{id: :persist_write_string, c_name: "RC_ERR_PERSIST_WRITE_STRING", severity: :logged},
    %{id: :persist_read_string, c_name: "RC_ERR_PERSIST_READ_STRING", severity: :logged},
    %{id: :persist_delete, c_name: "RC_ERR_PERSIST_DELETE", severity: :logged},
    %{id: :app_message_open, c_name: "RC_ERR_APP_MESSAGE_OPEN", severity: :logged},
    %{id: :app_message_outbox_begin, c_name: "RC_ERR_APP_MESSAGE_OUTBOX_BEGIN", severity: :logged},
    %{id: :app_message_outbox_send, c_name: "RC_ERR_APP_MESSAGE_OUTBOX_SEND", severity: :logged},
    %{id: :app_timer_register, c_name: "RC_ERR_APP_TIMER_REGISTER", severity: :logged},
    %{id: :app_timer_reschedule, c_name: "RC_ERR_APP_TIMER_RESCHEDULE", severity: :logged},
    %{id: :wakeup_schedule, c_name: "RC_ERR_WAKEUP_SCHEDULE", severity: :logged},
    %{id: :wakeup_cancel, c_name: "RC_ERR_WAKEUP_CANCEL", severity: :logged},
    %{id: :data_logging_create, c_name: "RC_ERR_DATA_LOGGING_CREATE", severity: :logged},
    %{id: :data_logging_log, c_name: "RC_ERR_DATA_LOGGING_LOG", severity: :logged},
    %{id: :dictation_session_create, c_name: "RC_ERR_DICTATION_SESSION_CREATE", severity: :logged},
    %{id: :gdraw_sequence_create, c_name: "RC_ERR_GDRAW_SEQUENCE_CREATE", severity: :logged},
    %{id: :gdraw_image_create, c_name: "RC_ERR_GDRAW_IMAGE_CREATE", severity: :logged}
  ]

  @spec all() :: [entry()]
  def all, do: @entries

  @spec c_names() :: [String.t()]
  def c_names, do: Enum.map(@entries, & &1.c_name)

  @spec enum_declarations() :: String.t()
  def enum_declarations do
    body =
      @entries
      |> Enum.map_join(",\n", fn %{c_name: name} -> "  #{name}" end)

    """
    /* Return codes (RC) — distinct from ElmcValue.rc reference counts. */
    typedef enum {
    #{body}
    } RC;
    """
  end

  @spec name_table_source() :: String.t()
  def name_table_source do
    rows =
      @entries
      |> Enum.map_join(",\n", fn %{c_name: name} ->
        "  \"#{name}\""
      end)

    """
    const char *elmc_rc_name(RC rc) {
      static const char * const elmc_rc_names[] = {
    #{rows}
      };

      if ((unsigned)rc >= (unsigned)(sizeof(elmc_rc_names) / sizeof(elmc_rc_names[0])))
        return "RC_UNKNOWN";
      return elmc_rc_names[(unsigned)rc];
    }

    static inline int elmc_rc_is_success(RC rc) {
      return rc == RC_SUCCESS;
    }
    """
  end
end
