require_relative "../../packaging/install/chorus_executor"

RSpec.configure do |config|
  config.mock_with :rr
end

describe ChorusExecutor do
  let(:executor) { ChorusExecutor.new(logger) }
  let(:logger) { Object.new }
  let(:destination_path) { "fooPath" }
  let(:version) { "extra_crispy" }
  let(:release_path) { "fooPath/releases/extra_crispy" }
  let(:prefix) { "PATH=#{release_path}/postgres/bin:$PATH &&" }
  let(:full_command) { "#{prefix} #{command}" }
  let(:command_success) { true }
  let(:command_times) { 1 }

  before do
    executor.destination_path = destination_path
    executor.version = version
    mock(logger).capture_output(full_command).times(command_times) { command_success }
  end

  describe "#exec" do
    let(:command) { "hello" }

    describe "with a valid command" do
      it "executes the command with the correct path" do
        executor.exec(command)
      end
    end

    describe "when the command fails" do
      let(:command_success) { false }
      it "raises command failed" do
        expect {
          executor.exec(command)
        }.to raise_error(InstallerErrors::CommandFailed)
      end
    end
  end

  describe "#rake" do
    let(:rake_task) { "hahaha" }
    let(:command) { "cd #{release_path} && RAILS_ENV=production bin/rake #{rake_task}" }

    it "should execute correctly" do
      executor.rake rake_task
    end
  end

  describe "#initdb" do
    let(:data_path) { "weee" }
    let(:database_user) { "some_user_guy" }
    let(:command) { "initdb --locale=en_US.UTF-8 -D #{data_path}/db --auth=md5 --pwfile=#{release_path}/postgres/pwfile --username=#{database_user}" }

    it "should execute the correct initdb command" do
      executor.initdb data_path, database_user
    end
  end

  describe "#start_postgres" do
    let(:command) { "CHORUS_HOME=#{release_path} #{release_path}/packaging/chorus_control.sh start postgres" }
    before do
      mock(logger).log("starting postgres...")
    end

    it "should work" do
      executor.start_postgres
    end
  end

  describe "#stop_postgres" do
    before do
      stub(File).directory?("#{release_path}/postgres") { postgres_extracted }
    end

    let(:command) { "CHORUS_HOME=#{release_path} #{release_path}/packaging/chorus_control.sh stop postgres" }

    context "when postgres has been extracted" do
      let(:postgres_extracted) { true }
      before do
        mock(logger).log("stopping postgres...")
      end

      it "should work" do
        executor.stop_postgres
      end
    end

    context "when postgres has not yet been extracted" do
      let(:postgres_extracted) { false }
      let(:command_times) { 0 } # don't actually run the command

      before do
        dont_allow(logger).log("stopping postgres...")
      end

      it "should do nothing" do
        executor.stop_postgres
      end
    end
  end

  describe "#extract_postgres" do
    let(:package_name) { 'postgres-blahblah.tar.gz' }
    let(:command) { "tar xzf #{release_path}/packaging/postgres/#{package_name} -C #{release_path}" }

    it "should work" do
      executor.extract_postgres package_name
    end
  end

  describe "#start_previous_release" do
    let(:command) { "CHORUS_HOME=#{destination_path}/current #{destination_path}/chorus_control.sh start" }

    it "should work" do
      executor.start_previous_release
    end
  end

  describe "#stop_previous_release" do
    let(:command) { "CHORUS_HOME=#{destination_path}/current #{destination_path}/chorus_control.sh stop" }

    it "should work" do
      executor.stop_previous_release
    end
  end

  context "legacy app operations" do
    let(:legacy_installation_path) { "/old/install" }
    let(:edc_env) { "cd #{legacy_installation_path} && source #{legacy_installation_path}/edc_path.sh &&" }

    describe "#import_legacy_schema" do
      let(:command) { "cd #{release_path} && INSTALL_ROOT=#{destination_path} CHORUS_HOME=#{release_path} packaging/chorus_migrate -s legacy_database.sql -w #{legacy_installation_path}/chorus-apps/runtime/data" }

      it "should work" do
        executor.import_legacy_schema legacy_installation_path
      end
    end

    describe "#stop_legacy_app" do
      let(:command) { "#{edc_env} bin/edcsrvctl stop; true" }

      it "should work" do
        executor.stop_legacy_app legacy_installation_path
      end
    end

    describe "#start_legacy_postgres" do
      let(:command) { "#{edc_env} (bin/edcsrvctl start || bin/edcsrvctl start)" }

      it "should run twice since sometimes the first one fails" do
        executor.start_legacy_postgres legacy_installation_path
      end
    end

    describe "#stop_legacy_app!" do
      let(:command) { "#{edc_env} bin/edcsrvctl stop" }

      it "should work" do
        executor.stop_legacy_app! legacy_installation_path
      end
    end
  end

  describe "#dump_legacy_data" do
    let(:command) { "cd #{release_path} && PGUSER=edcadmin pg_dump -p 8543 chorus -O -f legacy_database.sql" }

    it "should work" do
      executor.dump_legacy_data
    end
  end
end