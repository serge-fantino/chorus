module DataSources
  class MembersController < ApplicationController
    wrap_parameters :account, :include => [:db_username, :db_password, :owner_id]

    def index
      accounts = GpdbDataSource.find(params[:data_source_id]).accounts
      present paginate(accounts.includes(:owner).order(:id))
    end

    def create
      gpdb_data_source = GpdbDataSource.unshared.find(params[:data_source_id])
      authorize! :edit, gpdb_data_source

      account = gpdb_data_source.accounts.find_or_initialize_by_owner_id(params[:account][:owner_id])
      account.attributes = params[:account]

      account.save!

      present account, :status => :created
    end

    def update
      gpdb_data_source = GpdbDataSource.find(params[:data_source_id])
      authorize! :edit, gpdb_data_source

      account = gpdb_data_source.accounts.find(params[:id])
      account.attributes = params[:account]
      account.save!

      present account, :status => :ok
    end

    def destroy
      gpdb_data_source = GpdbDataSource.find(params[:data_source_id])
      authorize! :edit, gpdb_data_source
      account = gpdb_data_source.accounts.find(params[:id])

      account.destroy
      render :json => {}
    end
  end
end
