chorus.collections.DataSourceSet = chorus.collections.Base.extend({
    urlTemplate: 'data_sources',
    constructorName: 'DataSourceSet',
    model: chorus.models.DynamicDataSource,

    comparator: function(dataSource) {
        return dataSource.get("name").toLowerCase();
    }
});
