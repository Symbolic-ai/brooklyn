defmodule Mix.Tasks.Brooklyn.Test do
  use Mix.Task

  @requirements ["app.config"]

  @shortdoc "Test Brooklyn chat completion with a provider"
  
  @messages [
    %{role: "system", content: "You are a helpful assistant."},
    %{role: "user", content: "Who do you think would win in a fight - Batman or Gandalf?"}
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [stream: :boolean],
      aliases: [s: :stream]
    )

    case args do
      [provider, model | _] ->
        provider = String.to_atom(provider)
        stream? = Keyword.get(opts, :stream, false)
        
        Application.ensure_all_started(:brooklyn)

        if stream? do
          {provider, model}
          |> Brooklyn.chat_completion(@messages, fn
            {:ok, %Brooklyn.Types.Delta{content: content, reasoning_content: reasoning}} -> 
              if content, do: IO.write(content)
              if reasoning, do: IO.write(reasoning)
            {:ok, :done} -> 
              IO.puts("\n--- Stream finished ---")
            {:ok, %Brooklyn.Types.Usage{} = usage} ->
              IO.puts("\nUsage update: #{inspect(usage)}")
            other -> 
              IO.puts("\nEvent: #{inspect(other)}")
          end)
          |> case do
            {:ok, %Brooklyn.Types.Message{} = msg} -> 
              dbg(msg)
              IO.puts("\nFull message:")
              IO.puts("Role: #{msg.role}")
              IO.puts("Content: #{msg.content}")
              if msg.reasoning_content && msg.reasoning_content != "", do: IO.puts("Reasoning: #{msg.reasoning_content}")
              if msg.usage do
                IO.puts("\nUsage:")
                IO.puts("  Prompt tokens: #{msg.usage.prompt_tokens}")
                IO.puts("  Completion tokens: #{msg.usage.completion_tokens}")
                IO.puts("  Total tokens: #{msg.usage.total_tokens}")
              end
            {:error, reason} -> 
              IO.puts("\nError: #{inspect(reason)}")
          end
        else
          {provider, model}
          |> Brooklyn.chat_completion(@messages)
          |> case do
            {:ok, %Brooklyn.Types.Message{} = msg} -> 
              dbg(msg)
              IO.puts("\nRole: #{msg.role}")
              IO.puts("Content: #{msg.content}")
              if msg.reasoning_content && msg.reasoning_content != "", do: IO.puts("Reasoning: #{msg.reasoning_content}")
              if msg.usage do
                IO.puts("\nUsage:")
                IO.puts("  Prompt tokens: #{msg.usage.prompt_tokens}")
                IO.puts("  Completion tokens: #{msg.usage.completion_tokens}")
                IO.puts("  Total tokens: #{msg.usage.total_tokens}")
              end
            {:error, reason} -> 
              IO.puts("Error: #{inspect(reason)}")
          end
        end

      _ ->
        Mix.raise """
        Usage: mix brooklyn.test provider model [--stream|-s]
        Example: mix brooklyn.test anthropic claude-3 --stream
        """
    end
  end
end
