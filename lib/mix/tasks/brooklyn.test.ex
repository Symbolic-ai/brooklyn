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
            {:ok, %{content: content, reasoning_content: reasoning}} when is_binary(content) or is_binary(reasoning) -> 
              IO.write("#{reasoning || content}")
            {:ok, :stop} -> 
              IO.puts("\n--- Stream finished ---")
            other -> 
              IO.puts("\nEvent: #{inspect(other)}")
          end)
          |> case do
            {:ok, %{role: role, content: content, reasoning_content: reasoning, usage: usage} = msg} -> 
              dbg(msg)
              IO.puts("\nFull message:")
              IO.puts("Role: #{role}")
              IO.puts("Content: #{content}")
              if reasoning && reasoning != "", do: IO.puts("Reasoning: #{reasoning}")
              if usage do
                IO.puts("\nUsage:")
                IO.puts("  Prompt tokens: #{usage["prompt_tokens"]}")
                IO.puts("  Completion tokens: #{usage["completion_tokens"]}")
                IO.puts("  Total tokens: #{usage["total_tokens"]}")
              end
            {:error, reason} -> 
              IO.puts("\nError: #{inspect(reason)}")
          end
        else
          {provider, model}
          |> Brooklyn.chat_completion(@messages)
          |> case do
            {:ok, %{role: role, content: content, reasoning_content: reasoning, usage: usage} = msg} -> 
              dbg(msg)
              IO.puts("\nRole: #{role}")
              IO.puts("Content: #{content}")
              if reasoning && reasoning != "", do: IO.puts("Reasoning: #{reasoning}")
              if usage do
                IO.puts("\nUsage:")
                IO.puts("  Prompt tokens: #{usage["prompt_tokens"]}")
                IO.puts("  Completion tokens: #{usage["completion_tokens"]}")
                IO.puts("  Total tokens: #{usage["total_tokens"]}")
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
