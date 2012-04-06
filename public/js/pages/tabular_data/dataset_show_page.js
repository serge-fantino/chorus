chorus.pages.DatasetShowPage = chorus.pages.TabularDataShowPage.extend({
    constructorName: "DatasetShowPage",
    helpId: "dataset",
    hideDeriveChorusView: false,

    crumbs: function() {
        return [
            {label: t("breadcrumbs.home"), url: "#/"},
            {label: t("breadcrumbs.workspaces"), url: '#/workspaces'},
            {label: this.workspace.displayShortName(), url: this.workspace.showUrl()},
            {label: t("breadcrumbs.workspaces_data"), url: this.workspace.datasetsUrl()},
            {label: this.tabularData.get('objectName')}
        ];
    },

    setup: function() {
        this._super('setup', arguments);

        this.sidebarOptions = {
            workspace: this.workspace,
            requiredResources: [ this.workspace ]
        };

        this.contentDetailsOptions = {
            workspace: this.workspace
        }
        this.subNav = new chorus.views.SubNav({workspace: this.workspace, tab: "datasets"});
    },

    makeModel: function(workspaceId, datasetId) {
        this.workspaceId = workspaceId;
        this.workspace = new chorus.models.Workspace({id: workspaceId});
        this.requiredResources.add(this.workspace);
        this.workspace.fetch();
        this.model = this.tabularData = new chorus.models.Dataset({ workspace: { id: workspaceId }, id: datasetId })
    },

    drawColumns: function() {
        this._super('drawColumns');

        this.mainContent.contentDetails.bind("dataset:edit", this.editChorusView, this);
    },

    editChorusView: function() {
        var sameHeader = this.mainContent.contentHeader;
        this.mainContent = new chorus.views.MainContentView({
            content: new chorus.views.DatasetEditChorusView({model: this.tabularData}),
            contentHeader: sameHeader,
            contentDetails: new chorus.views.TabularDataContentDetails({ tabularData: this.tabularData, collection: this.columnSet, inEditChorusView: true })
        });

        this.mainContent.contentDetails.bind("dataset:cancelEdit", this.drawColumns, this);
        this.mainContent.contentDetails.forwardEvent("dataset:saveEdit", this.mainContent.content, this);

        this.renderSubview('mainContent');
    },

    constructSidebarForType: function(type) {
        switch (type) {
            case 'chorus_view':
                this.tabularData.setDatasetNumber(1);
                this.sidebar.disabled = true;
                this.mainContent.content.selectMulti = true;
                this.mainContent.content.showDatasetName = true;
                this.mainContent.content.render();
                this.mainContent.content.selectNone();
                this.secondarySidebar = new chorus.views.CreateChorusViewSidebar({model: this.model, aggregateColumnSet: this.columnSet});
                break;
            case 'edit_chorus_view':
                this.secondarySidebar = new chorus.views.DatasetEditChorusViewSidebar({model: this.model});
                break;
            default:
                this._super('constructSidebarForType', arguments);
        }
    },

    hideSidebar: function(type) {
        this.tabularData.clearDatasetNumber();
        this.columnSet.reset(this.tabularData.columns().models);
        this.mainContent.content.selectMulti = false;
        this.mainContent.content.showDatasetName = false;
        this._super('hideSidebar', arguments);
    },

    removeOldSecondaryClasses: function(type) {
        this._super('removeOldSecondaryClasses', arguments);
        this.$('.sidebar_content.secondary').removeClass("dataset_create_" + type + "_sidebar");
    }
});
