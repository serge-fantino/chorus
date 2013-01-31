require 'spec_helper'

describe DatasetsController do
  let(:user) { users(:the_collaborator) }
  let(:instance_account) { gpdb_data_source.account_for_user!(user) }
  let(:gpdb_data_source) { data_sources(:owners) }
  let(:schema) { schemas(:default) }
  let(:table) { datasets(:table) }

  before do
    log_in user
  end

  context "#index" do
    context "with stubbed greenplum" do
      let(:dataset1) { datasets(:table) }
      let(:dataset2) { datasets(:view) }
      let(:dataset3) { datasets(:other_table) }
      before do
        stub(Dataset).visible_to(is_a(InstanceAccount), schema, options) do
          [dataset1, dataset2, dataset3]
        end
        stub(Dataset).total_entries { 122 }
        stub(table).add_metadata!(instance_account)
      end

      context "without any filter " do
        let(:options) { {:limit => per_page} }
        let(:per_page) { 50 }
        it "should retrieve authorized db objects for a schema" do
          get :index, :schema_id => schema.to_param

          response.code.should == "200"
          decoded_response.length.should == 3
          decoded_response.map(&:object_name).should match_array([dataset1.name, dataset2.name, dataset3.name])
          schema.datasets.size > decoded_response.size #Testing that controller shows a subset of datasets
        end

        context "pagination" do
          let(:per_page) { 1 }

          it "should paginate results" do
            get :index, :schema_id => schema.to_param, :per_page => per_page
            decoded_response.length.should == 1
          end
        end

        it "should sort db objects by name" do
          get :index, :schema_id => schema.to_param
          # stub checks for valid SQL with sorting
        end
      end

      context "with filter" do
        let(:options) { {:name_filter => 'view', :limit => 50} }
        it "should filter db objects by name" do
          get :index, :schema_id => schema.to_param, :filter => 'view'
          # stub checks for valid SQL with sorting and filtering
        end
      end
    end

    context "with real greenplum", :greenplum_integration do
      let(:user) { users(:admin) }
      let(:schema) { InstanceIntegration.real_database.schemas.find_by_name('test_schema') }

      context "when searching" do
        before do
          get :index, :schema_id => schema.to_param, :filter => 'CANDY', :page => "1", :per_page => "5"
        end

        it "presents the correct count / pagination information" do
          decoded_pagination.records.should == 7
          decoded_pagination.total.should == 2
        end

        it "returns sandbox datasets that aren't on the first page of unfiltered results" do
          decoded_response.map(&:object_name).should include('candy_empty')
        end
      end
    end
  end

  describe "#show" do
    before do
      any_instance_of(GpdbTable) do |dataset|
        stub(dataset).verify_in_source(user) { true }
      end
    end

    context "when dataset is valid in GPDB" do
      it "should retrieve the db object for a schema" do
        mock.proxy(Dataset).find_and_verify_in_source(table.id, user)

        get :show, :id => table.to_param

        response.code.should == "200"
        decoded_response.object_name.should == table.name
        decoded_response.object_type.should == "TABLE"
      end

      context "when the user does not have permission" do
        let(:user) { users(:not_a_member) }

        it "should return forbidden" do
          get :show, :id => table.to_param

          response.code.should == "403"
        end
      end

      generate_fixture "dataset.json" do
        get :show, :id => table.to_param
      end
    end

    context "when dataset is not valid in GPDB" do
      it "should raise an error" do
        stub(Dataset).find_and_verify_in_source(table.id, user) { raise ActiveRecord::RecordNotFound.new }

        get :show, :id => table.to_param

        response.code.should == "404"
      end
    end
  end
end