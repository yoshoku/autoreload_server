# frozen_string_literal: true

module AutoreloadWebServer
  class Client
    def initialize
      @opts = {
        watch: "**/*",
        ignore: [],
        host: "127.0.0.1",
        directory: ".",
        port: 4000
      }
    end

    def run(args); end
  end
end
