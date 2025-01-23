defmodule Brooklyn do
  @moduledoc """
  Generic OpenAI-compatible API client.
  """
  
  use Application
  alias Brooklyn.Provider

  @impl true
  def start(_type, _args) do
    {:ok, self()}
  end

  @doc """
  Performs a chat completion request.

  ## Examples

      # Using config
      {:anthropic, "claude-3"} |> Brooklyn.chat_completion([
        %{role: "user", content: "Hello!"}
      ])

      # Using manual config
      {%Brooklyn.Provider{
        base_url: "https://api.anthropic.com/v1",
        api_key: "sk-..."
      }, "claude-3"} |> Brooklyn.chat_completion([%{role: "user", content: "Hello!"}])
  """
  def chat_completion({provider_name, model}, request) when is_atom(provider_name) do
    case Provider.from_config(provider_name) do
      {:ok, provider} -> chat_completion({provider, model}, request)
      {:error, reason} -> {:error, reason}
    end
  end

  def chat_completion({%Provider{} = provider, model}, messages) when is_list(messages) do
    {:ok, 
      Req.post(chat_completion_url(provider),
        json: %{messages: messages, model: model} |> set_stream(false),
        auth: {:bearer, provider.api_key},
        receive_timeout: :infinity
      )}
  end

  @doc """
  Performs a streaming chat completion request.
  Takes a callback function that will be called with each chunk of the response.
  """
  def chat_completion({provider_name, model}, request, callback) when is_atom(provider_name) do
    case Provider.from_config(provider_name) do
      {:ok, provider} -> chat_completion({provider, model}, request, callback)
      {:error, reason} -> {:error, reason}
    end
  end

  def chat_completion({%Provider{} = provider, model}, messages, callback) when is_list(messages) do
    {:ok,
      Req.post(chat_completion_url(provider),
        json: %{messages: messages, model: model} |> set_stream(true),
        auth: {:bearer, provider.api_key},
        receive_timeout: :infinity,
        into: fn {:data, data}, acc ->
          data
          |> parse(provider)
          |> Enum.each(callback)
          
          {:cont, acc}
        end
      )}
  end

  # Private helpers

  defp chat_completion_url(%Provider{base_url: base_url}) do
    "#{base_url}/chat/completions"
  end

  defp set_stream(request, value) do
    request
    |> Map.drop([:stream, "stream"])
    |> Map.put(:stream, value)
  end

  defp parse(chunk, _provider) do
    # TODO: Make parser provider-specific
    chunk
    |> String.split("data: ")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&decode/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode(""), do: nil
  defp decode("[DONE]"), do: nil
  defp decode(data), do: Jason.decode!(data)
end
