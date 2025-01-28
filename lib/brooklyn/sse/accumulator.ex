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
    
    # Process all events in order and collect processed events for callback
    {new_acc, processed_events} = Enum.reduce(events, {acc, []}, fn event, {curr_acc, events_acc} ->
      case event do
        {:ok, result, _thinking} -> 
          {process_event(curr_acc, event), [{:ok, result} | events_acc]}
        error -> 
          {curr_acc, [error | events_acc]}
      end
    end)
    
    {%{new_acc | 
      leftover: new_leftover,
      thinking: new_thinking
    }, Enum.reverse(processed_events)}
  end

  defp process_event(acc, {:ok, :done, _thinking}), do: acc
  
  defp process_event(acc, {:ok, %Usage{} = usage, _thinking}) do
    %{acc | usage: usage}
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
        {new_acc, events} = Brooklyn.SSE.Accumulator.process_chunk(acc, chunk)
        if new_acc.callback do
          Enum.each(events, new_acc.callback)
        end
        new_acc
      acc, :done -> acc
      acc, :halt -> acc
    end}
  end
end
