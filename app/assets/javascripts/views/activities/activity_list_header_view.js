chorus.views.ActivityListHeader = chorus.views.Base.extend({
    constructorName: "ActivityListHeaderView",
    templateName : "activity_list_header",
    persistent: true,

    events: {
        "click .all":     "onAllClicked",
        "click .insights": "onInsightsClicked"
    },

    setup: function() {
        this.subscribePageEvent("note:deleted", this.updateInsightCount);
        this.subscribePageEvent("insight:promoted", this.updateInsightCount);

        if(!this.collection) {
            this.collection = this.model.activities();
        }
        this.insightsCount = this.collection.clone();
        this.insightsCount.attributes.entity = this.collection.attributes.entity;
        this.insightsCount.attributes.insights = true;
        this.insightsCount.fetchPage(1, {per_page: 0});
        this.insightsCount.on("loaded", this.render, this);

        this.requiredResources.add(this.insightsCount);

        this.allTitle = this.options.allTitle;
        this.insightsTitle = this.options.insightsTitle;
    },

    additionalContext: function() {
        return {
            title: this.pickTitle(),
            showInsights: this.collection.attributes.insights,
            insightCount: this.insightsCount.totalRecordCount(),
            iconUrl: this.model && this.model.defaultIconUrl()
        };
    },

    pickTitle: function() {
        return this.collection.attributes.insights ? this.insightsTitle : this.allTitle;
    },

    updateInsightCount: function() {
        this.insightsCount.fetchPage(1, {per_page: 0});
    },

    reloadCollection: function() {
        this.collection.loaded = false;
        this.collection.reset();
        this.collection.fetch();
        this.render();
    },

    onAllClicked: function(e) {
        e.preventDefault();

        this.collection.attributes.insights = false;
        this.reloadCollection();
    },

    onInsightsClicked: function(e) {
        e.preventDefault();

        this.collection.attributes.insights = true;
        this.reloadCollection();
    }
});
