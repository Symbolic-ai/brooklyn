defmodule Brooklyn.SSE.Parser do
  @moduledoc """
  Parses Server-Sent Events (SSE) messages from a stream.
  Specifically handles the OpenAI chat completion streaming format.
  """

  @type parse_result :: 
    {:ok, :done} |
    {:ok, map()} |
    {:error, :invalid_json} |
    {:error, :invalid_message}

  @doc """
  Parses a chunk of SSE data, handling any leftover data from previous chunks.
  Returns a tuple of {parsed_events, leftover_data}.
  """
  @spec parse_chunk(String.t(), String.t()) :: {[parse_result()], String.t()}
  def parse_chunk(chunk, leftover) do
    full_chunk = leftover <> chunk
    case String.split(full_chunk, "\n\n", parts: 2) do
      [single] -> {[], single}
      [message, rest] ->
        {more_events, final_leftover} = parse_chunk(rest, "")
        {[parse_message(message) | more_events], final_leftover}
    end
  end

  @doc """
  Parses a single SSE message.

  ## Examples

      iex> Brooklyn.SSE.Parser.parse_message("data: [DONE]")
      {:ok, :done}

      iex> Brooklyn.SSE.Parser.parse_message(~s(data: {"choices":[{"delta":{"content":"Hi"}}]}))
      {:ok, %{"choices" => [%{"delta" => %{"content" => "Hi"}}]}}

      iex> Brooklyn.SSE.Parser.parse_message("invalid")
      {:error, :invalid_message}
  """
  @spec parse_message(String.t()) :: parse_result()
  def parse_message(message) do
    case String.trim(message) do
      "data: [DONE]" -> 
        {:ok, :done}
      "data: " <> data ->
        case Jason.decode(data) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, :invalid_json}
        end
      _ -> 
        {:error, :invalid_message}
    end
  end

  @doc """
  Determines if a message is complete and can be parsed.

  ## Examples

      iex> Brooklyn.SSE.Parser.complete_message?(~s(data: {"complete": true}\n\n))
      true

      iex> Brooklyn.SSE.Parser.complete_message?(~s(data: {"incomplete":))
      false
  """
  @spec complete_message?(String.t()) :: boolean()
  def complete_message?(message) do
    String.ends_with?(message, "\n\n")
  end

  # Private Functions

end
