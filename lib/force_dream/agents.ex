defmodule ForceDream.Agents do
  @moduledoc """
  Ported precisely from @forcedream/mcp-server's search_agents.ts (via the same logic
  already proven in every other SDK tonight). Real, load-bearing fact confirmed directly
  from that source in earlier work tonight, not assumed here: the server has no working
  server-side capability/query filter on /v1/agents/list -- filtering must happen
  client-side, after fetching the full list. Also merges in real reliability data from the
  separate /v1/agents/reliability endpoint, exactly as every other SDK does.
  """

  alias ForceDream.Http

  def search_agents_filtered(api_base, opts \\ []) do
    capability = Keyword.get(opts, :capability)
    query = Keyword.get(opts, :query)

    data = Http.get("#{api_base}/v1/agents/list")
    agents = Map.get(data, "agents", [])

    reliability_by_slug =
      try do
        rel_data = Http.get("#{api_base}/v1/agents/reliability")

        (Map.get(rel_data, "agents") || [])
        |> Enum.filter(&(Map.get(&1, "agent_slug") && Map.get(&1, "reliability")))
        |> Map.new(&{Map.get(&1, "agent_slug"), Map.get(&1, "reliability")})
      rescue
        _ -> %{}
      end

    agents =
      if capability do
        cap_lower = String.downcase(capability)

        Enum.filter(agents, fn a ->
          (Map.get(a, "capabilities") || [])
          |> Enum.any?(&(String.downcase(&1) == cap_lower))
        end)
      else
        agents
      end

    agents =
      if query do
        q_lower = String.downcase(query)

        Enum.filter(agents, fn a ->
          slug = String.downcase(Map.get(a, "slug", ""))
          name = String.downcase(Map.get(a, "name", ""))

          String.contains?(slug, q_lower) or String.contains?(name, q_lower) or
            (Map.get(a, "capabilities") || [])
            |> Enum.any?(&String.contains?(String.downcase(&1), q_lower))
        end)
      else
        agents
      end

    enriched =
      Enum.map(agents, fn a ->
        Map.put(a, "health", Map.get(reliability_by_slug, Map.get(a, "slug")))
      end)

    %{
      "count" => length(enriched),
      "agents" => enriched,
      "note" =>
        if Enum.empty?(enriched) do
          "No agents matched. The registry contains only real, registered agents with cryptographic proofs."
        else
          "Metrics are system-derived from proofs/ledger (proof_count, success_rate) -- never self-reported. Health (success_rate, avg_latency_ms, sample_size) is honestly null where no real reliability data exists yet."
        end
    }
  end
end
