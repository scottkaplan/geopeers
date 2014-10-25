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

ActiveRecord::Schema.define(version: 20141020160012) do

  create_table "accounts", force: true do |t|
    t.string   "name"
    t.string   "email"
    t.string   "mobile"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "active",     default: 1
  end

  add_index "accounts", ["email"], name: "email", unique: true, using: :btree
  add_index "accounts", ["mobile"], name: "mobile", unique: true, using: :btree

  create_table "auths", force: true do |t|
    t.string   "account_id"
    t.string   "auth_type"
    t.string   "cred"
    t.datetime "issue_time"
    t.datetime "auth_time"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "auth_key"
  end

  add_index "auths", ["cred"], name: "cred", using: :btree

  create_table "devices", force: true do |t|
    t.string   "device_id"
    t.string   "user_agent"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "account_id"
  end

  create_table "globals", force: true do |t|
    t.integer  "build_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "redeems", force: true do |t|
    t.integer  "share_id"
    t.string   "device_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "redeems", ["device_id"], name: "device_id", using: :btree
  add_index "redeems", ["share_id"], name: "share_id", using: :btree

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
    t.integer  "active"
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
