# frozen_string_literal: true

require 'sinatra/base'
require 'webrick'
require 'nokogiri'
require 'rackup'

require_relative 'watcher'

module AutoreloadWebServer
  class Server
    def initialize(opts)
      @opts = opts
      @directory = File.expand_path(opts[:directory])
      @watcher = nil
    end

    def start
      puts '[autoreload-web-server] Initializing server...'
      start_file_watcher

      puts '[autoreload-web-server] Starting server...'
      puts "[autoreload-web-server] Directory: #{@directory}"
      puts "[autoreload-web-server] Server: http://#{@opts[:host]}:#{@opts[:port]}"

      Rackup::Handler::WEBrick.run(
        create_sinatra_app,
        Host: @opts[:host],
        Port: @opts[:port],
        Logger: WEBrick::Log.new(IO::NULL),
        AccessLog: []
      )
    end

    def create_sinatra_app # rubocop:disable Metrics/AbcSize
      opts = @opts
      directory = @directory
      server = self

      app = Sinatra.new do
        set :server, :webrick
        set :bind, opts[:host]
        set :port, opts[:port]
        set :public_folder, directory
        set :static, true
        set :logging, false
        set :pending_reload, false

        get '/autoreload-events' do
          content_type :json
          headers['Cache-Control'] = 'no-cache'
          headers['Access-Control-Allow-Origin'] = '*'

          if settings.pending_reload
            puts '[autoreload-web-server] Sending reload response to client'
            settings.pending_reload = false
            { type: 'update', reload: true }.to_json
          else
            { type: 'ping' }.to_json
          end
        end

        get '/*' do
          file_path = File.join(directory, params['splat'].first || 'index.html')

          if File.directory?(file_path)
            index_file = File.join(file_path, 'index.html')
            file_path = index_file if File.exist?(index_file)
          end

          if File.exist?(file_path) && file_path.end_with?('.html')
            content = File.read(file_path)
            server.inject_client_script(content)
          elsif File.exist?(file_path)
            send_file file_path
          end
        end
      end

      @app = app
      app
    end

    def inject_client_script(html)
      doc = Nokogiri::HTML::DocumentFragment.parse(html)

      if (body = doc.at('body'))
        body.add_child(client_script)
      else
        doc.add_child(client_script)
      end

      doc.to_html
    end

    def start_file_watcher
      @watcher = Watcher.new(@directory, @opts[:watch]) do |file_path|
        puts "[autoreload-web-server] File changed: #{file_path}"

        if file_path.end_with?('.html', '.htm')
          puts '[autoreload-web-server] Setting reload flag for HTML file'
          @app&.set :pending_reload, true
        end
      end

      @watcher.start
      puts "[autoreload-web-server] File watcher started with pattern: #{@opts[:watch]}"
    end

    def client_script
      <<~SCRIPT
        <script>
          (function() {
            console.log('[autoreload-web-server] Initializing polling client script...');

            const checkForUpdates = async () => {
              try {
                const response = await fetch('/autoreload-events', {
                  cache: 'no-cache',
                  headers: {
                    'Cache-Control': 'no-cache'
                  }
                });
                const data = await response.json();
                if (data.type === 'update' && data.reload) {
                  console.log('[autoreload-web-server] Reloading page...');
                  window.location.reload(true);
                }
              } catch (error) {
                console.error('[autoreload-web-server] Polling error:', error);
              }
            };

            // Poll every second
            console.log('[autoreload-web-server] Starting polling every 1000ms');
            const pollInterval = setInterval(checkForUpdates, 1000);

            // Also check immediately
            checkForUpdates();

            // Clean up on page unload
            window.addEventListener('beforeunload', () => {
              clearInterval(pollInterval);
            });
          })();
        </script>
      SCRIPT
    end
  end
end
