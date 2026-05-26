defmodule Ide.Debugger.SampleViewTrees do
  @moduledoc false

  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.Types

  @spec default_for_target(Types.surface_target()) :: map()
  def default_for_target(:watch), do: Map.get(RuntimeSurfaces.default_watch(), :view_tree)
  def default_for_target(:companion), do: Map.get(RuntimeSurfaces.default_companion(), :view_tree)
  def default_for_target(:phone), do: Map.get(RuntimeSurfaces.default_phone(), :view_tree)

  @spec watch(String.t() | nil, String.t()) :: map()
  def watch(rel_path, revision) do
    path = rel_path || "unknown"

    %{
      "type" => "Window",
      "label" => path,
      "box" => %{"x" => 0, "y" => 0, "w" => 144, "h" => 168},
      "meta" => %{"revision" => revision},
      "children" => [
        %{
          "type" => "TextLayer",
          "label" => "Title",
          "box" => %{"x" => 8, "y" => 12, "w" => 128, "h" => 28},
          "children" => []
        },
        %{
          "type" => "Layer",
          "label" => "Body",
          "box" => %{"x" => 0, "y" => 48, "w" => 144, "h" => 96},
          "children" => [
            %{
              "type" => "Rect",
              "label" => "card",
              "box" => %{"x" => 12, "y" => 8, "w" => 120, "h" => 36},
              "children" => []
            }
          ]
        }
      ]
    }
  end

  @spec companion(String.t(), String.t()) :: map()
  def companion(rel_path, revision) do
    %{
      "type" => "CompanionRoot",
      "label" => "phone",
      "box" => %{"x" => 0, "y" => 0, "w" => 180, "h" => 320},
      "meta" => %{"revision" => revision},
      "children" => [
        %{
          "type" => "Status",
          "label" => rel_path,
          "box" => %{"x" => 6, "y" => 8, "w" => 168, "h" => 22},
          "children" => []
        },
        %{
          "type" => "ProtocolLog",
          "label" => revision,
          "box" => %{"x" => 6, "y" => 36, "w" => 168, "h" => 220},
          "children" => []
        }
      ]
    }
  end

  @spec phone(String.t(), String.t()) :: map()
  def phone(rel_path, revision) do
    %{
      "type" => "PhoneRoot",
      "label" => rel_path,
      "box" => %{"x" => 0, "y" => 0, "w" => 200, "h" => 360},
      "meta" => %{"revision" => revision},
      "children" => [
        %{
          "type" => "AppBar",
          "label" => "Elm · phone",
          "box" => %{"x" => 0, "y" => 0, "w" => 200, "h" => 48},
          "children" => []
        },
        %{
          "type" => "Scroll",
          "label" => "main",
          "box" => %{"x" => 0, "y" => 52, "w" => 200, "h" => 280},
          "children" => [
            %{
              "type" => "Card",
              "label" => rel_path,
              "box" => %{"x" => 12, "y" => 8, "w" => 176, "h" => 72},
              "children" => []
            }
          ]
        }
      ]
    }
  end
end
