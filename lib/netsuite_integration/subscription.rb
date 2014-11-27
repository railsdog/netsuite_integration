module NetsuiteIntegration
  class Subscription < Base

    attr_reader :shipment_payload, :existing_sales_order, :sales_order

    include NetsuiteIntegration::OrderHelper

    def initialize(config, payload = {})

      super config, payload

      #TODO need to check the lootcrate json generation is correct as shipments
      # and not shipment
      @shipment_payload = payload['shipments'][0]

      @existing_sales_order = sales_order_service.find_by_external_id( key_reference )

      if existing_sales_order
        puts "#TS SalesOrder already exists for ref : #{key_reference}"
        #TODO
      else
        puts "#TS Creating SalesOrder for ref : #{key_reference}"

        @sales_order = NetSuite::Records::SalesOrder.new({ order_status: '_pendingFulfillment'#,
                                                           #external_id: key_reference
        })

        # depending on your NS instance a custom form will need to be set to close the sales order
        if (custom_form_id = config['netsuite_sales_order_custom_form_id']).present?
          @sales_order.custom_form = NetSuite::Records::RecordRef.new(internal_id: custom_form_id)
        end
      end

    end

    # so we can use some of the order helpers, e.g we have the required nodes for customer
    def order_payload
        shipment_payload
    end

    def create

      sales_order.entity = set_up_customer

      sales_order.item_list = build_item_list

      sales_order.transaction_bill_address = build_bill_address
      sales_order.transaction_ship_address = build_ship_address

      sales_order.tran_date = shipment_payload[:updated_at]

      puts "#TS Add SalesOrder #{sales_order.inspect}"

      if sales_order.add

        puts "#TS SUCCESS!!! "

       # fresh_sales_order = sales_order_service.find_by_external_id(order_payload[:number] || order_payload[:id])
       # sales_order.tran_id = fresh_sales_order.tran_id
        # need entity on sales_order for CustomerDeposit.customer
       # sales_order.entity = fresh_sales_order.entity
        sales_order
      end
    end

    def link_to_invoice
      invoice =  NetSuite::Records::Invoice.get( {:external_id => key_reference } )

      puts invoice.inspect
    end


    private

    def invoice
      puts "#TS find invoice via \n#{invoice_reference}"

      @invoice ||= begin
        NetSuite::Records::Invoice.get({:external_id => invoice_reference})
      rescue NetSuite::RecordNotFound
        nil
      end

      @invoice
    end

    def key_reference
      @shipment_payload[:order_number] || @shipment_payload[:order_id]
    end

    def item_list_search
      @item_search ||= NetsuiteIntegration::Services::NonInventoryItem.new(config)
      ##inventory_item_service
    end


    def build_item_list

      @item_list = []

      shipment_payload[:items].map do |item|

        item_id = item_reference(item)

        #item_id = "ACC-KCHN-BG"

        puts "#TS find Item [#{item_id}]"

        netsuite_item = item_list_search.find_by_name(item_id)
        #netsuite_item = item_list_search.find_by_item_id(item_id)

        unless netsuite_item
          raise NetSuite::RecordNotFound, "Item \"#{item_id}\" not found in NetSuite"
        end

        puts "#TS found Item : #{item_id} (#{netsuite_item.internal_id})"

        @item_list << NetSuite::Records::SalesOrderItem.new({
            item: { internal_id: netsuite_item.internal_id },
            quantity: item[:quantity],
            amount: item[:quantity] * item[:price],
            # Force tax rate to 0. NetSuite might create taxes rates automatically which
            # will cause the sales order total to differ from the order in the Spree store
            tax_rate1: 0
        })

        puts "#TS Created  SalesOrderItem Int Id : #{netsuite_item.internal_id}"

      end   # Spree item list

      NetSuite::Records::SalesOrderItemList.new(item: @item_list)

    end

  end

end