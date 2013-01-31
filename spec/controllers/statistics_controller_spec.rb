require 'spec_helper'

describe StatisticsController do
  let(:user) { users(:owner) }

  before do
    log_in user
  end

  context "#show" do
    let(:schema) { schemas(:default) }
    let(:instance_account) { schema.database.gpdb_data_source.owner_account }
    let!(:table) { datasets(:table) }

    let(:metadata_sql) { Dataset::Query.new(schema).metadata_for_dataset("table").to_sql }
    let(:partition_data_sql) { Dataset::Query.new(schema).partition_data_for_dataset(["table"]).to_sql }
    let(:metadata_info) {
      {
          'name' => 'table',
          'description' => 'a description',
          'definition' => nil,
          'column_count' => '3',
          'row_count' => '5',
          'table_type' => 'BASE_TABLE',
          'last_analyzed' => '2012-06-06 23:02:42.40264+00',
          'disk_size' => '500',
          'partition_count' => '6'
      }
    }

    let(:partitiondata_info) {
      {
          'disk_size' => '120000'
      }
    }

    context "with fake gpdb" do
      before do
        stub_gpdb(instance_account,
                  metadata_sql => [
                      metadata_info
                  ],
                  partition_data_sql => [
                      partitiondata_info
                  ]
        )
      end

      it "should retrieve the db object for a schema" do
        get :show, :dataset_id => table.to_param

        response.code.should == "200"
        decoded_response.columns.should == 3
        decoded_response.rows.should == 5
        decoded_response.description.should == 'a description'
        decoded_response.last_analyzed_time.to_s.should == "2012-06-06T23:02:42Z"
        decoded_response.partitions.should == 6
      end

      generate_fixture "datasetStatisticsTable.json" do
        get :show, :dataset_id => table.to_param
      end

      context "generating statistics for a chorus view" do
        let(:metadata_info) {
          {
              'name' => 'table',
              'description' => 'a description',
              'definition' => nil,
              'column_count' => '3',
              'row_count' => '5',
              'table_type' => 'BASE_TABLE',
              'last_analyzed' => '2012-06-06 23:02:42.40264+00',
              'disk_size' => '500',
              'partition_count' => '6',
              'definition' => 'Bobby DROP TABLES;'
          }
        }

        generate_fixture "datasetStatisticsView.json" do
          get :show, :dataset_id => table.to_param
        end
      end
    end

    context "with real gpdb connection", :greenplum_integration do
      context "when a chorus view uses a table that has been deleted" do
        let(:workspace) { workspaces(:gpdb_workspace) }
        let(:schema) { workspace.sandbox }
        let(:bad_chorus_view) do
          cv = FactoryGirl.build(:chorus_view, :name => "bad_chorus_view", :schema => schema, :query => "select * from bogus_table", :workspace => workspace)
          cv.save(:validate => false)
          cv
        end
        let(:user) { users(:admin) }

        it "returns a 422" do
          get :show, :dataset_id => bad_chorus_view.to_param
          response.code.should == "422"
        end
      end
    end
  end
end
