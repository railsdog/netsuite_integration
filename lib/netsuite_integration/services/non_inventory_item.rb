module NetsuiteIntegration
  module Services

    class NonInventoryItem < InventoryItem

      def initialize(config, poll_param = 'netsuite_last_updated_after')
        super config, poll_param
      end

      def find_by_external_id(ext_id)
        NetSuite::Records::NonInventorySaleItem.get({:external_id => ext_id})
      end

      def find_by_name(name)
        puts "#TS in find_by_name #{name}"
        NetSuite::Records::InventoryItem.search({
                                                    criteria: {
                                                        basic: basic_criteria + [{ field: 'displayName', value: name, operator: 'contains' }]
                                                    },
                                                    preferences: default_preferences
                                                }).results.first

      end


      # See ItemTypes examples here https://system.netsuite.com/help/helpcenter/en_US/SchemaBrowser/lists/v2013_2_0/accountingTypes.html#listAcctTyp:ItemType
      # Over ride base - should over ride basic criteria in searches
      def item_type_to_fetch
          ['_nonInventoryItem']
      end

    end
  end
end
