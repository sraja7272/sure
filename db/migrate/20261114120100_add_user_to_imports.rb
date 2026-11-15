class AddUserToImports < ActiveRecord::Migration[8.1]
  # Build the index without blocking writes to imports.
  disable_ddl_transaction!

  def change
    add_reference :imports, :user, type: :uuid, null: true, index: false,
                  foreign_key: { on_delete: :nullify }
    add_index :imports, :user_id, algorithm: :concurrently
  end
end
