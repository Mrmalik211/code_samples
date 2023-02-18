require "csv"
require 'smarter_csv'

class ImportItemsJob < ApplicationJob
  queue_as :default

  def perform(item_file_id, user_id)
    f = ItemFile.find_by_id(item_file_id)
    return unless f.present?

    f.processing!

    path = f.file.path

    SmarterCSV.process(path, col_sep: ",", row_sep: :auto, chunk_size: 500, remove_empty_values: false, file_encoding: 'iso-8859-1') do |chunk|
      items = []
      chunk.each do |x|
        data = x.values + [user_id]
        delete_list = [5,5]
        delete_list.each do |del|
          data.delete_at(del)
        end
        items << data
      end
      save_items items
    end

    f.done!
  end

  def save_items(chunk)
    columns = %i[part_number brand brand_line_code cost upc title height width length weight user_id]

    chunk.uniq! { |row|
      [row[0]]
    }

    Item.import columns, chunk, on_duplicate_key_update: {conflict_target: [:part_number], columns: columns}, validate: false
  end
end
