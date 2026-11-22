# frozen_string_literal: true

require "digest"

# A picture's bytes stored once by their content (docs/journal.md,
# section 1): `picture_blobs` holds each distinct file under its
# SHA-256, and a `pictures` row points to one by `sha256`. The rows
# already there are moved, one blob per distinct content, and the
# `bytes` column goes. SQLite drops a column and adds a NOT NULL one
# only by rebuilding the table, so `pictures` is built again beside the
# old one and renamed; nothing points at it. All of it is the
# migration's one transaction: a journal is never left half-moved.

# The content types a mockup file may carry, as 001 gives them.
types = ["text/html; charset=utf-8", "text/css; charset=utf-8",
         "text/javascript; charset=utf-8", "application/json",
         "text/plain; charset=utf-8", "image/svg+xml", "image/png",
         "image/jpeg", "image/gif", "image/webp", "font/woff", "font/woff2",
         "font/ttf"].map { "'#{it}'" }.join(",")

Sequel.migration do
    up do
        create_table(:picture_blobs) do # one row per distinct file
            String :sha256, primary_key: true # lower-case hex of the bytes
            File :bytes, null: false # the file, byte for byte
            Integer :size, null: false # length(bytes)
            constraint :picture_blobs_sha256, <<~SQL
                length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*'
            SQL
        end
        create_table(:pictures_moved) do # S1: a mockup's files
            primary_key :id
            foreign_key :ledger_id, :ledgers, null: false
            String :name, null: false # the mockup's name (`mockup: NAME`)
            String :path, null: false # "" for one file; else its path
            String :type, null: false # the served content type
            foreign_key :sha256, :picture_blobs, type: String, null: false
            foreign_key :event_id, :events, null: false # the mockup command
            unique %i[ledger_id name path]
            constraint :pictures_name, "name <> ''"
            constraint :pictures_type, "type IN (#{types})"
        end
        blobs = self[:picture_blobs].insert_conflict
        self[:pictures].select_map(:id).each do |id|
            row = self[:pictures].where(id:).first
            bytes = row.delete(:bytes).to_s
            sha256 = Digest::SHA256.hexdigest(bytes)
            blobs.insert(sha256:, bytes: Sequel.blob(bytes),
                         size: bytes.bytesize)
            self[:pictures_moved].insert(row.merge(sha256:))
        end
        drop_table(:pictures)
        rename_table(:pictures_moved, :pictures)
        add_index :pictures, :sha256
    end
end
