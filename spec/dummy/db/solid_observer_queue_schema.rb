# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_15_000003) do
  create_table "solid_observer_metrics", force: :cascade do |t|
    t.string "metric_name", limit: 50, null: false
    t.datetime "period_start", null: false
    t.string "period_type", limit: 10, null: false
    t.bigint "value", default: 0, null: false
    t.index ["metric_name", "period_start", "period_type"], name: "idx_solid_observer_metrics_unique", unique: true
  end

  create_table "solid_observer_queue_events", force: :cascade do |t|
    t.string "correlation_id", limit: 64
    t.float "duration"
    t.string "event_type", limit: 50, null: false
    t.string "job_class", limit: 100
    t.text "metadata"
    t.string "queue_name", limit: 50
    t.datetime "recorded_at", null: false
    t.index ["correlation_id"], name: "index_solid_observer_queue_events_on_correlation_id", where: "correlation_id IS NOT NULL"
    t.index ["event_type"], name: "index_solid_observer_queue_events_on_event_type"
    t.index ["job_class"], name: "index_solid_observer_queue_events_on_job_class"
    t.index ["queue_name"], name: "index_solid_observer_queue_events_on_queue_name"
    t.index ["recorded_at"], name: "index_solid_observer_queue_events_on_recorded_at"
  end

  create_table "solid_observer_storage_info", force: :cascade do |t|
    t.bigint "db_size_bytes", null: false
    t.bigint "event_count", null: false
    t.datetime "recorded_at", null: false
    t.index ["recorded_at"], name: "index_solid_observer_storage_info_on_recorded_at"
  end
end
