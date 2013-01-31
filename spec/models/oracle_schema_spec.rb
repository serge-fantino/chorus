require 'spec_helper'

describe OracleSchema do
  describe "#data_source" do
    let(:schema) {
      OracleSchema.create!(:name => 'test_schema', :data_source => data_sources(:oracle))
    }

    it "returns the schemas parent" do
      schema.reload.data_source.should == data_sources(:oracle)
    end
  end

  describe "validations" do
    let(:schema) { OracleSchema.new(:name => 'test_schema', :data_source => data_sources(:oracle)) }

    it "requires there is a data source" do
      schema.data_source = nil
      schema.valid?.should be_false
      schema.errors_on(:data_source).should include(:blank)
    end

    it "requires a name" do
      schema.name = nil
      schema.valid?.should be_false
      schema.errors_on(:name).should include(:blank)
    end

    it "requires a unique name per data source" do
      schema.save!
      new_schema = OracleSchema.new(:name=> 'test_schema', :data_source => data_sources(:oracle))
      new_schema.valid?.should be_false
      new_schema.errors_on(:name).should include(:taken)

      new_schema.data_source = FactoryGirl.build(:oracle_data_source)
      new_schema.valid?.should be_true
    end

  end
end