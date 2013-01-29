(function() {
    var CLASS_MAP = {
        "actor": "User",
        "dataset": "WorkspaceDataset",
        'dataSource': 'DynamicDataSource',
        "gpdbDataSource": "GpdbDataSource",
        "gnipInstance": "GnipInstance",
        "newOwner": "User",
        "hadoopInstance": "HadoopInstance",
        "workfile": "Workfile",
        "workspace": "Workspace",
        "newUser" : "User",
        "noteObject" : "NoteObject",
        "hdfsEntry" : "HdfsEntry",
        "member": "User",
        "sourceDataset": "WorkspaceDataset"
    };

    function makeAssociationMethod(name, setupFunction) {
        return function() {
            var className = CLASS_MAP[name];
            var modelClass = chorus.models[className];
            var model = new modelClass(this.get(name));
            if (setupFunction) setupFunction.call(this, model);
            return model;
        };
    }

    chorus.models.Activity = chorus.models.Base.extend({
        constructorName: "Activity",
        urlTemplate: "activities/{{id}}",

        author: function() {
            if (!this._author) {
                if (this.has("author")) {
                    this._author = new chorus.models.User(this.get("author"));
                } else if (this.has("actor")) {
                    this._author = new chorus.models.User(this.get("actor"));
                }
            }

            return this._author;
        },

        newOwner: makeAssociationMethod("newOwner"),
        workspace: makeAssociationMethod("workspace"),
        actor: makeAssociationMethod("actor"),
        dataSource: makeAssociationMethod('dataSource'),
        gpdbDataSource: makeAssociationMethod("gpdbDataSource"),
        gnipInstance: makeAssociationMethod("gnipInstance"),
        hadoopInstance: makeAssociationMethod("hadoopInstance"),
        workfile: makeAssociationMethod("workfile"),
        newUser: makeAssociationMethod("newUser"),
        member: makeAssociationMethod("member"),

        dataset: makeAssociationMethod("dataset", function(model) {
            model.set({workspace: this.get("workspace")}, {silent: true});
        }),

        importSource: makeAssociationMethod("sourceDataset", function(model) {
            model.set({workspace: this.get("workspace")}, {silent: true});
        }),

        hdfsEntry: makeAssociationMethod("hdfsEntry", function(model) {
            var hdfsEntry = this.get("hdfsEntry");
            model.set({
                id : hdfsEntry.id,
                hadoopInstance: hdfsEntry.hadoopInstance
            });
        }),

        noteObject: function() {
            var model;

            switch (this.get("actionType")) {
                case "NoteOnHadoopInstance":
                    model = new chorus.models.HadoopInstance();
                    model.set(this.get("hadoopInstance"));
                    break;
                case "NoteOnGreenplumInstance":
                    model = new chorus.models.GpdbDataSource();
                    model.set(this.get("gpdbDataSource"));
                    break;
                case "NoteOnGnipInstance":
                    model = new chorus.models.GnipInstance();
                    model.set(this.get("gnipInstance"));
                    break;
                case "NoteOnHdfsFile":
                    model = new chorus.models.HdfsEntry();
                    model.set({
                        hadoopInstance: new chorus.models.HadoopInstance(this.get("hdfsFile").hadoopInstance),
                        id: this.get("hdfsFile").id,
                        name: this.get("hdfsFile").name
                    });
                    break;
                case "NoteOnWorkspace":
                    model = new chorus.models.Workspace();
                    model.set(this.get("workspace"));
                    break;
                case "NoteOnDataset":
                    model = new chorus.models.Dataset();
                    model.set(this.get("dataset"));
                    break;
                case "NoteOnWorkspaceDataset":
                    model = new chorus.models.WorkspaceDataset();
                    model.set(this.get("dataset"));
                    model.setWorkspace(this.get("workspace"));
                    break;
                case "NoteOnWorkfile":
                    model = new chorus.models.Workfile();
                    model.set(this.get("workfile"));
                    break;
            }
            return model;
        },

        comments: function() {
            this._comments || (this._comments = new chorus.collections.CommentSet(
                this.get("comments"), {
                    entityType: this.collection && this.collection.attributes.entityType,
                    entityId: this.collection && this.collection.attributes.entityId
                }
            ));
            return this._comments;
        },

        promoteToInsight: function(options) {
            var insight = new chorus.models.Insight({
                noteId: this.get("id"),
                action: "create"
            });
            insight.bind("saved", function() {
                this.fetch();
                if (options && options.success) {
                    options.success(this);
                }
            }, this);

            insight.save({ validateBody: false });
        },

        publish: function() {
            var insight = new chorus.models.Insight({
                noteId: this.get("id"),
                action: "publish"
            });

            insight.bind("saved", function() {
                this.fetch();
            }, this);

            insight.save({ validateBody: false }, {method: 'create'});
        },

        unpublish: function() {
            var insight = new chorus.models.Insight({
                noteId: this.get("id"),
                action: "unpublish"
            });

            insight.bind("saved", function() {
                this.fetch();
            }, this);

            insight.save({ validateBody: false }, {method: 'create'});
        },

        toNote: function() {
            var comment = new chorus.models.Note({
                id: this.id,
                body: this.get("body")
            });

            return comment;
        },

        attachments: function() {
            if (!this._attachments) {
                this._attachments = _.map(this.get("attachments"), function(artifactJson) {
                    var klass;
                    switch (artifactJson.entityType) {
                        case 'workfile':
                            klass = chorus.models.DynamicWorkfile;
                            break;
                        case 'dataset':
                            klass = chorus.models.WorkspaceDataset;
                            break;
                        default:
                            klass = chorus.models.Attachment;
                            break;
                    }
                    return new klass(artifactJson);
                });
            }
            return this._attachments;
        },

        isNote: function() {
            return this.get("action") === "NOTE";
        },

        canBePromotedToInsight: function() {
            return this.isNote() && !this.isInsight();
        },

        isInsight: function() {
            return this.get("isInsight");
        },

        isSubComment: function() {
            return this.get("action") === "SUB_COMMENT";
        },

        hasCommitMessage: function() {
            return (this.get("action") === "WorkfileUpgradedVersion" ||
                this.get("action") === "WorkfileCreated" ) &&
                this.get("commitMessage");
        },

        isUserGenerated: function () {
            return this.isNote() || this.isInsight() || this.isSubComment();
        },

        isPublished: function() {
            return this.get("isPublished");
        },

        isOwner: function() {
            return (this.actor().id === chorus.session.user().id);
        },

        isFailure: function() {
            return this.get('action') === "GnipStreamImportFailed" || this.get("action") === "FileImportFailed" ||  this.get("action") === "DatasetImportFailed";
        },

        isSuccessfulImport: function() {
            return this.get('action') === "GnipStreamImportSuccess" || this.get("action") === "FileImportSuccess" ||  this.get("action") === "DatasetImportSuccess" ;
        },

        promoterLink: function() {
            var promoter = this.promoter();
            return promoter ? chorus.helpers.userProfileLink(promoter) : "MISSING PROMOTER";
        },

        promoter: function () {
            return this.get("promotedBy") ? new chorus.models.User(this.get("promotedBy")) : null;
        },

        promotionTimestamp:function() {
            return this.get("promotionTime") ? chorus.helpers.relativeTimestamp(this.get("promotionTime")) : null;
        },

        reindexError: function() {
            if (this.isFailure()) {
                this.attributes['errorModelId'] = this.get("id");
            }
        }
    });
})();
