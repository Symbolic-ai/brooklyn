defmodule Brooklyn.SSEAccumulator do
  defstruct [
    :callback,
    :usage,
    leftover: "",
    accumulated_content: "",
    accumulated_reasoning_content: "",
    in_think_tags: false
  ]

  def process_chunk(chunk, leftover) do
    messages = (leftover <> chunk) |> String.split("\n\n", trim: true)
    
    parsed = Enum.map(messages, fn message ->
      case String.trim(message) do
        "data: [DONE]" -> 
          {:ok, :done}
        "data: " <> data ->
          case Jason.decode(data) do
            {:ok, parsed} -> {:ok, parsed}
            _ -> {:error, message}
          end
        _ -> {:error, message}
      end
    end)
    
    case List.last(parsed) do
      {:error, last_message} -> 
        {parsed |> Enum.drop(-1) |> process_events(), last_message}
      _ -> 
        {parsed |> process_events(), ""}
    end
  end

  defp process_events(events) do
    events
    |> Enum.map(fn
      {:ok, :done} -> {:ok, :stop}
      {:ok, %{"usage" => usage} = _msg} when not is_nil(usage) -> 
        {:ok, {:usage, Brooklyn.Types.Usage.from_map(usage)}}
      {:ok, %{"choices" => [%{"delta" => %{}, "finish_reason" => "stop"} | _]}} -> {:ok, :stop}
      {:ok, %{"choices" => [%{"delta" => %{}, "finish_reason" => "length"}]}} -> {:ok, :completion_max_tokens_reached}
      {:ok, %{"choices" => [%{"delta" => %{"content" => content} = delta} | _]}} -> 
        cond do
          String.contains?(content, "<think>") and String.contains?(content, "</think>") ->
            # Complete think tag in one chunk
            {content_parts, reasoning} = extract_think_content(content)
            {:ok, %{content: content_parts, reasoning_content: reasoning, think_state: :none}}
          String.contains?(content, "<think>") ->
            # Start of think tag
            content_before = String.split(content, "<think>") |> hd()
            {:ok, %{content: content_before, reasoning_content: nil, think_state: :start}}
          String.contains?(content, "</think>") ->
            # End of think tag
            [reasoning | rest] = String.split(content, "</think>")
            {:ok, %{content: Enum.join(rest), reasoning_content: reasoning, think_state: :end}}
          true ->
            # Regular content or within think tags - let accumulator decide based on state
            {:ok, %{content: content, reasoning_content: nil, think_state: :continue}}
        end
      {:ok, %{"choices" => [%{"delta" => delta} | _]}} -> 
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
      [before, thinking, after] -> {before <> after, thinking}
      [before, thinking] -> {before, thinking}
      [thinking] -> {"", thinking}
      _ -> {content, ""}
    end
  end
end

defimpl Collectable, for: Brooklyn.SSEAccumulator do
  def into(%Brooklyn.SSEAccumulator{} = acc) do
    initial_state = acc
    collection_fn = fn
      (%Brooklyn.SSEAccumulator{leftover: leftover, callback: cb, accumulated_content: content} = acc, {:cont, chunk}) ->
        {events, new_leftover} = Brooklyn.SSEAccumulator.process_chunk(chunk, leftover)

        {new_content, new_reasoning_content, new_in_think} = Enum.reduce(events, {content, acc.accumulated_reasoning_content, acc.in_think_tags}, fn
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

        new_usage = Enum.reduce(events, acc.usage, fn
          {:ok, {:usage, usage}}, _ -> 
            # Convert struct to map for later embedding
            usage |> Map.from_struct() |> Map.take([:prompt_tokens, :completion_tokens, :total_tokens])
          _, curr_usage -> curr_usage
        end)

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
