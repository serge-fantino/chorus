describe("chorus.models.DynamicDataSource", function() {
    it("returns an Oracle DS if the entity type is oracle", function() {
        var model = new chorus.models.DynamicDataSource({entityType: 'oracle_data_source'});
        expect(model).toBeA(chorus.models.OracleDataSource);
    });

    it("returns an GPDB DS if the entity type is gp", function() {
        var model = new chorus.models.DynamicDataSource({entityType: 'gpdb_data_source'});
        expect(model).toBeA(chorus.models.GpdbDataSource);
    });
});