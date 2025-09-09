# frozen_string_literal: true

require 'optparse'
require_relative 'server'

module AutoreloadWebServer
  class Client
    def initialize
      @opts = {
        watch: '**/*',
        ignore: [],
        host: '127.0.0.1',
        directory: './public',
        port: 4000
      }
    end

    def run(args)
      parse_options(args)
      validate_options
      start_server
    rescue StandardError => e
      puts "[autoreload-web-server] Error: #{e.message}"
      puts e.backtrace
      exit 1
    end

    private

    def parse_options(args) # rubocop:disable Metrics/AbcSize
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: autoreload-web-server [options] [directory] [port]'
        opts.version = AutoreloadWebServer::VERSION

        opts.on('-w', '--watch PATTERN', "File pattern to watch (default: #{@opts[:watch]})") do |pattern|
          @opts[:watch] = pattern
        end

        opts.on('-h', '--help', 'Show this help message') do
          puts opts
          exit
        end

        opts.on('-v', '--version', 'Show version') do
          puts AutoreloadWebServer::VERSION
          exit
        end
      end

      remaining = parser.parse!(args)

      if remaining.size == 1
        @opts[:directory] = remaining[0]
      elsif remaining.size == 2
        @opts[:directory] = remaining[0]
        @opts[:port] = remaining[1].to_i
      elsif remaining.size > 2
        warn 'Too many arguments.'
        puts parser
        exit 1
      end
    end

    def validate_options
      abort "[autoreload-web-server] Error: '#{@opts[:directory]}' does not exist" unless Dir.exist?(@opts[:directory])

      return if @opts[:port].between?(1, 65_535)

      abort '[autoreload-web-server] Error: port number must be between 1 and 65535'
    end

    def start_server
      @server = AutoreloadWebServer::Server.new(@opts)

      trap('INT') do
        puts '[autoreload-web-server] Shutting down...'
        exit
      end

      @server.start
    end
  end
end
