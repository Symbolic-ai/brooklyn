defmodule Brooklyn.SSE.Parser do
  @moduledoc """
  Parses Server-Sent Events (SSE) messages from a stream.
  Specifically handles the OpenAI chat completion streaming format.
  """

  alias Brooklyn.Types.Delta

  @type parse_result :: 
    {:ok, :done, boolean()} |
    {:ok, Delta.t(), boolean()} |
    {:error, :invalid_json, String.t()} |
    {:error, :invalid_message, String.t()}

  @doc """
  Parses a single SSE message.

  ## Examples

      iex> Brooklyn.SSE.Parser.parse_message("data: [DONE]", false)
      {:ok, :done, false}

      iex> Brooklyn.SSE.Parser.parse_message(~s(data: {"choices":[{"delta":{"content":"Hi"}}]}), false)
      {:ok, %Brooklyn.Types.Delta{content: "Hi", reasoning_content: nil}, false}

      iex> Brooklyn.SSE.Parser.parse_message("invalid", false)
      {:error, :invalid_message, "invalid"}
  """

  @doc """
  Parses a chunk of SSE data, handling any leftover data from previous chunks.
  Returns a tuple of {parsed_events, leftover_data}.
  """
  @spec parse_chunk(String.t(), String.t()) :: {[parse_result()], String.t()}
  def parse_chunk(chunk, leftover, in_thinking_mode \\ false) do
    full_chunk = leftover <> chunk
    messages = full_chunk
        |> String.split("\n\n")
        |> Enum.reject(&(String.trim(&1) == ""))
    
    # First pass: parse all messages
    {events, final_thinking} = Enum.reduce(messages, {[], in_thinking_mode}, fn message, {acc, thinking} ->
      case parse_message(message, thinking) do
        {:ok, result, new_thinking} -> {[{:ok, result, new_thinking} | acc], new_thinking}
        {:error, reason, msg} -> {[{:error, reason, msg} | acc], thinking}
      end
    end)
    events = Enum.reverse(events)
    dbg(events)

    # Check if last message was an error and use its content as leftover
    case List.last(events) do
      {:error, :invalid_json, msg} -> 
        {Enum.reject(Enum.drop(events, -1), &match?({:error, _, _}, &1)), msg, final_thinking}
      _ -> 
        {Enum.reject(events, &match?({:error, _, _}, &1)), "", final_thinking}
    end
  end

  @doc """
  Parses a single SSE message.

  ## Examples

      iex> Brooklyn.SSE.Parser.parse_message("data: [DONE]", false)
      {:ok, :done, false}

      iex> Brooklyn.SSE.Parser.parse_message(~s(data: {"choices":[{"delta":{"content":"Hi"}}]}), false)
      {:ok, %Brooklyn.Types.Delta{content: "Hi", reasoning_content: nil}, false}

      iex> Brooklyn.SSE.Parser.parse_message("invalid", false)
      {:error, :invalid_message, "invalid"}
  """
  @spec parse_message(String.t(), boolean()) :: parse_result()
  def parse_message(message, in_thinking_mode) do
    case String.trim(message) do
      "data: [DONE]" -> 
        {:ok, :done, in_thinking_mode}
      "data: " <> data ->
        case Jason.decode(data) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} ->
            next_thinking = cond do
              String.contains?(content, "<think>") -> true
              String.contains?(content, "</think>") -> false
              true -> in_thinking_mode
            end
            
            # If the content contains think tags, it's reasoning content
            delta = if String.contains?(content, "<think>") or String.contains?(content, "</think>") do
              Delta.new(nil, content)
            else
              if in_thinking_mode do
                Delta.new(nil, content)
              else
                Delta.new(content)
              end
            end
            
            {:ok, delta, next_thinking}
          {:ok, %{"usage" => usage}} when not is_nil(usage) ->
            {:ok, :usage, usage}
          {:error, _} -> 
            {:error, :invalid_json, message}
        end
      _ -> 
        {:error, :invalid_message, message}
    end
  end

  @doc """
  Determines if a message is complete and can be parsed.

  """
  @spec complete_message?(String.t()) :: boolean()
  def complete_message?(message) do
    String.ends_with?(message, "\n\n")
  end

  # Private Functions

end
