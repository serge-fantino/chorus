describe('chorus.pages.OracleSchemaIndexPage', function(){
    var page, oracle;

    beforeEach(function() {
        oracle = rspecFixtures.oracleDataSource();
        page = new chorus.pages.OracleSchemaIndexPage(oracle.id);
    });

    it('sets up the right collection', function(){
        expect(page.collection.url()).toBe(oracle.schemas().url());
    });

    it('fetches the collection', function(){
        expect(page.collection).toHaveBeenFetched();
    });

    describe('when the schemas have been fetched', function(){
        it('renders', function(){

        });
    });
});