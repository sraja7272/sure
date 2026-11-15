class AddUserToLlmUsages < ActiveRecord::Migration[8.1]
  # Build the index without blocking writes to llm_usages, which every AI call
  # appends to.
  disable_ddl_transaction!

  def change
    add_reference :llm_usages, :user, type: :uuid, null: true, index: false,
                  foreign_key: { on_delete: :nullify }
    add_index :llm_usages, [ :user_id, :created_at ], algorithm: :concurrently
  end
end
