require 'greenplum_connection'

class GpdbSchema < Schema
  include Stale
  include SoftDelete

  attr_accessible :database

  belongs_to :database, {
      :polymorphic => true,
      :foreign_key => 'parent_id',
      :foreign_type => 'parent_type',
      :class_name => 'GpdbDatabase'
  }

  has_many :workspaces, :foreign_key => :sandbox_id, :dependent => :nullify
  has_many :active_tables_and_views, :foreign_key => :schema_id, :class_name => 'Dataset',
           :conditions => ['type != :chorus_view AND stale_at IS NULL', :chorus_view => 'ChorusView']
  has_many :workfiles_as_execution_schema, :class_name => 'Workfile', :foreign_key => :execution_schema_id, :dependent => :nullify
  has_many :views, :source => :datasets, :class_name => 'GpdbView', :foreign_key => :schema_id
  has_many :tables, :source => :datasets, :class_name => 'GpdbTable', :foreign_key => :schema_id

  validates :name,
            :presence => true,
            :uniqueness => { :scope => [:parent_type, :parent_id] },
            :format => /^[^\/?&]*$/

  delegate :data_source, :account_for_user!, :to => :database

  before_save :mark_schemas_as_stale

  def self.refresh(account, database, options = {})
    found_schemas = []

    database.connect_with(account).schemas.each do |name|
      schema = database.schemas.find_or_initialize_by_name(name)
      next if schema.invalid?
      schema.stale_at = nil
      schema.save!
      GpdbDataset.refresh(account, schema, options) if options[:refresh_all]
      found_schemas << schema
    end

    found_schemas
  rescue ActiveRecord::JDBCError, ActiveRecord::StatementInvalid => e
    Chorus.log_error "Could not refresh schemas: #{e.message} on #{e.backtrace[0]}"
    return []
  ensure
    if options[:mark_stale]
      (database.schemas.not_stale - found_schemas).each do |schema|
        schema.stale_at = Time.current
        schema.save!
      end
    end
  end

  def self.visible_to(*args)
    refresh(*args)
  end

  def accessible_to(user)
    database.data_source.accessible_to(user)
  end

  def stored_functions(account)
    results = connect_with(account).functions

    #This would be a lot easier if the schema_function_query could use ARRAY_AGG,
    #but it is not available on GPDB 4.0

    reduced_results = results.reduce [-1, []] do |last, result|
      record = result.values
      last_record_id = last[0]
      functions = last[1]
      current_function = functions.last
      current_function_types = current_function[5] if current_function
      arg_type = record[5]

      if current_function and record[0] == last_record_id
        current_function_types << arg_type
      else
        record[5] = [arg_type]
        functions << record
      end

      [record[0], last[1]]
    end

    reduced_results.last.map do |record|
      GpdbSchemaFunction.new(name, *record[1..7])
    end
  end

  def disk_space_used(account)
    @disk_space_used ||= connect_with(account).disk_space_used
    @disk_space_used == :error ? nil : @disk_space_used
  rescue Exception
    @disk_space_used = :error
    nil
  end

  def with_gpdb_connection(account, set_search=true)
    database.with_gpdb_connection(account) do |conn|
      if set_search
        add_schema_to_search_path(conn)
      end
      yield conn
    end
  end
  def connect_with(account)
    ::GreenplumConnection.new(
        :host => data_source.host,
        :port => data_source.port,
        :username => account.db_username,
        :password => account.db_password,
        :database => database.name,
        :schema => name,
        :logger => Rails.logger
    )
  end

  def class_for_type(type)
    type == 'r' ? GpdbTable : GpdbView
  end

  private

  def add_schema_to_search_path(conn)
    conn.schema_search_path = "#{conn.quote_column_name(name)}, 'public'"
  rescue ActiveRecord::StatementInvalid
    conn.schema_search_path = "#{conn.quote_column_name(name)}"
  end

  def mark_schemas_as_stale
    if stale? && stale_at_changed?
      datasets.each do |dataset|
        dataset.mark_stale! unless dataset.type == "ChorusView"
      end
    end
  end
end
