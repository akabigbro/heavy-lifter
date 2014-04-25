module HeavyLifter
  @@logger = Logger.new(STDOUT)

  class Railtie < Rails::Railtie
    initializer "heavy_lifter.load_logger" do
      HeavyLifter.logger = Rails.logger
    end
  end

  class Bulk
    attr_reader :response

    def initialize(attributes = {})
      @url = attributes[:url]
      @index = attributes[:index]
      @types = {}
    end

    def add(type, document, options = {})
      @types[type] ||= []
      @types[type] << {id: options[:id], document: document}
    end

    def add_documents(type, documents, options = {})
      @types[type] ||= []
      documents.each do |document|
        @types[type] << {id: options[:id], document: document}
      end
    end

    def process(options = {})
      file = Tempfile.new('bulk')
      begin
        count = 0
        @types.each do |type, documents|
          count += documents.count
          HeavyLifter.logger.debug("bulk processing #{documents.count} #{type} documents")
          documents.each do |doc|
            file.write "#{{"index" => {"_index" => @index, "_type" => type, "_id" => doc[:id]}}.to_json}\n"
            file.write "#{doc[:document].to_json}\n"
          end
        end
        file.close
        return true unless 0 < count
        HeavyLifter.logger.debug("bulk processing #{count} documents total")
        @response = Response.new(`curl -s -XPOST "#{@url}/_bulk" --data-binary @#{file.path}`)
        return !@response.errors
      rescue => e
        HeavyLifter.logger.error("unable to bulk index: #{e.message}")
        e.backtrace.each { |error| HeavyLifter.logger.error("  #{error}") }
        return false
      ensure
        if @response and !@response.errors
          file.unlink
        else
          HeavyLifter.logger.error("bulk load file #{file.path} was rejected!")
          HeavyLifter.logger.error("bulk error: #{@response.error}") if @response
        end
      end
    end

    class Response
      attr_accessor :took, :items, :errors

      def initialize(response)
        begin
          r = JSON.parse(response, symbolize_names: true) unless response.is_a?(Hash)
          @errors = r[:errors]
          @took = r[:took]
          @items = (r[:items]||[]).map { |i| Item.new(i) }
        rescue
          @errors = true
          @items ||= []
          HeavyLifter.logger.debug("unable to parse bulk response: #{response}")
        end
      end
    end

    class Item
      attr_accessor :actions, :rejected

      def initialize(attributes = {})
        @actions = attributes
      end

      def ok?
        @actions.each do |action,value|
          ok = value[:ok] || value['ok']
          unless ok
            rejected = value
            return false
          end
        end
        return true
      end
    end
  end
end
