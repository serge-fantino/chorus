class TaggingsController < ApplicationController
  MAXIMUM_TAG_LENGTH=100

  def create
    model = ModelMap.model_from_params(params[:entity_type], params[:entity_id])
    authorize! :show, model

    tag_names = params[:tag_names] || []
    tag_names.each do |tagname|
      raise_validation_error if tagname.length > MAXIMUM_TAG_LENGTH
    end

    model.tag_list = tag_names.uniq(&:downcase).sort.join "~"

    begin
      model.save!
    rescue ActiveRecord::RecordNotUnique
      model.save!
    end

    render :json => {}, :status => :created
  end

  private

  def raise_validation_error
    raise ApiValidationError.new(:base, :too_long,
                                 {:field => "Tag",
                                  :count => MAXIMUM_TAG_LENGTH })
  end

end
