describe("chorus.views.DatasetShowContentHeader", function() {
    beforeEach(function() {
        this.model = rspecFixtures.workspaceDataset.sourceTable({
            tags: [
                {name: "alpha"}
            ]
        });
        this.model.loaded = false;
        delete this.model.statusCode;
        this.model.fetch();
        this.view = new chorus.views.DatasetShowContentHeader({
            model: this.model,
            workspaceId: 123
        });
        this.view.render();
    });

    describe('when the dataset is not loaded', function() {
        it('does not render', function() {
            expect(this.view.$('img.icon')).not.toExist();
        });
    });

    describe('when the dataset fetch completes', function() {
        beforeEach(function(){
            this.server.completeFetchFor(this.model);
        });

        it('renders the header', function() {
            expect(this.view.$('img.icon')).toExist();
        });

        it("renders the list of tags", function() {
            expect(this.view.$('.text-tags')).toContainText("alpha");
        });

        it("has a workspace id for the tagbox", function() {
            expect(this.view.tagBox.options.workspaceIdForTagLink).toBe(123);
        });
    });
});