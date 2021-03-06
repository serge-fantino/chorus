require 'spec_helper'

describe DatasetStatistics do
  context "#initialize" do
    let(:statistics) { DatasetStatistics.new({
          'description' => 'New Description',
          'column_count' => '4',
          'row_count' => '23',
          'table_type' => 'BASE_TABLE',
          'last_analyzed' => '2012-06-06 23:02:42.40264+00',
          'disk_size' => '230',
          'partition_count' => '2'
    })}

    it "parses the values" do
      statistics.row_count.should == 23
      statistics.table_type.should == "BASE_TABLE"
      statistics.column_count.should == 4
      statistics.description.should == 'New Description'
      statistics.last_analyzed.to_s.should == "2012-06-06 23:02:42 UTC"
      statistics.disk_size.should == 230
      statistics.partition_count.should == 2
    end
  end

  it "doesn't crash when it is being initialized with nil" do
    fail = DatasetStatistics.new(nil)
  end
end
