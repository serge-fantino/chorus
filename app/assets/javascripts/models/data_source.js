//= require ./instance
chorus.models.DataSource = chorus.models.Instance.extend({
    constructorName: 'DataSource',

    urlTemplate: 'data_sources/{{id}}',
    entityType: 'data_source',

    canHaveIndividualAccounts: function() {
        return true;
    },

    isShared: function() {
        return !!this.get('shared');
    },

    isGreenplum: function() {
        return this.get('entityType') === 'gpdb_data_source';
    },

    isOracle: function() {
      return this.get('entityType') === 'oracle_data_source';
    },

    accounts: function() {
        this._accounts || (this._accounts = new chorus.collections.InstanceAccountSet([], {instanceId: this.get("id")}));
        return this._accounts;
    },

    accountForUser: function(user) {
        return new chorus.models.InstanceAccount({ instanceId: this.get("id"), userId: user.get("id") });
    },

    accountForCurrentUser: function() {
        if(!this._accountForCurrentUser) {
            this._accountForCurrentUser = this.accountForUser(chorus.session.user());
            this._accountForCurrentUser.bind("destroy", function() {
                delete this._accountForCurrentUser;
                this.trigger("change");
            }, this);
        }
        return this._accountForCurrentUser;
    },

    accountForOwner: function() {
        var ownerId = this.get("owner").id;
        return _.find(this.accounts().models, function(account) {
            return account.get("owner").id === ownerId;
        });
    },

    usage: function() {
        if(!this.instanceUsage) {
            this.instanceUsage = new chorus.models.InstanceUsage({ instanceId: this.get('id')});
        }
        return this.instanceUsage;
    },

    hasWorkspaceUsageInfo: function() {
        return this.usage().has("workspaces");
    },

    sharing: function() {
        if(!this._sharing) {
            this._sharing = new chorus.models.InstanceSharing({instanceId: this.get("id")});
        }
        return this._sharing;
    },

    sharedAccountDetails: function() {
        return this.accountForOwner() && this.accountForOwner().get("dbUsername");
    }
});