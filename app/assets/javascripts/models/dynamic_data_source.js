chorus.models.DynamicDataSource = function(attributes){
    if(attributes.entityType === "oracle_data_source") {
        return new chorus.models.OracleDataSource(attributes);
    }
    return new chorus.models.GpdbDataSource(attributes);
};