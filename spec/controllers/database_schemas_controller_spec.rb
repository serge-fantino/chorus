require 'spec_helper'

describe DatabaseSchemasController do
  ignore_authorization!

  let(:user) { users(:owner) }

  before do
    log_in user
  end

  describe "#index" do
    let(:gpdb_data_source) { data_sources(:owners) }
    let(:database) { gpdb_databases(:default) }
    let(:schema1) { database.schemas[0] }
    let(:schema2) { database.schemas[1] }

    before do
      stub(GpdbSchema).refresh(gpdb_data_source.account_for_user!(user), database) { [schema1, schema2] }
    end

    it 'uses authorization' do
      mock(subject).authorize!(:show_contents, gpdb_data_source)
      get :index, :database_id => database.to_param
    end

    it 'retrieves all schemas for a database' do
      get :index, :database_id => database.to_param

      response.code.should == "200"
      decoded_response.should have(2).items

      decoded_response[0].name.should == schema1.name
      decoded_response[0].database.instance.id.should == gpdb_data_source.id
      decoded_response[0].database.name.should == schema1.database.name
      decoded_response[0].dataset_count.should == schema1.active_tables_and_views.count

      decoded_response[1].name.should == schema2.name
      decoded_response[1].database.instance.id.should == gpdb_data_source.id
      decoded_response[1].database.name.should == schema2.database.name
      decoded_response[1].dataset_count.should == schema2.active_tables_and_views.count
    end

    it_behaves_like "a paginated list" do
      let(:params) {{ :database_id => database.to_param }}
    end

    generate_fixture "schemaSet.json" do
      get :index, :database_id => database.to_param
    end
  end
end