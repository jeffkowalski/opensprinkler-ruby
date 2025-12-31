# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'opensprinkler/web/app'
require 'opensprinkler/controller'
require 'opensprinkler/options'

RSpec.describe OpenSprinkler::Web::App do
  include Rack::Test::Methods

  let(:int_options) { OpenSprinkler::IntegerOptions.new }
  let(:string_options) { OpenSprinkler::StringOptions.new }
  let(:options) { double('Options', int: int_options, string: string_options) }
  let(:gpio) { OpenSprinkler::Hardware::MockGPIO.new }
  let(:data_dir) { Dir.mktmpdir }
  let(:controller) do
    OpenSprinkler::Controller.new(options: options, gpio: gpio, data_dir: data_dir)
  end

  def app
    OpenSprinkler::Web::App
  end

  before do
    OpenSprinkler::Web::App.controller = controller
    OpenSprinkler::Web::App.options = options
  end

  after do
    FileUtils.rm_rf(data_dir) if data_dir && File.exist?(data_dir)
  end

  describe 'authentication' do
    it 'returns unauthorized without password' do
      get '/jc'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(2)  # UNAUTHORIZED
    end

    it 'returns unauthorized with wrong password' do
      get '/jc', pw: 'wrongpassword'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(2)
    end

    it 'accepts correct password' do
      default_pw = OpenSprinkler::Constants::Defaults::PASSWORD
      get '/jc', pw: default_pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json).to have_key('devt')
    end

    it 'allows access when ignore_password is set' do
      int_options[:ignore_password] = 1

      get '/jc'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json).to have_key('devt')
    end
  end

  describe 'GET /jc (controller status)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns controller status' do
      get '/jc', pw: pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json).to have_key('devt')
      expect(json).to have_key('nbrd')
      expect(json).to have_key('en')
      expect(json).to have_key('rd')
      expect(json).to have_key('rdst')
    end
  end

  describe 'GET /jo (options)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns options' do
      get '/jo', pw: pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json).to have_key('fwv')
      expect(json).to have_key('tz')
      expect(json).to have_key('wl')
      expect(json['fwv']).to eq(OpenSprinkler::Constants::FW_VERSION)
    end
  end

  describe 'GET /jp (programs)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns program list' do
      get '/jp', pw: pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json).to have_key('nprogs')
      expect(json).to have_key('nboards')
      expect(json).to have_key('mnp')
      expect(json).to have_key('pd')
      expect(json['pd']).to be_an(Array)
    end
  end

  describe 'GET /js (station status)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns station status' do
      get '/js', pw: pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json).to have_key('sn')
      expect(json).to have_key('nboards')
      expect(json['sn']).to be_an(Array)
    end
  end

  describe 'GET /jn (station names)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns station names' do
      get '/jn', pw: pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json).to have_key('snames')
      expect(json).to have_key('maxlen')
      expect(json['snames']).to be_an(Array)
    end
  end

  describe 'GET /je (station special data)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns station attributes' do
      get '/je', pw: pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json).to have_key('masop')
      expect(json).to have_key('masop2')
      expect(json).to have_key('ignore_rain')
      expect(json).to have_key('stn_dis')
      expect(json).to have_key('stn_grp')
      expect(json['masop']).to be_an(Array)
    end
  end

  describe 'GET /jl (logs)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns log data' do
      get '/jl', pw: pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json).to be_an(Array)
    end

    it 'accepts date range parameters' do
      get '/jl', pw: pw, start: 0, end: Time.now.to_i

      expect(last_response).to be_ok
    end
  end

  describe 'GET /ja (all data)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns combined data' do
      get '/ja', pw: pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json).to have_key('settings')
      expect(json).to have_key('programs')
      expect(json).to have_key('options')
      expect(json).to have_key('status')
      expect(json).to have_key('stations')
    end
  end

  describe 'unknown routes' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns page not found' do
      get '/unknown', pw: pw

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(32)  # PAGE_NOT_FOUND
    end
  end

  describe 'root path' do
    it 'redirects to UI' do
      get '/'

      expect(last_response).to be_redirect
      expect(last_response.location).to eq('https://ui.opensprinkler.com')
    end
  end
end
