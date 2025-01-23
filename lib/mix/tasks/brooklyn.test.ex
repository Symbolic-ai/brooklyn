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
            {:ok, content} when is_binary(content) -> 
              IO.write("#{content}")
            {:ok, :stop} -> 
              IO.puts("\n--- Stream finished ---")
            other -> 
              IO.puts("\nEvent: #{inspect(other)}")
          end)
          |> case do
            {:ok, full_message} -> 
              IO.puts("\nFull message:\n#{inspect(full_message, pretty: true)}")
            {:error, reason} -> 
              IO.puts("\nError: #{inspect(reason)}")
          end
        else
          {provider, model}
          |> Brooklyn.chat_completion(@messages)
          |> case do
            {:ok, %{role: role, content: content}} -> 
              IO.puts("\nRole: #{role}\nContent: #{content}")
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
