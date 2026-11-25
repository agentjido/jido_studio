defmodule Mix.Tasks.JidoStudio.Benchmark.Triage do
  use Mix.Task

  @shortdoc "Runs the Studio time-to-triage benchmark test"

  @impl true
  def run(_args) do
    Mix.Task.run("test", ["test/jido_studio/triage_benchmark_test.exs", "--only", "benchmark"])
  end
end
