require "spec_helper"

describe ChorusView do
  describe "validations" do
    it { should validate_presence_of(:workspace) }
    it { should validate_presence_of(:query) }

    describe "#validate_query", :greenplum_integration do
      let(:database) { InstanceIntegration.real_database }
      let(:schema) { database.schemas.find_by_name('public') }
      let(:account) { InstanceIntegration.real_gpdb_account }
      let(:gpdb_data_source) { InstanceIntegration.real_gpdb_data_source }
      let(:workspace) { workspaces(:public)}
      let(:user) { users(:the_collaborator) }
      let(:chorus_view) { FactoryGirl.build(:chorus_view, :schema => schema, :workspace => workspace) }
      let(:query) { "selecT 1;" }

      before do
        set_current_user(user)
        chorus_view.query = query # Factory by default represses validation
      end

      it "can be valid" do
        chorus_view.should be_valid
      end

      describe 'with comment containing semicolon' do
        describe 'single line comment' do
          let(:query) {  "select 1; -- a comment with semicolon ; in it" }

          it "can be valid" do
            chorus_view.should be_valid
          end

          describe 'with multiple statements' do
            let(:query) {  "select 1; -- a comment with semicolon ; in it\n select 2;" }

            it 'is invalid' do
              chorus_view.should_not be_valid
              chorus_view.should have_error_on(:query).with_message(:multiple_result_sets)
            end
          end
        end

        describe 'multi line comment' do
          let(:query) {  "select 1; /* a comment with semicolon ; in\n it */" }

          it "can be valid" do
            chorus_view.should be_valid
          end

          describe 'with multiple statements' do
            let(:query) {  "select 1; /* a comment with semicolon ; in\n it */ select 2;" }

            it 'is invalid' do
              chorus_view.should_not be_valid
              chorus_view.should have_error_on(:query).with_message(:multiple_result_sets)
            end
          end
        end
      end

      describe 'with multiple statements' do
        let(:query) {  "select 1; create table a_new_table()" }

        it 'is invalid' do
          chorus_view.should_not be_valid
          chorus_view.should have_error_on(:query).with_message(:multiple_result_sets)
        end

        it 'cleans up' do
          chorus_view.validate_query
          schema.connect_with(account).table_exists?('a_new_table').should be_false
        end
      end

      describe 'when it references a nonexistent table' do
        let(:query) { "select * from a_non_existent_table_aaa;" }

        it 'is invalid' do
          chorus_view.should_not be_valid
          chorus_view.should have_error_on(:query).with_message(:generic)
        end
      end

      describe 'when it starts with not select or with' do
        let(:query) { "create table query_not_starting_with_keyword_table();" }
        it 'is invalid' do
          chorus_view.should_not be_valid
          chorus_view.should have_error_on(:query).with_message(:start_with_keywords)
        end
      end
    end
  end

  describe "update" do
    let(:chorus_view) { datasets(:chorus_view) }

    it "prevents schema from being updated" do
      new_schema = schemas(:public)
      chorus_view.schema.should_not == new_schema
      chorus_view.schema = new_schema
      chorus_view.schema_id = new_schema.id
      chorus_view.save!
      chorus_view.reload
      chorus_view.schema.should_not == new_schema
    end

    it "prevents workspace from being updated" do
      new_workspace = workspaces(:public_with_no_collaborators)
      chorus_view.workspace.should_not == new_workspace
      chorus_view.workspace = new_workspace
      chorus_view.workspace_id = new_workspace.id
      chorus_view.save!
      chorus_view.reload
      chorus_view.workspace.should_not == new_workspace
    end
  end

  describe "#preview_sql" do
    let(:chorus_view) do
      ChorusView.new({:name => "query",
                      :schema => schemas(:default),
                      :query => "select 1"},
                     :without_protection => true)
    end

    it "returns the query" do
      chorus_view.preview_sql.should == "select 1"
    end
  end

  describe "#all_row_sql" do
    let(:chorus_view) do
      ChorusView.new({:name => "query",
                      :schema => schemas(:default),
                      :query => "select 1"},
                     :without_protection => true)
    end

    it "returns the correct sql" do
      chorus_view.all_rows_sql().strip.should == %Q{SELECT * FROM (select 1) AS cv_query}
    end

    it "returns the sql without semicolon" do
      chorus_view.query = "select 2;"
      chorus_view.all_rows_sql().strip.should == %Q{SELECT * FROM (select 2) AS cv_query}
    end

    context "with a limit" do
      it "uses the limit" do
        chorus_view.all_rows_sql(10).should match "LIMIT 10"
      end
    end
  end

  describe "#convert_to_database_view" do
    let(:chorus_view) { datasets(:executable_chorus_view) }
    let(:schema) { chorus_view.schema }
    let(:database) { schema.database }
    let(:gpdb_data_source) { database.gpdb_data_source }
    let(:account) { gpdb_data_source.owner_account }
    let(:user) { account.owner }
    let(:connection) { Object.new }
    let(:view_name) { 'a_new_database_view' }

    before do
      stub(schema).connect_as(user) { connection }
      stub(connection).view_exists?(anything) { false }
      stub(connection).create_view(anything, anything)
    end

    it 'creates a database view' do
      expect {
        chorus_view.convert_to_database_view(view_name, user)
      }.to change(GpdbView, :count).by(1)

      GpdbView.last.query.should == chorus_view.query
      GpdbView.last.name.should == view_name
    end

    it 'creates the view in greenplum db' do
      mock(connection).create_view(view_name, chorus_view.query)

      chorus_view.convert_to_database_view(view_name, user)
    end

    it "raises if a view with the same name already exists" do
      stub(connection).view_exists?(anything) { true }

      expect {
        chorus_view.convert_to_database_view(view_name, user)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "raises if it cant create the view" do
      stub(connection).create_view(view_name, anything) { raise GreenplumConnection::DatabaseError.new(StandardError.new()) }

      expect {
        chorus_view.convert_to_database_view(view_name, user)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '#check_duplicate_column' do
    let(:user) { users(:admin) }
    let(:chorus_view) { datasets(:executable_chorus_view) }

    it 'raises with duplicate column names' do
      chorus_view.update_attribute :query, 'select 1, 2, 3;'
      expect {
        chorus_view.check_duplicate_column(user)
      }.to raise_error(GreenplumConnection::DatabaseError)
    end

    it 'returns true when the column names are unique' do
      chorus_view.check_duplicate_column(user).should be_true
    end
  end

  describe '#add_metadata!(account)', :greenplum_integration do
    let(:schema) { database.schemas.find_by_name('test_schema') }
    let(:database) { InstanceIntegration.real_database }
    let(:chorus_view) { FactoryGirl.build(:chorus_view, :schema => schema, :query => "select 1, 2, 3, 4, 5") }
    let(:gpdb_data_source) { InstanceIntegration.real_gpdb_data_source }
    let(:account) { gpdb_data_source.owner_account }

    it "retrieves the statistics" do
      chorus_view.add_metadata!(account)
      chorus_view.statistics.column_count.should == 5
    end
  end
end