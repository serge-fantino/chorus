require 'spec_helper'

describe OracleDataSource do
  describe "validations" do
    let(:instance) { FactoryGirl.build(:oracle_data_source) }

    it { should validate_presence_of(:host) }
    it { should validate_presence_of(:port) }

    context "when creating" do
      it "should validate owner account" do
        mock(instance).owner_account { mock(FactoryGirl.build(:instance_account)).valid? { true } }
        instance.valid?
      end
    end

    context "when host, port, or db_name change" do
      before do
        instance.save!(:validate => false)
        mock(instance).owner_account { mock(FactoryGirl.build(:instance_account)).valid? { true } }
      end

      it "validates the account when host changes" do
        instance.host = 'something_new'
        instance.valid?
      end
      it "validates the account when port changes" do
        instance.port = '5413'
        instance.valid?
      end
      it "validates the account when db_name changes" do
        instance.db_name = 'something_new'
        instance.valid?
      end
    end
  end

  describe "owner_account" do
    it "is created automatically" do
      instance = FactoryGirl.build(:oracle_data_source, :owner_account => nil)
      stub(instance).valid_db_credentials?(anything) { true }
      instance.save!
      instance.owner_account.should_not be_nil
    end
  end

  describe "#schemas" do
    let(:new_oracle) { FactoryGirl.create(:oracle_data_source) }
    let(:schema) { OracleSchema.create!(:name => 'test_schema', :data_source => new_oracle) }

    it "includes schemas" do
      new_oracle.schemas.should include schema
    end
  end

  describe "#refresh_schemas" do
    let(:instance) { data_sources(:oracle) }
    let(:connection) { Object.new }

    before do
      mock(OracleConnection).new(anything) {
        connection
      }

      mock(connection).schemas { ["schema_one", "schema_two"] }
    end

    it "returns the OracleSchemas in the data source" do
      schemas = instance.refresh_schemas
      schemas.map(&:name).should == ["schema_one", "schema_two"]
      schemas.reject { |schema| schema.class == OracleSchema }.length == 0
    end

    it "updates the data sources schemas" do
      instance.schemas.should be_empty
      instance.schemas.create(:name => 'test_schema')
      instance.refresh_schemas

      instance.reload.schemas.map(&:name).should == ["schema_one", "schema_two"]
    end
  end
end