require "tempfile"
require 'digest/md5'
require 'yaml'
require 'socket'

module InstanceIntegration
  REAL_GPDB_HOST = ENV['GPDB_HOST']
  REAL_HADOOP_HOST = ENV['HADOOP_HOST']
  REAL_ORACLE_HOST = ENV['ORACLE_HOST']
  FILES_TO_TRACK_CHANGES_OF = %w(instance_integration.rb create_gpadmin.sql create_private_test_schema.sql create_test_schemas.sql drop_and_create_gpdb_databases.sql drop_public_schema.sql)
  GPDB_VERSIONS_FILE = (File.join(File.dirname(__FILE__), '../../..', 'tmp/instance_integration_file_versions')).to_s

  def self.execute_sql(sql_file, database = greenplum_config['db_name'])
    puts "Executing SQL file: #{sql_file} on host: #{REAL_GPDB_HOST}"
    sql_read = File.read(File.expand_path("../#{sql_file}", __FILE__))

    sql = sql_read.gsub('gpdb_test_database', InstanceIntegration.database_name)

    database_string = "jdbc:postgresql://#{REAL_GPDB_HOST}:#{greenplum_port}/#{database}?user=#{greenplum_username}&password=#{greenplum_password}"
    Sequel.connect(database_string) do |database_connection|
      database_connection.run(sql)
    end
    return true
  rescue Exception => e
    puts e.message
    return false
  end

  def self.exec_sql_line(sql)
    conn = ActiveRecord::Base.postgresql_connection(
        :host => REAL_GPDB_HOST,
        :port => greenplum_port,
        :database => self.database_name,
        :username => greenplum_username,
        :password => greenplum_password,
        :adapter => "jdbcpostgresql")
    conn.exec_query(sql)
  end

  def self.setup_gpdb
    if gpdb_changed?
      puts "  Importing into #{InstanceIntegration.database_name}"
      execute_sql("create_gpadmin.sql")
      execute_sql("drop_and_create_gpdb_databases.sql")
      execute_sql("create_test_schemas.sql", database_name)
      execute_sql("create_private_test_schema.sql", "#{database_name}_priv")
      execute_sql("create_test_schemas.sql", "#{database_name}_wo_pub")
      execute_sql("drop_public_schema.sql", "#{database_name}_wo_pub")
      record_changes
    end
  end

  def self.record_changes
    results_hash = FILES_TO_TRACK_CHANGES_OF.inject({}) do |hash, file_name|
      hash[file_name] = sql_file_hash(file_name)
      hash
    end
    results_hash["GPDB_HOST"] = ENV['GPDB_HOST']
    gpdb_versions_file.open('w') do |f|
      YAML.dump(results_hash, f)
    end
  end

  def self.gpdb_changed?
    versions = gpdb_versions_hash
    FILES_TO_TRACK_CHANGES_OF.any? do |file_name|
      versions[file_name.to_s] != sql_file_hash(file_name)
    end || versions["GPDB_HOST"] != ENV['GPDB_HOST']
  end

  def self.gpdb_versions_hash
    return {} unless gpdb_versions_file.exist?
    YAML.load_file(gpdb_versions_file.to_s)
  end

  def self.gpdb_versions_file
    Pathname.new(GPDB_VERSIONS_FILE + "_#{ENV['RAILS_ENV']}.yml")
  end

  def self.sql_file_hash(file_name)
    full_path = File.expand_path("../#{file_name}",  __FILE__)
    Digest::MD5.hexdigest(File.read(full_path))
  end

  def self.database_name
    "gpdb_#{Socket.gethostname.gsub('.', '_')}_#{ENV['RAILS_ENV']}".slice(0, 26) # needs to fit in 31 characters with _priv appended
  end

  def self.instance_config_for_gpdb(name)
    config = find_greenplum_instance name
    account_config = config['account']
    config.reject { |k, v| k == "account" }.merge(account_config)
  end

  def self.instance_config_for_hadoop(name = REAL_HADOOP_HOST)
    config['instances']['hadoop'].find { |hash| hash["host"] == name }
  end

  def self.account_config_for_gpdb(name)
    find_greenplum_instance(name)['account']
  end

  def self.refresh_chorus
    InstanceIntegration.setup_gpdb

    account = InstanceIntegration.real_gpdb_account
    GpdbDatabase.refresh(account)

    database = GpdbDatabase.find_by_name(InstanceIntegration.database_name)
    GpdbSchema.refresh(account, database)
    gpdb_schema = database.schemas.find_by_name('test_schema')
    Dataset.refresh(account, gpdb_schema)

    database_without_public_schema = GpdbDatabase.find_by_name("#{InstanceIntegration.database_name}_priv")
    GpdbSchema.refresh(account, database_without_public_schema)
    gpdb_schema_without_public_schema = database_without_public_schema.schemas.find_by_name('non_public_schema')
    Dataset.refresh(account, gpdb_schema_without_public_schema)

    account
  end

  def refresh_chorus
    InstanceIntegration.refresh_chorus
  end

  def self.greenplum_hostname
    REAL_GPDB_HOST
  end

  def self.real_gpdb_account
    gpdb_data_source = InstanceIntegration.real_gpdb_data_source
    gpdb_data_source.owner_account
  end

  def self.real_gpdb_data_source
    GpdbDataSource.find_by_name(greenplum_hostname)
  end

  def self.real_oracle_data_source
    OracleDataSource.find_by_host(oracle_hostname)
  end

  def self.real_database
    real_gpdb_data_source.databases.find_by_name!(self.database_name)
  end

  def self.greenplum_username
    greenplum_account['db_username']
  end

  def self.greenplum_password
    greenplum_account['db_password']
  end

  def self.greenplum_port
    greenplum_config['port']
  end

  def self.oracle_hostname
    REAL_ORACLE_HOST
  end

  def self.oracle_username
    oracle_account['db_username']
  end

  def self.oracle_password
    oracle_account['db_password']
  end

  def self.oracle_port
    oracle_config['port']
  end

  def self.oracle_db_name
    oracle_config['db_name']
  end

  private

  def self.config
    config_file = "test_instance_connection_config.yml"
    @@config ||= YAML.load_file(File.join(File.dirname(__FILE__), '../../..', "spec/support/#{config_file}"))
  end

  def self.greenplum_config
    @@gp_config ||= find_greenplum_instance REAL_GPDB_HOST
  end

  def self.oracle_config
    @@oracle_config ||= find_oracle_data_source REAL_ORACLE_HOST
  end

  def self.find_greenplum_instance(name)
    config['instances']['gpdb'].find { |hash| hash["host"] == name }
  end

  def self.find_oracle_data_source(name)
    config['instances']['oracle'].find { |hash| hash["host"] == name }
  end

  def self.greenplum_account
    greenplum_config['account'] || {}
  end

  def self.oracle_account
    oracle_config['account'] || {}
  end



end

