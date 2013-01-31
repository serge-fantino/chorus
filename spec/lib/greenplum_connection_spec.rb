require 'spec_helper'

describe GreenplumConnection, :greenplum_integration do
  let(:username) { InstanceIntegration.greenplum_username }
  let(:password) { InstanceIntegration.greenplum_password }
  let(:database_name) { InstanceIntegration.database_name }
  let(:the_host) { InstanceIntegration.greenplum_hostname }
  let(:port) { InstanceIntegration.greenplum_port }
  let(:db_url) {
    query_params = URI.encode_www_form(:user => details[:username], :password => details[:password], :loginTimeout => GreenplumConnection.gpdb_login_timeout)
    "jdbc:postgresql://#{details[:host]}:#{details[:port]}/#{details[:database]}?" << query_params
  }

  before :all do
    InstanceIntegration.setup_gpdb
  end

  before do
    stub.proxy(Sequel).connect.with_any_args
  end

  let(:details) { {
      :host => the_host,
      :username => username,
      :password => password,
      :port => port,
      :database => database_name
  } }

  let(:connection) { GreenplumConnection.new(details) }

  describe "#connect!" do
    context "when a logger is not provided" do
      before do
        mock.proxy(Sequel).connect(db_url, :test => true)
      end

      context "with valid credentials" do
        it "connects successfully passing no logging options" do
          connection.connect!
          connection.should be_connected
        end
      end
    end

    context "when a logger is provided" do
      let(:logger) do
        log = Object.new
        stub(log).debug
        log
      end

      let(:details) {
        {
            :host => the_host,
            :username => username,
            :password => password,
            :port => port,
            :database => database_name,
            :logger => logger
        }
      }

      before do
        mock.proxy(Sequel).connect(db_url, hash_including(:test => true, :sql_log_level => :debug, :logger => logger))
      end

      context "with valid credentials" do
        it "connects successfully passing the proper logging options" do
          connection.connect!
          connection.should be_connected
        end
      end
    end
  end

  describe "#disconnect" do
    before do
      mock_conn = Object.new

      mock(Sequel).connect(anything, anything) { mock_conn }
      mock(mock_conn).disconnect
      connection.connect!
    end

    it "disconnects Sequel connection" do
      connection.should be_connected
      connection.disconnect
      connection.should_not be_connected
    end
  end

  describe "#fetch" do
    let(:sql) { "SELECT 1 AS answer" }
    let(:parameters) { {} }
    let(:subject) { connection.fetch(sql) }
    let(:expected) { [{:answer => 1}] }

    it_should_behave_like "a well behaved database query"

    context "with SQL parameters" do
      let(:sql) { "SELECT :num AS answer" }
      let(:parameters) { {:num => 3} }

      it "succeeds" do
        connection.fetch(sql, parameters).should == [{:answer => 3}]
      end
    end
  end

  describe "#fetch_value" do
    let(:sql) { "SELECT * FROM ((SELECT 1) UNION (SELECT 2) UNION (SELECT 3)) AS thing" }
    let(:subject) { connection.fetch_value(sql) }
    let(:expected) { 1 }

    it_should_behave_like "a well behaved database query"

    it "returns nil for an empty set" do
      sql = "SELECT * FROM (SELECT * FROM (SELECT 1 as column1) AS set1 WHERE column1 = 2) AS empty"
      connection.fetch_value(sql).should == nil
    end
  end

  describe "#execute" do
    let(:sql) { "SET search_path TO 'public'" }
    let(:parameters) { {} }
    let(:subject) { connection.execute(sql) }
    let(:expected) { true }

    it_should_behave_like "a well behaved database query"
  end

  describe "#prepare_and_execute_statement" do
    let(:sql) { "SELECT 1 AS answer" }
    let(:options) { {} }
    let(:subject) { connection.prepare_and_execute_statement(sql, options) }
    let(:expected) { [{'answer' => '1'}] }

    it "should return a SqlResult" do
      subject.should be_a(SqlResult)
      subject.hashes.should == expected
    end

    describe "when the schema is set" do
      before do
        details.merge!(
            :schema => "test_schema",
            :logger => Rails.logger
        )
      end

      let(:sql) { "SELECT * from table_in_public" }

      it "doesn't search public by default" do
        expect {
          subject
        }.to raise_error(GreenplumConnection::QueryError, /"table_in_public" does not exist/)
      end

      describe "when including the public schema in the search path" do
        let(:options) { { :include_public_schema_in_search_path => true } }

        it "finds the the table in the public schema" do
          expect {
            subject.should be_a(SqlResult)
          }.not_to raise_error
        end

        context "when the database does not have a public schema" do
          let(:database_name) { InstanceIntegration.database_name << "_wo_pub" }
          let(:sql) { "SELECT 1" }

          it "does not raise an error" do
            expect {
              subject
            }.not_to raise_error
          end
        end
      end
    end

    context "when the query has no results" do
      let(:sql) { "" }

      it "should be empty" do
        subject.rows.should be_empty
      end
    end

    context "when there are multiple statements" do
      context "with multiple results" do
        let(:sql) { "SELECT 2 AS question; SELECT 1 AS answer" }

        it "should return the last results" do
          subject.should be_a(SqlResult)
          subject.hashes.should == expected
        end
      end

      context "when some don't have results" do
        let(:sql) { "create table surface_warnings (id INT PRIMARY KEY); drop table surface_warnings; SELECT 1 AS answer" }

        it "should return the last results" do
          subject.hashes.should == expected
        end
      end
    end

    context 'with warnings enabled' do
      let(:sql) { "create table surface_warnings (id INT PRIMARY KEY); drop table surface_warnings;create table surface_warnings (id INT PRIMARY KEY); drop table surface_warnings;" }
      let(:options) { {:warnings => true} }

      it 'surfaces all notices and warnings' do
        subject.warnings.length.should == 2
        subject.warnings.each do |warning|
          warning.should match /will create implicit index/
        end
      end
    end

    context "limiting queries" do
      let(:sql) { "select 1 as hi limit 3; select * from test_schema.base_table1 limit 4" }

      context "when a limit is passed" do
        let(:options) { {:limit => 1} }

        it "should limit the query" do
          subject.rows.length.should == 1
        end

        it "should optimize the query to only actually fetch the limited number of rows, not just fetch all and subselect" do
          stub.proxy(Sequel).connect(db_url, :test => true) do |connection|
            connection.synchronize(:default) do |jdbc_conn|
              mock.proxy(jdbc_conn).set_auto_commit(false)
              stub.proxy(jdbc_conn).prepare_statement do |statement|
                mock.proxy(statement).set_fetch_size(1)
              end
              mock.proxy(jdbc_conn).commit

              stub(connection).synchronize.with_no_args.yields(jdbc_conn)
            end
            connection
          end

          subject
        end
      end

      context "when no limit is passed" do
        it "should not limit the query" do
          subject.rows.length.should > 1
        end

        it "should continue to use auto_commit" do
          stub.proxy(Sequel).connect(db_url, :test => true) do |connection|
            connection.synchronize(:default) do |jdbc_conn|
              dont_allow(jdbc_conn).set_auto_commit(false)
              dont_allow(jdbc_conn).commit

              stub(connection).synchronize.with_no_args.yields(jdbc_conn)
            end
            connection
          end

          subject
        end
      end
    end

    context "when an error occurs" do
      let(:sql) { "select hi from non_existant_table_please" }

      it "should wrap it in a QueryError" do
        expect { subject }.to raise_error(GreenplumConnection::QueryError)
      end
    end

    context "when a timeout is specified" do
      let(:options) { {:timeout => 100} }
      let(:sql) { "SELECT pg_sleep(.2);" }

      it "should raise a timeout error" do
        expect { subject }.to raise_error(GreenplumConnection::QueryError, /timeout/)
      end
    end
  end

  describe "DatabaseMethods" do
    let(:connection) { GreenplumConnection.new(details) }
    describe "#schemas" do
      let(:schema_list_sql) do
        <<-SQL
      SELECT
        schemas.nspname as schema_name
      FROM
        pg_namespace schemas
      WHERE
        schemas.nspname NOT LIKE 'pg_%'
        AND schemas.nspname NOT IN ('information_schema', 'gp_toolkit', 'gpperfmon')
      ORDER BY lower(schemas.nspname)
        SQL
      end
      let(:expected) { db.fetch(schema_list_sql).all.collect { |row| row[:schema_name] } }
      let(:subject) { connection.schemas }

      it_should_behave_like "a well behaved database query"
    end

    describe "#schema_exists?" do
      let(:schema_name) { 'test_schema' }
      let(:subject) { connection.schema_exists?(schema_name) }
      let(:expected) { true }

      it_should_behave_like "a well behaved database query"

      context "when the schema doesn't exist" do
        let(:schema_name) { "does_not_exist" }

        it 'returns false' do
          connection.schema_exists?(schema_name).should be_false
        end
      end
    end

    describe "#create_schema" do
      let(:new_schema_name) { "foobarbaz" }
      let(:subject) { connection.create_schema("foobarbaz") }
      let(:expected) { true }

      after do
        db = Sequel.connect(db_url)
        db.drop_schema(new_schema_name, :if_exists => true)
        db.disconnect
      end

      it_should_behave_like "a well behaved database query"

      it "adds a schema" do
        expect {
          connection.create_schema("foobarbaz")
        }.to change { connection.schemas }
      end
    end

    describe "#drop_schema" do
      context "if the schema exists" do
        let(:schema_to_drop) { "hopefully_unused_schema" }
        let(:subject) { connection.drop_schema(schema_to_drop) }
        let(:expected) { true }

        around do |example|
          db = Sequel.connect(db_url)
          db.create_schema(schema_to_drop)

          example.run

          db.drop_schema(schema_to_drop, :if_exists => true)
          db.disconnect
        end

        it_should_behave_like "a well behaved database query"

        it "drops it" do
          connection.schema_exists?(schema_to_drop).should == true
          connection.drop_schema(schema_to_drop)
          connection.schema_exists?(schema_to_drop).should == false
        end
      end

      context "if the schema does not exist" do
        let(:schema_to_drop) { "never_existed" }

        it "doesnt raise an error" do
          expect {
            connection.drop_schema(schema_to_drop)
          }.to_not raise_error
        end
      end
    end
  end

  describe "InstanceMethods" do
    let(:connection) { GreenplumConnection.new(details) }
    let(:database_name) { 'postgres' }

    describe "#databases" do
      let(:database_list_sql) do
        <<-SQL
          SELECT
            datname
          FROM
            pg_database
          WHERE
            datallowconn IS TRUE AND datname NOT IN ('postgres', 'template1')
            ORDER BY lower(datname) ASC
        SQL
      end

      let(:expected) { db.fetch(database_list_sql).all.collect { |row| row[:datname] } }
      let(:subject) { connection.databases }

      it_should_behave_like "a well behaved database query"
    end
  end

  describe "SchemaMethods" do
    let(:connection) { GreenplumConnection.new(details.merge(:schema => schema_name)) }
    let(:schema_name) { "test_schema" }

    describe "#functions" do
      let(:schema_functions_sql) do
        <<-SQL
          SELECT t1.oid, t1.proname, t1.lanname, t1.rettype, t1.proargnames, (SELECT t2.typname ORDER BY inputtypeid) AS argtypes, t1.prosrc, d.description
            FROM ( SELECT p.oid,p.proname,
               CASE WHEN p.proargtypes='' THEN NULL
                   ELSE unnest(p.proargtypes)
                   END as inputtype,
               now() AS inputtypeid, p.proargnames, p.prosrc, l.lanname, t.typname AS rettype
             FROM pg_proc p, pg_namespace n, pg_type t, pg_language l
             WHERE p.pronamespace=n.oid
               AND p.prolang=l.oid
               AND p.prorettype = t.oid
               AND n.nspname= '#{schema_name}') AS t1
          LEFT JOIN pg_type AS t2
          ON t1.inputtype=t2.oid
          LEFT JOIN pg_description AS d ON t1.oid=d.objoid
          ORDER BY t1.oid;
        SQL
      end
      let(:expected) { db.fetch(schema_functions_sql).all }
      let(:subject) { connection.functions }

      it_should_behave_like "a well behaved database query"
    end

    describe "#disk_space_used" do
      let(:disk_space_sql) do
        <<-SQL
          SELECT sum(pg_total_relation_size(pg_catalog.pg_class.oid))::bigint AS size
          FROM   pg_catalog.pg_class
          LEFT JOIN pg_catalog.pg_namespace ON relnamespace = pg_catalog.pg_namespace.oid
          WHERE  pg_catalog.pg_namespace.nspname = '#{schema_name}'
        SQL
      end
      let(:schema_name) { 'test_schema3' }
      let(:expected) { db.fetch(disk_space_sql).single_value }
      let(:subject) { connection.disk_space_used }

      it_should_behave_like "a well behaved database query"
    end

    describe '#create_view' do
      after do
        db = Sequel.connect(db_url)
        db.default_schema = schema_name
        db.drop_view('a_new_db_view') if db.views.map(&:to_s).include? 'a_new_db_view'
        db.disconnect
      end

      let(:subject) { connection.create_view('a_new_db_view', 'select 1;') }
      let(:expected) { true }

      it_should_behave_like "a well behaved database query"

      it 'creates a view' do
        expect {
          connection.create_view('a_new_db_view', 'select 1;')
        }.to change { Sequel.connect(db_url).views }
      end

      context 'when a view with that name already exists' do
        it 'raises an error' do
          expect {
            connection.create_view('view1', 'select 1;')
          }.to raise_error(GreenplumConnection::DatabaseError)
        end
      end
    end

    describe "#create_external_table" do
      after do
        if table_name == "a_new_external_table"
          db = Sequel.connect(db_url)
          db.default_schema = schema_name
          db.execute("DROP EXTERNAL TABLE IF EXISTS \"#{schema_name}\".\"#{table_name}\"")
          db.disconnect
        end
      end

      let(:table_name) { "a_new_external_table" }
      let(:columns) { "field1 varchar, field2 integer" }
      let(:location_url) { "gphdfs://foo/*.csv" }
      let(:delimiter) { "," }
      let(:web) { false }
      let(:execute_command) { nil }
      let(:subject) do
        connection.create_external_table(
            {
                :table_name => table_name,
                :columns => columns,
                :location_url => location_url,
                :execute => execute_command,
                :delimiter => delimiter,
                :web => web
            }
        )
      end
      let(:expected) { true }

      it_should_behave_like "a well behaved database query"

      it 'creates an external table' do
        expect {
          subject
        }.to change { Sequel.connect(db_url).tables }
      end

      context 'for an external web table' do
        let(:web) { true }
        let(:location_url) { nil }
        let(:execute_command) { 'echo "1,2"' }

        it 'creates an external table' do
          subject
          row = Sequel.connect(db_url).fetch("SELECT * from #{schema_name}.#{table_name}").first
          row[:field1].should == "1"
          row[:field2].should == 2
        end
      end

      context 'when a table with that name already exists' do
        let(:table_name) { "base_table1" }
        it 'raises an error' do
          expect {
            subject
          }.to raise_error(GreenplumConnection::DatabaseError)
        end
      end
    end

    describe "#table_exists?" do
      let(:subject) { connection.table_exists?(table_name) }
      let(:expected) { true }

      context "when the table exists" do
        let(:table_name) { "different_names_table" }

        it_should_behave_like "a well behaved database query"

        context 'when the table has weird chars in the name' do
          let(:table_name) { %Q(7_`~!@#\$%^&*()+=[]{}|\\;:',<.>/?) }

          it_should_behave_like "a well behaved database query" #regression
        end
      end

      context "when the table doesn't exist" do
        let(:table_name) { "please_dont_exist" }
        let(:expected) { false }

        it_should_behave_like "a well behaved database query"
      end

      context "when the table name given is nil" do
        let(:table_name) { nil }
        let(:expected) { false }

        it_should_behave_like "a well behaved database query"
      end
    end

    describe "#view_exists?" do
      let(:subject) { connection.view_exists?(view_name) }
      context "when the view exists" do
        let(:expected) { true }
        let(:view_name) { "view1" }

        it_behaves_like 'a well behaved database query'
      end

      context "when the view doesn't exist" do
        let(:view_name) { "please_dont_exist" }
        let(:expected) { false }

        it_behaves_like 'a well behaved database query'
      end

      context "when the view name given is nil" do
        let(:view_name) { nil }
        let(:expected) { false }

        it_behaves_like 'a well behaved database query'
      end
    end

    describe "#analyze_table" do
      context "when the table exists" do
        let(:table_name) { "table_to_analyze" }

        before do
          stub.proxy(Sequel).connect do |connection|
            stub(connection).execute(anything)
            mock(connection).execute(%Q{ANALYZE "#{schema_name}"."#{table_name}"})
          end
        end

        it "analyzes the table" do
          connection.analyze_table(table_name)
        end
      end

      context "when the table does not exist" do
        let(:table_name) { "this_table_does_not_exist" }

        it "raises an error" do
          expect do
            connection.analyze_table(table_name)
          end.to raise_error(GreenplumConnection::DatabaseError)
        end
      end
    end

    describe "#drop_table" do
      context "if the table exists" do
        let(:table_to_drop) { "hopefully_unused_table" }
        let(:subject) { connection.drop_table(table_to_drop) }
        let(:expected) { true }

        around do |example|
          db = Sequel.connect(db_url)
          db.default_schema = schema_name
          db.create_table(table_to_drop)

          example.run

          db.drop_table(table_to_drop, :if_exists => true)
          db.disconnect
        end

        it_behaves_like "a well behaved database query"

        it "should drop a table" do
          connection.table_exists?(table_to_drop).should == true
          connection.drop_table(table_to_drop)
          connection.table_exists?(table_to_drop).should == false
        end
      end

      context "if the table does not exist" do
        let(:table_to_drop) { "never_existed" }

        it "doesn't raise an error" do
          expect {
            connection.drop_table(table_to_drop)
          }.not_to raise_error
        end
      end
    end

    describe "#truncate_table" do
      let(:subject) { connection.truncate_table(table_to_truncate) }
      let(:expected) { true }

      context "if the table exists" do
        let(:table_to_truncate) { "trunc_table" }

        before do
          db = Sequel.connect(db_url)
          db.execute(<<-SQL)
            CREATE TABLE "test_schema"."trunc_table" (num integer);
            INSERT INTO "test_schema"."trunc_table" (num) VALUES (2)
          SQL
          db.disconnect
        end

        after do
          db = Sequel.connect(db_url)
          db.execute(<<-SQL)
            DROP TABLE IF EXISTS "test_schema"."trunc_table"
          SQL
          db.disconnect
        end

        it_behaves_like "a well behaved database query"

        it "should truncate a table" do
          expect {
            connection.truncate_table(table_to_truncate)
          }.to change { connection.fetch(<<-SQL)[0][:num] }.from(1).to(0)
            SELECT COUNT(*) AS num FROM "test_schema"."trunc_table"
          SQL
        end
      end
    end

    describe "#fetch" do
      let(:sql) { "SELECT 1 AS answer" }
      let(:parameters) { {} }
      let(:subject) { connection.fetch(sql) }
      let(:expected) { [{:answer => 1}] }

      it_behaves_like "a well behaved database query"

      it "sets the search path before any query" do
        stub.proxy(Sequel).connect do |connection|
          stub(connection).execute(anything, anything)
          mock(connection).execute("SET search_path TO \"#{schema_name}\"")
        end

        connection.fetch(sql)
      end

      context "with SQL parameters" do
        let(:sql) { "SELECT :num AS answer" }
        let(:parameters) { {:num => 3} }

        it "succeeds" do
          connection.fetch(sql, parameters).should == [{:answer => 3}]
        end
      end
    end

    describe "#fetch_value" do
      let(:sql) { "SELECT * FROM ((SELECT 1) UNION (SELECT 2) UNION (SELECT 3)) AS thing" }
      let(:subject) { connection.fetch_value(sql) }
      let(:expected) { 1 }
      let(:schema_name) { "test_schema_with_\"_" }

      it_behaves_like "a well behaved database query"

      it "sets the search path before any query" do
        stub.proxy(Sequel).connect do |connection|
          stub(connection).execute(anything, anything)
          mock(connection).execute("SET search_path TO \"#{schema_name.gsub("\"", "\"\"")}\"")
        end

        connection.fetch_value(sql)
      end
    end

    describe "#stream_table" do
      before do
        @db = Sequel.connect(db_url)
        @db.execute("SET search_path TO '#{schema_name}'")
        @db.execute("CREATE TABLE thing (one integer, two integer)")
        @db.execute("INSERT INTO thing VALUES (1, 2)")
        @db.execute("INSERT INTO thing VALUES (3, 4)")
      end

      after do
        @db.execute("DROP TABLE thing")
        @db.disconnect
      end

      let(:subject) {
        connection.stream_table('thing') do |row|
          true
        end
      }
      let(:expected) { true }

      it_behaves_like "a well behaved database query"

      it "streams all rows of the database" do
        bucket = []
        connection.stream_table('thing') do |row|
          bucket << row
        end

        bucket.should == @db.fetch('SELECT * FROM thing').all
      end

      context "when a limit is provided" do
        it "only processes part of the table" do
          bucket = []
          connection.stream_table('thing', 1) do |row|
            bucket << row
          end

          bucket.should == @db.fetch('SELECT * FROM thing LIMIT 1').all
        end
      end
    end

    describe "#execute" do
      let(:sql) { "SET search_path TO 'public'" }
      let(:parameters) { {} }
      let(:subject) { connection.execute(sql) }
      let(:expected) { true }

      it_behaves_like "a well behaved database query"
    end

    describe "#transaction" do
      let(:subject) {
        connection.test_transaction do |conn|
          conn.fetch_value('SELECT 1')
        end
      }

      let(:expected) { 1 }

      it_behaves_like "a well behaved database query"

      it 'rolls back all database operations' do
        connection.test_transaction do |conn|
          conn.execute('create table test_transaction()')
        end

        connection.table_exists?('test_transaction').should_not be_true
      end
    end

    describe "#datasets" do
      let(:datasets_sql) do
        <<-SQL
SELECT pg_catalog.pg_class.relkind as type, pg_catalog.pg_class.relname as name, pg_catalog.pg_class.relhassubclass as master_table
FROM pg_catalog.pg_class
LEFT OUTER JOIN pg_partition_rule on (pg_partition_rule.parchildrelid = pg_catalog.pg_class.oid AND pg_catalog.pg_class.relhassubclass = 'f')
WHERE pg_catalog.pg_class.relnamespace in (SELECT oid from pg_namespace where pg_namespace.nspname = :schema)
AND pg_catalog.pg_class.relkind in ('r', 'v')
AND (pg_catalog.pg_class.relhassubclass = 't' OR pg_partition_rule.parchildrelid IS NULL)
ORDER BY lower(replace(relname,'_', '')) ASC
        SQL
      end
      let(:expected) { db.fetch(datasets_sql, :schema => schema_name).all }
      let(:subject) { connection.datasets }

      it_should_behave_like "a well behaved database query"

      context "when the user doesn't have permission to the schema" do
        let(:subject) { connection.datasets }
        let(:db) { Sequel.connect(db_url) }
        let(:restricted_user) { "user_with_no_access" }
        let(:restricted_password) { "secret" }

        let(:connection) do
          GreenplumConnection.new(details.merge(:schema => schema_name, :username => restricted_user, :password => restricted_password))
        end

        before do
          db.execute("CREATE USER #{restricted_user} WITH PASSWORD '#{restricted_password}';") rescue nil
          db.execute("GRANT CONNECT ON DATABASE \"#{database_name}\" TO #{restricted_user};")
          db.execute("REVOKE ALL ON SCHEMA #{schema_name} FROM #{restricted_user};")
        end

        after do
          db.execute("REVOKE CONNECT ON DATABASE \"#{database_name}\" FROM #{restricted_user};") rescue nil
          db.execute("DROP USER #{restricted_user};") rescue nil
          db.disconnect
        end

        it "should raise a SqlPermissionDenied" do
          expect { subject }.to raise_error(GreenplumConnection::SqlPermissionDenied)
        end
      end

      context "when a limit is passed" do
        let(:datasets_sql) do
          <<-SQL
SELECT pg_catalog.pg_class.relkind as type, pg_catalog.pg_class.relname as name, pg_catalog.pg_class.relhassubclass as master_table
FROM pg_catalog.pg_class
LEFT OUTER JOIN pg_partition_rule on (pg_partition_rule.parchildrelid = pg_catalog.pg_class.oid AND pg_catalog.pg_class.relhassubclass = 'f')
WHERE pg_catalog.pg_class.relnamespace in (SELECT oid from pg_namespace where pg_namespace.nspname = :schema)
AND pg_catalog.pg_class.relkind in ('r', 'v')
AND (pg_catalog.pg_class.relhassubclass = 't' OR pg_partition_rule.parchildrelid IS NULL)
ORDER BY lower(replace(relname,'_', '')) ASC
LIMIT 2
          SQL
        end
        let(:expected) { db.fetch(datasets_sql, :schema => schema_name).all }
        let(:subject) { connection.datasets(:limit => 2) }

        it_should_behave_like "a well behaved database query"
      end

      context "when a name filter is passed" do
        let(:datasets_sql) do
          <<-SQL
SELECT pg_catalog.pg_class.relkind as type, pg_catalog.pg_class.relname as name, pg_catalog.pg_class.relhassubclass as master_table
FROM pg_catalog.pg_class
LEFT OUTER JOIN pg_partition_rule on (pg_partition_rule.parchildrelid = pg_catalog.pg_class.oid AND pg_catalog.pg_class.relhassubclass = 'f')
WHERE pg_catalog.pg_class.relnamespace in (SELECT oid from pg_namespace where pg_namespace.nspname = :schema)
AND pg_catalog.pg_class.relkind in ('r', 'v')
AND (pg_catalog.pg_class.relhassubclass = 't' OR pg_partition_rule.parchildrelid IS NULL)
AND (pg_catalog.pg_class.relname ILIKE '%candy%')
ORDER BY lower(replace(relname,'_', '')) ASC
          SQL
        end
        let(:expected) { db.fetch(datasets_sql, :schema => schema_name).all }
        let(:subject) { connection.datasets(:name_filter => 'cANdy') }

        it_should_behave_like "a well behaved database query"
      end

      context "when only showing tables" do
        let(:datasets_sql) do
          <<-SQL
SELECT pg_catalog.pg_class.relkind as type, pg_catalog.pg_class.relname as name, pg_catalog.pg_class.relhassubclass as master_table
FROM pg_catalog.pg_class
LEFT OUTER JOIN pg_partition_rule on (pg_partition_rule.parchildrelid = pg_catalog.pg_class.oid AND pg_catalog.pg_class.relhassubclass = 'f')
WHERE pg_catalog.pg_class.relnamespace in (SELECT oid from pg_namespace where pg_namespace.nspname = :schema)
AND pg_catalog.pg_class.relkind = 'r'
AND (pg_catalog.pg_class.relhassubclass = 't' OR pg_partition_rule.parchildrelid IS NULL)
ORDER BY lower(replace(relname,'_', '')) ASC
          SQL
        end
        let(:expected) { db.fetch(datasets_sql, :schema => schema_name).all }
        let(:subject) { connection.datasets(:tables_only => true) }

        it_should_behave_like "a well behaved database query"
      end

      context "when multiple options are passed" do
        let(:datasets_sql) do
          <<-SQL
SELECT pg_catalog.pg_class.relkind as type, pg_catalog.pg_class.relname as name, pg_catalog.pg_class.relhassubclass as master_table
FROM pg_catalog.pg_class
LEFT OUTER JOIN pg_partition_rule on (pg_partition_rule.parchildrelid = pg_catalog.pg_class.oid AND pg_catalog.pg_class.relhassubclass = 'f')
WHERE pg_catalog.pg_class.relnamespace in (SELECT oid from pg_namespace where pg_namespace.nspname = :schema)
AND pg_catalog.pg_class.relkind in ('r', 'v')
AND (pg_catalog.pg_class.relhassubclass = 't' OR pg_partition_rule.parchildrelid IS NULL)
AND (pg_catalog.pg_class.relname ILIKE '%candy%')
ORDER BY lower(replace(relname,'_', '')) ASC
LIMIT 2
          SQL
        end
        let(:expected) { db.fetch(datasets_sql, :schema => schema_name).all }
        let(:subject) { connection.datasets(:name_filter => 'caNDy', :limit => 2) }

        it_should_behave_like "a well behaved database query"
      end
    end

    describe "#datasets_count" do
      let(:datasets_sql) do
        <<-SQL
SELECT count(pg_catalog.pg_class.relname)
FROM pg_catalog.pg_class
LEFT OUTER JOIN pg_partition_rule on (pg_partition_rule.parchildrelid = pg_catalog.pg_class.oid AND pg_catalog.pg_class.relhassubclass = 'f')
WHERE pg_catalog.pg_class.relnamespace in (SELECT oid from pg_namespace where pg_namespace.nspname = :schema)
AND pg_catalog.pg_class.relkind in ('r', 'v')
AND (pg_catalog.pg_class.relhassubclass = 't' OR pg_partition_rule.parchildrelid IS NULL)
        SQL
      end
      let(:expected) { db.fetch(datasets_sql, :schema => schema_name).single_value }
      let(:subject) { connection.datasets_count }

      it_should_behave_like "a well behaved database query"

      context "when the user doesn't have permission to the schema" do
        let(:subject) { connection.datasets_count }
        let(:db) { Sequel.connect(db_url) }
        let(:restricted_user) { "user_with_no_access" }
        let(:restricted_password) { "secret" }

        let(:connection) do
          GreenplumConnection.new(details.merge(:schema => schema_name, :username => restricted_user, :password => restricted_password))
        end

        before do
          db.execute("CREATE USER #{restricted_user} WITH PASSWORD '#{restricted_password}';") rescue nil
          db.execute("GRANT CONNECT ON DATABASE \"#{database_name}\" TO #{restricted_user};")
          db.execute("REVOKE ALL ON SCHEMA #{schema_name} FROM #{restricted_user};")
        end

        after do
          db.execute("REVOKE CONNECT ON DATABASE \"#{database_name}\" FROM #{restricted_user};") rescue nil
          db.execute("DROP USER #{restricted_user};") rescue nil
          db.disconnect
        end

        it "should raise a SqlPermissionDenied" do
          expect { subject }.to raise_error(GreenplumConnection::SqlPermissionDenied)
        end
      end

      context "when a name filter is passed" do
        let(:datasets_sql) do
          <<-SQL
SELECT count(pg_catalog.pg_class.relname)
FROM pg_catalog.pg_class
LEFT OUTER JOIN pg_partition_rule on (pg_partition_rule.parchildrelid = pg_catalog.pg_class.oid AND pg_catalog.pg_class.relhassubclass = 'f')
WHERE pg_catalog.pg_class.relnamespace in (SELECT oid from pg_namespace where pg_namespace.nspname = :schema)
AND pg_catalog.pg_class.relkind in ('r', 'v')
AND (pg_catalog.pg_class.relhassubclass = 't' OR pg_partition_rule.parchildrelid IS NULL)
AND (pg_catalog.pg_class.relname ILIKE '%candy%')
          SQL
        end
        let(:expected) { db.fetch(datasets_sql, :schema => schema_name).single_value }
        let(:subject) { connection.datasets_count(:name_filter => 'cANdy') }

        it_should_behave_like "a well behaved database query"
      end
    end

    describe "#column_info" do
      let(:table_name) { "base_table1" }
      let(:columns_sql) do
        <<-SQL
        SELECT a.attname, format_type(a.atttypid, a.atttypmod), des.description, a.attnum,
               s.null_frac, s.n_distinct, s.most_common_vals, s.most_common_freqs, s.histogram_bounds,
               c.reltuples
          FROM pg_attribute a
          LEFT JOIN pg_description des
            ON a.attrelid = des.objoid AND a.attnum = des.objsubid
          LEFT JOIN pg_namespace n
            ON n.nspname = :schema
          LEFT JOIN pg_class c
            ON c.relnamespace = n.oid
           AND c.relname = :table
          LEFT JOIN pg_stats s
            ON s.attname = a.attname
           AND s.schemaname = n.nspname
           AND s.tablename = c.relname
          WHERE a.attrelid = '"#{table_name}"'::regclass
          AND a.attnum > 0 AND NOT a.attisdropped
        ORDER BY a.attnum;
        SQL
      end
      let(:expected) do
        db.execute("SET search_path TO #{db.send(:quote_identifier, schema_name)}")
        db.fetch(columns_sql, :schema => schema_name, :table => table_name).all
      end

      context "with no setup sql" do
        let(:subject) { connection.column_info(table_name, '') }

        it_should_behave_like "a well behaved database query"
      end

      context "with setup sql for a temp view" do
        let(:subject) { connection.column_info('TMP_VIEW', 'CREATE TEMP VIEW "TMP_VIEW" as select * from base_table1;;') }
        let(:expected) do
          db.execute("SET search_path TO #{db.send(:quote_identifier, schema_name)}")
          table_results = db.fetch(columns_sql, :schema => schema_name, :table => table_name).all
          table_results.map do |result|
            result.merge(:description => nil, :null_frac => nil, :n_distinct => nil, :most_common_vals => nil, :most_common_freqs => nil, :histogram_bounds => nil, :reltuples => nil)
          end
        end

        it_should_behave_like "a well behaved database query"
      end
    end
  end

  describe "GreenplumConnection::DatabaseError" do
    let(:sequel_exception) {
      obj = Object.new
      wrp_exp = Object.new
      stub(obj).wrapped_exception { wrp_exp }
      stub(obj).message { "A message" }
      obj
    }

    let(:error) do
      GreenplumConnection::DatabaseError.new(sequel_exception)
    end

    describe "error_type" do
      context "when the wrapped error has a sql state error code" do
        before do
          stub(sequel_exception.wrapped_exception).get_sql_state { error_code }
        end

        context "when the error code is 3D000" do
          let(:error_code) { '3D000' }

          it "returns :DATABASE_MISSING" do
            error.error_type.should == :DATABASE_MISSING
          end
        end

        context "when the error code is 28P01" do
          let(:error_code) { '28P01' }

          it "returns :INVALID_PASSWORD" do
            error.error_type.should == :INVALID_PASSWORD
          end
        end

        context "when the error code is 53300" do
          let(:error_code) { '53300' }

          it "returns :TOO_MANY_CONNECTIONS" do
            error.error_type.should == :TOO_MANY_CONNECTIONS
          end
        end

        context "when the error code is 08NNN" do
          let(:error_code) { '08123' }

          it "returns :INSTANCE_UNREACHABLE" do
            error.error_type.should == :INSTANCE_UNREACHABLE
          end
        end

        context "when the error code is 42NNN" do
          let(:error_code) { '42123' }

          it "returns :INVALID_STATEMENT" do
            error.error_type.should == :INVALID_STATEMENT
          end
        end
      end

      context "when the wrapped error has no sql state error code" do
        it "returns :GENERIC" do
          error.error_type.should == :GENERIC
        end
      end
    end

    describe "sanitizing exception messages" do
      let(:error) { GreenplumConnection::DatabaseError.new(StandardError.new(message)) }

      context "one kind" do
        let(:message) do
          "foo jdbc:postgresql://somehost:5432/db_name?user=someguy&password=secrets and stuff"
        end

        it "should sanitize the connection string" do
          error.message.should == "foo jdbc:postgresql://somehost:5432/db_name?user=xxxx&password=xxxx and stuff"
        end
      end

      context "another kind" do
        let(:message) do
          "foo jdbc:postgresql://somehost:5432/db_name?user=someguy&password=secrets"
        end

        it "should sanitize the connection string" do
          error.message.should == "foo jdbc:postgresql://somehost:5432/db_name?user=xxxx&password=xxxx"
        end
      end

      context "and another kind" do
        let(:message) do
          "foo jdbc:postgresql://somehost:5432/db_name?user=someguy&password=secrets&somethingelse=blah"
        end

        it "should sanitize the connection string" do
          error.message.should == "foo jdbc:postgresql://somehost:5432/db_name?user=xxxx&password=xxxx&somethingelse=blah"
        end
      end

      context "with other orders" do
        let(:message) do
          "foo jdbc:postgresql://somehost:5432/db_name?password=secrets&user=someguy blah"
        end

        it "should sanitize the connection string" do
          error.message.should == "foo jdbc:postgresql://somehost:5432/db_name?password=xxxx&user=xxxx blah"
        end
      end
    end
  end
end
