require 'spec_helper'

describe DataSources::SharingController do
  let(:gpdb_data_source) { data_sources(:owners) }
  let(:owner_account) { gpdb_data_source.owner_account }
  let(:owner) { users(:owner) }
  let(:user) { users(:default) }

  describe "#create" do
    before do
      log_in owner
    end

    it "sets the shared attribute on an unshared gpdb instance" do
      gpdb_data_source.update_attributes(:shared => false)
      post :create, :data_source_id => gpdb_data_source.to_param
      decoded_response.shared.should be_true
    end

    it "keeps the shared attribute on a shared gpdb instance" do
      gpdb_data_source.update_attributes(:shared => true)
      post :create, :data_source_id => gpdb_data_source.to_param
      decoded_response.shared.should be_true
    end

    it "deletes accounts other than those belonging to the gpdb instance owner" do
      other_account = gpdb_data_source.account_for_user(users(:the_collaborator))

      post :create, :data_source_id => gpdb_data_source.to_param

      owner_account.reload.should be_present
      InstanceAccount.where(:id => other_account.id).exists?.should be_false
    end

    it "rejects non-owners" do
      log_in user
      post :create, :data_source_id => gpdb_data_source.to_param
      response.should be_forbidden
    end

    it "rejects non-owners of shared accounts" do
      log_in user
      gpdb_data_source.update_attributes(:shared => true)

      post :create, :data_source_id => gpdb_data_source.to_param
      response.should be_forbidden
    end
  end

  describe "#destroy" do
    before do
      log_in owner
    end

    it "removes the shared attribute from a shared gpdb instance" do
      gpdb_data_source.update_attributes(:shared => true)
      delete :destroy, :data_source_id => gpdb_data_source.to_param
      decoded_response.shared.should_not be_true
    end

    it "keeps the unshared attribute on an unshared gpdb instance" do
      gpdb_data_source.update_attributes(:shared => false)
      delete :destroy, :data_source_id => gpdb_data_source.to_param
      decoded_response.shared.should_not be_true
    end

    it "rejects non-owners" do
      log_in user
      delete :destroy, :data_source_id => gpdb_data_source.to_param
      response.should be_forbidden
    end

    it "rejects non-owners of shared accounts" do
      log_in user
      gpdb_data_source.update_attributes(:shared => true)

      delete :destroy, :data_source_id => gpdb_data_source.to_param
      response.should be_forbidden
    end
  end
end
