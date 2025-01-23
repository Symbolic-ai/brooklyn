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
          |> Brooklyn.chat_completion(@messages, &IO.inspect/1)
        else
          {provider, model}
          |> Brooklyn.chat_completion(@messages)
          |> case do
            {:ok, response} -> IO.puts(inspect(response, pretty: true))
            {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
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
