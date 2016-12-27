# Copyright (C) 2015-2016 all contributors <dtas-all@nongnu.org>
# License: GPL-3.0+ <https://www.gnu.org/licenses/gpl-3.0.txt>

Sequel.migration do
  up do
    create_table(:nodes) do
      primary_key :id
      String :name, null: false # encoding: binary, POSIX
      Integer :ctime
      foreign_key :parent_id, :nodes, null: false # parent dir
      # >= 0: tlen of track, -2: ignore, -1: directory
      Integer :tlen, null: false
      unique [ :parent_id, :name ]
    end

    create_table(:tags) do
      primary_key :id
      String :tag, null: false, unique: true # encoding: US-ASCII
    end

    create_table(:vals) do
      primary_key :id
      String :val, null: false, unique: true # encoding: UTF-8
    end

    create_table(:comments) do
      foreign_key :node_id, :nodes, null: false
      foreign_key :tag_id, :tags, null: false
      foreign_key :val_id, :vals, null: false
      primary_key [ :node_id, :tag_id, :val_id ]
      index :node_id
      index [ :tag_id, :val_id ]
    end
  end

  down do
    drop_table(:nodes)
    drop_table(:tags)
    drop_table(:vals)
    drop_table(:comments)
  end
end
