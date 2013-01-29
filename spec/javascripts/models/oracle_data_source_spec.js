describe("chorus.models.OracleDataSource", function() {
    beforeEach(function() {
        this.instance = rspecFixtures.oracleDataSource({id: 1});
        this.instance.set({
            dbName: 'RockinDB',
            dbUsername: 'system',
            dbPassword: 'oracle'
        });
    });

    it("has the right entity type", function() {
        expect(this.instance.entityType).toBe("oracle_data_source");
    });

    it("has the right show url", function() {
        expect(this.instance.showUrl()).toBe("#/data_sources/1/schemas");
    });

    it("has the right url", function() {
        expect(this.instance.url()).toContain('/data_sources/1');

        this.instance.unset("id", { silent: true });
        expect(this.instance.url()).toBe('/data_sources/');
    });

    it('has the type', function() {
        expect(this.instance.get('entityType')).toBe('oracle_data_source');
    });

    describe("#isGreenplum", function() {
        it("returns false for oracle instances", function() {
            expect(this.instance.isGreenplum()).toBeFalsy();
        });
    });

    describe("validations", function() {
        beforeEach(function() {
            this.attrs = {
                name: "foo",
                host: "gillette",
                dbUsername: "dude",
                dbPassword: "whatever",
                port: "1234",
                dbName: "foo"
            };
        });

        context("when the instance is new", function() {
            beforeEach(function() {
                this.instance.unset("id", { silent: true });
            });

            it("returns true when the model is valid", function() {
                expect(this.instance.performValidation(this.attrs)).toBeTruthy();
            });

            _.each(["name", "host", "dbUsername", "dbPassword", "port", "dbName"], function(attr) {
                it("requires " + attr, function() {
                    this.attrs[attr] = "";
                    expect(this.instance.performValidation(this.attrs)).toBeFalsy();
                    expect(this.instance.errors[attr]).toBeTruthy();
                });
            });

            it("allows name with spaces", function() {
                this.attrs.name = "foo bar";
                expect(this.instance.performValidation(this.attrs)).toBeTruthy();
            });

            it("requires name with valid length", function() {
                this.attrs.name = "testtesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttest";
                expect(this.instance.performValidation(this.attrs)).toBeFalsy();
                expect(this.instance.errors.name).toMatchTranslation("validation.required_pattern", {fieldName: t('instances.dialog.instance_name')});
            });

            it("requires valid port", function() {
                this.attrs.port = "z123";
                expect(this.instance.performValidation(this.attrs)).toBeFalsy();
                expect(this.instance.errors.port).toBeTruthy();
            });
        });

        context("when the instance has already been created", function() {
            it("does not require a dbUsername or dbPassword", function() {
                delete this.attrs.dbPassword;
                delete this.attrs.dbUsername;
                expect(this.instance.performValidation(this.attrs)).toBeTruthy();
            });
        });
    });

    describe('#schemas', function(){
        it('has the right url', function(){
            expect(this.instance.schemas().url()).toHaveUrlPath('/data_sources/' + this.instance.id + '/schemas');
        });
    });
});
