defmodule Brooklyn.Types.MessageTest do
  use ExUnit.Case
  alias Brooklyn.Types.Message

  test "extracts thinking content from content when reasoning_content is not provided" do
    message = Message.new(%{
      role: "assistant",
      content: "Hello! <think>I should be polite</think> How are you?"
    })

    assert message.content == "Hello!  How are you?"
    assert message.reasoning_content == "<think>I should be polite</think>"
  end

  test "preserves existing reasoning_content when provided" do
    message = Message.new(%{
      role: "assistant",
      content: "Hello! <think>I should be polite</think> How are you?",
      reasoning_content: "Some existing reasoning"
    })

    assert message.content == "Hello! <think>I should be polite</think> How are you?"
    assert message.reasoning_content == "Some existing reasoning"
  end
end
