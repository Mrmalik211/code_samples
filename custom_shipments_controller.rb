class CustomShipmentsController < ApplicationController
  before_action :set_custom_shipment,
                only: %i[ show edit update destroy pack_and_label create_transaction packing_slip ]
  load_and_authorize_resource
  before_action :load_permissions

  def index
    @custom_shipments = current_user.custom_shipments.all.order(updated_at: :desc).page(params[:page]).per(15)
    @custom_shipments = @custom_shipments.where(
      'po_number ILIKE :query OR ship_from_name ILIKE :query OR ship_to_name ILIKE :query', query: "%#{params[:po_search]}%") if params[:po_search].present?
  end

  def show
    @packages = @custom_shipment.packages.where.not(tracking_number: nil).includes(:box)
  end

  def new
    @custom_shipment = current_user.custom_shipments.new
  end

  def packing_slip
    file_name = "#{@custom_shipment.po_number}-packing-slip"
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
    send_data pdf.to_pdf, filename: "#{@custom_shipment.po_number}_packing_slip_and_labels.pdf", type: "application/pdf"
  end

  def combine_slip_and_label
    pdf = CombinePDF.new

    slip = render_to_string pdf: "packing_slip", template: "custom_shipments/packing_slip.pdf", page_height: 152.4,
                            page_width: 101.6,
                            margin: { top: 3, # default 10 (mm)
                                      bottom: 1, left: 6, right: 1 }

    save_path = Rails.root.join("packing_slip_#{@custom_shipment.id}.pdf")
    File.open(save_path, 'wb') do |file|
      file << slip
    end

    pdf << CombinePDF.load(save_path)
    @custom_shipment.packages.where.not(label_url: nil).each do |p|
      pdf << CombinePDF.parse(Net::HTTP.get_response(URI.parse(p.label_url)).body)
    end

    save_path.unlink
    pdf
  end

  def create_transaction
    if current_user.vendor?
      package = @custom_shipment.packages.find(params[:package_id])
      transaction = Ship.new(@custom_shipment.user_id).create_transaction(params[:rate_object_id])
      if package.present? && transaction.present? && transaction["status"] == "SUCCESS"
        package.tracking_number = transaction.tracking_number
        package.label_url = transaction.label_url
        package.carrier = params[:carrier]
        package.rate_object_id = params[:rate_object_id]

        rate = package.rates.select { |x| x["object_id"] == params[:rate_object_id] }.first rescue nil
        if rate.present?
          package.freight = rate["amount"]
        end

        package.save
        render json: { success: true }
      else
        if transaction.present?
          render json: { error: transaction.messages.map { |x| x['text'] } }
        else
          render json: { error: 'Some error Occured.' }
        end
      end
    else
      render json: {}
    end
  end

  def edit
    errors = []
    @custom_shipment.packages.where(rates: nil).each do |p|
      if p.weight.present? && p.box.present? && p.weight > 0 && !p.tracking_number.present?
        shipment = Ship.new(@custom_shipment.user_id).create_custom_shipment(@custom_shipment, p)
        if shipment["messages"].any?
          errors << shipment["messages"].map { |x| x["text"] }
        end
        p.rates = Package.sort_rates(shipment.rates)
        p.save
      end
    end
    if errors.any? && @custom_shipment.packages.where(rates: nil).count > 0
      @custom_shipment.error_message = errors.flatten.uniq.to_sentence
    else
      @custom_shipment.error_message = nil
    end
    @custom_shipment.save
  end

  def create
    @custom_shipment = current_user.custom_shipments.new(custom_shipment_params)

    if @custom_shipment.save
      redirect_to custom_shipment_url(@custom_shipment), notice: "Custom shipment was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @custom_shipment.update(custom_shipment_params)
      redirect_to custom_shipment_url(@custom_shipment), notice: "Custom shipment was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @custom_shipment.destroy

    redirect_to custom_shipments_url, notice: "Custom shipment was successfully destroyed."
  end

  def westar_shipments
    @custom_shipment = current_user.custom_shipments.new(custom_shipment_params)

    if @custom_shipment.save
      redirect_to custom_shipment_url(@custom_shipment), notice: "Custom shipment was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_custom_shipment
    @custom_shipment = current_user.custom_shipments.find(params[:id])
  end

  def custom_shipment_params
    params.require(:custom_shipment).permit(:ship_from_name, :ship_from_apt_number, :ship_from_city,
                                            :ship_from_country, :ship_from_phone, :ship_from_state, :ship_from_street,
                                            :ship_from_zip,
                                            :ship_to_name,
                                            :ship_to_apt_number,
                                            :ship_to_city,
                                            :ship_to_country,
                                            :ship_to_phone,
                                            :ship_to_state,
                                            :ship_to_street,
                                            :ship_to_zip,
                                            :notes,
                                            :po_number,
                                            :part_numbers,
                                            packages_attributes: %i[id weight box_id _destroy])
  end
end
