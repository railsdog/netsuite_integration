module NetsuiteIntegration
  class Subscription < Base

    attr_reader :shipment_payload, :existing_sales_order, :sales_order, :invoice

    include NetsuiteIntegration::OrderHelper

    def initialize(config, payload = {})

      super config, payload

      puts "#TS Process PayLoad : #{payload}"

      #TODO need to check the lootcrate json generation is correct as shipments
      # and not shipment
      set_shipment_payload

      puts "#TS Check SalesOrder exists for ref : #{order_reference}"

      @existing_sales_order = sales_order_service.find_by_external_id( order_reference )

      if existing_sales_order
        raise NetSuite::InitializationError, "NetSuite SalesOrder already raised for Order \"#{order_reference}\""
      else
        puts "#TS Creating SalesOrder for ref : #{order_reference}"

        find_related_invoice

        @sales_order = NetSuite::Records::SalesOrder.new({ order_status: '_pendingFulfillment'
                                                           # ,external_id: order_reference
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

      if(@invoice)
        sales_order.tran_date = @invoice.tran_date
      else
        sales_order.tran_date = shipment_payload[:updated_at]
      end

      if(config['netsuite_save_ref_in_memo'].present?)
        sales_order.memo = order_reference
      end

      puts "#TS CREATE SalesOrder #{sales_order.inspect}"
      sales_order.add

      verify_errors(sales_order)
    end


    def find_related_invoice
      puts "#TS find invoice via \n#{order_reference}"
      @invoice = begin
        NetSuite::Records::Invoice.get({:external_id => order_reference})
      rescue NetSuite::RecordNotFound
        nil
      end

      # puts @invoice.inspect
      @invoice
    end


    def find_item(item)

      # NS format in "April 2015 Crate Mens - L"
      # Spree format in "Mens - L"

      #TODO move this to config

      puts LootCrateSpecifics.month_year_for_date(DateTime.now)

      config["netsuite_item_search_prefix"] = LootCrateSpecifics.item_search_prefix

      ns_item_ref = "#{config["netsuite_item_search_prefix"]}#{assembly_item_reference(item)}"

      puts "#TS find Item [#{ns_item_ref}]"

      begin
        # this does not work :
        #  NetSuite::Records::AssemblyItem.get({ :item_id => "December 2014 Crate Mens - L" })

        # search seems to be driven by global config - so cannot be sure of impact changing this so
        # ensure ww store original value
        original = config["netsuite_item_types"]

        config["netsuite_item_types"] = "Assembly"

        item_list_search.find_by_item_id(ns_item_ref)

      rescue NetSuite::RecordNotFound
        nil
      ensure
        config["netsuite_item_types"] = original
      end
    end

    private

    def set_shipment_payload
      @shipment_payload =  payload['shipments'] ? payload['shipments'][0]: payload['shipment']
    end


    def order_reference
      @shipment_payload[:order_number] || @shipment_payload[:order_id]
    end

    def item_list_search
      #@item_search ||= NetsuiteIntegration::Services::NonInventoryItem.new(config)
      inventory_item_service
    end


    def assembly_item_reference(item)
      item[:product_id] || item[:name] || item[:id]
    end


    def build_item_list

      @item_list = []

      shipment_payload[:items].each do |item|

        puts "#TS build_item_list - find_item"
        netsuite_item = find_item(item)

        unless netsuite_item
          raise NetSuite::RecordNotFound, "Assembly Item \"#{assembly_item_reference(item)}\" not found in NetSuite"
        end

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