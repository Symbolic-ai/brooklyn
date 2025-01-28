defmodule Brooklyn.SSE.Accumulator do
  @moduledoc """
  Accumulates SSE events into a final message, handling content, reasoning content, and usage.
  """

  alias Brooklyn.Types.{Delta, Usage}

  defstruct [
    :callback,
    :usage,
    content: "",
    reasoning_content: "",
    leftover: "",
    thinking: false
  ]

  def process_chunk(%__MODULE__{} = acc, chunk) do
    {events, new_leftover, new_thinking} = Brooklyn.SSE.Parser.parse_chunk(chunk, acc.leftover, acc.thinking)
    
    # Process all events in order
    new_acc = Enum.reduce(events, acc, &process_event(&2, &1))
    
    %{new_acc | 
      leftover: new_leftover,
      thinking: new_thinking
    }
  end

  defp process_event(acc, {:ok, :done, _thinking}), do: acc
  
  defp process_event(acc, {:ok, {:usage, usage}, _thinking}) do
    %{acc | usage: Usage.from_map(usage)}
  end
  
  defp process_event(acc, {:ok, %Delta{content: content, reasoning_content: reasoning}, _thinking}) do
    %{acc |
      content: acc.content <> (content || ""),
      reasoning_content: acc.reasoning_content <> (reasoning || "")
    }
  end
end

defimpl Collectable, for: Brooklyn.SSE.Accumulator do
  def into(acc) do
    {acc, fn
      acc, {:cont, chunk} ->
        new_acc = Brooklyn.SSE.Accumulator.process_chunk(acc, chunk)
        if new_acc.callback, do: new_acc.callback.(chunk)
        new_acc
      acc, :done -> acc
      acc, :halt -> acc
    end}
  end
end
