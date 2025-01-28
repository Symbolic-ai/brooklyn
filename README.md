# Brooklyn

Brooklyn is a flexible client for OpenAI-compatible chat completion APIs. It supports both streaming and non-streaming responses, and works with various providers that implement the OpenAI chat completions API interface.

## Features

- Support for multiple OpenAI-compatible API providers through configuration
- Streaming and non-streaming chat completions
- Structured response types with validation
- Usage tracking and reporting
- Provider-agnostic interface

## Installation

Add `brooklyn` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:brooklyn, "~> 0.1.0"}
  ]
end
```

## Configuration

Brooklyn uses a provider-key based configuration system that allows you to define any number of providers under arbitrary keys. Each provider just needs to implement the OpenAI chat completions API interface.

Configure your providers in `config.exs`:

```elixir
# Standard OpenAI
config :brooklyn, :openai,
  base_url: "https://api.openai.com/v1",
  api_key: System.get_env("OPENAI_API_KEY")

# Azure OpenAI
config :brooklyn, :azure,
  base_url: "https://your-resource.openai.azure.com/openai/deployments/your-deployment",
  api_key: System.get_env("AZURE_OPENAI_API_KEY")

# Any other OpenAI-compatible API
config :brooklyn, :my_provider,
  base_url: "https://api.my-provider.com/v1",
  api_key: System.get_env("MY_PROVIDER_API_KEY")
```

The configuration key (`:openai`, `:azure`, `:my_provider`, etc.) is arbitrary and used only to look up the configuration. It doesn't affect the API interaction - Brooklyn only cares that the provider implements the OpenAI chat completions API interface.

This means you can have multiple configurations for the same provider, or use any provider that implements the OpenAI API interface:

```elixir
# Using different providers
Brooklyn.chat_completion({:openai, "gpt-4"}, messages)
Brooklyn.chat_completion({:azure, "gpt-35-turbo"}, messages)
Brooklyn.chat_completion({:my_provider, "custom-model"}, messages)

# Even multiple configs for the same provider
config :brooklyn, :openai_prod,
  base_url: "https://api.openai.com/v1",
  api_key: System.get_env("OPENAI_PROD_KEY")

config :brooklyn, :openai_dev,
  base_url: "https://api.openai.com/v1",
  api_key: System.get_env("OPENAI_DEV_KEY")

Brooklyn.chat_completion({:openai_prod, "gpt-4"}, messages)
Brooklyn.chat_completion({:openai_dev, "gpt-4"}, messages)
```

## Usage

### Basic Chat Completion

```elixir
messages = [
  %{role: "system", content: "You are a helpful assistant."},
  %{role: "user", content: "What is the capital of France?"}
]

{:ok, response} = Brooklyn.chat_completion({:openai, "gpt-4"}, messages)
IO.puts(response.content)
```

### Streaming Chat Completion

```elixir
Brooklyn.chat_completion({:openai, "gpt-4"}, messages, fn
  {:ok, %{content: content}} when is_binary(content) -> 
    IO.write(content)
  {:ok, :stop} -> 
    IO.puts("\n--- Stream finished ---")
  other -> 
    IO.puts("\nEvent: #{inspect(other)}")
end)
```

## Types

### Message

```elixir
%Brooklyn.Types.Message{
  role: String.t(),         # "system", "user", or "assistant"
  content: String.t(),      # The message content
  reasoning_content: String.t() | nil,  # Optional reasoning/thought process
  usage: Brooklyn.Types.Usage.t() | nil # Token usage information
}
```

### Usage

```elixir
%Brooklyn.Types.Usage{
  prompt_tokens: non_neg_integer(),
  completion_tokens: non_neg_integer(),
  total_tokens: non_neg_integer()
}
```

### Provider

```elixir
%Brooklyn.Provider{
  base_url: String.t(),
  api_key: String.t()
}
```

## Testing

Test the client with the included mix task:

```bash
# Non-streaming
mix brooklyn.test openai gpt-4

# Streaming
mix brooklyn.test openai gpt-4 --stream
```

## License

MIT License. See LICENSE file for details.

