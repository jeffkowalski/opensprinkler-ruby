# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/influxdb_client'

RSpec.describe OpenSprinkler::InfluxDBClient do
  let(:client) { described_class.new(host: 'localhost', port: 8086, database: 'test', enabled: true) }

  describe '#initialize' do
    it 'sets configuration' do
      expect(client.host).to eq('localhost')
      expect(client.port).to eq(8086)
      expect(client.database).to eq('test')
      expect(client.enabled).to be true
    end

    it 'defaults to disabled' do
      client = described_class.new
      expect(client.enabled).to be false
    end
  end

  describe '#configured?' do
    it 'returns true when enabled and configured' do
      expect(client.configured?).to be true
    end

    it 'returns false when disabled' do
      client = described_class.new(enabled: false)
      expect(client.configured?).to be false
    end
  end

  describe '#log_valve' do
    it 'does nothing when disabled' do
      disabled_client = described_class.new(enabled: false)
      expect(Net::HTTP).not_to receive(:start)
      disabled_client.log_valve(0, 1)
    end

    it 'tracks state changes' do
      allow(Net::HTTP).to receive(:start).and_return(nil)

      # First call should log
      client.log_valve(0, 1)

      # Same state should not log again (new client to reset call count)
      call_count = 0
      allow(Net::HTTP).to receive(:start) {
        call_count += 1
        nil
      }

      client.log_valve(0, 1)  # same state - should not call
      expect(call_count).to eq(0)

      client.log_valve(0, 0)  # different state - should call
      expect(call_count).to eq(1)
    end
  end

  describe '.from_config' do
    it 'returns disabled client when file does not exist' do
      client = described_class.from_config('/nonexistent/file.yml')
      expect(client.enabled).to be false
    end

    it 'loads configuration from YAML file' do
      require 'tempfile'
      config_file = Tempfile.new(['influxdb', '.yml'])
      config_file.write({
        'host' => '192.168.1.100',
        'port' => 8087,
        'database' => 'sprinkler',
        'enabled' => true
      }.to_yaml)
      config_file.close

      client = described_class.from_config(config_file.path)

      expect(client.host).to eq('192.168.1.100')
      expect(client.port).to eq(8087)
      expect(client.database).to eq('sprinkler')
      expect(client.enabled).to be true

      config_file.unlink
    end
  end
end
