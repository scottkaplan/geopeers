# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20140818201954) do

  create_table "beacons", force: true do |t|
    t.datetime "expire_time"
    t.string   "seen_device_id"
    t.string   "seer_device_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "share_to"
    t.string   "share_via",      limit: 8
    t.string   "share_cred"
  end

  create_table "devices", force: true do |t|
    t.string   "device_id"
    t.string   "user_agent"
    t.string   "name"
    t.string   "email"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "redeems", force: true do |t|
    t.integer  "share_id"
    t.string   "device_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "shares", force: true do |t|
    t.datetime "expire_time"
    t.string   "device_id"
    t.string   "share_via"
    t.string   "share_to"
    t.string   "share_cred"
    t.integer  "num_uses"
    t.integer  "num_uses_max"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "shares", ["share_cred"], name: "index_shares_on_share_cred", unique: true, using: :btree

  create_table "sightings", force: true do |t|
    t.string   "device_id"
    t.float    "gps_longitude"
    t.float    "gps_latitude"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end
