defmodule Ide.Resources.SvgPath do
  @moduledoc false

  @dialyzer :no_match

  @type point :: {float(), float()}

  @command_letters ~c"MmLlHhVvCcSsQqTtAaZz"

  @spec segment_starts(String.t()) :: {:ok, [point()], boolean()} | :error
  def segment_starts(path_data) when is_binary(path_data) do
    with {:ok, tokens} <- tokenize(path_data),
         {:ok, segments} <- parse_segments(tokens) do
      points = Enum.map(segments, & &1.start)

      open? =
        segments == [] or
          not close_points?(List.first(segments).start, List.last(segments).end)

      points =
        if open? and segments != [] do
          points ++ [List.last(segments).end]
        else
          points
        end

      points =
        case points do
          [first, _ | _] = list ->
            last = List.last(list)

            if close_points?(first, last), do: Enum.drop(list, -1), else: list

          list ->
            list
        end

      {:ok, points, open?}
    end
  end

  def segment_starts(_), do: :error

  @spec points(String.t(), keyword()) :: {:ok, [point()], boolean()} | :error
  def points(path_data, opts \\ []) when is_binary(path_data) do
    if Keyword.get(opts, :flatten_curves, false) do
      flatten_points(path_data, opts)
    else
      segment_starts(path_data)
    end
  end

  defp flatten_points(path_data, opts) do
    tolerance = Keyword.get(opts, :flatten_tolerance, 0.5)

    with {:ok, tokens} <- tokenize(path_data),
         {:ok, sampled} <- flatten_segments(tokens, tolerance) do
      open? =
        sampled == [] or
          not close_points?(List.first(sampled), List.last(sampled))

      points =
        case sampled do
          [first, _ | _] = list ->
            last = List.last(list)
            if close_points?(first, last), do: Enum.drop(list, -1), else: list

          list ->
            list
        end

      {:ok, points, open?}
    else
      :error -> :error
    end
  end

  defp flatten_segments(tokens, tolerance) do
    flatten_segments(tokens, %{x: 0.0, y: 0.0, start_x: 0.0, start_y: 0.0, points: []}, tolerance)
  end

  defp flatten_segments([], %{points: points}, _tolerance), do: {:ok, Enum.reverse(points)}

  defp flatten_segments([token | rest], state, tolerance) do
    if token in @command_letters do
      flatten_command(token, rest, state, tolerance)
    else
      :error
    end
  end

  defp flatten_command(command, tokens, state, tolerance) do
    {params, rest} = take_params(tokens, param_count(command))

    case apply_flatten_command(command, params, state, tolerance) do
      {:ok, next_state} ->
        if rest == [] do
          {:ok, Enum.reverse(next_state.points)}
        else
          next_command = implicit_command(command, params)
          flatten_command(next_command, rest, next_state, tolerance)
        end

      :error ->
        :error
    end
  end

  defp apply_flatten_command("Z", _params, state, _tolerance), do: {:ok, close_flatten(state)}
  defp apply_flatten_command("z", _params, state, _tolerance), do: {:ok, close_flatten(state)}

  defp apply_flatten_command(command, params, state, tolerance) do
    relative? = command == String.downcase(command)

    case String.upcase(command) do
      "M" -> move_flatten(params, state, relative?)
      "L" -> line_flatten(params, state, relative?)
      "H" -> horizontal_flatten(params, state, relative?)
      "V" -> vertical_flatten(params, state, relative?)
      "C" -> cubic_flatten(params, state, relative?, tolerance)
      "S" -> smooth_cubic_flatten(params, state, relative?, tolerance)
      "Q" -> quad_flatten(params, state, relative?, tolerance)
      "T" -> smooth_quad_flatten(params, state, relative?, tolerance)
      "A" -> arc_flatten(params, state, relative?, tolerance)
      _ -> :error
    end
  end

  defp move_flatten([x, y], state, relative?) do
    {x, y} = offset({x, y}, state, relative?)
    {:ok, %{state | x: x, y: y, start_x: x, start_y: y, points: [{x, y} | state.points]}}
  end

  defp move_flatten(_, _, _), do: :error

  defp line_flatten([x, y], state, relative?) do
    {x, y} = offset({x, y}, state, relative?)
    append_flatten(state, {x, y})
  end

  defp line_flatten(_, _, _), do: :error

  defp horizontal_flatten([x], state, relative?) do
    x = if relative?, do: state.x + x, else: x
    append_flatten(state, {x, state.y})
  end

  defp horizontal_flatten(_, _, _), do: :error

  defp vertical_flatten([y], state, relative?) do
    y = if relative?, do: state.y + y, else: y
    append_flatten(state, {state.x, y})
  end

  defp vertical_flatten(_, _, _), do: :error

  defp cubic_flatten([x1, y1, x2, y2, x3, y3], state, relative?, tolerance) do
    {x1, y1} = offset({x1, y1}, state, relative?)
    {x2, y2} = offset({x2, y2}, state, relative?)
    {x3, y3} = offset({x3, y3}, state, relative?)
    start = {state.x, state.y}
    samples = sample_cubic(start, {x1, y1}, {x2, y2}, {x3, y3}, tolerance)
    append_samples(state, samples)
  end

  defp cubic_flatten(_, _, _, _), do: :error

  defp smooth_cubic_flatten([x2, y2, x3, y3], state, relative?, tolerance) do
    {x2, y2} = offset({x2, y2}, state, relative?)
    {x3, y3} = offset({x3, y3}, state, relative?)
    start = {state.x, state.y}
    samples = sample_cubic(start, start, {x2, y2}, {x3, y3}, tolerance)
    append_samples(state, samples)
  end

  defp smooth_cubic_flatten(_, _, _, _), do: :error

  defp quad_flatten([x1, y1, x2, y2], state, relative?, tolerance) do
    {x1, y1} = offset({x1, y1}, state, relative?)
    {x2, y2} = offset({x2, y2}, state, relative?)
    start = {state.x, state.y}
    samples = sample_quad(start, {x1, y1}, {x2, y2}, tolerance)
    append_samples(state, samples)
  end

  defp quad_flatten(_, _, _, _), do: :error

  defp smooth_quad_flatten([x2, y2], state, relative?, tolerance) do
    {x2, y2} = offset({x2, y2}, state, relative?)
    start = {state.x, state.y}
    samples = sample_quad(start, start, {x2, y2}, tolerance)
    append_samples(state, samples)
  end

  defp smooth_quad_flatten(_, _, _, _), do: :error

  defp arc_flatten([_rx, _ry, _angle, _large, _sweep, x, y], state, relative?, tolerance) do
    {x, y} = offset({x, y}, state, relative?)
    samples = sample_line({state.x, state.y}, {x, y}, tolerance)
    append_samples(state, samples)
  end

  defp arc_flatten(_, _, _, _), do: :error

  defp append_flatten(state, {x, y}) do
    {:ok, %{state | x: x, y: y, points: [{x, y} | state.points]}}
  end

  defp append_samples(state, samples) do
    Enum.reduce(samples, {:ok, state}, fn pt, {:ok, st} -> append_flatten(st, pt) end)
  end

  defp close_flatten(state) do
    append_flatten(state, {state.start_x, state.start_y})
  end

  defp sample_line({x1, y1}, {x2, y2}, tolerance) do
    dist = :math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
    steps = max(trunc(Float.ceil(dist / max(tolerance, 0.1))), 1)

    for i <- 1..steps do
      t = i / steps
      {x1 + (x2 - x1) * t, y1 + (y2 - y1) * t}
    end
  end

  defp sample_quad({x0, y0}, {x1, y1}, {x2, y2}, tolerance) do
    sample_curve(
      fn t ->
        u = 1 - t
        {u * u * x0 + 2 * u * t * x1 + t * t * x2, u * u * y0 + 2 * u * t * y1 + t * t * y2}
      end,
      {x0, y0},
      {x2, y2},
      tolerance
    )
  end

  defp sample_cubic({x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}, tolerance) do
    sample_curve(
      fn t ->
        u = 1 - t

        {
          u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
          u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3
        }
      end,
      {x0, y0},
      {x3, y3},
      tolerance
    )
  end

  defp sample_curve(point_fn, start, finish, tolerance) do
    dx = elem(finish, 0) - elem(start, 0)
    dy = elem(finish, 1) - elem(start, 1)
    dist = :math.sqrt(dx * dx + dy * dy)
    steps = max(trunc(Float.ceil(dist / max(tolerance, 0.1))), 1)

    for i <- 1..steps, do: point_fn.(i / steps)
  end

  defp tokenize(path_data) when is_binary(path_data) do
    normalized = String.replace(path_data, ~r/,[\s]*/, " ")
    re = ~r/[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?/

    case Regex.scan(re, normalized) do
      [] -> :error
      matches -> {:ok, Enum.map(matches, &List.first/1)}
    end
  end

  defp tokenize(_), do: :error

  defp parse_segments(tokens) do
    parse_segments(tokens, %{
      x: 0.0,
      y: 0.0,
      start_x: 0.0,
      start_y: 0.0,
      segments: []
    })
  end

  defp parse_segments([], %{segments: segments}), do: {:ok, segments}

  defp parse_segments([token | rest], state) do
    if token in @command_letters do
      parse_command(token, rest, state)
    else
      :error
    end
  end

  defp parse_command(command, tokens, state) do
    {params, rest} = take_params(tokens, param_count(command))

    case apply_command(command, params, state) do
      {:ok, next_state} ->
        if rest == [] do
          {:ok, next_state.segments}
        else
          next_command = implicit_command(command, params)
          parse_command(next_command, rest, next_state)
        end

      :error ->
        :error
    end
  end

  defp param_count("M"), do: 2
  defp param_count("m"), do: 2
  defp param_count("L"), do: 2
  defp param_count("l"), do: 2
  defp param_count("H"), do: 1
  defp param_count("h"), do: 1
  defp param_count("V"), do: 1
  defp param_count("v"), do: 1
  defp param_count("C"), do: 6
  defp param_count("c"), do: 6
  defp param_count("S"), do: 4
  defp param_count("s"), do: 4
  defp param_count("Q"), do: 4
  defp param_count("q"), do: 4
  defp param_count("T"), do: 2
  defp param_count("t"), do: 2
  defp param_count("A"), do: 7
  defp param_count("a"), do: 7
  defp param_count("Z"), do: 0
  defp param_count("z"), do: 0

  defp implicit_command("M", _params), do: "L"
  defp implicit_command("m", _params), do: "l"
  defp implicit_command(command, _params), do: command

  defp take_params(tokens, count) do
    {numbers, rest} =
      Enum.split_while(tokens, fn token ->
        token not in @command_letters
      end)

    if length(numbers) >= count do
      {params, remaining} = Enum.split(numbers, count)
      {Enum.map(params, &String.to_float/1), remaining ++ rest}
    else
      {[], tokens}
    end
  end

  defp apply_command("Z", _params, state), do: {:ok, close_path(state)}
  defp apply_command("z", _params, state), do: {:ok, close_path(state)}

  defp apply_command(command, params, state) do
    relative? = command == String.downcase(command)

    case String.upcase(command) do
      "M" -> move_to(params, state, relative?)
      "L" -> line_to(params, state, relative?)
      "H" -> horizontal_to(params, state, relative?)
      "V" -> vertical_to(params, state, relative?)
      "C" -> curve_to(params, state, relative?, 6)
      "S" -> curve_to(params, state, relative?, 4)
      "Q" -> curve_to(params, state, relative?, 4)
      "T" -> curve_to(params, state, relative?, 2)
      "A" -> curve_to(params, state, relative?, 7)
      _ -> :error
    end
  end

  defp move_to([x, y], state, relative?) do
    {x, y} = offset({x, y}, state, relative?)
    start = {x, y}

    {:ok,
     %{
       state
       | x: x,
         y: y,
         start_x: x,
         start_y: y,
         segments: [%{start: start, end: start} | state.segments]
     }}
  end

  defp move_to(_, _, _), do: :error

  defp line_to([x, y], state, relative?) do
    {x, y} = offset({x, y}, state, relative?)
    append_line(state, {x, y})
  end

  defp line_to(_, _, _), do: :error

  defp horizontal_to([x], state, relative?) do
    x = if relative?, do: state.x + x, else: x
    append_line(state, {x, state.y})
  end

  defp horizontal_to(_, _, _), do: :error

  defp vertical_to([y], state, relative?) do
    y = if relative?, do: state.y + y, else: y
    append_line(state, {state.x, y})
  end

  defp vertical_to(_, _, _), do: :error

  defp curve_to(params, state, relative?, count) do
    {x, y} =
      case count do
        6 -> {Enum.at(params, 4), Enum.at(params, 5)}
        4 -> {Enum.at(params, 2), Enum.at(params, 3)}
        2 -> {Enum.at(params, 0), Enum.at(params, 1)}
        7 -> {Enum.at(params, 5), Enum.at(params, 6)}
      end

    {x, y} = offset({x, y}, state, relative?)
    append_line(state, {x, y})
  end

  defp append_line(state, {x, y}) do
    start = {state.x, state.y}
    end_point = {x, y}

    {:ok,
     %{
       state
       | x: x,
         y: y,
         segments: [%{start: start, end: end_point} | state.segments]
     }}
  end

  defp close_path(state) do
    start = {state.x, state.y}
    end_point = {state.start_x, state.start_y}

    %{
      state
      | x: state.start_x,
        y: state.start_y,
        segments: [%{start: start, end: end_point} | state.segments]
    }
  end

  defp offset({x, y}, state, true), do: {state.x + x, state.y + y}
  defp offset({x, y}, _state, false), do: {x, y}

  defp close_points?({x1, y1}, {x2, y2}), do: x1 == x2 and y1 == y2
end
