defmodule Brooklyn.Provider do
  @moduledoc """
  Provider configuration struct for OpenAI-compatible APIs.
  
  Providers are configured with:
  - base_url: The API endpoint base URL
  - api_key: Authentication key for the API
  """

  @enforce_keys [:base_url, :api_key]
  defstruct [:base_url, :api_key]

  @type t :: %__MODULE__{
    base_url: String.t(),
    api_key: String.t()
  }

  @doc """
  Creates a new provider configuration from application config.
  """
  def from_config(provider_name) when is_atom(provider_name) do
    case Application.get_env(:brooklyn, provider_name) do
      nil -> 
        {:error, "Provider #{provider_name} not configured"}
      config when is_list(config) ->
        {:ok, struct!(__MODULE__, config)}
      _ ->
        {:error, "Invalid configuration for provider #{provider_name}"}
    end
  end
end
