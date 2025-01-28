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
      
      {events, leftover, thinking} = Parser.parse_chunk(chunk, "")
      assert leftover == ""
      assert thinking == false
      assert events == [
        {:ok, %Brooklyn.Types.Delta{content: "Hello", reasoning_content: nil}, false},
        {:ok, %Brooklyn.Types.Delta{content: " World", reasoning_content: nil}, false}
      ]
    end

    test "handles thinking mode" do
      chunk = """
      data: {"choices":[{"delta":{"content":"<think>"}}]}

      data: {"choices":[{"delta":{"content":"thinking..."}}]}

      data: {"choices":[{"delta":{"content":"</think>"}}]}

      """
      
      {events, leftover, thinking} = Parser.parse_chunk(chunk, "")
      assert leftover == ""
      assert thinking == false
      assert events == [
        {:ok, %Brooklyn.Types.Delta{content: nil, reasoning_content: "<think>"}, true},
        {:ok, %Brooklyn.Types.Delta{content: nil, reasoning_content: "thinking..."}, true},
        {:ok, %Brooklyn.Types.Delta{content: nil, reasoning_content: "</think>"}, false}
      ]
    end

    test "handles invalid json as leftover data" do
      chunk1 = "data: {\"choices\":[{\"delta\":"
      {events1, leftover1, thinking1} = Parser.parse_chunk(chunk1, "")
      assert events1 == []
      assert leftover1 == "data: {\"choices\":[{\"delta\":"
      assert thinking1 == false

      chunk2 = "{\"content\":\"Hello\"}}]}\n\n"
      {events2, leftover2, thinking2} = Parser.parse_chunk(chunk2, leftover1)
      assert leftover2 == ""
      assert thinking2 == false
      assert events2 == [
        {:ok, %Brooklyn.Types.Delta{content: "Hello", reasoning_content: nil}, false}
      ]
    end

    test "handles [DONE] message" do
      chunk = "data: [DONE]\n\n"
      {events, leftover, _thinking} = Parser.parse_chunk(chunk, "")
      assert leftover == ""
      assert events == [{:ok, :done, false}]
    end

    test "handles invalid JSON" do
      chunk = "data: {invalid_json}\n\n"
      {events, leftover, thinking} = Parser.parse_chunk(chunk, "")
      assert events == []
      assert leftover == "data: {invalid_json}"
      assert thinking == false
    end

    test "handles invalid message format" do
      chunk = "invalid: message\n\n"
      {events, leftover, _thikning} = Parser.parse_chunk(chunk, "")
      assert leftover == ""
      assert events == []
    end

    test "handles complex multi-chunk response with thinking" do
      chunk1 = """
      data: {"choices":[{"delta":{"content":"Let me "}}]}

      data: {"choices":[{"delta":{"content":"help you. "}}]}

      data: {"choices":[{"delta":{"content":"<think>First, I should "}}]}

      """

      chunk2 = """
      data: {"choices":[{"delta":{"content":"consider the best "}}]}

      data: {"choices":[{"delta":{"content":"approach</think>"}}]}

      data: {"choices":[{"delta":{"content":"Based on my "}}]}

      """

      chunk3 = """
      data: {"choices":[{"delta":{"content":"analysis, "}}]}

      data: {"choices":[{"delta":{"content":"<think>double checking"}}]}

      data: {"choices":[{"delta":{"content":"</think>here's what "}}]}

      data: {"choices":[{"delta":{"content":"I found."}}]}

      """

      # Process first chunk
      {events1, leftover1, thinking1} = Parser.parse_chunk(chunk1, "")
      assert leftover1 == ""
      assert thinking1 == true
      assert events1 == [
        {:ok, %Brooklyn.Types.Delta{content: "Let me ", reasoning_content: nil}, false},
        {:ok, %Brooklyn.Types.Delta{content: "help you. ", reasoning_content: nil}, false},
        {:ok, %Brooklyn.Types.Delta{content: nil, reasoning_content: "<think>First, I should "}, true}
      ]

      # Process second chunk
      {events2, leftover2, thinking2} = Parser.parse_chunk(chunk2, leftover1)
      assert leftover2 == ""
      assert thinking2 == false
      assert events2 == [
        {:ok, %Brooklyn.Types.Delta{content: nil, reasoning_content: "consider the best "}, true},
        {:ok, %Brooklyn.Types.Delta{content: nil, reasoning_content: "approach</think>"}, false},
        {:ok, %Brooklyn.Types.Delta{content: "Based on my "}, false}
      ]

      # Process third chunk
      {events3, leftover3, thinking3} = Parser.parse_chunk(chunk3, leftover2)
      assert leftover3 == ""
      assert thinking3 == false
      assert events3 == [
        {:ok, %Brooklyn.Types.Delta{content: "analysis, ", reasoning_content: nil}, false},
        {:ok, %Brooklyn.Types.Delta{content: nil, reasoning_content: "<think>double checking"}, true},
        {:ok, %Brooklyn.Types.Delta{content: nil, reasoning_content: "</think>here's what "}, false},
        {:ok, %Brooklyn.Types.Delta{content: "I found."}, false}
      ]
    end
  end

  describe "parse_message/2" do
    test "parses valid JSON message" do
      message = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
      assert Parser.parse_message(message, false) == 
        {:ok, %Brooklyn.Types.Delta{content: "Hello", reasoning_content: nil}, false}
    end

    test "parses [DONE] message" do
      assert Parser.parse_message("data: [DONE]", false) == {:ok, :done, false}
    end

    test "handles invalid JSON" do
      assert Parser.parse_message("data: {invalid}", false) == {:error, :invalid_json, "data: {invalid}"}
    end

    test "handles invalid message format" do
      assert Parser.parse_message("invalid", false) == {:error, :invalid_message, "invalid"}
    end
  end
end
