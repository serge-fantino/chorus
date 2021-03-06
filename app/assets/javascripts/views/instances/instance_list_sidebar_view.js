chorus.views.InstanceListSidebar = chorus.views.Sidebar.extend({
    constructorName: "InstanceListSidebarView",
    templateName: "instance_list_sidebar",
    useLoadingSection: true,

    subviews: {
        '.tab_control': 'tabs'
    },

    setup: function() {
        this.subscribePageEvent("instance:selected", this.setInstance);
        this.tabs = new chorus.views.TabControl(["activity", "configuration"]);
    },

    additionalContext: function() {
        if (!this.model) {
            return {};
        }

        var instanceAccounts = this.instance.accounts();
        var instanceAccountsCount = instanceAccounts.persistedAccountCount ? instanceAccounts.persistedAccountCount() : instanceAccounts.length;

        return {
            isGreenplum: this.model.isGreenplum(),
            userHasAccount: this.model.accountForCurrentUser() && this.model.accountForCurrentUser().has("id"),
            userCanEditPermissions: this.canEditPermissions(),
            userCanEditInstance: this.canEditInstance(),
            instanceAccountsCount: instanceAccountsCount,
            editable: true,
            deleteable: false,
            isOnlineOrOffline: this.instance.isOnline() || this.instance.isOffline(),
            entityType: this.model.entityType,
            instanceProvider: t("instances.provider." + this.model.get('entityType')),
            shared: this.model.isShared && this.model.isShared(),
            isGnip: this.model.isGnip(),
            isOracle: this.model.isOracle()
        };
    },

    setupSubviews: function() {
        this.tabs.activity && this.tabs.activity.teardown();
        this.tabs.configuration && this.tabs.configuration.teardown();

        if (this.instance) {
            this.tabs.activity = new chorus.views.ActivityList({
                collection: this.instance.activities(),
                displayStyle: 'without_object'
            });

            this.tabs.configuration = new chorus.views.InstanceConfigurationDetails({ model: this.instance });

            this.registerSubView(this.tabs.activity);
            this.registerSubView(this.tabs.configuration);
        }
    },

    setInstance: function(instance) {
        this.resource = this.instance = this.model = instance;

        this.resource.loaded = true;

        this.instance.activities().fetch();

        this.requiredResources.reset();
        this.bindings.removeAll();
        this.bindings.add(this.resource, "change", this.render, this);

        if(this.resource.isGreenplum()) {
            var account = this.instance.accountForCurrentUser();
            this.instance.accounts().fetchAllIfNotLoaded();
            account.fetchIfNotLoaded();
            this.requiredResources.push(this.instance.accounts());
            this.requiredResources.push(account);
            this.bindings.add(this.instance.accounts(), "change", this.render);
            this.bindings.add(this.instance.accounts(), "remove", this.render);
            this.bindings.add(account, "change", this.render);
            this.bindings.add(account, "fetchFailed", this.render);
        }

        var instanceUsage = this.instance.usage();
        if(instanceUsage) {
            this.bindings.add(instanceUsage, "loaded", this.updateWorkspaceUsage);
            this.bindings.add(instanceUsage, "fetchFailed", this.updateWorkspaceUsage, this);
            instanceUsage.fetchIfNotLoaded();
        }
        this.render();
    },

    postRender: function() {
        this._super("postRender");
        if (this.instance) {
            this.$("a.dialog").data("instance", this.instance);
            if(this.instance.usage()) {
                this.updateWorkspaceUsage();
            }
        }
    },

    canEditPermissions: function() {
        return this.resource.canHaveIndividualAccounts() && this.canEditInstance();
    },

    canEditInstance: function() {
        return (this.resource.owner().get("id") === chorus.session.user().get("id") ) || chorus.session.user().get("admin");
    },

    updateWorkspaceUsage: function() {
        if (this.instance.usage().loaded) {
            this.$(".workspace_usage_container").empty();
            if(this.model.hasWorkspaceUsageInfo()) {
                var el;
                var count = this.instance.usage().workspaceCount();
                if (count > 0) {
                    el = $("<a class='dialog workspace_usage' href='#' data-dialog='InstanceUsage'></a>");
                    el.data("instance", this.instance);
                } else {
                    el = $("<span class='disabled workspace_usage'></span>");
                }
                el.text(t("instances.sidebar.usage", {count: count}));
                this.$(".workspace_usage_container").append(el);
            }
        }
    }
});
