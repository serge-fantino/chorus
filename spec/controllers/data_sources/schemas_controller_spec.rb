require 'spec_helper'

describe DataSources::SchemasController do
  let(:user) { users(:owner) }
  let(:data_source) { data_sources(:oracle) }

  before do
    log_in user
  end

  describe "#index" do
    let(:schema_1) { FactoryGirl.create(:oracle_schema) }
    let(:schema_2) { FactoryGirl.create(:oracle_schema) }

    before do
      mock(DataSource).find(data_source.id.to_s) {
        mock(data_source).refresh_schemas {
          [schema_1, schema_2]
        }
      }
    end

    it 'returns a 200 status code' do
      get :index, :data_source_id => data_source.to_param
      response.status.should == 200
    end

    it 'presents the schemas' do
      mock_present do |models|
        models.should == [schema_1, schema_2]
      end

      get :index, :data_source_id => data_source.to_param
    end
  end
end