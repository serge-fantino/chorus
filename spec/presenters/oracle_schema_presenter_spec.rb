require 'spec_helper'

describe OracleSchemaPresenter, :type => :view  do
  let(:schema) { FactoryGirl.create(:oracle_schema) }
  let(:presenter) { OracleSchemaPresenter.new(schema, view) }
  let(:hash) { presenter.to_hash }

  describe '#to_hash' do
    it 'includes the fields' do
      hash[:id].should == schema.id
      hash[:name].should == schema.name
    end
  end
end