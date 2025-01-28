defmodule Brooklyn.SSE.Parser do
  @moduledoc """
  Parses Server-Sent Events (SSE) messages from a stream.
  Specifically handles the OpenAI chat completion streaming format.
  """

  alias Brooklyn.Types.Delta

  @type parse_result :: 
    {:ok, :done, boolean()} |
    {:ok, Delta.t(), boolean()} |
    {:error, :invalid_json} |
    {:error, :invalid_message}

  @doc """
  Parses a single SSE message.

  ## Examples

      iex> Brooklyn.SSE.Parser.parse_message("data: [DONE]", false)
      {:ok, :done, false}

      iex> Brooklyn.SSE.Parser.parse_message(~s(data: {"choices":[{"delta":{"content":"Hi"}}]}), false)
      {:ok, %Brooklyn.Types.Delta{content: "Hi", reasoning_content: nil}, false}

      iex> Brooklyn.SSE.Parser.parse_message("invalid", false)
      {:error, :invalid_message}
  """

  @doc """
  Parses a chunk of SSE data, handling any leftover data from previous chunks.
  Returns a tuple of {parsed_events, leftover_data}.
  """
  @spec parse_chunk(String.t(), String.t()) :: {[parse_result()], String.t()}
  def parse_chunk(chunk, leftover, in_thinking_mode \\ false) do
    full_chunk = leftover <> chunk
    messages = String.split(full_chunk, "\n\n")
    
    # First pass: parse all messages
    {events, final_thinking} = Enum.reduce(messages, {[], in_thinking_mode}, fn message, {acc, thinking} ->
      case parse_message(message, thinking) do
        {status, result, new_thinking} -> {[{status, result} | acc], new_thinking}
        {:error, _reason} = error -> {[error | acc], thinking}
      end
    end)
    events = Enum.reverse(events)

    # Second pass: check last message and handle leftover
    last_message = List.last(messages)
    last_result = List.last(events)

    case last_result do
      {:error, :invalid_message} -> {Enum.drop(events, -1), last_message, final_thinking}
      _ -> {events, "", final_thinking}
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
      {:error, :invalid_message}
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
            
            delta = if in_thinking_mode do
              Delta.new(nil, content)
            else
              Delta.new(content)
            end
            
            {:ok, delta, next_thinking}
          {:ok, %{"usage" => usage}} when not is_nil(usage) ->
            {:ok, :usage, usage}
          {:error, _} -> 
            {:error, :invalid_json}
        end
      _ -> 
        {:error, :invalid_message}
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
