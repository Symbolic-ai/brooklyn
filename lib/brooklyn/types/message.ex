defmodule Brooklyn.Types.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :role, :string
    field :content, :string
    field :reasoning_content, :string, default: ""
    embeds_one :usage, Brooklyn.Types.Usage
  end

  def changeset(message \\ %__MODULE__{}, attrs) do
    # Handle usage struct in attrs
    attrs = if is_struct(attrs.usage, Brooklyn.Types.Usage) do
      Map.update!(attrs, :usage, &Map.from_struct/1)
    else
      attrs
    end

    message
    |> cast(attrs, [:role, :content, :reasoning_content])
    |> validate_required([:role, :content])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
    |> cast_embed(:usage, required: false, with: &Brooklyn.Types.Usage.changeset/2)
  end

  def new(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_changes()
  end

  def new(role, content, opts \\ []) do
    new(%{
      role: role,
      content: content,
      reasoning_content: Keyword.get(opts, :reasoning_content, ""),
      usage: Keyword.get(opts, :usage)
    })
  end
end
