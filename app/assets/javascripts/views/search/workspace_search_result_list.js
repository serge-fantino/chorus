(function() {
    var viewConstructorMap = {
        workfile:                   chorus.views.SearchWorkfile,
        linked_tableau_workfile:    chorus.views.SearchWorkfile,
        dataset:                    chorus.views.SearchDataset,
        chorusView:                 chorus.views.SearchDataset,
        workspace:                  chorus.views.SearchWorkspace,
        attachment:                 chorus.views.SearchAttachment
    };

    chorus.views.WorkspaceSearchResultList = chorus.views.SearchResultList.extend({
        constructorName: "WorkspaceSearchResultList",

        title: function() {
            return t("search.type.this_workspace", { name: this.search.workspace().get("name") });
        },

        listClass: chorus.views.CheckableList.extend({
            constructorName: "WorkspaceSearchResultCheckableList",
            makeListItemView: function(model) {
                var viewConstructor = viewConstructorMap[model.get("entityType")];
                return new viewConstructor({
                    model: model,
                    search: this.listItemOptions.search,
                    workspaceIdForTagLink: this.listItemOptions.search.get('workspaceId')
                });
            }
        }),

        buildList: function() {
            return new this.listClass({
                collection: this.collection,
                selectedModels: this.selectedModels,
                listItemOptions: {search: this.options.search}
            });
        },

        showAll: function(e) {
            e.preventDefault();
            this.search.set({ searchIn: "this_workspace" });
            chorus.router.navigate(this.search.showUrl());
        }
    });
})();
