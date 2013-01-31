shared_examples "a well behaved database query" do
  let(:db) { Sequel.connect(db_url) }

  it "returns the expected result and manages its connection" do
    connection.should_not be_connected
    subject.should == expected
    connection.should_not be_connected
    db.disconnect
  end

  it "masks sequel errors" do
    stub(Sequel).connect(anything, anything) do
      raise Sequel::DatabaseError
    end

    expect {
      subject
    }.to raise_error(DataSourceConnection::Error)
  end
end