defmodule Brooklyn.SSEAccumulator do
  defstruct [:callback, leftover: "", accumulated_content: ""]

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
      {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} -> {:ok, content}
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

        new_content = Enum.reduce(events, content, fn
          {:ok, content}, acc when is_binary(content) -> acc <> content
          _, acc -> acc
        end)

        Enum.each(events, cb)
        %{acc | leftover: new_leftover, accumulated_content: new_content}

      (acc, :done) ->
        acc

      (acc, :halt) ->
        acc
    end

    {initial_state, collection_fn}
  end
end
