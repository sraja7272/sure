class AddUserToLlmUsages < ActiveRecord::Migration[8.1]
  def change
    add_reference :llm_usages, :user, type: :uuid, null: true, index: false,
                  foreign_key: { on_delete: :nullify }
    add_index :llm_usages, [ :user_id, :created_at ]
  end
end
