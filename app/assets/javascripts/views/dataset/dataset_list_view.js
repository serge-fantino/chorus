chorus.views.DatasetList = chorus.views.SelectableList.extend({
    constructorName: "DatasetListView",
    templateName: "dataset_list",
    useLoadingSection: true,
    eventName: "dataset",

    events: {
        "click  li input[type=checkbox]": "checkboxClicked",
        "change li input[type=checkbox]": "checkboxChanged"
    },

    setup: function() {
        this._super("setup", arguments);
        this.selectedDatasets = this.collection.clone().reset();
        this.subscribePageEvent("selectAll", this.selectAll);
        this.subscribePageEvent("selectNone", this.selectNone);
    },

    selectAll: function() {
        this.bindings.add(this.selectedDatasets, "reset", this.selectAllFetched);
        this.selectedDatasets.fetchAll();
    },

    selectAllFetched: function() {
        this.$("> li input[type=checkbox]").prop("checked", true).change();
        chorus.PageEvents.broadcast("dataset:checked", this.selectedDatasets);
    },

    selectNone: function() {
        this.selectedDatasets.reset([]);
        this.$("> li input[type=checkbox]").prop("checked", false).change();
        chorus.PageEvents.broadcast("dataset:checked", this.selectedDatasets);
    },

    postRender: function() {
        var $list = $(this.el);
        if(this.collection.length === 0 && this.collection.loaded) {
            var linkText = Handlebars.helpers.linkTo("#/data_sources", t("datasource.browse"));
            var noDatasetEl = $("<div class='browse_more'></div>");

            var hintText;
            if (this.collection.hasFilter && this.collection.hasFilter()) {
                hintText = t("dataset.filtered_empty");
            } else if (this.collection.attributes.workspaceId) {
                hintText = t("dataset.browse_more_workspace", {linkText: linkText});
            } else {
                hintText = t("dataset.browse_more_instance", {linkText: linkText});
            }

            noDatasetEl.append(hintText);
            $list.append(noDatasetEl);
        }

        _.each(this.datasetViews, function(datasetView) {
            datasetView.teardown();
        });
        this.datasetViews = [];

        this.collection.each(function(model) {
            var view = new chorus.views.Dataset({ model: model, activeWorkspace: this.options.activeWorkspace, checkable: this.options.checkable });
            $list.append(view.render().el);
            this.datasetViews.push(view);
            this.registerSubView(view);
        }, this);
        this._super("postRender", arguments);

        this.checkSelectedDatasets();
    },

    checkSelectedDatasets: function() {
        var checkboxes = this.$("input[type=checkbox]");
        this.collection.each(function(model, i) {
            if (this.selectedDatasets.get(model.id)) {
                checkboxes.eq(i).prop("checked", true);
            }
        }, this);
    },

    checkboxChanged: function(e) {
        var clickedBox = $(e.currentTarget);
        var clickedLi = $(e.currentTarget.parentElement);
        var index = this.$("> li input[type=checkbox]").index(clickedBox);
        var isChecked = clickedBox.prop("checked");
        var model = this.collection.at(index);

        clickedLi.toggleClass("checked", isChecked);

        if (isChecked) {
            if (!this.selectedDatasets.contains(model)) {
                this.selectedDatasets.add(model);
            }
        } else {
            this.selectedDatasets.remove(model);
        }

        chorus.PageEvents.broadcast("dataset:checked", this.selectedDatasets);
    },

    checkboxClicked: function(e) {
        e.stopPropagation();
    }
});
