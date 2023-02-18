# == Schema Information
#
# Table name: packages
#
#  id               :bigint           not null, primary key
#  carrier          :string
#  freight          :float
#  label_url        :string
#  name             :string
#  packageable_type :string
#  rates            :text
#  tracking_number  :string
#  weight           :float
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  box_id           :bigint           not null
#  packageable_id   :bigint
#  rate_object_id   :string
#
# Indexes
#
#  index_packages_on_box_id       (box_id)
#  index_packages_on_packageable  (packageable_type,packageable_id)
#
# Foreign Keys
#
#  fk_rails_...  (box_id => boxes.id)
#
class Package < ApplicationRecord
  serialize :rates, Array

  belongs_to :packageable, :polymorphic => true
  belongs_to :box

  def self.sort_rates(rates)
    return unless rates.present?
    
    s_rates = rates.sort_by{|x| x['amount'].to_f }
    best_value = []
    cheapest = []
    fastest = []
    s_rates.delete_if {|v| best_value << v if v['attributes'].include?('BESTVALUE')}
    s_rates.delete_if {|v| cheapest << v if v['attributes'].include?('CHEAPEST')}
    s_rates.delete_if {|v| fastest << v if v['attributes'].include?('FASTEST')}
    (cheapest + best_value + fastest + s_rates).map{|x| x.to_hash}
  end

  def self.sort_all_rates
    Package.all.each do |p|
      p.rates = Package.sort_rates(p.rates)
      p.save
    end
  end
end
