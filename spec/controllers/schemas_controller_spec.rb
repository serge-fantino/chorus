require 'spec_helper'

describe SchemasController do
  ignore_authorization!

  let(:user) { users(:owner) }

  before do
    log_in user
  end

  describe "#show" do
    let(:schema) { schemas(:default) }
    before do
      any_instance_of(GpdbSchema) do |schema|
        stub(schema).verify_in_source { true }
      end
    end

    it "uses authorization" do
      mock(subject).authorize!(:show_contents, schema.gpdb_data_source)
      get :show, :id => schema.to_param
    end

    it "renders the schema" do
      get :show, :id => schema.to_param
      response.code.should == "200"
      decoded_response.id.should == schema.id
    end

    it "verifies the schema exists" do
      mock.proxy(GpdbSchema).find_and_verify_in_source(schema.id.to_s, user)
      get :show, :id => schema.to_param
      response.code.should == "200"
    end

    context "when the schema can't be found" do
      it "returns 404" do
        get :show, :id => "-1"
        response.code.should == "404"
      end
    end

    generate_fixture "schema.json" do
      get :show, :id => schema.to_param
    end

    context "when the schema is not in GPDB" do
      it "should raise an error" do
        stub(GpdbSchema).find_and_verify_in_source(schema.id.to_s, user) { raise ActiveRecord::RecordNotFound.new }

        get :show, :id => schema.to_param

        response.code.should == "404"
      end
    end
  end
end
