# frozen_string_literal: true

require 'spec_helper'
require 'autoreload_web_server/watcher'
require 'pathname'
require 'tmpdir'

RSpec.describe AutoreloadWebServer::Watcher do
  subject(:watcher) { described_class.new(test_directory, watch_pattern) { |file| callback.call(file) } }

  let(:test_directory) { '/tmp/test_watch_dir' }
  let(:watch_pattern) { '**/*.html' }
  let(:callback) { double('callback') }
  let(:listener_mock) { double('Listen::Listener') }

  before do
    allow(Listen).to receive(:to).and_return(listener_mock)
    allow(listener_mock).to receive(:start)
    allow(listener_mock).to receive(:stop)
  end

  describe '#initialize' do
    it 'sets the directory, pattern, and callback' do
      expect(watcher.instance_variable_get(:@directory)).to eq(test_directory)
      expect(watcher.instance_variable_get(:@watch_pattern)).to eq(watch_pattern)
      expect(watcher.instance_variable_get(:@callback)).to be_a(Proc)
    end
  end

  describe '#start' do
    it 'creates a listener with the specified directory' do
      expect(Listen).to receive(:to).with(test_directory)
      watcher.start
    end

    it 'starts the listener' do
      expect(listener_mock).to receive(:start)
      watcher.start
    end

    context 'when files are modified, added, or removed' do
      let(:modified_files) { ['/tmp/test_watch_dir/index.html'] }
      let(:added_files) { ['/tmp/test_watch_dir/new.html'] }
      let(:removed_files) { ['/tmp/test_watch_dir/old.html'] }

      before do
        allow(Listen).to receive(:to) do |_directory, &block|
          @listener_callback = block
          listener_mock
        end
      end

      it 'calls the callback for matching files' do
        watcher.start

        expect(callback).to receive(:call).with('index.html')
        expect(callback).to receive(:call).with('new.html')
        expect(callback).to receive(:call).with('old.html')

        @listener_callback.call(modified_files, added_files, removed_files)
      end

      it 'does not call callback for non-matching files' do
        non_matching_files = ['/tmp/test_watch_dir/script.js']

        watcher.start

        expect(callback).not_to receive(:call)

        @listener_callback.call(non_matching_files, [], [])
      end

      it 'converts absolute paths to relative paths' do
        watcher.start

        expect(callback).to receive(:call).with('index.html')

        @listener_callback.call(['/tmp/test_watch_dir/index.html'], [], [])
      end

      it 'handles nested directory paths correctly' do
        nested_file = '/tmp/test_watch_dir/pages/about.html'

        watcher.start

        expect(callback).to receive(:call).with('pages/about.html')

        @listener_callback.call([nested_file], [], [])
      end
    end
  end

  describe '#stop' do
    context 'when listener exists' do
      it 'stops the listener' do
        watcher.start

        expect(listener_mock).to receive(:stop)
        watcher.stop
      end
    end

    context 'when listener does not exist' do
      it 'does not raise an error' do
        expect { watcher.stop }.not_to raise_error
      end
    end
  end

  describe 'file pattern matching behavior' do
    context 'with different patterns' do
      let(:css_pattern_watcher) { described_class.new(test_directory, '**/*.css') { |file| callback.call(file) } }

      before do
        allow(Listen).to receive(:to) do |_directory, &block|
          @listener_callback = block
          listener_mock
        end
      end

      it 'only processes files matching the specified pattern' do
        css_pattern_watcher.start

        expect(callback).to receive(:call).with('style.css')
        expect(callback).not_to receive(:call).with('script.js')

        @listener_callback.call(
          ["#{test_directory}/style.css", "#{test_directory}/script.js"],
          [],
          []
        )
      end
    end
  end

  describe 'listener lifecycle' do
    it 'stores the listener instance after starting' do
      watcher.start
      expect(watcher.instance_variable_get(:@listener)).to eq(listener_mock)
    end

    it 'can start and stop multiple times without error' do
      expect { watcher.start }.not_to raise_error
      expect { watcher.stop }.not_to raise_error
      expect { watcher.start }.not_to raise_error
      expect { watcher.stop }.not_to raise_error
    end
  end
end
