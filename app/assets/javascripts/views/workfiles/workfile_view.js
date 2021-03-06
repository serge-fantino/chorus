chorus.views.Workfile = chorus.views.Base.extend(chorus.Mixins.TagsContext).extend({
    templateName:"workfile",
    tagName: "li",

    subviews: {
        ".comment .body": "commentBody"
    },

    setup: function() {
        this._super("setup", arguments);
        this.bindings.add(this.model, "invalidated", function() { this.model.fetch(); }, this);
    },

    setupSubviews: function() {
        this.commentBody = new chorus.views.TruncatedText({
            model: this.model.lastComment(),
            attribute: "body",
            attributeIsHtmlSafe: true
        });
    },

    postRender: function() {
        $(this.el).attr('data-id', this.model.id);
    },

    additionalContext: function() {
        var ctx = new chorus.presenters.Attachment(this.model, { iconSize:'icon' });

        ctx.tableauWorkbook = this.model.get('fileType') === 'tableau_workbook';
        ctx.tableauIcon = chorus.helpers.tableauIcon();
        ctx.checkable = this.options.checkable;

        _.extend(ctx, this.additionalContextForTags());

        var lastComment = this.model.lastComment();
        if (lastComment) {
            var date = Date.parseFromApi(lastComment.get("commentCreatedStamp"));

            ctx.lastComment = {
                body:lastComment.get("body"),
                creator:lastComment.author(),
                on:date && date.toString("MMM d")
            };

            ctx.otherCommentCount = parseInt(this.model.get("commentCount"), 10) - 1;
        }

        return ctx;
    }
});
