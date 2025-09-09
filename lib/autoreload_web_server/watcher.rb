# frozen_string_literal: true

require 'listen'

module AutoreloadWebServer
  class Watcher
    def initialize(directory, watch_pattern, &callback)
      @directory = directory
      @watch_pattern = watch_pattern
      @callback = callback
    end

    def start
      @listener = Listen.to(@directory) do |modified, added, removed|
        (modified + added + removed).each do |file|
          next unless match_file?(file)

          relative_path = Pathname.new(file).relative_path_from(Pathname.new(@directory)).to_s
          @callback.call(relative_path)
        end
      end

      @listener.start
    end

    def stop
      @listener&.stop
    end

    private

    def match_file?(file)
      File.fnmatch(@watch_pattern, file, File::FNM_PATHNAME)
    end
  end
end
