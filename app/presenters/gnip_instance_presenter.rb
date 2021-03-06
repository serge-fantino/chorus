class GnipInstancePresenter < Presenter

  def to_hash
    {
        :name => model.name,
        :stream_url => model.stream_url,
        :id => model.id,
        :description => model.description,
        :username => model.username,
        :state => "online",
        :entity_type => model.entity_type_name
    }.merge(owner_hash)
  end

  def complete_json?
    !rendering_activities?
  end

  private

  def owner_hash
    if rendering_activities?
      {}
    else
      {:owner => model.owner}
    end
  end
end
