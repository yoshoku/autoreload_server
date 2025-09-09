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

    def create_sinatra_app # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      opts = @opts
      directory = @directory
      server = self

      app = Sinatra.new do # rubocop:disable Metrics/BlockLength
        set :server, :webrick
        set :bind, opts[:host]
        set :port, opts[:port]
        set :static, false
        set :logging, false
        set :pending_reload, false
        set :connections, []

        get '/autoreload-events' do
          content_type 'text/event-stream'
          headers['Cache-Control'] = 'no-cache'
          headers['Access-Control-Allow-Origin'] = '*'
          headers['Connection'] = 'keep-alive'

          # Create a new EventSource connection
          stream do |out|
            # Send initial connection message
            out << "data: #{JSON.generate({ type: 'connected' })}\n\n"

            # Keep connection alive with periodic heartbeat
            heartbeat_thread = Thread.new do
              loop do
                sleep 30
                begin
                  out << "data: #{JSON.generate({ type: 'heartbeat' })}\n\n"
                rescue StandardError
                  # Connection closed
                  break
                end
              end
            end

            # Monitor for reload events
            loop do
              if settings.pending_reload
                puts '[autoreload-web-server] Sending reload event to client'
                settings.pending_reload = false
                out << "data: #{JSON.generate({ type: 'update', reload: true })}\n\n"
                break
              end
              sleep 1
            end

            heartbeat_thread.kill if heartbeat_thread&.alive?
          end
        end

        get '/*' do
          requested_path = params['splat'].first || ''
          requested_path = 'index.html' if requested_path.empty?
          file_path = File.join(directory, requested_path)

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
      doc = Nokogiri::HTML::Document.parse(html)

      if (head = doc.at('head'))
        head.add_child(client_script)
      else
        doc.at('html').add_child("<head>#{client_script}</head>")
      end

      doc.to_html
    end

    def start_file_watcher
      @watcher = Watcher.new(@directory, @opts[:watch]) do |file_path|
        puts "[autoreload-web-server] File changed: #{file_path}"
        puts '[autoreload-web-server] Setting reload flag for HTML file'
        @app&.set :pending_reload, true
      end

      @watcher.start
      puts "[autoreload-web-server] File watcher started with pattern: #{@opts[:watch]}"
    end

    def client_script
      <<~SCRIPT
        <script type="text/javascript">
          (function() {
            console.log('[autoreload-web-server] Initializing Server-Sent Events client...');

            if (!window.EventSource) {
              console.error('[autoreload-web-server] EventSource not supported in this browser');
              return;
            }

            const eventSource = new EventSource('/autoreload-events');

            eventSource.onopen = function(event) {
              console.log('[autoreload-web-server] Connected to event stream');
            };

            eventSource.onmessage = function(event) {
              try {
                const data = JSON.parse(event.data);
                console.log('[autoreload-web-server] Received event:', data);

                if (data.type === 'update' && data.reload) {
                  console.log('[autoreload-web-server] Reloading page...');
                  eventSource.close();
                  window.location.reload(true);
                } else if (data.type === 'connected') {
                  console.log('[autoreload-web-server] Connection established');
                } else if (data.type === 'heartbeat') {
                  // Keep-alive message, no action needed
                }
              } catch (error) {
                console.error('[autoreload-web-server] Error parsing event data:', error);
              }
            };

            eventSource.onerror = function(event) {
              console.error('[autoreload-web-server] EventSource error:', event);
              if (eventSource.readyState === EventSource.CLOSED) {
                console.log('[autoreload-web-server] Connection closed');
              }
            };

            window.addEventListener('beforeunload', () => {
              eventSource.close();
            });
          })();
        </script>
      SCRIPT
    end
  end
end
