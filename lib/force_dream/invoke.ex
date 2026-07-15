defmodule ForceDream.InvokeResult do
  @moduledoc false
  defstruct [:status, :agent, :task_id, :output, :charged_pence, :proof_id, :message, :error]
end

defmodule ForceDream.Invoke do
  @moduledoc """
  Ported precisely from @forcedream/mcp-server's invoke_agent.ts (via the same logic
  already proven in every other SDK tonight) -- exact endpoints, exact polling interval
  ramp (starts 2500ms, +1000ms per attempt, capped at 6000ms), exact status handling.
  Invokes ONCE; never re-invokes on timeout (would double-charge) -- returns a pollable
  task_id instead.
  """

  alias ForceDream.{Http, InvokeResult}

  def invoke_agent_polling(api_base, api_key, agent_slug, task, max_wait_seconds \\ 60) do
    max_wait_ms = max(5, min(120, max_wait_seconds)) * 1000
    encoded_slug = URI.encode(agent_slug)

    try do
      inv = Http.post_result("#{api_base}/v1/agents/#{encoded_slug}/invoke", %{task: task}, api_key)

      cond do
        inv.status == 401 ->
          %InvokeResult{status: "error", agent: agent_slug, message: "Invalid API key (401).", error: "invalid_key"}

        is_nil(Map.get(inv.json, "task_id")) ->
          err_msg = Map.get(inv.json, "error") || Map.get(inv.json, "note") || "no task_id"

          %InvokeResult{
            status: "error",
            agent: agent_slug,
            message: "Invoke failed (HTTP #{inv.status}): #{err_msg}",
            error: "invoke_failed"
          }

        true ->
          task_id = Map.get(inv.json, "task_id")
          encoded_task_id = URI.encode(task_id)
          poll_loop(api_base, api_key, agent_slug, encoded_slug, task_id, encoded_task_id, max_wait_ms, 2500, now_ms())
      end
    rescue
      e ->
        %InvokeResult{status: "error", agent: agent_slug, message: "Invoke request failed: #{Exception.message(e)}", error: "request_failed"}
    end
  end

  defp now_ms, do: System.system_time(:millisecond)

  defp poll_loop(api_base, api_key, agent_slug, encoded_slug, task_id, encoded_task_id, max_wait_ms, interval_ms, start_ms) do
    if now_ms() - start_ms >= max_wait_ms do
      %InvokeResult{
        status: "pending",
        agent: agent_slug,
        task_id: task_id,
        message: "Still processing after #{div(max_wait_ms, 1000)}s. Not re-invoked (would double-charge). Poll the result later with this task_id."
      }
    else
      Process.sleep(interval_ms)

      poll = Http.get_result("#{api_base}/v1/agents/#{encoded_slug}/result/#{encoded_task_id}", api_key)
      d = poll.json
      poll_status = Map.get(d, "status") || Map.get(d, "outcome") || ""
      ok_true = Map.get(d, "ok") == true

      cond do
        poll_status in ["completed", "succeeded"] or ok_true ->
          output = Map.get(d, "output")
          outcome_insufficient = Map.get(d, "outcome") == "insufficient"
          confidence_insufficient = is_map(output) && Map.get(output, "confidence") == "insufficient"

          if outcome_insufficient or confidence_insufficient do
            %InvokeResult{
              status: "insufficient",
              agent: agent_slug,
              task_id: task_id,
              output: output,
              charged_pence: 0,
              message: "Agent returned insufficient evidence and declined rather than fabricate. Charged nothing."
            }
          else
            charged = Map.get(d, "charged_pence")
            proof_id = Map.get(d, "proof_id") || task_id

            %InvokeResult{
              status: "completed",
              agent: agent_slug,
              task_id: task_id,
              output: output,
              charged_pence: charged,
              proof_id: proof_id,
              message: "Completed. Charged #{charged || 0}p. Cryptographically proven (proof_id #{proof_id})."
            }
          end

        poll_status == "insufficient" ->
          %InvokeResult{
            status: "insufficient",
            agent: agent_slug,
            task_id: task_id,
            output: Map.get(d, "output"),
            charged_pence: 0,
            message: "Agent declined (insufficient evidence). Charged nothing."
          }

        poll_status == "charge_failed" ->
          reason = Map.get(d, "reason") || "insufficient_balance"

          %InvokeResult{
            status: "error",
            agent: agent_slug,
            task_id: task_id,
            charged_pence: 0,
            error: "charge_failed",
            message: "Charge failed: #{reason}. Nothing charged or delivered. Top up and retry."
          }

        poll_status in ["failed", "dead_letter"] ->
          reason = Map.get(d, "reason") || Map.get(d, "last_error") || "unknown"

          %InvokeResult{
            status: "error",
            agent: agent_slug,
            task_id: task_id,
            message: "Task #{poll_status}: #{reason}",
            error: poll_status
          }

        true ->
          next_interval = min(interval_ms + 1000, 6000)
          poll_loop(api_base, api_key, agent_slug, encoded_slug, task_id, encoded_task_id, max_wait_ms, next_interval, start_ms)
      end
    end
  end
end
