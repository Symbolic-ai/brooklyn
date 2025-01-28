defmodule Brooklyn.Types.Delta do
  @moduledoc """
  Represents a chunk of content from a streaming response.
  May contain regular content and/or reasoning content.
  """

  @type t :: %__MODULE__{
    content: String.t() | nil,
    reasoning_content: String.t() | nil
  }

  defstruct [:content, :reasoning_content]

  def new(content \\ nil, reasoning_content \\ nil) do
    %__MODULE__{
      content: content,
      reasoning_content: reasoning_content
    }
  end
end

