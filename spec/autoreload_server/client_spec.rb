# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe AutoreloadServer::Client do
  let(:client) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#initialize' do
    it 'sets default options' do
      expect(client.instance_variable_get(:@opts)).to eq(
        {
          watch: '**/*',
          ignore: [],
          host: '127.0.0.1',
          directory: './public',
          port: 4000
        }
      )
    end
  end

  describe '#run' do
    context 'with valid arguments' do
      before do
        allow(client).to receive(:start_server)
        allow(Dir).to receive(:exist?).and_return(true)
      end

      it 'runs with default options when no arguments provided' do
        expect { client.run([]) }.not_to raise_error
      end

      it 'accepts directory argument' do
        expect { client.run([temp_dir]) }.not_to raise_error
        expect(client.instance_variable_get(:@opts)[:directory]).to eq(temp_dir)
      end

      it 'accepts directory and port arguments' do
        expect { client.run([temp_dir, '8080']) }.not_to raise_error
        expect(client.instance_variable_get(:@opts)[:directory]).to eq(temp_dir)
        expect(client.instance_variable_get(:@opts)[:port]).to eq(8080)
      end

      it 'accepts watch pattern option' do
        expect { client.run(['-w', '*.html']) }.not_to raise_error
        expect(client.instance_variable_get(:@opts)[:watch]).to eq('*.html')
      end
    end

    context 'with invalid arguments' do
      it 'exits with error when directory does not exist' do
        expect { client.run(['/nonexistent/directory']) }.to raise_error(SystemExit)
      end

      it 'exits with error when port is out of range' do
        allow(Dir).to receive(:exist?).with(temp_dir).and_return(true)

        expect { client.run([temp_dir, '70000']) }.to raise_error(SystemExit)
      end

      it 'exits with error when too many arguments provided' do
        expect do
          capture_output { client.run(%w[dir1 port extra]) }
        end.to raise_error(SystemExit)
      end
    end

    context 'with help option' do
      it 'exits when help option is provided' do
        expect do
          capture_output { client.run(['-h']) }
        end.to raise_error(SystemExit)
      end
    end

    context 'with version option' do
      it 'exits when version option is provided' do
        expect do
          capture_output { client.run(['-v']) }
        end.to raise_error(SystemExit)
      end
    end

    context 'when server raises an error' do
      before do
        allow(Dir).to receive(:exist?).and_return(true)
        allow(client).to receive(:start_server).and_raise(StandardError, 'Server error')
      end

      it 'catches and handles StandardError' do
        expect do
          capture_output { client.run([]) }
        end.to raise_error(SystemExit)
      end
    end
  end

  def capture_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
end
