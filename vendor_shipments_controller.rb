class VendorShipmentsController < ApplicationController
  load_and_authorize_resource
  before_action :load_permissions
  before_action :set_vendor_shipment, only: %i[show edit update destroy pack_and_label combine_slip_and_label create_transaction]

  def index
    return redirect_to(edit_user_registration_path) if (current_user.vendor? and not current_user.is_form_completed?)

    vendor_shipments = current_user.admin? ? VendorShipment.all : VendorShipment.where(vendor_id: current_user.id)
    @vendor_shipments = vendor_shipments.page(params[:page]).per(20)
  end

  def show
    errors = []
    @vendor_shipment.packages.where(rates: nil).each do |p|
      if p.weight.present? && p.box.present? && p.weight > 0 && !p.tracking_number.present?
        shipment = Ship.new(@vendor_shipment.user_id).create_custom_shipment(@vendor_shipment, p)
        if shipment['messages']&.any?
          errors << shipment['messages'].map{|x| x['text']}
        end
        p.rates = Package.sort_rates(shipment['rates'])
        p.save
      end
    end
  end

  def packing_slip
    file_name = "#{@vendor_shipment.po_number}-packing-slip"
    respond_to do |format|
      format.html
      format.pdf do
        render pdf: file_name,
               disposition: 'attachment',
               page_height: 152.4,
               page_width: 101.6,
               margin: { top: 3, # default 10 (mm)
                         bottom: 1, left: 6, right: 1 }
      end
    end
  end

  def pack_and_label
    pdf = combine_slip_and_label
    send_data pdf.to_pdf, filename: "#{@vendor_shipment.po_number}_packing_slip_and_labels.pdf", type: 'application/pdf'
  end

  def combine_slip_and_label
    pdf = CombinePDF.new

    slip = render_to_string pdf: 'packing_slip', template: 'vendor_shipments/packing_slip.pdf', page_height: 152.4,
                            page_width: 101.6,
                            margin: { top: 3, # default 10 (mm)
                                      bottom: 1, left: 6, right: 1 }

    save_path = Rails.root.join("packing_slip_#{@vendor_shipment.id}.pdf")
    File.open(save_path, 'wb') do |file|
      file << slip
    end

    pdf << CombinePDF.load(save_path)
    @vendor_shipment.packages.where.not(label_url: nil).each do |p|
      pdf << CombinePDF.parse(Net::HTTP.get_response(URI.parse(p.label_url)).body)
    end

    save_path.unlink
    pdf
  end

  def create_transaction
    if current_user.vendor?
      package = @vendor_shipment.packages.find(params[:package_id])
      transaction = Ship.new(@vendor_shipment.user_id).create_transaction(params[:rate_object_id])
      if package.present? && transaction.present? && transaction['status'] == 'SUCCESS'
        package.tracking_number = transaction['tracking_number']
        package.label_url = transaction['label_url']
        package.carrier = params[:carrier]
        package.rate_object_id = params[:rate_object_id]

        rate = package.rates.select { |x| x['object_id'] == params[:rate_object_id] }.first rescue nil
        if rate.present?
          package.freight = rate['amount']
        end

        package.save
        @vendor_shipment.update status: true
        render json: { success: true }
      else
        if transaction.present?
          render json: { error: transaction['messages'].map { |x| x['text'] } }
        else
          render json: { error: 'Some error Occured.' }
        end
      end
    else
      render json: {}
    end
  end

  def new
    @vendor_shipment = VendorShipment.new
  end
  
  def create
    @vendor_shipment = current_user.vendor_shipments.new(vendor_shipment_params) # 'current_user.vendor_shipments.new' wrong it should be for user we selected from dropdown, current_user is admin
    if @vendor_shipment.save 
      flash[:success] = 'VendorShipment successfully created'
      redirect_to @vendor_shipment
    else
      flash[:error] = 'Something went wrong'
      render 'new'
    end
  end

  def edit; end

  def update
    if @vendor_shipment.update(vendor_shipment_params)
      flash[:success] = 'VendorShipment was successfully updated'
      redirect_to @vendor_shipment
    else
      flash[:error] = 'Something went wrong'
      render 'edit'
    end
  end
  
  def destroy
    if @vendor_shipment.destroy
      flash[:success] = 'Object was successfully deleted.'
      redirect_to vendor_shipments_url
    else
      flash[:error] = 'Something went wrong'
      redirect_to vendor_shipments_url
    end
  end

  private

  def vendor_shipment_params
    params.require(:vendor_shipment).permit(:vendor_id, :po_number, :ship_to_name, :ship_to_phone, :ship_to_street, :ship_to_apt_number, :ship_to_country, :ship_to_city, :ship_to_state, :ship_to_zip, :notes, vendor_shipment_items_attributes: %i[id part_number brand_line_code qty _destroy], packages_attributes: %i[id weight box_id _destroy])
  end

  def set_vendor_shipment
    @vendor_shipment = VendorShipment.find(params[:id])
  end
end
