# frozen_string_literal: true

require "listen"

module AutoreloadWebServer
  class Watcher
    def initialize(directory, watch_pattern, callback)
      @directory = directory
      @watch_pattern = watch_pattern
      @callback = callback
    end

    def start; end

    def stop; end
  end
end
