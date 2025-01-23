defmodule Brooklyn.SSEAccumulator do
  defstruct [
    :callback,
    leftover: "",
    accumulated_content: "",
    accumulated_reasoning_content: ""
  ]

  def process_chunk(chunk, leftover) do
    messages = (leftover <> chunk) |> String.split("\n\n", trim: true)
    
    parsed = Enum.map(messages, fn message ->
      case String.trim(message) do
        "data: [DONE]" -> {:ok, :done}
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
      {:ok, %{"choices" => [%{"delta" => %{}, "finish_reason" => "stop"} | _]}} -> {:ok, :stop}
      {:ok, %{"choices" => [%{"delta" => %{}, "finish_reason" => "length"}]}} -> {:ok, :completion_max_tokens_reached}
      {:ok, %{"choices" => [%{"delta" => delta} | _]}} -> 
        case delta do
          %{"content" => content, "reasoning_content" => reasoning} -> 
            {:ok, %{content: content, reasoning_content: reasoning}}
          %{"content" => content} -> 
            {:ok, %{content: content, reasoning_content: nil}}
          %{"reasoning_content" => reasoning} -> 
            {:ok, %{content: nil, reasoning_content: reasoning}}
          _ -> 
            nil
        end
      {:ok, %{"choices" => [], "usage" => usage}} -> {:ok, {:usage, usage}}
      {:ok, %{"code" => 400}} -> {:error, :prompt_tokens_exceeded}
      {:ok, %{"code" => 429}} -> {:error, :rate_limit}
      {:ok, unknown} -> {:error, {:unknown_response, unknown}}
      {:error, _} -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end

defimpl Collectable, for: Brooklyn.SSEAccumulator do
  def into(%Brooklyn.SSEAccumulator{} = acc) do
    initial_state = acc
    collection_fn = fn
      (%Brooklyn.SSEAccumulator{leftover: leftover, callback: cb, accumulated_content: content} = acc, {:cont, chunk}) ->
        {events, new_leftover} = Brooklyn.SSEAccumulator.process_chunk(chunk, leftover)

        {new_content, new_reasoning_content} = Enum.reduce(events, {content, acc.accumulated_reasoning_content}, fn
          {:ok, %{content: content, reasoning_content: nil}}, {c, r} when is_binary(content) -> {c <> content, r}
          {:ok, %{content: nil, reasoning_content: content}}, {c, r} when is_binary(content) -> {c, r <> content}
          _, acc -> acc
        end)

        Enum.each(events, cb)
        %{acc | 
          leftover: new_leftover, 
          accumulated_content: new_content,
          accumulated_reasoning_content: new_reasoning_content
        }

      (acc, :done) ->
        acc

      (acc, :halt) ->
        acc
    end

    {initial_state, collection_fn}
  end
end
