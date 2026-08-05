# Runs the shared ForceDream Verification Specification conformance suite
# against a local mock server. Start the spec repo's harness/mock_server.py first.

api_base = "http://127.0.0.1:8787"

cases = [
  {"conf_a_real_batched", true},
  {"conf_b_real_batched", true},
  {"conf_c_bad_signature", false},
  {"conf_d_bad_payload", false},
  {"conf_e_bad_algorithm", false},
  {"conf_f_siblings_wrong_root", false},
  {"conf_g_missing_root", false}
]

{passed, failed, errored} =
  Enum.reduce(cases, {0, 0, 0}, fn {id, expected}, {p, f, e} ->
    try do
      r = ForceDream.Verify.verify_proof(api_base, task_id: id)

      if r.verified == expected do
        IO.puts("  PASS  #{String.pad_trailing(id, 32)} verified=#{r.verified}")
        {p + 1, f, e}
      else
        IO.puts("  FAIL  #{String.pad_trailing(id, 32)} expected=#{expected} got=#{r.verified}")
        {p, f + 1, e}
      end
    rescue
      ex ->
        IO.puts("  ERROR #{String.pad_trailing(id, 32)} #{inspect(ex)}")
        {p, f, e + 1}
    end
  end)

IO.puts("")
IO.puts("#{passed}/#{length(cases)} passed, #{failed} failed, #{errored} raised")
if failed > 0 or errored > 0, do: System.halt(1)
