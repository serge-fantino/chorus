module DataSources
  class SchemasController < ApplicationController
    def index
      data_source = DataSource.find(params[:data_source_id])
      present data_source.refresh_schemas
    end
  end
end