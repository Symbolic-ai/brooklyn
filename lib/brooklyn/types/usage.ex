defmodule Brooklyn.Types.Usage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :total_tokens, :integer
  end

  def changeset(usage \\ %__MODULE__{}, attrs) do
    usage
    |> cast(attrs, [:prompt_tokens, :completion_tokens, :total_tokens])
    |> validate_required([:prompt_tokens, :completion_tokens, :total_tokens])
    |> validate_number(:prompt_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:completion_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:total_tokens, greater_than_or_equal_to: 0)
  end

  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_changes()
  end
end
