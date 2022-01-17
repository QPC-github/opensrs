module OpenSRS
  module XmlProcessor
    class << self
      def build(data)
        builder = ::Nokogiri::XML::Builder.new

        envelope   = ::Nokogiri::XML::Node.new("OPS_envelope", builder.doc)
        header     = ::Nokogiri::XML::Node.new("header", builder.doc)
        version    = ::Nokogiri::XML::Node.new("version", builder.doc)
        body       = ::Nokogiri::XML::Node.new("body", builder.doc)
        data_block = ::Nokogiri::XML::Node.new("data_block", builder.doc)
        other_data = encode_data(data, builder.doc)
        version << '0.9'
        header << version
        envelope << header
        builder.doc << envelope
        data_block << other_data
        body << data_block
        envelope << body
        return builder.to_xml
      end

      # Parses the main data block from OpenSRS and discards
      # the rest of the response.
      def parse(response)
        data_block = data_block_element(response)

        raise ArgumentError.new("No data found in document") if !data_block

        return decode_data(data_block)
      end

      # Encodes individual elements, and their child elements, for the root XML document.
      def encode_data(data, container = nil)
        case data
        when Array
          encode_dt_array(data, container)
        when Hash
          encode_dt_assoc(data, container)
        when String, Numeric, Date, Time, Symbol, NilClass
          data.to_s
        else
          data.inspect
        end
      end

      protected

      def encode_dt_array(data, container)
        build_element(:dt_array, data, container)
      end

      def encode_dt_assoc(data, container)
        build_element(:dt_assoc, data, container)
      end

      def build_element(type, data, container)
        element = new_element(type, container)

        # if array, item = the item
        # if hash, item will be array of the key & value
        data.each_with_index do |item, index|
          item_node = new_element(:item, container)
          item_node["key"] = item.is_a?(Array) ? item[0].to_s : index.to_s

          value = item.is_a?(Array) ? item[1] : item

          encoded_data = encode_data(value, container)
          if encoded_data.is_a?(String)
            item_node.content = encoded_data
          else
            item_node << encoded_data
          end
          element << item_node
        end

        element
      end

      # Recursively decodes individual data elements from OpenSRS
      # server response.
      def decode_data(data)
        data.each do |element|
          case element.name
          when "dt_array"
            return decode_dt_array_data(element)
          when "dt_assoc"
            return decode_dt_assoc_data(element)
          when "text", "item", "dt_scalar"
            next if element.content.strip.empty?
            return element.content.strip
          end
        end
      end

      def data_block_element(response)
        doc = ::Nokogiri::XML(response)
        return doc.xpath('//OPS_envelope/body/data_block/*')
      end

      def decode_dt_array_data(element)
        dt_array = []

        element.children.each do |item|
          next if item.content.strip.empty?
          dt_array[item.attributes["key"].value.to_i] = decode_data(item.children)
        end

        return dt_array
      end

      def decode_dt_assoc_data(element)
        dt_assoc = {}

        element.children.each do |item|
          next if item.content.strip.empty?
          dt_assoc[item.attributes["key"].value] = decode_data(item.children)
        end

        return dt_assoc
      end

      def new_element(element_name, container)
        return ::Nokogiri::XML::Node.new(element_name.to_s, container)
      end
    end
  end
end
