require 'dataset'

class ChorusView < GpdbDataset
  include SharedSearch

  attr_accessible :query, :object_name, :schema_id, :workspace_id
  attr_readonly :schema_id, :workspace_id

  belongs_to :workspace

  include_shared_search_fields :workspace, :workspace

  validates_presence_of :workspace, :query
  validate :validate_query, :if => :query

  alias_attribute :object_name, :name

  def create_duplicate_chorus_view name
    chorus_view = ChorusView.new
    chorus_view.schema = schema
    chorus_view.query = query
    chorus_view.master_table = master_table
    chorus_view.name = name
    chorus_view.workspace = workspace
    chorus_view
  end

  def validate_query
    return unless changes.include?(:query)
    unless query.upcase.start_with?("SELECT", "WITH")
      errors.add(:query, :start_with_keywords)
    end

    query_without_comments = query.gsub(/\-\-.*?$|\/\*[\s\S]*?\*\//, "")
    if query_without_comments.match /;\s*\S/
      errors.add(:query, :multiple_result_sets)
      return
    end
    schema.connect_as(current_user).test_transaction do |conn|
      begin
        conn.fetch_value(query_without_comments.gsub ";", "")
      rescue GreenplumConnection::DatabaseError => e
        errors.add(:query, :generic, {:message => e.message})
      end
    end
  end

  def preview_sql
    query
  end

  def column_name
  end

  def check_duplicate_column(user)
    account = data_source.account_for_user!(user)
    GpdbColumn.columns_for(account, self)
  end

  def query_setup_sql
    #set search_path to "#{schema.name}";
    %Q{create temp view "#{name}" as #{query};}
  end

  def as_sequel
    {
        :query => query_setup_sql,
        :identifier => Sequel.qualify(schema.name, name)
    }
  end

  def scoped_name
    %Q{"#{name}"}
  end

  def all_rows_sql(limit = nil)
    sql = "SELECT * FROM (#{query.gsub(';', '');}) AS cv_query"
    sql += " LIMIT #{limit}" if limit
    sql
  end

  def convert_to_database_view(name, user)
    view = schema.views.build(:name => name)
    view.query = query

    if schema.connect_as(user).view_exists?(name)
      view.errors.add(:name, :taken)
      raise ActiveRecord::RecordInvalid.new(view)
    end

    begin
      schema.connect_as(user).create_view(name, query)
      view.save!
      view
      # TODO
    rescue GreenplumConnection::DatabaseError => e
      view.errors.add(:base, :generic, {:message => e.message})
      raise ActiveRecord::RecordInvalid.new(view)
    end
  end

  def add_metadata!(account)
    result = connect_with(account).prepare_and_execute_statement(query, :describe_only => true)
    @statistics = DatasetStatistics.new('column_count' => result.columns.count)
  end

  def verify_in_source(user)
    true
  end
end