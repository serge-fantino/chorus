chorus.pages.DashboardPage = chorus.pages.Base.extend({
    constructorName: "DashboardPage",

    crumbs:[
        { label:t("breadcrumbs.home") }
    ],
    helpId: "dashboard",

    setup:function () {
        this.collection = this.workspaceSet = new chorus.collections.WorkspaceSet();
        this.workspaceSet.attributes.userId = chorus.session.user().id;
        this.workspaceSet.attributes.showLatestComments = true;
        this.workspaceSet.attributes.active = true;
        this.workspaceSet.sortAsc("name");
        this.workspaceSet.fetchAll();

        this.dataSourceSet = new chorus.collections.DataSourceSet([], { accessible: true });
        this.hadoopInstanceSet = new chorus.collections.HadoopInstanceSet([]);
        this.gnipInstanceSet = new chorus.collections.GnipInstanceSet([]);

        this.subscribePageEvent("instance:added", function() { this.fetchInstances(); });

        this.fetchInstances();
        this.model = chorus.session.user();

        this.userSet = new chorus.collections.UserSet();
        this.userSet.bindOnce("loaded", function() {
            this.userCount = this.userSet.pagination.records;
            this.showUserCount();
        }, this);
        this.userSet.fetchAll();
    },

    fetchInstances: function() {
        this.bindings.add(this.dataSourceSet, "loaded", this.mergeInstances);
        this.dataSourceSet.fetchAll();

        this.bindings.add(this.hadoopInstanceSet, "loaded", this.mergeInstances);
        this.hadoopInstanceSet.fetchAll();

        this.bindings.add(this.gnipInstanceSet, "loaded", this.mergeInstances);
        this.gnipInstanceSet.fetchAll();
    },

    instancesLoaded: function() {
        return (this.dataSourceSet && this.dataSourceSet.loaded &&
            this.hadoopInstanceSet && this.hadoopInstanceSet.loaded &&
                this.gnipInstanceSet && this.gnipInstanceSet.loaded);
    },

    mergeInstances: function() {
        if(this.instancesLoaded()) {
            var wrapInstances = function(set) {
                return _.map(set, function(instance) {
                    return new chorus.models.Base({ theInstance: instance });
                });
            };

            var proxyInstances = wrapInstances(this.dataSourceSet.models);
            var proxyHadoopInstances = wrapInstances(this.hadoopInstanceSet.models);
            var proxyGnipInstances = wrapInstances(this.gnipInstanceSet.models);

            this.arraySet = new chorus.collections.Base();
            this.arraySet.comparator = function(instanceWrapper) {
                return instanceWrapper.get("theInstance").name().toLowerCase();
            };

            this.arraySet.add(proxyInstances);
            this.arraySet.add(proxyHadoopInstances);
            this.arraySet.add(proxyGnipInstances);
            this.arraySet.loaded = true;

            this.mainContent = new chorus.views.Dashboard({
                collection: this.workspaceSet,
                dataSourceSet: this.arraySet
            });
            this.render();
        }
    },

    showUserCount: function() {
        if (this.userCount) {
            this.$("#user_count a").text(t("dashboard.user_count", {count: this.userCount}));
            this.$("#user_count").removeClass("hidden");
        }
    },

    postRender:function () {
        this._super('postRender');
        this.$(".pill").insertAfter(this.$("#breadcrumbs"));
        this.$("#sidebar_wrapper").remove();
        this.showUserCount();
    }
});
