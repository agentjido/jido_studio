defmodule JidoStudio.Persistence.Adapter do
  @moduledoc false

  @type namespace :: atom() | String.t()
  @type id :: String.t()
  @type doc :: map()
  @type stream :: String.t()
  @type event :: map()

  @callback put_doc(namespace(), id(), doc(), keyword()) :: :ok | {:error, term()}
  @callback get_doc(namespace(), id(), keyword()) :: {:ok, doc()} | :not_found | {:error, term()}
  @callback list_docs(namespace(), keyword()) :: [doc()]
  @callback delete_doc(namespace(), id(), keyword()) :: :ok | {:error, term()}

  @callback append_event(stream(), event(), keyword()) :: {:ok, event()} | {:error, term()}
  @callback read_events(stream(), keyword()) :: [event()]
end
