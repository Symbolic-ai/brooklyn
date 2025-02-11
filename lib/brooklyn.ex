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
    case Req.post(chat_completion_url(provider),
      json: %{messages: messages, model: model} |> set_stream(false),
      auth: {:bearer, provider.api_key},
      receive_timeout: :infinity
    ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => message} | _], "usage" => usage} = _body}} -> 
        {:ok, Brooklyn.Types.Message.new(%{
          role: message["role"],
          content: message["content"],
          reasoning_content: message["reasoning_content"] || "",
          usage: usage
        })}
      error -> 
        {:error, error}
    end
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
    accumulator = %Brooklyn.SSE.Accumulator{callback: callback}
    
    case Req.post(chat_completion_url(provider),
      json: %{messages: messages, model: model} |> set_stream(true),
      auth: {:bearer, provider.api_key},
      receive_timeout: :infinity,
      into: accumulator
    ) do
      {:ok, %{status: 200} = resp} -> 
        {:ok, Brooklyn.Types.Message.new(%{
          role: "assistant",
          content: resp.body.content,
          reasoning_content: resp.body.reasoning_content,
          usage: resp.body.usage
        })}
      error -> 
        {:error, error}
    end
  end

  # Private helpers

  defp chat_completion_url(%Provider{base_url: base_url}) do
    "#{base_url}/chat/completions"
  end

  defp set_stream(request, true) do
    request
    |> Map.drop([:stream, "stream"])
    |> Map.put(:stream, true)
    |> Map.put(:stream_options, %{include_usage: true})
  end

  defp set_stream(request, false) do
    request
    |> Map.drop([:stream, "stream"])
    |> Map.put(:stream, false)
  end
end
