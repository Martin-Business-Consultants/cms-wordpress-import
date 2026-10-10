# frozen_string_literal: true

class CreateWordpressImportRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :wordpress_import_runs do |t|
      t.string :status, null: false, default: "queued"
      t.string :filename, null: false
      t.json :options, null: false, default: {}
      t.json :counts, null: false, default: {}
      t.text :log, null: false, default: ""
      t.references :requested_by, foreign_key: {to_table: :users, on_delete: :nullify}
      t.datetime :finished_at
      t.timestamps
    end
  end
end
