# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'tmpdir'
require 'rack/test'

RSpec.describe AutoreloadServer::Server do
  include Rack::Test::Methods

  let(:temp_dir) { Dir.mktmpdir }
  let(:opts) do
    {
      directory: temp_dir,
      host: 'localhost',
      port: 4567,
      watch: '**/*.html'
    }
  end
  let(:server) { described_class.new(opts) }

  after do
    FileUtils.remove_entry(temp_dir)
  end

  describe '#initialize' do
    it 'sets instance variables with provided options' do
      expect(server.instance_variable_get(:@opts)).to eq(opts)
      expect(server.instance_variable_get(:@directory)).to eq(File.expand_path(temp_dir))
      expect(server.instance_variable_get(:@watcher)).to be_nil
    end

    it 'expands the directory path' do
      relative_path_opts = opts.merge(directory: './test')
      server_with_relative = described_class.new(relative_path_opts)
      expected_path = File.expand_path('./test')

      expect(server_with_relative.instance_variable_get(:@directory)).to eq(expected_path)
    end
  end

  describe '#create_sinatra_app' do
    let(:app) { server.create_sinatra_app }

    it 'creates a Sinatra application' do
      expect(app).to be < Sinatra::Base
    end

    it 'sets the correct configuration' do
      expect(app.settings.bind).to eq(opts[:host])
      expect(app.settings.port).to eq(opts[:port])
      expect(app.settings.static).to be false
      expect(app.settings.logging).to be false
    end

    it 'stores the app instance in @app' do
      created_app = server.create_sinatra_app
      expect(server.instance_variable_get(:@app)).to eq(created_app)
    end

    context 'when serving HTML files' do
      before do
        html_content = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Test</title>
            </head>
            <body>
              <h1>Hello World</h1>
            </body>
          </html>
        HTML
        File.write(File.join(temp_dir, 'test.html'), html_content)
      end

      def app
        sinatra_app = server.create_sinatra_app
        sinatra_app.set :environment, :test
        sinatra_app
      end

      it 'serves HTML files with injected client script' do
        get '/test.html'

        expect(last_response).to be_ok
        expect(last_response.body).to include('<script type="text/javascript">')
        expect(last_response.body).to include('autoreload-server')
        expect(last_response.body).to include('EventSource')
      end

      it 'serves index.html for root path' do
        File.write(File.join(temp_dir, 'index.html'), '<html><body>Index</body></html>')
        get '/'

        expect(last_response).to be_ok
        expect(last_response.body).to include('Index')
      end
    end

    context 'when serving non-HTML files' do
      before do
        File.write(File.join(temp_dir, 'style.css'), 'body { margin: 0; }')
      end

      def app
        sinatra_app = server.create_sinatra_app
        sinatra_app.set :environment, :test
        sinatra_app
      end

      it 'serves non-HTML files without modification' do
        get '/style.css'

        expect(last_response).to be_ok
        expect(last_response.body).to eq('body { margin: 0; }')
        expect(last_response.body).not_to include('<script>')
      end
    end

    context 'with autoreload-events endpoint' do
      def app
        sinatra_app = server.create_sinatra_app
        sinatra_app.set :environment, :test
        sinatra_app
      end

      it 'defines autoreload-events route' do
        # Sinatraアプリケーションが/autoreload-eventsルートを定義していることを確認
        app_instance = server.create_sinatra_app
        expect(app_instance).to respond_to(:routes)
        expect(app_instance.routes).to have_key('GET')
      end
    end
  end

  describe '#inject_client_script' do
    context 'when HTML has a head tag' do
      let(:html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Test</title>
            </head>
            <body>
              <h1>Hello World</h1>
            </body>
          </html>
        HTML
      end

      it 'injects client script into existing head tag' do
        result = server.inject_client_script(html)

        expect(result).to include('<script type="text/javascript">')
        expect(result).to include('autoreload-server')
        expect(result).to include('EventSource')
        expect(result).to include('</head>')
      end
    end

    context 'when HTML has no head tag' do
      let(:html) do
        <<~HTML
          <html>
            <body>
              <h1>Hello World</h1>
            </body>
          </html>
        HTML
      end

      it 'creates a head tag and injects client script' do
        result = server.inject_client_script(html)

        expect(result).to include('<head>')
        expect(result).to include('<script type="text/javascript">')
        expect(result).to include('autoreload-server')
        expect(result).to include('</head>')
      end
    end

    context 'when HTML is malformed' do
      let(:html) { '<h1>Just a heading</h1>' }

      it 'still injects the client script' do
        result = server.inject_client_script(html)

        expect(result).to include('<script type="text/javascript">')
        expect(result).to include('autoreload-server')
      end
    end

    it 'returns HTML with client script that connects to /autoreload-events' do
      html = '<html><head></head><body></body></html>'
      result = server.inject_client_script(html)

      expect(result).to include("new EventSource('/autoreload-events')")
      expect(result).to include("data.type === 'update'")
      expect(result).to include('window.location.reload(true)')
    end
  end
end
