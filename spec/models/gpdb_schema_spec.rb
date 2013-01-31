require 'spec_helper'

describe GpdbSchema do
  describe "associations" do
    it { should belong_to(:database) }
    it { should have_many(:datasets) }
    it { should have_many(:workspaces) }

    describe "#database" do
      let(:schema) {
         GpdbSchema.create!(:name => 'test_schema', :database => gpdb_databases(:default))
      }

      it "returns the schemas parent" do
        schema.reload.database.should == gpdb_databases(:default)
      end
    end

    describe 'validations' do
      it 'has a valid factory' do
        FactoryGirl.build(:gpdb_schema).should be_valid
      end

      it { should validate_presence_of(:name) }

      it 'does not allow slashes, ampersands and question marks' do
        ['/', '&', '?'].each do |char|
          new_schema = FactoryGirl.build(:gpdb_schema, :name => "schema#{char}name")
          new_schema.should_not be_valid
          new_schema.should have_error_on(:name)
        end
      end

      describe 'name uniqueness' do
        let(:existing) { schemas(:default) }

        context 'in the same db' do
          it 'does not allow two databases with the same name' do
            new_schema = FactoryGirl.build(:gpdb_schema,
                                           :name => existing.name,
                                           :database => existing.database)
            new_schema.should_not be_valid
            new_schema.should have_error_on(:name).with_message(:taken)
          end
        end

        context 'in a different db' do
          it 'allows same names' do
            new_schema = FactoryGirl.build(:gpdb_schema,
                                           :name => existing.name)
            new_schema.should be_valid
          end
        end
      end
    end

    describe "cascading deletes" do
      it "deletes its datasets when it is destroyed" do
        schema = schemas(:default)

        expect {
          schema.destroy
        }.to change(schema.datasets, :count).to(0)
      end

      it "nullifies its sandbox association in workspaces" do
        schema = schemas(:searchquery_schema)
        workspace = FactoryGirl.create(:workspace, :sandbox => schema)

        expect {
          expect {
            schema.destroy
          }.to change(Workspace, :count).by(0)
        }.to change { workspace.reload.sandbox }.from(schema).to(nil)
      end
    end
  end

  describe '#accessible_to' do
    let(:gpdb_data_source) { data_sources(:owners) }
    let(:account) { gpdb_data_source.owner_account }
    let(:schema) { schemas(:default) }

    it 'returns true if the user can access the gpdb instance' do
      owner = account.owner
      any_instance_of(GpdbDataSource) do |instance|
        mock(instance).accessible_to(owner) { true }
      end

      schema.accessible_to(owner).should be_true
    end
  end

  context ".refresh" do
    let(:gpdb_data_source) { data_sources(:owners) }
    let(:account) { gpdb_data_source.owner_account }
    let(:database) do
      stub(schema.database).connect_with(account) { connection }
      schema.database
    end
    let(:schema) { schemas(:default) }
    let(:settings) do
      {
          :host => gpdb_data_source.host,
          :port => gpdb_data_source.port,
          :username => account.db_username,
          :password => account.db_password,
          :database => database.name
      }
    end
    let(:connection) { Object.new }

    before(:each) do
      stub(Dataset).refresh

      stub(connection).schemas { ["new_schema", schema.name] }
    end

    it "creates new copies of the schemas in our db" do
      schemas = GpdbSchema.refresh(account, database)

      database.schemas.where(:name => "new_schema").should exist
    end

    it "passes the options Dataset.refresh" do
      options = {:dostuff => true, :refresh_all => true}
      mock(Dataset).refresh(account, anything, options)
      GpdbSchema.refresh(account, database, options)
    end

    it "does not re-create schemas that already exist in our database" do
      GpdbSchema.refresh(account, database)
      expect {
        GpdbSchema.refresh(account, database)
      }.not_to change(GpdbSchema, :count)
    end

    it "does not refresh existing Datasets" do
      GpdbSchema.refresh(account, database)
      dont_allow(Dataset).refresh.with_any_args
      GpdbSchema.refresh(account, database)
    end

    it "refreshes all Datasets when :refresh_all is true" do
      mock(Dataset).refresh.with_any_args.twice
      GpdbSchema.refresh(account, database, :refresh_all => true)
    end

    it "marks schema as stale if it does not exist" do
      missing_schema = database.schemas.where("id <> #{schema.id}").first
      GpdbSchema.refresh(account, database, :mark_stale => true)
      missing_schema.reload.should be_stale
      missing_schema.stale_at.should be_within(5.seconds).of(Time.current)
    end

    it "does not mark schema as stale if flag is not set" do
      missing_schema = database.schemas.where("id <> #{schema.id}").first
      GpdbSchema.refresh(account, database)
      missing_schema.reload.should_not be_stale
    end

    it "does not update the stale_at time" do
      missing_schema = database.schemas.where("id <> #{schema.id}").first
      missing_schema.update_attributes({:stale_at => 1.year.ago}, :without_protection => true)
      GpdbSchema.refresh(account, database, :mark_stale => true)
      missing_schema.reload.stale_at.should be_within(5.seconds).of(1.year.ago)
    end

    it "clears stale flag on schema if it is found again" do
      schema.mark_stale!
      GpdbSchema.refresh(account, database)
      schema.reload.should_not be_stale
    end

    context "when the database is not available" do
      before do
        stub(connection).schemas { raise ActiveRecord::JDBCError.new("Broken!") }
      end

      it "marks all the associated schemas as stale if the flag is set" do
        GpdbSchema.refresh(account, database, :mark_stale => true)
        schema.reload.should be_stale
      end

      it "does not mark the associated schemas as stale if the flag is not set" do
        GpdbSchema.refresh(account, database)
        schema.reload.should_not be_stale
      end

      it "should return an empty array" do
        GpdbSchema.refresh(account, database).should == []
      end
    end
  end

  context "refresh returns the list of schemas", :greenplum_integration do
    let(:account) { InstanceIntegration.real_gpdb_account }
    let(:database) { GpdbDatabase.find_by_name(InstanceIntegration.database_name) }

    it "returns the sorted list of schemas" do
      schemas = GpdbSchema.refresh(account, database)
      schemas.should be_a(Array)
      schemas.map(&:name).sort.should == schemas.map(&:name).sort
    end
  end

  describe ".find_and_verify_in_source" do
    let(:schema) { schemas(:public) }
    let(:database) { schema.database }
    let(:user) { users(:owner) }
    let(:connection) { Object.new }

    before do
      mock(database).connect_as(anything) { connection }
      stub(GpdbSchema).find(schema.id) { schema }
    end

    context "when it exists in the source database" do
      before do
        mock(connection).schema_exists?(anything) { true }
      end

      it "returns the schema" do
        described_class.find_and_verify_in_source(schema.id, user).should == schema
      end
    end

    context "when it does not exist in the source database" do
      before do
        mock(connection).schema_exists?(anything) { false }
      end

      it "should raise ActiveRecord::RecordNotFound exception" do
        expect {
          described_class.find_and_verify_in_source(schema.id, user)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "#stored_functions" do
    let(:schema) { schemas(:public) }
    let(:account) { schema.database.gpdb_data_source.owner_account }
    let(:connection) { Object.new }

    before do
      stub(schema).connect_with(account) { connection }
      stub(connection).functions do
        [
            {:oid => 62792, :proname => "funky_town", :lanname => "sql", :rettype => "text", :proargnames => ["i"], :argtypes => "int4", :prosrc => " SELECT CAST($1 AS text) || ' is text' ", :description => "comment on funky_town"},
            {:oid => 62793, :proname => "towny_funk", :lanname => "sql", :rettype => "record", :proargnames => ["i", "foo", "bar"], :argtypes => "int4", :prosrc => " SELECT $1, CAST($1 AS text) || ' is text' ", :description => nil},
            {:oid => 63121, :proname => "multi_arg_function", :lanname => "sql", :rettype => "int4", :proargnames => ["i", "j", "k"], :argtypes => "float8", :prosrc => "select 1", :description => "comment on multi_arg"},
            {:oid => 63121, :proname => "multi_arg_function", :lanname => "sql", :rettype => "int4", :proargnames => ["i", "j", "k"], :argtypes => "varchar", :prosrc => "select 1", :description => "comment on multi_arg"},
            {:oid => 63121, :proname => "multi_arg_function", :lanname => "sql", :rettype => "int4", :proargnames => ["i", "j", "k"], :argtypes => "int4", :prosrc => "select 1", :description => "comment on multi_arg"}
          ]
      end
    end

    it "returns the GpdbSchemaFunctions" do
      functions = schema.stored_functions(account)

      functions.count.should == 3

      last_function = functions.last
      last_function.should be_a GpdbSchemaFunction
      last_function.schema_name.should == schema.name
      last_function.function_name.should == "multi_arg_function"
      last_function.language.should == "sql"
      last_function.return_type.should == "int4"
      last_function.arg_names.should == ["i", "j", "k"]
      last_function.arg_types.should == ["float8", "varchar", "int4"]
      last_function.definition.should == "select 1"
      last_function.description.should == "comment on multi_arg"
    end
  end

  describe "#disk_space_used" do
    let(:schema) { schemas(:default) }
    let(:account) { instance_accounts(:unauthorized) }
    let(:connection) { Object.new }
    let(:disk_space_used) { 12345 }

    before do
      stub(schema).connect_with(account) { connection }
      mock(connection).disk_space_used { disk_space_used }
    end

    it "returns the disk space used by all relations in the schema" do
      schema.disk_space_used(account).should == 12345
    end

    it "caches the value" do
      schema.disk_space_used(account).should == 12345
      schema.disk_space_used(account).should == 12345
    end

    context "when we can't calculate the size" do
      let(:disk_space_used) { raise Exception }

      it "should return nil" do
        schema.disk_space_used(account).should be_nil
      end

      it "should cache the value correctly" do
        schema.disk_space_used(account).should be_nil
        schema.disk_space_used(account).should be_nil
      end
    end
  end

  describe "callbacks" do
    let(:schema) { schemas(:default) }

    describe "before_save" do
      describe "#mark_datasets_as_stale" do
        it "if the schema has become stale, datasets will also be marked as stale" do
          schema.update_attributes!({:stale_at => Time.current}, :without_protection => true)
          dataset = schema.datasets.views_tables.first
          dataset.should be_stale
          dataset.stale_at.should be_within(5.seconds).of(Time.current)
        end
      end
    end
  end

  describe "#connect_with" do
    let(:schema) { schemas(:public) }
    let(:account) { instance_accounts(:unauthorized) }

    it "should create a Greenplum SchemaConnection" do
      mock(GreenplumConnection).new({
                                                          :host => schema.gpdb_data_source.host,
                                                          :port => schema.gpdb_data_source.port,
                                                          :username => account.db_username,
                                                          :password => account.db_password,
                                                          :database => schema.database.name,
                                                          :schema => schema.name,
                                                          :logger => Rails.logger
                                                      })
      schema.connect_with(account)
    end
  end

  describe '#active_tables_and_views' do
    let(:schema) { schemas(:default) }

    it 'does not include chorus views' do
      cv = nil
      expect {
        cv = FactoryGirl.create(:chorus_view, :schema => schema)
      }.not_to change { schema.reload.active_tables_and_views.size }
      schema.active_tables_and_views.should_not include(cv)
    end

    it 'includes tables' do
      table = nil
      expect {
        table = FactoryGirl.create(:gpdb_table, :schema => schema)
      }.to change { schema.reload.active_tables_and_views.size }.by(1)
      schema.active_tables_and_views.should include(table)

      expect {
        table.stale_at = Time.now
        table.save!
      }.to change { schema.reload.active_tables_and_views.size }.by(-1)
      schema.active_tables_and_views.should_not include(table)
    end

    it 'includes views' do
      view = nil

      expect {
        view = FactoryGirl.create(:gpdb_view, :schema => schema)
      }.to change { schema.reload.active_tables_and_views.size }.by(1)
      schema.active_tables_and_views.should include(view)

      expect {
        view.stale_at = Time.now
        view.save!
      }.to change { schema.reload.active_tables_and_views.size }.by(-1)
      schema.active_tables_and_views.should_not include(view)
    end
  end
end
