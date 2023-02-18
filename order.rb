# == Schema Information
#
# Table name: orders
#
#  id                 :bigint           not null, primary key
#  apt_number         :string
#  city               :string
#  country            :string
#  discount           :float
#  email              :string
#  external_po_number :string
#  items_pushed       :boolean          default(FALSE)
#  name               :string
#  notes              :text
#  order_from         :integer
#  part_numbers       :text
#  phone              :string
#  picked             :boolean          default(FALSE)
#  po_number          :string
#  pushed             :boolean          default(FALSE)
#  pushed_to          :string           default("")
#  qty_scanned        :integer          default(0)
#  qty_to_scan        :integer          default(0)
#  qty_total          :integer          default(0)
#  shipping_method    :integer          default("standard")
#  shipping_service   :string
#  state              :string
#  status             :integer          default("open")
#  street             :string
#  tax                :float
#  zip                :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint
#  batch_id           :bigint
#  ebay_order_id      :bigint
#  location_id        :bigint
#  user_id            :bigint           not null
#
# Indexes
#
#  index_orders_on_account_id   (account_id)
#  index_orders_on_batch_id     (batch_id)
#  index_orders_on_location_id  (location_id)
#  index_orders_on_po_number    (po_number) UNIQUE
#  index_orders_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class Order < ApplicationRecord
  extend OrderAsSpecified
  include Sortable::Model
  include Packageable

  serialize :part_numbers, Array
  sortable :po_number, :location_id, :status
  sortable :customer_name, -> { joins(:user) }, column: "users.name"
  
  belongs_to :user
  belongs_to :batch, optional: true
  belongs_to :location, optional: true
  belongs_to :account, optional: true

  has_many :order_items, dependent: :destroy
  has_many :items, through: :order_items
  has_many :trackings, dependent: :destroy

  before_create :set_po_number
  before_save :set_quantities, :set_part_numbers

  enum status: [:open, :submitted, :processing, :shipped, :cancelled, :completed, :insufficient_inventory, :scanned]
  enum shipping_method: [:standard, :next_day, :second_day_air]
  enum order_from: [:ebay, :amazon, :walmart, :autobuffy]

  validates_presence_of :po_number, :city, :state, :zip
  validates_uniqueness_of :po_number

  accepts_nested_attributes_for :packages, allow_destroy: true
  accepts_nested_attributes_for :trackings, allow_destroy: true

  def set_quantities
    oi = order_items
    self.qty_to_scan = oi.map{|x| x.qty_to_scan}.flatten.sum
    self.qty_scanned = oi.pluck(:quantity_scanned).sum
  end

  def set_part_numbers
    self.part_numbers = self.get_part_numbers_per_quantity
  end

  def self.set_all_part_numbers
    Order.where(part_numbers: nil).each do |o|
      o.part_numbers = o.get_part_numbers_per_quantity
      o.save
    end
  end

  def self.set_all_quantities
    Order.where(qty_total: 0).each do |o|
      o.set_quantities
      o.save
    end
  end

  def get_part_numbers_per_quantity
    part_numbers = []
    order_items.each do |o|
      item = o.item
      (1..o.quantity_ordered).each do
        part_numbers << item.part_number
      end
    end
    part_numbers.sort
  end

  def subtotal
    total = []
    order_items.each do |ci|
      item = ci.item
      total << item.get_cost(self.user) * ci.quantity_ordered
    end
    total.sum
  end

  def freight
    packages.pluck(:freight).compact.sum
  end

  def total
    subtotal + freight
  end

  def self.set_freight
    Order.includes(:packages).find_each do |o|
      o.packages.each do |p|
        rate = p.rates.select{ |x| x["object_id"] == p.rate_object_id }.first
        if rate.present?
          p.freight = rate["amount"]
          p.save
        end
      end
    end
  end

  def estimated_weight
    (order_items.includes(:item).map{ |oi| oi.item.weight * oi.quantity_ordered }.flatten.sum + 1).round
  end

  def get_trackings
    trackings.map{ |t| [t.carrier, t.number] }
  end

  private

  def set_po_number
    self.po_number = generate_po_number unless po_number.present?
  end

  def generate_po_number
    loop do
      token = "O-#{SecureRandom.random_number(9999)}-#{SecureRandom.random_number(9999)}-#{SecureRandom.random_number(9999)}"
      break token unless Order.where(po_number: token).exists?
    end
  end
end
