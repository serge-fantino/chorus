require 'spec_helper'

describe DataSourcesController do
  ignore_authorization!

  let(:user) { users(:owner) }

  before do
    log_in user
  end

  describe "#index" do
    it "returns all data source" do
      get :index
      response.code.should == "200"
      decoded_response.size.should == DataSource.count
    end

    it_behaves_like "a paginated list"

    it "returns all data sources (online and offline) that the user can access when accessible is passed" do
      get :index, :accessible => "true"
      response.code.should == "200"
      decoded_response.map(&:id).should include(data_sources(:offline).id)
    end

    describe "filtering by type" do
      it "filters by gpdb data sources" do
        get :index, :entity_type => "gpdb_data_source"
        decoded_response.map(&:id).should =~ GpdbDataSource.all.map(&:id)
      end

      it "filters by oracle data sources" do
        get :index, :entity_type => "oracle_data_source"
        decoded_response.map(&:id).should =~ OracleDataSource.all.map(&:id)
      end
    end
  end

  describe "#show" do
    let(:data_source) { DataSource.first }

    context "with a valid instance id" do
      it "does not require authorization" do
        dont_allow(subject).authorize!.with_any_args
        get :show, :id => data_source.to_param
      end

      it "succeeds" do
        get :show, :id => data_source.to_param
        response.should be_success
      end

      it "presents the gpdb instance" do
        mock.proxy(controller).present(data_source)
        get :show, :id => data_source.to_param
      end
    end

    generate_fixture "gpdbDataSource.json" do
      get :show, :id => data_sources(:owners).to_param
    end

    generate_fixture "oracleDataSource.json" do
      get :show, :id => data_sources(:oracle).to_param
    end

    context "with an invalid gpdb instance id" do
      it "returns not found" do
        get :show, :id => -1
        response.should be_not_found
      end
    end
  end

  describe "#update" do
    let(:changed_attributes) { {} }
    let(:gpdb_data_source) { data_sources(:shared) }
    let(:params) do
      {
          :id => gpdb_data_source.id,
          :name => "changed"
      }
    end

    before do
      any_instance_of(DataSource) { |ds| stub(ds).valid_db_credentials? { true } }
    end

    it "uses authorization" do
      mock(subject).authorize!(:edit, gpdb_data_source)
      put :update, params
    end

    it "presents the gpdb instance" do
      mock.proxy(controller).present(gpdb_data_source)
      put :update, params
    end

    it "returns 200" do
      put :update, params
      response.code.should == "200"
    end

    it "returns 422 when the update parameters are invalid" do
      params[:name] = ''
      put :update, params
      response.code.should == "422"
    end
  end

  describe "#create" do
    it_behaves_like "an action that requires authentication", :put, :update, :id => '-1'

    let(:valid_attributes) do
      {
          :name => "create_spec_name",
          :port => 12345,
          :host => "server.emc.com",
          :db_name => "postgres",
          :description => "old description",
          :db_username => "bob",
          :db_password => "secret",
          :entity_type => entity_type,
          :shared => false
      }
    end

    before do
      any_instance_of(DataSource) { |ds| stub(ds).valid_db_credentials? { true } }
    end

    context "for a GpdbDataSource" do
      let(:entity_type) { "gpdb_data_source" }

      it "creates the data source" do
        expect {
          post :create, valid_attributes
        }.to change(GpdbDataSource, :count).by(1)
        response.code.should == "201"
      end

      it "presents the gpdb data_source" do
        mock_present do |data_source|
          data_source.name == valid_attributes[:name]
        end
        post :create, valid_attributes
      end

      it "schedules a job to refresh the data_source" do
        stub(QC.default_queue).enqueue_if_not_queued(anything, anything)
        mock(QC.default_queue).enqueue_if_not_queued("GpdbDataSource.refresh", numeric, {'new' => true})
        post :create, :data_source => valid_attributes
      end

      context "with invalid attributes" do
        it "responds with validation errors" do
          valid_attributes.delete(:name)
          post :create, valid_attributes
          response.code.should == "422"
        end
      end
    end

    context "for an OracleDataSource" do
      let(:entity_type) { "oracle_data_source" }

      before do
        stub(ChorusConfig.instance).oracle_configured? { true }
      end

      it "creates a new OracleDataSource" do
        expect {
          post :create, valid_attributes
        }.to change(OracleDataSource, :count).by(1)
        response.code.should == "201"
      end

      it "presents the OracleDataSource" do
        mock_present do |data_source|
          data_source.name == valid_attributes[:name]
        end

        post :create, :data_source => valid_attributes
      end

      it "creates a shared OracleDataSource" do
        post :create, valid_attributes
        OracleDataSource.last.should be_shared
      end

      context "when oracle is not configured" do
        before do
          stub(ChorusConfig.instance).oracle_configured? { false }
        end

        it "should return an error" do
          post :create, valid_attributes
          response.code.should == "422"
          decoded_errors.fields.oracle.should have_key :NOT_CONFIGURED
        end
      end
    end

    context "for an unknown entity type" do
      let(:entity_type) { "######" }

      it "returns an error" do
        post :create, valid_attributes
        response.code.should == "422"
        decoded_errors.fields.entity_type.should have_key :INVALID
      end
    end
  end
end
