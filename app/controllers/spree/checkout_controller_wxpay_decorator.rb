#encoding: utf-8
module Spree
  CheckoutController.class_eval do
    before_filter :wxpay_checkout_hook, :only => [:update]

    # this is called when user choose "wxpay" and clicks "next" or sth equivalent
    # which would go to the "update" action in checkout controller
    def wxpay_checkout_hook
      #TODO support step confirmation 
      return unless params['state'] == 'payment' && is_wxpay?  # @order.next_step_complete?
      case request.user_agent
      when /MicroMessenger/ #weixin embedded browser
      Rails.logger.info("#{__FILE__}-#{__LINE__}")
      retrieve_payment(:jsapi)
        handle_weixin_client_payment
      else
      retrieve_payment(:native)
        handle_web_client_payment
      end
    end

    def handle_weixin_client_payment
      Rails.logger.info("#{__FILE__}-#{__LINE__}")
      redirect_to service_manager.get_authorize_url( wcpay_code_url(payment_id: @payment.id)) and return;
    end

    def handle_web_client_payment
      begin
        @payment.payment_url = service_manager.get_payment_url(@payment, request )
        @payment.save!
      rescue Spree::OffsitePayments::Wxpay::BusinessError => e
        flash[:warn] = e.message
        redirect_to order_url(@order) and return
      rescue ::OffsitePayments::Integrations::Wxpay::CommunicationError,
        ::OffsitePayments::Integrations::Wxpay::CredentialMismatchError,
        ::OffsitePayments::Integrations::Wxpay::UnVerifiableResponseError => e
        flash[:error] = Spree.t(:comm_error)
      end
      render :edit
    end

    # assuming @order is set
    def retrieve_payment(current_api)
          Rails.logger.info("#{__FILE__}-#{__LINE__} ")
      existing_payment = @order.payments.processing.find_by(amount: @order.outstanding_balance, payment_method: @payment_method)
          Rails.logger.info("#{__FILE__}-#{__LINE__} ")
      if existing_payment 
          Rails.logger.info("#{__FILE__}-#{__LINE__} ")
        case 
        when current_api == :jsapi # && existing_payment.payment_url.present?
          Rails.logger.info("#{__FILE__}-#{__LINE__} voiding #{existing_payment.identifier} since it is for qrcode")
          existing_payment.void!
        when current_api == :native && existing_payment.prepay_id.present?
          Rails.logger.info("#{__FILE__}-#{__LINE__} voiding #{existing_payment.identifier} since it is for H5")
          existing_payment.void!
        end
      else
          Rails.logger.info("#{__FILE__}-#{__LINE__} no existing")
      end
          Rails.logger.info("#{__FILE__}-#{__LINE__} ")
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: @payment_method)
    end

    def is_wxpay?
      @payment_method = PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
      Spree::BillingIntegration::Wxpay == @payment_method.class
    end

    # this is the redirect back from Wxpay H5 authorization URL
    def wcpay_code
      Rails.logger.info("#{__FILE__}-#{__LINE__}")
      access_auth_result = service_manager.get_client_openid(params['code'])
      Rails.logger.info("#{__FILE__}-#{__LINE__} #{access_auth_result.inspect}")
      @payment = Spree::Payment.find(params[:payment_id])
      @payment.prepay_id = service_manager.get_prepay_id(@payment, request, access_auth_result.result[:openid] )
      @payment.save!
      @wcpay = service_manager.get_wcpay_request_payload(@payment.prepay_id)
      @goto_page_when_paid = spree.order_path(@payment.order)
      render :edit
    end

    def payment_qrcode
      @payment_url = Payment.find(params[:payment_id]).payment_url
      respond_to do |format|
        format.html { render qrcode: @payment_url }
        format.svg  { render :qrcode => @payment_url, :level => :l, :unit => 10 }
        format.png  { render :qrcode => @payment_url }
        format.gif  { render :qrcode => @payment_url }
        format.jpeg { render :qrcode => @payment_url }
      end
    end

    private 
    def service_manager
      @@service_manager ||= Spree::OffsitePayments::Wxpay::Manager.new()
    end

  end
end
