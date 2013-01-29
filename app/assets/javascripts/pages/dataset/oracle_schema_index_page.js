chorus.pages.OracleSchemaIndexPage = chorus.pages.Base.extend({
    setup: function(oracleDataSourceId){
        this.dataSource = new chorus.models.OracleDataSource({id: oracleDataSourceId});
        this.collection = this.dataSource.schemas();
        this.collection.fetch();
        this.dependOn(this.collection);
    }
});