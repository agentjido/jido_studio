defmodule JidoStudio.PersistenceMigration do
  use Ecto.Migration

  def change do
    create table(:jido_studio_docs, primary_key: false) do
      add :namespace, :string, null: false
      add :doc_id, :string, null: false
      add :data, :map, null: false
      timestamps(updated_at: :updated_at, inserted_at: :inserted_at, type: :utc_datetime_usec)
    end

    create unique_index(:jido_studio_docs, [:namespace, :doc_id],
             name: :jido_studio_docs_namespace_doc_id_index
           )

    create table(:jido_studio_events, primary_key: false) do
      add :seq, :bigserial, primary_key: true
      add :stream, :string, null: false
      add :event, :map, null: false
      timestamps(updated_at: false, inserted_at: :inserted_at, type: :utc_datetime_usec)
    end

    create index(:jido_studio_events, [:stream, :seq], name: :jido_studio_events_stream_seq_index)
  end
end
