defmodule Brooklyn.SSE.Accumulator do
  defstruct [
    :callback,
    :usage,
    leftover: "",
    accumulated_content: "",
    accumulated_reasoning_content: "",
    in_think_tags: false
  ]

  def process_chunk(chunk, leftover) do
    {parsed, new_leftover} = Brooklyn.SSE.Parser.parse_chunk(chunk, leftover)
    {process_events(parsed), new_leftover}
  end

  defp process_events(events) do
    events
    |> Enum.map(fn
      {:ok, :done} -> {:ok, :stop}
      {:ok, %{"usage" => usage} = _msg} when not is_nil(usage) -> 
        {:ok, {:usage, Brooklyn.Types.Usage.from_map(usage)}}
      {:ok, %{"choices" => [%{"delta" => %{}, "finish_reason" => "stop"} | _]}} -> {:ok, :stop}
      {:ok, %{"choices" => [%{"delta" => %{}, "finish_reason" => "length"}]}} -> {:ok, :completion_max_tokens_reached}
      {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} ->
        cond do
          String.contains?(content, "<think>") and String.contains?(content, "</think>") ->
            # Complete think tag in one chunk
            {content_parts, reasoning} = extract_think_content(content)
            {:ok, Delta.new(content_parts, reasoning)}
          String.contains?(content, "<think>") ->
            # Start of think tag
            [content_before | _] = String.split(content, "<think>")
            {:ok, Delta.new(content_before)}
          String.contains?(content, "</think>") ->
            # End of think tag
            [reasoning | rest] = String.split(content, "</think>")
            {:ok, Delta.new(Enum.join(rest), reasoning)}
          true ->
            # Regular content
            {:ok, Delta.new(content)}
        end
      {:ok, %{"usage" => usage}} when not is_nil(usage) ->
        {:ok, :usage, usage}
      {:ok, %{"choices" => [%{"delta" => _} | _]}} -> 
        nil
      {:ok, %{"code" => 400}} -> {:error, :prompt_tokens_exceeded}
      {:ok, %{"code" => 429}} -> {:error, :rate_limit}
      {:ok, unknown} -> {:error, {:unknown_response, unknown}}
      {:error, _msg} -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp extract_think_content(content) do
    parts = String.split(content, ~r/<think>|<\/think>/)
    case parts do
      [before, thinking, aft] -> {before <> aft, thinking}
      [before, thinking] -> {before, thinking}
      [thinking] -> {"", thinking}
      _ -> {content, ""}
    end
  end

  def handle_content_events(events, current_content, acc) do
    Enum.reduce(events, {current_content, acc.accumulated_reasoning_content, acc.in_think_tags}, fn
      {:ok, %{content: content, reasoning_content: reasoning, think_state: :none}}, {c, r, _} when is_binary(content) -> 
        {c <> content, r <> (reasoning || ""), false}
      {:ok, %{content: content, reasoning_content: nil, think_state: :start}}, {c, r, _} -> 
        {c <> content, r, true}
      {:ok, %{content: content, reasoning_content: reasoning, think_state: :end}}, {c, r, _} -> 
        {c <> content, r <> reasoning, false}
      {:ok, %{content: content, reasoning_content: nil, think_state: :continue}}, {c, r, true} -> 
        {c, r <> content, true}
      {:ok, %{content: content, reasoning_content: nil, think_state: :continue}}, {c, r, false} -> 
        {c <> content, r, false}
      _, acc -> acc
    end)
  end

  def handle_usage_events(events, current_usage) do
    events
    |> Enum.filter(fn
      {:ok, {:usage, _}} -> true
      _ -> false
    end)
    |> case do
      [] -> current_usage
      usage_events ->
        # Take the last usage event
        {:ok, {:usage, usage}} = List.last(usage_events)
        usage |> Map.from_struct() |> Map.take([:prompt_tokens, :completion_tokens, :total_tokens])
    end
  end
end

defimpl Collectable, for: Brooklyn.SSE.Accumulator do
  import Brooklyn.SSE.Accumulator, only: [
    handle_content_events: 3,
    handle_usage_events: 2
  ]

  def into(%Brooklyn.SSE.Accumulator{} = acc) do
    initial_state = acc
    collection_fn = fn
      (%Brooklyn.SSE.Accumulator{leftover: leftover, callback: cb, accumulated_content: content} = acc, {:cont, chunk}) ->
        {events, new_leftover} = Brooklyn.SSE.Accumulator.process_chunk(chunk, leftover)

        # First pass: handle content
        {new_content, new_reasoning_content, new_in_think} = handle_content_events(events, content, acc)

        # Second pass: handle usage separately
        new_usage = handle_usage_events(events, acc.usage)

        Enum.each(events, cb)
        %{acc | 
          leftover: new_leftover, 
          accumulated_content: new_content,
          accumulated_reasoning_content: new_reasoning_content,
          usage: new_usage,
          in_think_tags: new_in_think
        }

      (acc, :done) ->
        acc

      (acc, :halt) ->
        acc
    end

    {initial_state, collection_fn}
  end
end
