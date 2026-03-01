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
      expect(json['result']).to eq(2) # UNAUTHORIZED
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

    it 'includes dexp, mexp, ms for backup compatibility' do
      get '/jo', pw: pw

      json = JSON.parse(last_response.body)

      expect(json).to have_key('dexp')
      expect(json).to have_key('mexp')
      expect(json).to have_key('ms')
      expect(json['mexp']).to eq(OpenSprinkler::Constants::MAX_EXT_BOARDS)
      expect(json['ms']).to be_an(Array)
      expect(json['ms'].length).to eq(6)
    end

    it 'decodes water_time options for output' do
      # Default station_delay_time is 120 (encoded byte)
      # Decoded: (120 - 120) * 5 = 0 seconds
      get '/jo', pw: pw

      json = JSON.parse(last_response.body)
      expect(json['sdt']).to eq(0)
      expect(json['mton']).to eq(0)
      expect(json['mtof']).to eq(0)
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
      expect(json).to have_key('nstations')
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

      expect(last_response.status).to eq(404)
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(32) # PAGE_NOT_FOUND
    end
  end

  describe 'root path' do
    it 'redirects to UI' do
      get '/'

      expect(last_response).to be_redirect
      expect(last_response.location).to eq('https://ui.opensprinkler.com')
    end
  end

  # ============ Write Endpoints ============

  describe 'GET /cv (change values)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'requires authentication' do
      get '/cv', en: 1

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(2)  # UNAUTHORIZED
    end

    it 'sets enable/disable' do
      get '/cv', pw: pw, en: 0

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)  # SUCCESS
      expect(int_options[:device_enable]).to eq(0)
    end

    it 'sets rain delay' do
      get '/cv', pw: pw, rd: 24

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
    end

    it 'stops all stations with rsn' do
      expect(controller).to receive(:stop_all_stations)

      get '/cv', pw: pw, rsn: 1

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
    end
  end

  describe 'GET /co (change options)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'requires authentication' do
      get '/co', wl: 50

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(2)
    end

    it 'changes integer options' do
      get '/co', pw: pw, wl: 75, sdt: 600

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
      expect(int_options[:water_percentage]).to eq(75)
      # sdt=600 seconds encodes to byte (600+600)/5 = 240
      expect(int_options[:station_delay_time]).to eq(240)
    end

    it 'changes string options' do
      get '/co', pw: pw, loc: '37.7749,-122.4194'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
      expect(string_options[:location]).to eq('37.7749,-122.4194')
    end

    it 'handles all backup option keys' do
      get '/co', pw: pw,
                 ntp1: 10, ntp2: 20, ntp3: 30, ntp4: 40,
                 dns1: 8, dns2: 8, dns3: 4, dns4: 4,
                 ife: 3, ife2: 5,
                 subn1: 255, subn2: 255, subn3: 255, subn4: 0,
                 fwire: 1, laton: 50, latof: 60,
                 imin: 15, imax: 200, tpdv: 80

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)

      expect(int_options[:ntp_ip1]).to eq(10)
      expect(int_options[:ntp_ip4]).to eq(40)
      expect(int_options[:dns_ip1]).to eq(8)
      expect(int_options[:dns_ip4]).to eq(4)
      expect(int_options[:notif_enable]).to eq(3)
      expect(int_options[:notif2_enable]).to eq(5)
      expect(int_options[:subnet_mask1]).to eq(255)
      expect(int_options[:force_wired]).to eq(1)
      expect(int_options[:latch_on_voltage]).to eq(50)
      expect(int_options[:latch_off_voltage]).to eq(60)
      expect(int_options[:i_min_threshold]).to eq(15)
      expect(int_options[:i_max_limit]).to eq(200)
      expect(int_options[:target_pd_voltage]).to eq(80)
    end
  end

  describe 'GET /cm (manual control)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'requires authentication' do
      get '/cm', sid: 0, en: 1, t: 60

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(2)
    end

    it 'requires station id' do
      get '/cm', pw: pw, en: 1, t: 60

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(16)  # DATA_MISSING
    end

    it 'starts a station manually' do
      expect(controller).to receive(:manual_start_station).with(0, 60)

      get '/cm', pw: pw, sid: 0, en: 1, t: 60

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
    end

    it 'stops a station manually' do
      expect(controller).to receive(:manual_stop_station).with(2)

      get '/cm', pw: pw, sid: 2, en: 0

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
    end

    it 'requires duration when enabling' do
      get '/cm', pw: pw, sid: 0, en: 1

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(16)  # DATA_MISSING
    end

    it 'rejects out of bound station id' do
      get '/cm', pw: pw, sid: 100, en: 1, t: 60

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(17)  # OUT_OF_BOUND
    end
  end

  describe 'GET /cr (run once)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'requires authentication' do
      get '/cr', t: '[60,0,120,0,0,0,0,0]'

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(2)
    end

    it 'requires durations parameter' do
      get '/cr', pw: pw

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(16)  # DATA_MISSING
    end

    it 'runs stations once with specified durations' do
      expect(controller).to receive(:run_once).with([60, 0, 120], use_weather: false)

      get '/cr', pw: pw, t: '[60,0,120]'

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
    end

    it 'accepts use weather flag' do
      expect(controller).to receive(:run_once).with([60, 60], use_weather: true)

      get '/cr', pw: pw, t: '[60,60]', uwt: 1

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
    end

    it 'returns format error for invalid JSON' do
      get '/cr', pw: pw, t: 'not-json'

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(18)  # FORMAT_ERROR
    end
  end

  describe 'GET /pq (pause queue)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'requires authentication' do
      get '/pq', dur: 3600

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(2)
    end

    it 'pauses the queue' do
      expect(controller).to receive(:pause).with(3600)

      get '/pq', pw: pw, dur: 3600

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
    end

    it 'resumes the queue' do
      expect(controller).to receive(:resume)

      get '/pq', pw: pw, dur: 0

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
    end
  end

  describe 'GET /cs (change stations)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'requires authentication' do
      get '/cs', sn: 'New Name', sid: 0

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(2)
    end

    it 'changes a single station name' do
      get '/cs', pw: pw, sn: 'Front Yard', sid: 0

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
      expect(controller.stations[0].name).to eq('Front Yard')
    end

    it 'changes multiple station names via JSON' do
      names = ['Zone 1', 'Zone 2', 'Zone 3']
      get '/cs', pw: pw, snames: names.to_json

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
      expect(controller.stations[0].name).to eq('Zone 1')
      expect(controller.stations[1].name).to eq('Zone 2')
      expect(controller.stations[2].name).to eq('Zone 3')
    end

    it 'changes station groups' do
      groups = [0, 0, 1, 1, 255, 255, 2, 2]
      get '/cs', pw: pw, stn_grp: groups.to_json

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
      expect(controller.stations[4].group_id).to eq(255) # parallel
    end
  end

  describe 'GET /cp (create/change program)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'requires authentication' do
      get '/cp', v: '[1,127,0,[360],[60,0,0,0,0,0,0,0],"Test"]'

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(2)
    end

    it 'creates a new program' do
      program_data = [1, 127, 0, [360], [60, 0, 0, 0, 0, 0, 0, 0], 'Test', [0, 0, 0]]
      get '/cp', pw: pw, v: program_data.to_json, pid: -1

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
      expect(controller.program_store.count).to eq(1)
      expect(controller.program_store[0].name).to eq('Test')
    end

    it 'requires program data' do
      get '/cp', pw: pw, pid: 0

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(16) # DATA_MISSING
    end
  end

  describe 'GET /dp (delete program)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    before do
      # Create a program first
      program = OpenSprinkler::Scheduling::Program.new
      program.name = 'ToDelete'
      controller.program_store.add(program)
    end

    it 'deletes a program' do
      expect(controller.program_store.count).to eq(1)

      get '/dp', pw: pw, pid: 0

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
      expect(controller.program_store.count).to eq(0)
    end

    it 'requires program id' do
      get '/dp', pw: pw

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(16)  # DATA_MISSING
    end

    it 'rejects out of bound program id' do
      get '/dp', pw: pw, pid: 99

      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(17)  # OUT_OF_BOUND
    end
  end

  describe 'GET /dl (delete logs)' do
    let(:pw) { OpenSprinkler::Constants::Defaults::PASSWORD }

    it 'returns success' do
      get '/dl', pw: pw, day: 0

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['result']).to eq(1)
    end
  end
end
