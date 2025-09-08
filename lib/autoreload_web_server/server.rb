# frozen_string_literal: true

require 'sinatra/base'
require 'websocket'
require 'nokogiri'
require 'json'
require 'pathname'
require 'base64'
require 'digest/sha1'

module AutoreloadWebServer
  class Server < Sinatra::Base
    set :server, :puma
    set :bind, '127.0.0.1'
    set :websockets, []

    def initialize(opts)
      @opts = opts
      @directory = File.expand_path(opts[:directory])
      @watcher = nil

      configure_server
      super()
    end

    def start
      start_file_watcher

      puts '[autoreload-web-server] Starting server...'
      puts "[autoreload-web-server] Directory: #{@directory}"
      puts "[autoreload-web-server] Server: http://#{@opts[:host]}:#{@opts[:port]}"

      set :bind, @opts[:host]
      set :port, @opts[:port]
      set :public_folder, @directory
      set :static, true

      run!
    end

    private

    def configure_server # rubocop:disable Metrics/AbcSize
      before do
        if request.env['HTTP_UPGRADE']&.downcase == 'websocket'
          handle_websocket_upgrade
          halt
        end
      end

      get '/*' do
        file_path = File.join(@directory, path.empty? ? 'index.html' : path)

        if File.directory?(file_path)
          index_file = File.join(file_path, 'index.html')
          file_path = index_file if File.exist?(index_file)
        end

        if File.exist?(file_path) && file_path.end_with?('.html')
          content = File.read(file_path)
          inject_client_script(content)
        end
      end
    end

    def handle_websocket_upgrade # rubocop:disable Metrics/AbcSize
      return unless websocket_request?

      key = request.env['HTTP_SEC_WEBSOCKET_KEY']
      return unless key

      response.status = 101
      response.headers['Upgrade'] = 'websocket'
      response.headers['Connection'] = 'Upgrade'
      response.headers['Sec-WebSocket-Accept'] = websocket_accept_key(key)

      Thread.new do
        handle_websocket_connection(request.env['rack.hijack_io'] || env['rack.hijack'].call)
      end
    end

    def websocket_accept_key(key)
      magic_string = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
      Base64.strict_encode64(Digest::SHA1.digest(key + magic_string))
    end

    def handle_websocket_connection(socket) # rubocop:disable Metrics/AbcSize
      settings.websockets << socket

      send_websocket_message(socket, { type: 'open' })

      begin
        loop do
          data = socket.read_nonblock(1024)
          break if data.nil? || data.empty?

          puts "[autoreload-web-server] Received WebSocket data: #{data.inspect}"
        rescue IO::WaitReadable
          socket.wait_readable
          retry
        rescue StandardError => e
          puts "[autoreload-web-server] WebSocket error: #{e.message}"
          break
        end
      ensure
        settings.websockets.delete(socket)
        begin
          socket.close
        rescue StandardError
          nil
        end
        puts '[autoreload-web-server] WebSocket client disconnected'
      end
    end

    def send_websocket_message(socket, data)
      data.to_json frame = create_websocket_frame(message)
      socket.write(frame)
    rescue StandardError => e
      puts "[autoreload-web-server] Failed to send WebSocket message: #{e.message}"
      settings.websockets.delete(socket)
    end

    def create_websocket_frame(payload)
      frame = []
      frame << 0x81 # FIN=1, Opcode=1 (text)

      payload_length = payload.bytesize
      if payload_length < 126
        frame << payload_length
      elsif payload_length < 65_536
        frame << 126
        frame += [payload_length].pack('n').bytes
      else
        frame << 127
        frame += [payload_length].pack('Q>').bytes
      end

      frame += payload.bytes
      frame.pack('C*')
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

        message = {
          type: 'update',
          path: file_path,
          reload: file_path.end_with?('.html')
        }

        settings.websockets.dup.each do |socket|
          send_websocket_message(socket, message)
        end
      end

      @watcher.start
      puts "[autoreload-web-server] File watcher started with pattern: #{@opts[:watch]}"
    end

    def client_script
      <<~SCRIPT
        <script>
          (function() {
            const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
            const ws = new WebSocket(`${protocol}//${location.host}`);
            const refreshAssets = function(path) {
              const selectors = [
                { sel: 'link[rel="stylesheet"]', attr: 'href' },
                { sel: 'script[src]', attr: 'src' },
                { sel: 'img[src]', attr: 'src' }
              ];

              selectors.forEach(({ sel, attr }) => {
                document.querySelectorAll(sel).forEach(el => {
                  try {
                    const url = new URL(el.getAttribute(attr), document.baseURI);

                    if (url.pathname === `/${path}`) {
                      const timestamp = Date.now();
                      const separator = url.search ? '&' : '?';
                      el.setAttribute(attr, `${url.origin}${url.pathname}${url.search}${separator}_t=${timestamp}`);
                    }
                  } catch (e) {
                    console.error('[autoreload-web-server] Failed to refresh element:', el, e);
                  }
                });
              });
            }

            ws.onmessage = function(event) {
              try {
                const data = JSON.parse(event.data);
                if (data.type === 'update') {
                  console.log('[autoreload-web-server] Reloading page...');
                  location.reload();
                } else {
                  console.log('[autoreload-web-server] Refresh assets...');
                  refreshAssets(data.path);
                }
              } catch (e) {
                console.error('[autoreload-web-server] Error parsing message:', e);
              }
            };

            ws.onclose = function() {
              console.log('[autoreload-web-server] WebSocket connection closed. Reconnecting in 1 second...');
              setTimeout(() => location.reload(), 1000);
            };

            ws.onerror = function(error) {
              console.error('[autoreload-web-server] WebSocket error:', error);
            };
          })();
        </script>
      SCRIPT
    end
  end
end
