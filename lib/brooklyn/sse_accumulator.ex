defmodule Brooklyn.SSEAccumulator do
  defstruct [:callback, leftover: ""]

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
        {parsed |> Enum.drop(-1) |> Enum.flat_map(fn
          {:ok, :done} -> []
          {:ok, message} -> [message]
          {:error, _} -> []
        end), last_message}
      _ -> 
        {parsed |> Enum.flat_map(fn
          {:ok, :done} -> []
          {:ok, message} -> [message]
          {:error, _} -> []
        end), ""}
    end
  end
end

defimpl Collectable, for: Brooklyn.SSEAccumulator do

  def into(%Brooklyn.SSEAccumulator{} = acc) do
    initial_state = acc
    collection_fn = fn
      (%Brooklyn.SSEAccumulator{leftover: leftover, callback: cb} = acc, {:cont, chunk}) ->
        {events, new_leftover} = Brooklyn.SSEAccumulator.process_chunk(chunk, leftover)

        Enum.each(events, cb)
        %{acc | leftover: new_leftover}

      (acc, :done) ->
        acc

      (acc, :halt) ->
        acc
    end


    {initial_state, collection_fn}
  end
end
