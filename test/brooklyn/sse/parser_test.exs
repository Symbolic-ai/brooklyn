defmodule Brooklyn.SSE.ParserTest do
  use ExUnit.Case
  doctest Brooklyn.SSE.Parser

  alias Brooklyn.SSE.Parser

  describe "parse_chunk/2" do
    test "handles complete messages" do
      chunk = """
      data: {"choices":[{"delta":{"content":"Hello"}}]}

      data: {"choices":[{"delta":{"content":" World"}}]}

      """
      
      {events, leftover} = Parser.parse_chunk(chunk, "")
      assert leftover == ""
      assert events == [
        {:ok, %{"choices" => [%{"delta" => %{"content" => "Hello"}}]}},
        {:ok, %{"choices" => [%{"delta" => %{"content" => " World"}}]}}
      ]
    end

    test "handles incomplete messages" do
      chunk1 = "data: {\"choices\":[{\"delta\":"
      {events1, leftover1} = Parser.parse_chunk(chunk1, "")
      assert events1 == []
      assert leftover1 == chunk1

      chunk2 = "{\"content\":\"Hello\"}}]}\n\n"
      {events2, leftover2} = Parser.parse_chunk(chunk2, leftover1)
      assert leftover2 == ""
      assert events2 == [
        {:ok, %{"choices" => [%{"delta" => %{"content" => "Hello"}}]}}
      ]
    end

    test "handles [DONE] message" do
      chunk = "data: [DONE]\n\n"
      {events, leftover} = Parser.parse_chunk(chunk, "")
      assert leftover == ""
      assert events == [{:ok, :done}]
    end

    test "handles invalid JSON" do
      chunk = "data: {invalid_json}\n\n"
      {events, leftover} = Parser.parse_chunk(chunk, "")
      assert leftover == ""
      assert events == [{:error, :invalid_json}]
    end

    test "handles invalid message format" do
      chunk = "invalid: message\n\n"
      {events, leftover} = Parser.parse_chunk(chunk, "")
      assert leftover == ""
      assert events == [{:error, :invalid_message}]
    end
  end

  describe "parse_message/1" do
    test "parses valid JSON message" do
      message = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
      assert Parser.parse_message(message) == 
        {:ok, %{"choices" => [%{"delta" => %{"content" => "Hello"}}]}}
    end

    test "parses [DONE] message" do
      assert Parser.parse_message("data: [DONE]") == {:ok, :done}
    end

    test "handles invalid JSON" do
      assert Parser.parse_message("data: {invalid}") == {:error, :invalid_json}
    end

    test "handles invalid message format" do
      assert Parser.parse_message("invalid") == {:error, :invalid_message}
    end
  end
end
