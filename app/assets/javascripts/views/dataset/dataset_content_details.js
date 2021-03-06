chorus.views.DatasetContentDetails = chorus.views.Base.extend({
    templateName: "dataset_content_details",
    constructorName: 'DatasetContentDetails',
    persistent: true,

    subviews: {
        ".data_preview": "resultsConsole",
        ".filters": "filterWizardView",
        ".chart_config": "chartConfig"
    },

    events: {
        "click .preview": "dataPreview",
        "click .create_chart .cancel": "cancelVisualization",
        "click .create_chorus_view .cancel": "cancelCreateChorusView",
        "click .edit_chorus_view .cancel": "cancelEditChorusView",
        "click .edit_chorus_view .save": "saveChorusView",
        "click .chart_icon": "selectVisualization",
        "click .close_errors": "closeErrorWithDetailsLink",
        "click .view_error_details": "viewErrorDetails",
        "click a.select_all": "triggerSelectAll",
        "click a.select_none": "triggerSelectNone",
        "mouseenter .chart_icon": "showTitle",
        "mouseleave .chart_icon": "showSelectedTitle",
        "click button.visualize": "startVisualizationWizard",
        "click button.derive": "startCreateChorusViewWizard",
        "click button.edit": "startEditChorusViewWizard",
        "click button.publish": "displayPublishDialog"
    },

    setup: function() {
        this.closePreviewHandle = this.subscribePageEvent("action:closePreview", this.closeDataPreview);
        this.subscriptions.push(this.closePreviewHandle);
        this.dataset = this.options.dataset;
        this.resultsConsole = new chorus.views.ResultsConsole({
            titleKey: "dataset.data_preview",
            enableResize: true,
            enableExpander: true,
            enableClose: true,
            showDownloadDialog: true,
            dataset: this.dataset
        });
        this.filterWizardView = new chorus.views.DatasetFilterWizard({columnSet: this.collection});

        this.statistics = this.dataset.statistics();
        this.statistics.fetchIfNotLoaded();

        this.bindings.add(this.statistics, "loaded", this.render);
        this.bindings.add(this.collection, "add remove", this.updateColumnCount);
    },

    dataPreview: function(e) {
        e.preventDefault();

        this.$(".column_count").addClass("hidden");
        this.$(".edit_chorus_view_info").addClass("hidden");
        this.$(".data_preview").removeClass("hidden");
        this.resultsConsole.execute(this.dataset.preview());
    },

    closeDataPreview: function() {
        if (!this.inDeriveChorusView) {
            if (!this.options.inEditChorusView) {
                this.$(".column_count").removeClass("hidden");
            } else {
                this.$(".edit_chorus_view_info").removeClass("hidden");
            }
        }
        this.$(".data_preview").addClass("hidden");
    },

    postRender: function() {
        if (this.options.inEditChorusView) {
            this.showEditChorusViewWizard();
        }

        chorus.search({
            input: this.$("input.search"),
            list: this.options.$columnList
        });

        if(this.collection.serverErrors && _.keys(this.collection.serverErrors).length){
            this.showErrorWithDetailsLink(this.collection, chorus.alerts.Error);
        }
        this.showErrors(this.dataset);
    },

    triggerSelectAll: function(e) {
        e && e.preventDefault();
        chorus.PageEvents.broadcast("column:select_all");
    },

    triggerSelectNone: function(e) {
        e && e.preventDefault();
        chorus.PageEvents.broadcast("column:select_none");
    },

    startVisualizationWizard: function() {
        this.$('.chart_icon:eq(0)').click();
        this.$('.column_count').addClass('hidden');
        this.$('.info_bar').removeClass('hidden');
        this.$('.definition').addClass("hidden");
        this.$('.create_chart').removeClass("hidden");
        this.$(".filters").removeClass("hidden");
        this.filterWizardView.options.showAliasedName = false;
        this.filterWizardView.resetFilters();
        chorus.PageEvents.broadcast("start:visualization");
    },

    selectVisualization: function(e) {
        var type = $(e.target).data('chart_type');
        $(e.target).siblings(".cancel").data("type", type);
        $(e.target).siblings('.chart_icon').removeClass('selected');
        $(e.target).addClass('selected');
        this.showTitle(e);
        this.showVisualizationConfig(type);
    },

    cancelVisualization: function(e) {
        e.preventDefault();
        this.$('.definition').removeClass("hidden");
        this.$('.create_chart').addClass("hidden");
        this.$(".filters").addClass("hidden");
        this.$('.column_count').removeClass("hidden");
        this.$('.info_bar').addClass('hidden');
        this.$(".chart_config").addClass('hidden');
        chorus.PageEvents.broadcast('cancel:visualization');
        if(this.chartConfig) {
            this.chartConfig.teardown(true);
            delete this.chartConfig;
        }

    },

    startCreateChorusViewWizard: function() {
        this.trigger("transform:sidebar", "chorus_view");
        this.$('.chorusview').addClass("selected");
        this.$('.definition').addClass("hidden");
        this.$('.create_chart').addClass("hidden");
        this.$('.create_chorus_view').removeClass("hidden");
        this.$('.chorus_view_info').removeClass("hidden");
        this.$('.column_count').addClass("hidden");
        this.$('.filters').removeClass("hidden");
        this.filterWizardView.options.showAliasedName = true;
        this.filterWizardView.resetFilters();
        this.inDeriveChorusView = true;

        this.$(".chorus_view_info input.search").trigger("textchange");
    },

    cancelCreateChorusView: function(e) {
        e.preventDefault();
        chorus.PageEvents.broadcast('cancel:sidebar', 'chorus_view');
        this.$('.definition').removeClass("hidden");
        this.$('.create_chorus_view').addClass("hidden");
        this.$(".filters").addClass("hidden");
        this.$('.column_count').removeClass("hidden");
        this.$('.chorus_view_info').addClass('hidden');

        this.$(".column_count input.search").trigger("textchange");
        this.closePreviewHandle = this.subscribePageEvent("action:closePreview", this.closeDataPreview);
        this.inDeriveChorusView = false;
    },

    startEditChorusViewWizard: function() {
        this.trigger("transform:sidebar", "edit_chorus_view");
        this.showEditChorusViewWizard();
        this.trigger("dataset:edit");
    },

    showEditChorusViewWizard: function() {
        this.$(".edit_chorus_view").removeClass("hidden");
        this.$(".create_chorus_view").addClass("hidden");
        this.$(".create_chart").addClass("hidden");
        this.$(".definition").addClass("hidden");

        this.$(".edit_chorus_view_info").removeClass("hidden");
        this.$(".column_count").addClass("hidden");
    },

    cancelEditChorusView: function(e) {
        e.preventDefault();
        this.$(".edit_chorus_view").addClass("hidden");
        this.$(".edit_chorus_view_info").addClass("hidden");
        this.$(".column_count").removeClass("hidden");
        this.$(".definition").removeClass("hidden");
        this.dataset.set({query: this.dataset.initialQuery});
        chorus.PageEvents.broadcast('cancel:sidebar', 'chorus_view');
        chorus.PageEvents.broadcast('dataset:cancelEdit');
    },

    saveChorusView: function() {
        chorus.PageEvents.broadcast("dataset:saveEdit");
    },

    closeErrorWithDetailsLink: function(e) {
        e && e.preventDefault();
        this.$(".dataset_errors").addClass("hidden");
    },

    viewErrorDetails: function(e) {
        e.preventDefault();

        var alert = new this.alertClass({model: this.errorSource});
        alert.launchModal();
        $(".errors").addClass("hidden");
    },

    showTitle: function(e) {
        $(e.target).siblings('.title').addClass('hidden');
        $(e.target).siblings('.title.' + $(e.target).data('chart_type')).removeClass('hidden');
    },

    showVisualizationConfig: function(chartType) {
        if(this.chartConfig) { this.chartConfig.teardown(true);}

        var options = { model: this.dataset, collection: this.collection, errorContainer: this };
        this.chartConfig = chorus.views.ChartConfiguration.buildForType(chartType, options);
        this.chartConfig.filters = this.filterWizardView.collection;

        this.$(".chart_config").removeClass("hidden");
        this.renderSubview("chartConfig");
    },

    showSelectedTitle: function(e) {
        $(e.target).siblings('.title').addClass('hidden');
        var type = this.$('.selected').data('chart_type');
        $(e.target).siblings('.title.' + type).removeClass('hidden');
    },

    additionalContext: function() {
        var workspaceArchived = this.options.workspace && !this.options.workspace.isActive();
        var canUpdate = this.dataset.workspace() && this.dataset.workspace().canUpdate();
        return {
            definition: this.dataset.isChorusView() ? this.dataset.get("query") : this.statistics.get("definition"),
            showEdit: this.dataset.isChorusView() && !workspaceArchived,
            showDerive: !this.dataset.isChorusView() && !this.options.isInstanceBrowser && !workspaceArchived,
            showPublish: chorus.models.Config.instance().get('tableauConfigured') && !this.options.isInstanceBrowser && !workspaceArchived && canUpdate
        };
    },

    showErrorWithDetailsLink: function(taskOrColumnSet, alertClass) {
        this.$('.dataset_errors').removeClass('hidden');
        this.alertClass = alertClass;
        this.errorSource = taskOrColumnSet;
    },

    updateColumnCount: function() {
        this.$('.count').text(t("dataset.column_count", {count: this.collection.length}));
    },

    displayPublishDialog: function() {
      this.dialog && this.dialog.teardown();
      this.dialog = new chorus.dialogs.PublishToTableau({
          model: this.dataset.deriveTableauWorkbook(),
          dataset: this.dataset
      });
      this.dialog.launchModal();
    }
});
