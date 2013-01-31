require_relative 'data_source_connection'

if ChorusConfig.instance.oracle_configured?
  begin
    require_relative 'libraries/ojdbc6.jar'
  rescue LoadError
    Rails.logger.warn "Error loading Oracle driver"
  end
elsif ChorusConfig.instance.oracle_driver_expected_but_missing?
  Rails.logger.warn "Oracle driver ojdbc6.jar not found"
end

class OracleConnection < DataSourceConnection
  class DatabaseError < Error
    def error_type
      error_code = @exception.wrapped_exception && @exception.wrapped_exception.respond_to?(:get_error_code) && @exception.wrapped_exception.get_error_code
      Rails.logger.error "Oracle error code = #{error_code}"
      errortype = case error_code
        when 1017 then :INVALID_PASSWORD
        when 12514 then :DATABASE_MISSING
        when 17002 then :INSTANCE_UNREACHABLE
        else :GENERIC
      end
      Rails.logger.error "Oracle error code type = #{errortype}"
      errortype
    end

    private

    def sanitize_message(message)
      # jdbc:oracle:thin:username/password@//host:port/database
      message.gsub /\:[^\:]+\/.+@\/\//, ':xxxx/xxxx@//'
    end
  end

  def initialize(details)
    @settings = details
  end

  def connect!
    @connection ||= Sequel.connect(db_url, :test => true)
  rescue Sequel::DatabaseError => e
    raise OracleConnection::DatabaseError.new(e)
  end

  def connected?
    !!@connection
  end

  def disconnect
    @connection.disconnect if @connection
    @connection = nil
  end

  def version
    connect!
    result = @connection.fetch(%Q{select * from v$version where banner like 'Oracle%'}).first.first[1]
    disconnect
    result.match(/((\d+\.)+\d+)/)[1]
  end

  def schemas
    with_connection { @connection.fetch(SCHEMAS_SQL).map { |row| row[:name] } }
  end

  private

  SCHEMAS_SQL = <<-SQL
      SELECT DISTINCT OWNER as name
      FROM ALL_OBJECTS
      WHERE OBJECT_TYPE IN ('TABLE', 'VIEW') AND OWNER NOT IN ('OBE', 'SCOTT', 'DIP', 'ORACLE_OCM', 'XS$NULL', 'MDDATA', 'SPATIAL_WFS_ADMIN_USR', 'SPATIAL_CSW_ADMIN_USR', 'TESTUSER2', 'IX', 'SH', 'PM', 'BI', 'DEMO', 'HR1', 'OE1', 'XDBPM', 'XDBEXT', 'XFILES', 'APEX_PUBLIC_USER', 'TIMESTEN', 'CACHEADM', 'PLS', 'TTHR', 'APEX_REST_PUBLIC_USER', 'APEX_LISTENER', 'OE', 'HR', 'HR_TRIG', 'PHPDEMO', 'APPQOSSYS', 'WMSYS', 'OWBSYS_AUDIT', 'OWBSYS', 'SYSMAN', 'EXFSYS', 'CTXSYS', 'XDB', 'ANONYMOUS', 'OLAPSYS', 'APEX_040200', 'ORDSYS', 'ORDDATA', 'ORDPLUGINS', 'FLOWS_FILES', 'SI_INFORMTN_SCHEMA', 'MDSYS', 'DBSNMP', 'OUTLN', 'MGMT_VIEW', 'SYSTEM', 'SYS')
  SQL

  def db_url
    "jdbc:oracle:thin:#{@settings[:username]}/#{@settings[:password]}@//#{@settings[:host]}:#{@settings[:port]}/#{@settings[:database]}"
  end

  def with_connection(options = {})
    connect!
    yield
  rescue Sequel::DatabaseError => e
    raise OracleConnection::DatabaseError.new(e)
  ensure
    disconnect
  end
end