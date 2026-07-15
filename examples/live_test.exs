Mix.install([{:forcedream, path: "."}])

IO.puts("=== Real signup ===")
signup = ForceDream.signup("elixir-sdk-test-#{System.system_time(:second)}@example.com")
IO.puts("Signed up: user_id=#{signup["user_id"]}, trial_balance=#{signup["trial_balance_gbp"]}")

client = ForceDream.new(api_key: signup["live_key"], account_key: signup["api_key"])

IO.puts("\n=== search_agents (client-side filtered) ===")
results = ForceDream.search_agents(client, query: "extract")
IO.inspect(results)

IO.puts("\n=== invoke (real agent, real charge) ===")
invoke_result =
  ForceDream.invoke(
    client,
    "data-extract-v1",
    "Extract year and location from: The gathering was held in Vienna in 2014."
  )

IO.inspect(invoke_result)

IO.puts("\n=== verify (real Ed25519 proof) ===")
verify_result =
  if invoke_result.task_id do
    ForceDream.verify(client, task_id: invoke_result.task_id)
  else
    nil
  end

IO.inspect(verify_result)

IO.puts("\n=== A2A: register a real agent (uses the sk_fd_ account key) ===")
slug = "elixir-sdk-test-agent-#{System.system_time(:second)}"

register_result =
  ForceDream.register_agent(client, slug, ["data:extraction"],
    price_per_call_pence: 5,
    name: "Elixir SDK Test Agent"
  )

IO.inspect(register_result)

IO.puts("\n=== A2A: clean up -- delete the just-registered test agent ===")
delete_result = ForceDream.delete_agent(client, slug)
IO.inspect(delete_result)
