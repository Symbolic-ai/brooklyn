defmodule Brooklyn.SSE.AccumulatorTest do
  use ExUnit.Case

  alias Brooklyn.SSE.Accumulator

  describe "Collectable implementation" do
    test "accumulates simple content with callbacks" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:callback, chunk}) end
      
      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n",
        "data: {\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":20,\"total_tokens\":30}}\n\n",
        "data: [DONE]\n\n"
      ]

      result = Enum.into(chunks, %Accumulator{callback: callback})

      assert result.content == "Hello world"
      assert result.reasoning_content == ""
      assert result.usage == %Brooklyn.Types.Usage{
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30
      }

      # Assert callbacks were called for each chunk
      Enum.each(chunks, fn chunk ->
        assert_receive {:callback, ^chunk}
      end)
    end

    test "accumulates content with think tags" do
      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Start \"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"<think>\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"thinking process\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"</think>\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" end\"}}]}\n\n",
        "data: {\"usage\":{\"prompt_tokens\":15,\"completion_tokens\":25,\"total_tokens\":40}}\n\n",
        "data: [DONE]\n\n"
      ]

      result = Enum.into(chunks, %Accumulator{})

      assert result.content == "Start  end"
      assert result.reasoning_content == "<think>thinking process</think>"
      assert result.usage == %Brooklyn.Types.Usage{
        prompt_tokens: 15,
        completion_tokens: 25,
        total_tokens: 40
      }
    end

    test "handles incomplete chunks" do
      chunks = [
        "data: {\"cho",
        "ices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: [DONE]\n\n"
      ]

      result = Enum.into(chunks, %Accumulator{})

      assert result.content == "Hello"
      assert result.reasoning_content == ""
    end

    test "handles usage in different positions" do
      # Usage in separate message
      chunks1 = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":1,\"total_tokens\":6}}\n\n",
        "data: [DONE]\n\n"
      ]

      result1 = Enum.into(chunks1, %Accumulator{})
      assert result1.usage == %Brooklyn.Types.Usage{
        prompt_tokens: 5,
        completion_tokens: 1,
        total_tokens: 6
      }

      # Verify we can create a Message from the accumulator result
      message = Brooklyn.Types.Message.new(%{
        role: "assistant",
        content: result1.content,
        reasoning_content: result1.reasoning_content,
        usage: result1.usage
      })
      assert message.usage == result1.usage

      # Multiple usage events (should take last one)
      chunks2 = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":1,\"total_tokens\":6}}\n\n",
        "data: {\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2,\"total_tokens\":7}}\n\n",
        "data: [DONE]\n\n"
      ]

      result2 = Enum.into(chunks2, %Accumulator{})
      assert result2.usage == %Brooklyn.Types.Usage{
        prompt_tokens: 5,
        completion_tokens: 2,
        total_tokens: 7
      }

      # Verify we can create a Message from the accumulator result
      message2 = Brooklyn.Types.Message.new(%{
        role: "assistant",
        content: result2.content,
        reasoning_content: result2.reasoning_content,
        usage: result2.usage
      })
      assert message2.usage == result2.usage
    end
  end
end
