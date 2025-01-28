defmodule Brooklyn.SSE.Accumulator do
  alias Brooklyn.Types.Delta

  defstruct [
    :callback,
    :usage,
    leftover: "",
    accumulated_content: "",
    accumulated_reasoning_content: "",
    in_think_tags: false
  ]

  def process_chunk(chunk, leftover) do
    {events, new_leftover, thinking} = Brooklyn.SSE.Parser.parse_chunk(chunk, leftover)
    {process_events(events), new_leftover, thinking}
  end

  defp process_events(events) do
    events
    |> Enum.map(fn
      {:ok, :done, _thinking} -> {:ok, :stop}
      {:ok, :usage, usage} -> {:ok, {:usage, Brooklyn.Types.Usage.from_map(usage)}}
      {:ok, delta, _thinking} -> {:ok, delta}
      {:error, _reason, _msg} -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  def handle_content_events(events, current_content, acc) do
    Enum.reduce(events, {current_content, acc.accumulated_reasoning_content, acc.in_think_tags}, fn
      {:ok, %Brooklyn.Types.Delta{content: content, reasoning_content: reasoning}}, {c, r, t} ->
        {
          c <> (content || ""),
          r <> (reasoning || ""),
          t
        }
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
