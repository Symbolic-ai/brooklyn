defmodule Brooklyn.SSEAccumulatorTest do
  use ExUnit.Case

  alias Brooklyn.SSEAccumulator

  describe "Collectable implementation" do
    test "accumulates simple content with callbacks" do
      # Set up test process to receive callbacks
      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end
      
      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":20,\"total_tokens\":30}}\n\n"
      ]

      result = Enum.into(chunks, %SSEAccumulator{callback: callback})

      # Assert final accumulator state
      assert result.accumulated_content == "Hello world"
      assert result.accumulated_reasoning_content == ""
      assert result.usage == %{
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      }

      # Assert callbacks were called in order
      assert_receive {:callback, {:ok, %{content: "Hello", reasoning_content: nil, think_state: :continue}}}, 100
      assert_receive {:callback, {:ok, %{content: " world", reasoning_content: nil, think_state: :continue}}}, 100
      assert_receive {:callback, {:ok, {:usage, %Brooklyn.Types.Usage{
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      }}}}, 100
      assert_receive {:callback, {:ok, :stop}}, 100
    end

    test "accumulates content with think tags" do
      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end
      
      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Start \"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"<think>\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"thinking process\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"</think>\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" end\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":15,\"completion_tokens\":25,\"total_tokens\":40}}\n\n"
      ]

      result = Enum.into(chunks, %SSEAccumulator{callback: callback})

      # Assert final accumulator state
      assert result.accumulated_content == "Start  end"
      assert result.accumulated_reasoning_content == "thinking process"
      assert result.usage == %{
        prompt_tokens: 15,
        completion_tokens: 25,
        total_tokens: 40
      }

      # Assert callbacks were called in order
      assert_receive {:callback, {:ok, %{content: "Start ", reasoning_content: nil, think_state: :continue}}}, 100
      assert_receive {:callback, {:ok, %{content: "", reasoning_content: nil, think_state: :start}}}, 100
      assert_receive {:callback, {:ok, %{content: "thinking process", reasoning_content: nil, think_state: :continue}}}, 100
      assert_receive {:callback, {:ok, %{content: " end", reasoning_content: "thinking process", think_state: :end}}}, 100
      assert_receive {:callback, {:ok, {:usage, %Brooklyn.Types.Usage{
        prompt_tokens: 15,
        completion_tokens: 25,
        total_tokens: 40
      }}}}, 100
      assert_receive {:callback, {:ok, :stop}}, 100
    end

    test "handles complete think tag in single chunk" do
      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end
      
      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Before <think>reasoning</think> after\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":10,\"total_tokens\":15}}\n\n"
      ]

      result = Enum.into(chunks, %SSEAccumulator{callback: callback})

      assert result.accumulated_content == "Before  after"
      assert result.accumulated_reasoning_content == "reasoning"
      
      assert_receive {:callback, {:ok, %{content: "Before  after", reasoning_content: "reasoning", think_state: :none}}}, 100
      assert_receive {:callback, {:ok, {:usage, %Brooklyn.Types.Usage{
        prompt_tokens: 5,
        completion_tokens: 10,
        total_tokens: 15
      }}}}, 100
      assert_receive {:callback, {:ok, :stop}}, 100
    end

    test "handles incomplete chunks" do
      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end
      
      chunks = [
        "data: {\"cho",
        "ices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
      ]

      result = Enum.into(chunks, %SSEAccumulator{callback: callback})

      assert result.accumulated_content == "Hello"
      assert result.accumulated_reasoning_content == ""
      
      assert_receive {:callback, {:ok, %{content: "Hello", reasoning_content: nil, think_state: :continue}}}, 100
      assert_receive {:callback, {:ok, :stop}}, 100
    end

    test "handles usage in different message positions" do
      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end
      
      # Usage in empty message
      chunks1 = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{}}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":1,\"total_tokens\":6}}\n\n"
      ]

      result1 = Enum.into(chunks1, %SSEAccumulator{callback: callback})
      assert result1.usage == %{prompt_tokens: 5, completion_tokens: 1, total_tokens: 6}
      
      # Usage in stop message
      chunks2 = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":1,\"total_tokens\":6}}\n\n"
      ]

      result2 = Enum.into(chunks2, %SSEAccumulator{callback: callback})
      assert result2.usage == %{prompt_tokens: 5, completion_tokens: 1, total_tokens: 6}

      # Multiple usage events (should take last one)
      chunks3 = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":1,\"total_tokens\":6}}\n\n",
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2,\"total_tokens\":7}}\n\n"
      ]

      result3 = Enum.into(chunks3, %SSEAccumulator{callback: callback})
      assert result3.usage == %{prompt_tokens: 5, completion_tokens: 2, total_tokens: 7}
    end
  end
end
