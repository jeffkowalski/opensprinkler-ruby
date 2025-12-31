# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/options'
require 'tempfile'

RSpec.describe OpenSprinkler::IntegerOptions do
  subject(:opts) { described_class.new }

  describe '#initialize' do
    it 'sets all options to defaults' do
      expect(opts[:fw_version]).to eq(221)
      expect(opts[:timezone]).to eq(28)
      expect(opts[:water_percentage]).to eq(100)
    end
  end

  describe '#[]' do
    it 'returns option value' do
      expect(opts[:use_ntp]).to eq(1)
    end

    it 'raises for unknown option' do
      expect { opts[:unknown] }.to raise_error(ArgumentError)
    end
  end

  describe '#[]=' do
    it 'sets option value' do
      opts[:water_percentage] = 80
      expect(opts[:water_percentage]).to eq(80)
    end

    it 'clamps to byte range' do
      opts[:water_percentage] = 300
      expect(opts[:water_percentage]).to eq(44)  # 300 & 0xFF
    end

    it 'raises for read-only options' do
      expect { opts[:fw_version] = 999 }.to raise_error(ArgumentError, /read-only/)
    end
  end

  describe '#http_port' do
    it 'combines two bytes into port number' do
      expect(opts.http_port).to eq(8080)  # 144 + 31*256
    end

    it 'allows setting port' do
      opts.http_port = 80
      expect(opts.http_port).to eq(80)
      expect(opts[:httpport_0]).to eq(80)
      expect(opts[:httpport_1]).to eq(0)
    end
  end

  describe '#timezone_hours' do
    it 'converts encoded timezone to hours' do
      expect(opts.timezone_hours).to eq(-5.0)  # (28-48)/4
    end

    it 'allows setting timezone' do
      opts.timezone_hours = 0
      expect(opts[:timezone]).to eq(48)
    end
  end

  describe '#station_delay_seconds' do
    it 'converts encoded delay to seconds' do
      expect(opts.station_delay_seconds).to eq(0)  # 120-120
    end
  end

  describe '#num_boards' do
    it 'returns 1 plus expansion boards' do
      expect(opts.num_boards).to eq(1)
      opts[:ext_boards] = 2
      expect(opts.num_boards).to eq(3)
    end
  end

  describe 'persistence' do
    let(:tmpfile) { Tempfile.new(['iopts', '.yml']) }
    let(:opts_with_file) { described_class.new(file_path: tmpfile.path) }

    after { tmpfile.unlink }

    it 'saves and loads options' do
      opts_with_file[:water_percentage] = 75
      opts_with_file[:ext_boards] = 3
      opts_with_file.save

      new_opts = described_class.new(file_path: tmpfile.path)
      new_opts.load

      expect(new_opts[:water_percentage]).to eq(75)
      expect(new_opts[:ext_boards]).to eq(3)
    end

    it 'preserves read-only defaults on load' do
      opts_with_file.save

      new_opts = described_class.new(file_path: tmpfile.path)
      new_opts.load

      expect(new_opts[:fw_version]).to eq(221)
    end
  end
end

RSpec.describe OpenSprinkler::StringOptions do
  subject(:opts) { described_class.new }

  describe '#initialize' do
    it 'sets defaults' do
      expect(opts[:password]).to eq('a6d82bced638de3def1e9bbb4983225c')
      expect(opts[:location]).to eq('42.36,-71.06')
      expect(opts[:device_name]).to eq('My OpenSprinkler')
    end
  end

  describe '#[]=' do
    it 'sets string value' do
      opts[:device_name] = 'Backyard Controller'
      expect(opts[:device_name]).to eq('Backyard Controller')
    end

    it 'truncates long strings' do
      opts[:device_name] = 'x' * 500
      expect(opts[:device_name].length).to eq(320)
    end
  end

  describe '#verify_password' do
    it 'returns true for matching hash' do
      expect(opts.verify_password('a6d82bced638de3def1e9bbb4983225c')).to be true
    end

    it 'returns false for wrong hash' do
      expect(opts.verify_password('wrong')).to be false
    end
  end

  describe 'persistence' do
    let(:tmpfile) { Tempfile.new(['sopts', '.yml']) }
    let(:opts_with_file) { described_class.new(file_path: tmpfile.path) }

    after { tmpfile.unlink }

    it 'saves and loads options' do
      opts_with_file[:device_name] = 'Test Device'
      opts_with_file[:location] = '40.71,-74.01'
      opts_with_file.save

      new_opts = described_class.new(file_path: tmpfile.path)
      new_opts.load

      expect(new_opts[:device_name]).to eq('Test Device')
      expect(new_opts[:location]).to eq('40.71,-74.01')
    end
  end
end
