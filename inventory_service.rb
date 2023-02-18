class InventoryService
  def initialize()
    @conn = Faraday.new(url: ENV['INVENTORY_URL'])
    init_token
  end

  def init_token
    response = @conn.get('get_log_in_token') do |req|
      req.params = {
        email: ENV['INVENTORY_EMAIL'],
        password: ENV['INVENTORY_PASSWORD']
      }
    end
    if response.status == 200
      @conn.headers = {
        Authorization: JSON.parse(response.body)['auth_token']
      }
    end
  end

  def get_single_inventory vb, part_number, qty
    response = @conn.get('single_inventory') do |req|
      req.params = {
        vendor_type: vb.vendor.name.downcase.gsub(" ", "_"),
        part_number: part_number,
        quantity: qty
      }
    end
    if response.status == 200
      response_body = JSON.parse(response.body, symbolize_names: true)[:response][:data]
      if response_body
        line_codes = vb.line_code.split ','
        vb_data = response_body.map{ |res| 
          line_codes.include?(res[:line_code]) ? ( res.values_at(:cost, :line_code) + [res[:inventories].map{ |i| i[:quantity].to_i }.compact.sum] ) : nil
        }.compact&.sort_by { |x| x.first }
        
        vb_data&.each do |data|
          if (vb.vendor.stock_value <= data.last ? data.last : 0) >= qty
            vb.brand_items.find_by_part_number(part_number).update inventory: data.last, cost: data.first
            return data[0..1]
          end
        end
      end
    end

    [vb.brand_items.find_by_part_number(part_number).cost, vb.line_code]
  end

  def export_inventory vendor_id
    vendor = Vendor.find(vendor_id)
    response = @conn.get('export_inventory') do |req|
      req.params['vendor_type'] = vendor.name.downcase.gsub(" ", "_")
    end
    if response.status == 200
      response_body = JSON.parse(response.body, symbolize_names: true)
      response_body[:message].nil? ? UpdateVendorInventoryJob.perform_later(vendor_id, response_body[:file_url]) : Rails.logger.info(response_body[:message])
    end
  end

  def get_all_inventory vendor_id
    vendor = Vendor.find(vendor_id)
    response = @conn.get('all_inventory') do |req|
      req.params['vendor_type'] = vendor.name.downcase
    end
    if response.status == 200
      response_body = JSON.parse(response.body, symbolize_names: true)[:response].first[:data]
      inventory_details = response_body.map{ |r| [r[:part_number],r[:inventories].map{ |i| i[:quantity] }.sum] }
      update_inventory vendor.vendor_brands, inventory_details
    elsif response.status == 401
      puts response.body
    end
  end
  
  private

  def update_inventory vendor_brands, inventories
    inventories.each do |i|
      brand_item = BrandItem.where(vendor_brand: vendor_brands).find_by_part_number(i.first)
      if brand_item and brand_item.inventory != i.second
        brand_item.update(inventory: i.second)
      end
    end
  end
end
