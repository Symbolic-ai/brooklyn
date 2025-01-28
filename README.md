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

Configure your providers in `config.exs`:

```elixir
config :brooklyn, :openai,
  base_url: "https://api.openai.com/v1",
  api_key: System.get_env("OPENAI_API_KEY")

config :brooklyn, :azure_openai,
  base_url: "https://your-resource.openai.azure.com/openai/deployments/your-deployment",
  api_key: System.get_env("AZURE_OPENAI_API_KEY")
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

