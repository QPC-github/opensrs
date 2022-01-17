describe OpenSRS::Server do
  let(:server) { OpenSRS::Server.new }

  describe '#new' do
    it 'allows timeouts to be set' do
      server = OpenSRS::Server.new({ :timeout => 90 })

      expect(server.timeout).to be(90)
      expect(server.open_timeout).to be_nil
    end

    it 'allows open timeouts to be set' do
      server = OpenSRS::Server.new({ :timeout => 90, :open_timeout => 10 })

      expect(server.timeout).to be(90)
      expect(server.open_timeout).to be(10)
    end

    it 'leaves it up to Net::HTTP if no timeouts given' do
      expect(server.timeout).to be_nil
      expect(server.open_timeout).to be_nil
    end

    it 'allows a logger to be set during initialization' do
      logger = double(:info => '')
      server = OpenSRS::Server.new({ :logger => logger })

      expect(server.logger).to be(logger)
    end

    it 'allows a proxy to be set during initialization' do
      proxy = 'http://user:password@example.com:1234'
      server = OpenSRS::Server.new(proxy: proxy)

      expect(server.proxy).to be_a(URI)
    end
  end

  describe ".call" do
    let(:response) { double(:body => 'some response') }
    let(:header) { {"some" => "header" } }
    let(:xml) { '<some xml></some xml>' }
    let(:response_xml) { xml }
    let(:xml_processor) { OpenSRS::XmlProcessor }
    let(:http) { double(Net::HTTP, :use_ssl= => true, :verify_mode= => true)  }

    before :each do
      allow(server).to receive(:headers).and_return header
      allow(xml_processor).to receive(:build).and_return xml
      allow(xml_processor).to receive(:parse).and_return response_xml
      allow(server).to receive(:xml_processor).and_return xml_processor
      allow(http).to receive(:post).and_return response
      allow(http).to receive(:ciphers=)
      allow(Net::HTTP).to receive(:new).and_return http
    end

    it "builds XML request" do
      expect(xml_processor).to receive(:build).with(:protocol => "XCP", :some => 'option')
      server.call(:some => 'option')
    end

    it "posts to given path" do
      server.server = URI.parse 'http://with-path.com/endpoint'
      expect(http).to receive(:post).with('/endpoint', xml, header).and_return double.as_null_object
      server.call
    end

    it "parses the response" do
      expect(xml_processor).to receive(:parse).with(response.body)
      server.call(:some => 'option')
    end

    it "posts to root path" do
      server.server = URI.parse 'http://root-path.com/'
      expect(http).to receive(:post).with('/', xml, header).and_return double.as_null_object
      server.call
    end

    it "defaults path to '/'" do
      server.server = URI.parse 'http://no-path.com'
      expect(http).to receive(:post).with('/', xml, header).and_return double.as_null_object
      server.call
    end

    it 'allows overriding of default (Net:HTTP) timeouts' do
      server.timeout = 90

      expect(http).to receive(:open_timeout=).with(90)
      expect(http).to receive(:read_timeout=).with(90)

      server.call( { :some => 'data' } )
    end

    it 'allows overriding of default (Net:HTTP) timeouts' do
      server.timeout = 180
      server.open_timeout = 30

      expect(http).to receive(:read_timeout=).with(180)
      expect(http).to receive(:open_timeout=).with(180)
      expect(http).to receive(:open_timeout=).with(30)

      server.call( { :some => 'data' } )
    end

    it 'allows setting a proxy' do
      proxy = URI('http://user:password@example.com:1234')
      server.proxy = proxy

      expect(Net::HTTP).to receive(:new).with anything,
        anything,
        proxy.host,
        proxy.port,
        proxy.user,
        proxy.password

      server.call(some: 'data')
    end

    it 're-raises Net:HTTP timeouts' do
      expect(http).to receive(:post).and_raise err = Timeout::Error.new('test')
      expect { server.call }.to raise_exception OpenSRS::TimeoutError
    end

    it 'wraps connection errors' do
      expect(http).to receive(:post).and_raise err = Errno::ECONNREFUSED
      expect { server.call }.to raise_exception OpenSRS::ConnectionError

      expect(http).to receive(:post).and_raise err = Errno::ECONNRESET
      expect { server.call }.to raise_exception OpenSRS::ConnectionError
    end

    describe "logger is present" do
      let(:logger) { OpenSRS::TestLogger.new }
      before :each do
        server.logger = logger
      end

      it "should log the request and the response" do
        expect(xml_processor).to receive(:build).with(:protocol => "XCP", :some => 'option')
        server.call(:some => 'option')

        expect(logger.messages.length).to be(2)
        expect(logger.messages.first).to match(/\[OpenSRS\] Request XML/)
        expect(logger.messages.first).to match(/<some xml>/)
        expect(logger.messages.last).to match(/\[OpenSRS\] Response XML/)
        expect(logger.messages.last).to match(/some response/)
      end

      describe "sanitize_logs" do
        let(:xml) { "<?xml version=\"1.0\"?>\n   <OPS_envelope>\n<item>foo bar</item><item key=\"reg_password\">password</item>\n/OPS_envelope>\n" }
        before :each do
          allow(xml_processor).to receive(:build).and_return xml
          allow(xml_processor).to receive(:parse).and_return xml
        end

        it "if enabled, sw_register's logs should be sanitized" do
          server.sanitize_logs = true

          server.call(action: "SW_REGISTER", object: "DOMAIN")

          expect(logger.messages.first).to match(
            %r{<item key="reg_password">\*\*sanitized\*\*</item>}
          )
        end

        it "if disabled, sw_register's logs should not be sanitized" do
          server.sanitize_logs = false

          server.call(action: "SW_REGISTER", object: "DOMAIN")

          expect(logger.messages.first).to match(
            %r{<item key="reg_password">password<\/item>}
          )
        end

        it 'if log_compaction is on, remove lines and whitespace from the left from logs' do
          server.log_compaction = true

          server.call(action: "SW_REGISTER", object: "DOMAIN")

          expect(logger.messages.first).to eq("[OpenSRS] Request XML for DOMAIN SW_REGISTER<?xml version=\"1.0\"?><OPS_envelope><item>foo bar</item><item key=\"reg_password\">password</item>/OPS_envelope>")
        end

        it 'if log_compaction is off, do not remove lines from logs' do
          server.log_compaction = false

          server.call(action: "SW_REGISTER", object: "DOMAIN")
          expect(logger.messages.first).to include("\n")
        end
      end
    end
  end
end
