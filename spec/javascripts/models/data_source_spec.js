describe('chorus.models.DataSource', function() {
    beforeEach(function() {
            this.model = new chorus.models.DataSource({id: 1, owner: rspecFixtures.user()});
        }
    );

    it("has the right url", function() {
        expect(this.model.url()).toHaveUrlPath('/data_sources/1');

        this.model.unset("id", { silent: true });
        expect(this.model.url()).toHaveUrlPath('/data_sources/');
    });

    describe('#canHaveIndividualAccounts', function(){
        it('is true for greenplum data sources', function(){
            var gpdbDataSource = rspecFixtures.gpdbDataSource();
            expect(gpdbDataSource.canHaveIndividualAccounts()).toBeTruthy();
        });

        it('is true for oracle data sources', function(){
            var oracleDataSource = rspecFixtures.gpdbDataSource();
            expect(oracleDataSource.canHaveIndividualAccounts()).toBeTruthy();
        });
    });

    describe('#isShared', function(){
        it('returns true if the instance is marked as shared', function(){
            var shared = new chorus.models.DataSource({shared: true});
            expect(shared.isShared()).toBeTruthy();
            var unshared = new chorus.models.DataSource();
            expect(unshared.isShared()).toBeFalsy();
        });
    });

    describe('#isGreenplum', function(){
        it('returns true if the instance is a greenplum db', function(){
            var gpdb = new chorus.models.DataSource({entityType: 'gpdb_data_source'});
            expect(gpdb.isGreenplum()).toBeTruthy();
            var oracle = new chorus.models.DataSource({entityType: 'oracle_data_source'});
            expect(oracle.isGreenplum()).toBeFalsy();
        });
    });

    describe("#accountForUser", function() {
        beforeEach(function() {
            this.user = rspecFixtures.user();
            this.model.set(rspecFixtures.gpdbDataSource().attributes);
            this.account = this.model.accountForUser(this.user);
        });

        it("returns an InstanceAccount", function() {
            expect(this.account).toBeA(chorus.models.InstanceAccount);
        });

        it("sets the instance id", function() {
            expect(this.account.get("instanceId")).toBe(this.model.get("id"));
        });

        it("sets the user id based on the given user", function() {
            expect(this.account.get("userId")).toBe(this.user.get("id"));
        });
    });

    describe("#accountForCurrentUser", function() {
        beforeEach(function() {
            this.model.set(rspecFixtures.gpdbDataSource().attributes);
            this.currentUser = rspecFixtures.user();
            setLoggedInUser(this.currentUser.attributes);
            this.model.set(rspecFixtures.gpdbDataSource().attributes);
        });

        it("memoizes", function() {
            var account = this.model.accountForCurrentUser();
            expect(account).toBe(this.model.accountForCurrentUser());
        });

        context("when the account is destroyed", function() {
            it("un-memoizes the account", function() {
                var previousAccount = this.model.accountForCurrentUser();
                previousAccount.trigger("destroy");

                var account = this.model.accountForCurrentUser();
                expect(account).not.toBe(previousAccount);
            });

            it("triggers 'change' on the instance", function() {
                spyOnEvent(this.model, 'change');
                this.model.accountForCurrentUser().trigger("destroy");
                expect("change").toHaveBeenTriggeredOn(this.model);
            });
        });
    });

    describe("#accountForOwner", function() {
        beforeEach(function() {
            this.model.set(rspecFixtures.gpdbDataSource().attributes);

            var owner = this.owner = this.model.owner();
            this.accounts = rspecFixtures.instanceAccountSet();
            this.accounts.each(function(account) {
                account.set({
                    owner: {
                        id: owner.id + 1
                    }
                });
            });

            this.accounts.models[1].set({owner: this.owner.attributes});
            spyOn(this.model, "accounts").andReturn(this.accounts);
        });

        it("returns the account for the owner", function() {
            expect(this.model.accountForOwner()).toBeA(chorus.models.InstanceAccount);
            expect(this.model.accountForOwner()).toBe(this.accounts.models[1]);
        });
    });

    describe("#accounts", function() {
        beforeEach(function() {
            this.model.set(rspecFixtures.gpdbDataSource().attributes);

            this.instanceAccounts = this.model.accounts();
        });

        it("returns an InstanceAccountSet", function() {
            expect(this.instanceAccounts).toBeA(chorus.collections.InstanceAccountSet);
        });

        it("sets the instance id", function() {
            expect(this.instanceAccounts.attributes.instanceId).toBe(this.model.get('id'));
        });

        it("memoizes", function() {
            expect(this.instanceAccounts).toBe(this.model.accounts());
        });
    });

    describe("#usage", function() {
        beforeEach(function() {
            this.model.set(rspecFixtures.gpdbDataSource().attributes);

            this.instanceUsage = this.model.usage();
        });

        it("returns an InstanceUsage object", function() {
            expect(this.instanceUsage).toBeA(chorus.models.InstanceUsage);
        });

        it("sets the instance id", function() {
            expect(this.instanceUsage.attributes.instanceId).toBe(this.model.get('id'));
        });

        it("memoizes", function() {
            expect(this.instanceUsage).toBe(this.model.usage());
        });
    });

    describe("#hasWorkspaceUsageInfo", function() {
        it("returns true when the instance's usage is loaded", function() {
            this.model.usage().set({workspaces: []});
            expect(this.model.hasWorkspaceUsageInfo()).toBeTruthy();
        });

        it("returns false when the instances's usage is not loaded", function() {
            this.model.usage().unset("workspaces");
            expect(this.model.hasWorkspaceUsageInfo()).toBeFalsy();
        });
    });

    describe("#sharing", function() {
        it("returns an instance sharing model", function() {
            expect(this.model.sharing().get("instanceId")).toBe(this.model.get("id"));
        });

        it("caches the sharing model", function() {
            var originalModel = this.model.sharing();
            expect(this.model.sharing()).toBe(originalModel);
        });
    });

    describe("#sharedAccountDetails", function() {
        beforeEach(function() {
            this.owner = this.model.owner();
            this.accounts = rspecFixtures.instanceAccountSet();
            this.accounts.models[1].set({owner: this.owner.attributes});
            spyOn(this.model, "accounts").andReturn(this.accounts);
        });

        it("returns the account name of the user who owns the instance and shared it", function() {
            this.user = rspecFixtures.user();
            this.account = this.model.accountForUser(this.user);
            expect(this.model.sharedAccountDetails()).toBe(this.model.accountForOwner().get("dbUsername"));
        });
    });
});
