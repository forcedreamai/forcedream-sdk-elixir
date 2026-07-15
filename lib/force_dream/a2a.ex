defmodule ForceDream.A2A do
  @moduledoc """
  Real A2A (agent-to-agent) bindings -- lets a developer register their own agent on the
  real A2A network (making it discoverable and invokable by others, earning them revenue
  when invoked) and invoke other registered agents. Endpoint shapes confirmed directly
  against the real backend source (api/server.ts) earlier tonight, ported here from that
  same verified source -- not re-guessed for Elixir.

  Uses a real, different credential from FD_LIVE_KEY/invoke(): these four endpoints all
  authenticate via the backend's resolveUserId(), which requires an sk_fd_... account key
  specifically -- confirmed directly, not assumed (the same class of key-type mismatch
  already caught and fixed once elsewhere tonight). Passing an fd_live_ key here will fail
  auth.
  """

  alias ForceDream.Http

  def register_agent(api_base, account_key, agent_slug, capabilities, opts \\ []) do
    body =
      %{agent_slug: agent_slug, capabilities: capabilities}
      |> maybe_put(:price_per_call_pence, Keyword.get(opts, :price_per_call_pence))
      |> maybe_put(:name, Keyword.get(opts, :name))
      |> maybe_put(:description, Keyword.get(opts, :description))
      |> maybe_put(:version, Keyword.get(opts, :version))
      |> maybe_put(:recommends, Keyword.get(opts, :recommends))

    Http.post("#{api_base}/v1/a2a/register-agent", body, account_key)
  end

  def delete_agent(api_base, account_key, agent_slug) do
    Http.post("#{api_base}/v1/a2a/delete-agent", %{agent_slug: agent_slug}, account_key)
  end

  def invoke(api_base, account_key, target_agent, payload, opts \\ []) do
    body =
      %{target_agent: target_agent, payload: payload, task_type: Keyword.get(opts, :task_type, "general")}
      |> maybe_put(:amount_pence, Keyword.get(opts, :amount_pence))
      |> maybe_put(:idempotency_key, Keyword.get(opts, :idempotency_key))
      |> maybe_put(:fx_quote_id, Keyword.get(opts, :fx_quote_id))

    Http.post("#{api_base}/v1/a2a/invoke", body, account_key)
  end

  def poll_result(api_base, account_key, invoke_id) do
    Http.get("#{api_base}/v1/a2a/result/#{invoke_id}", account_key)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
