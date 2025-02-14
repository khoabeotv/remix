defmodule Remix do
  use Application
  require Logger

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # Define workers and child supervisors to be supervised
      {Remix.Worker, []}
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Remix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defmodule Worker do
    use GenServer

    defmodule State, do: defstruct last_mtime: nil

    def start_link(_) do
      Process.send_after(__MODULE__, :poll_and_reload, 10000)
      GenServer.start_link(__MODULE__, %State{}, name: Remix.Worker)
    end

    def init(state) do
      {:ok, state}
    end

    def handle_info(:poll_and_reload, state) do
      current_mtime = get_current_mtime()

      state = if state.last_mtime != current_mtime do
        comp_elixir =
          fn ->
            case Mix.Tasks.Compile.Elixir.run(["--ignore-module-conflict", "--verbose", "--warnings-as-errors"]) do
              {:error, _} ->
                Logger.error("COMPILE ERROR !!!")
              _ ->
                Logger.info("COMPILE SUCCESS !!!", ansi_color: :green)
            end

            if Application.get_all_env(:remix)[:escript] == true do
              Mix.Tasks.Escript.Build.run([])
            end
          end

        case Application.get_all_env(:remix)[:silent] do
          true ->
            ExUnit.CaptureIO.capture_io(comp_elixir)

          _ ->
            comp_elixir.()
        end

        %State{last_mtime: current_mtime}
      else
        state
      end

      Process.send_after(__MODULE__, :poll_and_reload, 1000)
      {:noreply, state}
    end

    def get_current_mtime, do: get_current_mtime("lib")

    def get_current_mtime(dir) do
      case File.ls(dir) do
        {:ok, files} -> get_current_mtime(files, [], dir)
        _            -> nil
      end
    end

    def get_current_mtime([], mtimes, _cwd) do
      mtimes
      |> Enum.sort
      |> Enum.reverse
      |> List.first
    end

    def get_current_mtime([h | tail], mtimes, cwd) do
      mtime = case File.dir?("#{cwd}/#{h}") do
        true  -> get_current_mtime("#{cwd}/#{h}")
        false -> File.stat!("#{cwd}/#{h}").mtime
      end
      get_current_mtime(tail, [mtime | mtimes], cwd)
    end
  end
end
