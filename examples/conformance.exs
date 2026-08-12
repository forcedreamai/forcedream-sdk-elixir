# Runs the shared ForceDream Verification Specification conformance suite
# against a local mock server. Start the spec repo's harness/mock_server.py first.

api_base = "http://127.0.0.1:8787"

# Cases come from the server, never a literal here. A hardcoded list is a snapshot that
# silently drifts: when the contract gained conf_h and conf_i, every hardcoded harness
# kept running seven cases and reporting green -- validating fixes without testing them.
:inets.start()
:ssl.start()

cases =
  case :httpc.request(:get, {~c"#{api_base}/conformance/cases", []}, [], body_format: :binary) do
    {:ok, {{_, 200, _}, _, body}} ->
      body
      |> Jason.decode!()
      |> Enum.map(fn {id, meta} -> {id, Map.get(meta, "expected")} end)
      |> Enum.sort()

    other ->
      IO.puts(:stderr, "Could not fetch the contract: #{inspect(other)}")
      IO.puts(:stderr, "Start harness/mock_server.py in the conformance repo first.")
      System.halt(2)
  end

if cases == [] do
  IO.puts(:stderr, "INCONCLUSIVE: the server returned no cases.")
  System.halt(2)
end

{passed, failed, errored, verified_true} =
  Enum.reduce(cases, {0, 0, 0, 0}, fn {id, expected}, {p, f, e, vt} ->
    try do
      r = ForceDream.Verify.verify_proof(api_base, task_id: id)

      if r.verified == expected do
        IO.puts("  PASS  #{String.pad_trailing(id, 32)} verified=#{r.verified}")
        {p + 1, f, e, if(r.verified, do: vt + 1, else: vt)}
      else
        IO.puts("  FAIL  #{String.pad_trailing(id, 32)} expected=#{expected} got=#{r.verified}")
        {p, f + 1, e, if(r.verified, do: vt + 1, else: vt)}
      end
    rescue
      ex ->
        IO.puts("  ERROR #{String.pad_trailing(id, 32)} #{inspect(ex)}")
        {p, f, e + 1, vt}
    end
  end)

IO.puts("")
IO.puts("#{passed}/#{length(cases)} passed, #{failed} failed, #{errored} raised")

# Most cases expect false, so an unreachable server or an implementation that rejects
# everything would otherwise report a green partial pass.
if verified_true == 0 do
  IO.puts("INCONCLUSIVE: no case produced a genuine verified=true.")
  System.halt(2)
end

if failed > 0 or errored > 0, do: System.halt(1)
