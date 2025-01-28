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

  ## Examples

      iex> chunk = ~s(data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n)
      iex> Brooklyn.SSE.Parser.parse_chunk(chunk, "")
      {[{:ok, %{"choices" => [%{"delta" => %{"content" => "Hello"}}]}}], ""}

      iex> chunk = "data: [DONE]\\n\\n"
      iex> Brooklyn.SSE.Parser.parse_chunk(chunk, "")
      {[{:ok, :done}], ""}

      iex> chunk = ~s(data: {"choices":[{"delta":)
      iex> Brooklyn.SSE.Parser.parse_chunk(chunk, "")
      {[], ~s(data: {"choices":[{"delta":))}
  """
  @spec parse_chunk(String.t(), String.t()) :: {[parse_result()], String.t()}
  def parse_chunk(chunk, leftover) do
    messages = (leftover <> chunk) |> String.split("\n\n", trim: true)
    
    {parsed, last_message} = parse_messages(messages)
    {parsed, last_message}
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

  defp parse_messages(messages) do
    case List.last(messages) do
      nil -> 
        {[], ""}
      last_message ->
        if complete_message?(last_message) do
          {Enum.map(messages, &parse_message/1), ""}
        else
          {messages |> Enum.drop(-1) |> Enum.map(&parse_message/1), last_message}
        end
    end
  end
end
