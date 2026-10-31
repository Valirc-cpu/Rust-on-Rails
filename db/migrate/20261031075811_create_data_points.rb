class CreateDataPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :data_points do |t|
      t.string :device_id
      t.float :value
      t.string :status

      t.timestamps
    end
  end
end
