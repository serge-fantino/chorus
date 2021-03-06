chorus.views.Bare = Backbone.View.include(
    chorus.Mixins.Events
).extend({
        constructorName: "View",

        //The order in which setup methods are called on views is as follows:
        // - _configure
        // - _ensureElement
        // - initialize
        // -> preInitialize
        // -> -> makeModel
        // -> _initializeHeaderAndBreadcrumbs
        // -> setup
        // -> bindCallbacks
        // -> bindHotKeys
        // - delegateEvents
        preInitialize: function() {
            this.makeModel.apply(this, arguments);
            this.resource = this.model || this.collection;
        },

        initialize: function initialize() {
            this.bindings = new chorus.BindingGroup(this);
            this.preInitialize.apply(this, arguments);
            chorus.viewsToTearDown.push(this);
            this.subViewObjects = [];
            this.subscriptions = [];

            this._initializeHeaderAndBreadcrumbs();
            this.setup.apply(this, arguments);

            this.bindCallbacks();
            this.bindHotkeys();

            if (this.requiredResources.length !== 0 && this.requiredResources.allResponded()) {
                this.resourcesLoaded();
            }
        },

        _initializeHeaderAndBreadcrumbs: $.noop,
        makeModel: $.noop,
        setup: $.noop,
        postRender: $.noop,
        bindCallbacks: $.noop,
        preRender: $.noop,
        setupSubviews: $.noop,
        resourcesLoaded: $.noop,
        displayLoadingSection: $.noop,

        //Subviews that don't require any configuration should be included in the subviews hash.
        //Subviews can also be manually added (for example within callbacks) using this.registerSubView(view)
        // in the parent view after creating the new view
        //
        //See wiki
        registerSubView: function(view) {
            if (_.indexOf(this.subViewObjects, view) === -1) {
                this.subViewObjects.push(view);
                chorus.unregisterView(view);

                view.parentView = this;
            }
        },

        getSubViews: function() {
            return this.subViewObjects;
        },

        torndown: false,

        // Remove a view from the dom, unbind any events, and hopefully remove it from memory.
        teardown: function(preserveContainer) {
            this.torndown = true;

            chorus.unregisterView(this);
            this.unbind();
            this.stopListening();
            this.undelegateEvents();
            this.bindings.removeAll();
            delete this.bindings.defaultContext;
            this.requiredResources.cleanUp(this);
            this.$el.unbind();
            if(preserveContainer) {
                $(this.el).children().remove();
                $(this.el).html("");
            } else {
                $(this.el).remove();
            }

            this.scrollHandle && chorus.PageEvents.unsubscribe(this.scrollHandle);

            while(!_.isEmpty(this.subViewObjects)) {
                var subViewObject = this.subViewObjects.pop();
                subViewObject.teardown();
            }

            _.each(this.subscriptions, function(handle) {
                chorus.PageEvents.unsubscribe(handle);
            });
            this.subscriptions = [];

            if(this.parentView) {
                var subViewObjects = this.parentView.subViewObjects;
                var index = subViewObjects.indexOf(this);
                if(index > -1) subViewObjects.splice(index, 1);
                delete this.parentView;
            }
        },

        bindHotkeys: function() {
            var keydownEventName = "keydown." + this.cid;
            _.each(this.hotkeys, _.bind(function(eventName, hotkey) {
                this.bindings.add($(document), keydownEventName, chorus.hotKeyMeta + '+' + hotkey, function(event) {
                    chorus.PageEvents.broadcast(eventName, event);
                });
            }, this));

            if (this.hotkeys) {
                chorus.afterNavigate(function() {
                    $(document).unbind(keydownEventName);
                });
            }
        },

        context: {},
        subviews: {},

        //Sets backbone view options and creates a listener for completion of requiredResources
        _configure: function(options) {
            var backboneOptions = [{}];
            if (arguments.length > 0 && _.isObject(arguments[0])) {
                backboneOptions = [arguments[0]];
            }
            this._super('_configure', backboneOptions);

            this.requiredResources = new chorus.RequiredResources();

            this.listenTo(this.requiredResources, 'allResourcesResponded', function() {
                this.resourcesLoaded();
                this.render();
            });

            this.requiredResources.reset(options.requiredResources);
        },

        //Creates a modal of a given type and launches it.
        createModal: function(e, modalType) {
            e.preventDefault();
            var button = $(e.target).closest("button, a");
            var modalClass = chorus[modalType + 's'][button.data(modalType)];
            var options = _.extend(button.data(), { pageModel: this.model, pageCollection: this.collection });
            var modal = new modalClass(options);
            modal.launchModal();
        },

        createDialog: function(e) {
            this.createModal(e, "dialog");
        },

        createAlert: function(e) {
            this.createModal(e, "alert");
        },

        //Render the view and all subviews, if all requiredResources have responded from the server
        //Calls pre/postRender
        render: function render() {
            this.preRender();

            var evaluatedContext = {};
            if (!this.displayLoadingSection()) {
                if (!this.requiredResources.allResponded()) {
                    return this;
                }
                // The only template rendered when loading section is displayed is the loading section itself, so no context is needed.
                evaluatedContext = _.isFunction(this.context) ? this.context() : this.context;
            }

            $(this.el).html(this.template(evaluatedContext))
                .addClass(this.className || "")
                .addClass(this.additionalClass || "")
                .attr("data-template", this.templateName);
            this.renderSubviews();
            this.postRender($(this.el));
            this.renderHelps();
            chorus.PageEvents.broadcast("content:changed");
            return this;
        },

        renderSubviews: function() {
            this.setupSubviews();
            var subviews;
            if (this.displayLoadingSection()) {
                subviews = {".loading_section": "makeLoadingSectionView"};
            } else {
                subviews = this.subviews;
            }

            _.each(subviews, function(property, selector) {
                var subview = this.getSubview(property);
                if(subview) this.registerSubView(subview);
                this.renderSubview(property, selector);
            }, this);
        },

        renderSubview: function(property, selector) {
            var view = this.getSubview(property);
            if (view) {
                if (!selector) {
                    _.each(this.subviews, function(value, key) {
                        if (value === property) {
                            selector = key;
                        }
                    });
                }
                var element = this.$(selector);
                if (element.length) {
                    if (element[0] !== view.el) {
                        var id = element.attr("id"), klass = element.attr("class");
                        $(view.el).attr("id", id);
                        $(view.el).addClass(klass);
                        element.replaceWith(view.el);
                    }

                    if (!view.requiredResources || view.requiredResources.allResponded()) {
                        view.render();
                    }
                    view.delegateEvents();
                }
            }
        },

        getSubview: function(property) {
            return _.isFunction(this[property]) ? this[property]() : this[property];
        },

        renderHelps: function() {
            var classes;
            var helpElements = this.$(".help");
            if (helpElements.length) {
                if ($(this.el).closest(".dialog").length) {
                    classes = "tooltip-help tooltip-modal";
                } else {
                    classes = "tooltip-help";
                }
            }
            _.each(helpElements, function(element) {
                $(element).qtip({
                    content: $(element).data("text"),
                    show: 'mouseover',
                    hide: {
                        delay: 1000,
                        fixed: true,
                        event: 'mouseout'
                    },
                    position: {
                        viewport: $(window),
                        my: "bottom center",
                        at: "top center"
                    },
                    style: {
                        classes: classes,
                        tip: {
                            width: 20,
                            height: 13
                        }
                    }
                });
            });
        },

        subscribePageEvent: function(eventName, callback, context, id) {
            context = context || this;
            if(!id && _.isString(context)) {
                id = context;
                context = this;
            }
            var subscription = chorus.PageEvents.subscribe(eventName, callback, context, id);
            this.subscriptions.push(subscription);
        },

        template: function template(context) {
            if (this.displayLoadingSection()) {
                return '<div class="loading_section"/>';
            } else {
                return Handlebars.helpers.renderTemplate(this.templateName, context).toString();
            }
        },

        makeLoadingSectionView: function() {
            var opts = _.extend({}, this.loadingSectionOptions());
            return new chorus.views.LoadingSection(opts);
        },

        loadingSectionOptions: function() {
            return { delay: 125 };
        },

        setupScrolling: function(selector, options) {
            _.defer(_.bind(function() {
                if(this.torndown) { return; }
                var $el = this.$(selector);
                if (!$el.length) {
                    $el = $(selector);
                }

                if ($el.length > 0) {
                    var alreadyInitialized = $el.data("jsp");

                    $el.jScrollPane(options);
                    $el.find('.jspVerticalBar').hide();
                    $el.find('.jspHorizontalBar').hide();

                    // TODO #42333397: clean up this binding at teardown because it leaks memory
                    $el.bind("jsp-scroll-y", _.bind(function() { this.trigger("scroll"); }, this));

                    if(this.scrollHandle) {
                        chorus.PageEvents.unsubscribe(this.scrollHandle);
                        var index = this.subscriptions.indexOf(this.scrollHandle);
                        if(index > -1) this.subscriptions.splice(index, 1);
                    }
                    this.scrollHandle = this.subscribePageEvent("content:changed", function() { this.recalculateScrolling($el); });
                    this.subscriptions.push(this.scrollHandle);

                    if (!alreadyInitialized) {
                        $el.addClass("custom_scroll");
                        $el.unbind('hover').hover(function() {
                            $el.find('.jspVerticalBar, .jspHorizontalBar').fadeIn(150);
                        }, function() {
                            $el.find('.jspVerticalBar, .jspHorizontalBar').fadeOut(150);
                        });

                        $el.find('.jspContainer').unbind('mousewheel', this.onMouseWheel).bind('mousewheel', this.onMouseWheel);

                        if (chorus.page && chorus.page.bind) {
                            if(this.resizeCallback) {
                                this.bindings.remove(chorus.page, "resized", this.resizeCallback);
                            }
                            this.resizeCallback = function() { this.recalculateScrolling($el); };
                            this.bindings.add(chorus.page, "resized", this.resizeCallback, this);
                        }
                    }
                }
            }, this));
        },

        onMouseWheel: function(event) {
            event.preventDefault();
        },

        recalculateScrolling: function(el) {
            var elements = el ? [el] : this.$(".custom_scroll");
            _.each(elements, function(el) {
                el = $(el);
                var api = el.data("jsp");
                if (api) {
                    _.defer(_.bind(function() {
                        api.reinitialise();
                        if (!api.getIsScrollableH() && api.getContentPositionX() > 0) {
                            el.find(".jspPane").css("left", 0);
                        }
                        if (!api.getIsScrollableV() && api.getContentPositionY() > 0) {
                            el.find(".jspPane").css("top", 0);
                        }
                        el.find('.jspVerticalBar').hide();
                        el.find('.jspHorizontalBar').hide();
                    }, this));
                }
            });
        }
    }, {
        extended: function(subclass) {
            var proto = subclass.prototype;
            if (proto.templateName) {
                proto.className = proto.templateName.replace(/\//g, "_");
            }

            _.defaults(proto.events, this.prototype.events);
        }
    });

chorus.views.Bare.extend = chorus.classExtend;

chorus.views.Base = chorus.views.Bare.extend({
    collectionModelContext: $.noop,
    additionalContext: function() {
        return {};
    },

    //Bind various callbacks to the view's resource (model or collection)
    bindCallbacks: function() {
        if (this.resource) {
            this.listenTo(this.resource, "saveFailed validationFailed", this.showErrors);
            this.listenTo(this.resource, "validated", this.clearErrors);
            if (!this.persistent) {
                this.listenTo(this.resource, "change reset sort", this.render);
            }
        }
    },

    //Remove default bindings from view
    unbindCallbacks: function() {
        if(this.resource) {
            this.stopListening(this.resource, "saveFailed", this.showErrors);
            this.stopListening(this.resource, "validationFailed", this.showErrors);
            this.stopListening(this.resource, "validated", this.clearErrors);
            this.stopListening(this.resource, "change", this.render);
            this.stopListening(this.resource, "reset", this.render);
            this.stopListening(this.resource, "sort", this.render);
        }
    },

    //A JSON object with view attributes for handlebars to render within.
    context: function context(resource) {
        resource = resource || this.resource;
        var ctx;
        var self = this;

        if (resource) {
            ctx = _.clone(resource.attributes);
            ctx.resource = resource;
            ctx.loaded = resource.loaded;
            if (this.collection) {
                ctx.models = _.map(this.collection.models, function(model) {
                    return _.extend({model: model}, model.attributes, self.collectionModelContext(model));
                });
            }
            if (resource.serverErrors) ctx.serverErrors = resource.serverErrors;
            $.extend(ctx, this.additionalContext(ctx));
        } else {
            ctx = this.additionalContext({});
        }

        ctx.view = self;
        return ctx;
    },

    render: function() {
        var result = this._super('render', arguments);
        chorus.placeholder(this.$("input[placeholder], textarea[placeholder]"));
        return result;
    },

    displayLoadingSection: function() {
        if (!this.useLoadingSection) {
            return false;
        }
        if (this.requiredResources.length > 0) {
            return !this.requiredResources.allResponded();
        } else {
            return this.resource && !this.resource.loaded;
        }
    },

    showErrors: function(model) {
        var self = this;

        var isModal = $(this.el).closest(".dialog").length;

        this.clearErrors();

        if (!model) {
            model = this.resource;
        }
        _.each(model.errors, function(val, key) {
            var $input = self.$("input[name=" + key + "], form textarea[name=" + key + "]");
            self.markInputAsInvalid($input, val, isModal);
        });

        this.$(".errors").replaceWith(Handlebars.VM.invokePartial(Handlebars.partials.errorDiv, "errorDiv", this.context(model), Handlebars.helpers, Handlebars.partials));
    },

    markInputAsInvalid: function($input, message, isModal) {
        var classes = isModal ? "tooltip-error tooltip-modal" : "tooltip-error";
        $input.addClass("has_error");
        $input.qtip({
            content: {
                text: message
            },
            show: 'mouseover focus',
            hide: 'mouseout blur',
            style: {
                classes: classes,
                tip: {
                    width: 12,
                    height: 12
                }
            },
            position: {
                my: "left center",
                at: "right center",
                container: this.el
            }
        });
    },

    clearErrors: function() {
        this.clearPopupErrors();
        this.$(".errors").empty();
    },

    clearPopupErrors: function() {
        var errors = this.$(".has_error");
        errors.qtip("destroy");
        errors.removeData("qtip");
        errors.removeClass("has_error");
    },

    setModel: function(model) {
        this.unbindCallbacks();
        this.resource = this.model = model;
        this.bindCallbacks();
    }
});

chorus.views.MainContentView = chorus.views.Base.extend({
    constructorName: "MainContentView",
    templateName: "main_content",

    setup: function(options) {
        options = options || {};
        this.contentHeader = this.contentHeader || options.contentHeader;
        this.contentDetails = this.contentDetails || options.contentDetails;
        this.content = this.content || options.content;
        this.contentFooter = this.contentFooter || options.contentFooter;
    },

    subviews: {
        ".content_header > div": "contentHeader",
        ".content_details > div": "contentDetails",
        ".content > div": "content",
        ".content_footer > div": "contentFooter"
    },

    postRender: function() {
        if (!this.contentDetails) this.$(".content_details").addClass("hidden");
        if (!this.content)        this.$(".content").addClass("hidden");
        if (!this.contentFooter)  this.$(".content_footer").addClass("hidden");
    }
});

chorus.views.ListHeaderView = chorus.views.Base.extend({
    templateName: "default_content_header",

    context: function() {
        var ctx = this.options;
        return _.extend({}, ctx, this.additionalContext());
    },

    postRender: function() {
        var self = this;
        if (this.options.linkMenus) {
            _.each(this.options.linkMenus, function(menuOptions, menuKey) {
                var menu = new chorus.views.LinkMenu(menuOptions);
                self.$(".menus").append(
                    menu.render().el
                );
                $(menu.el).addClass(menuKey);
                menu.bind("choice", function(eventType, choice) {
                    self.trigger("choice:" + eventType, choice);
                });
            });
        }
    }
});

chorus.views.MainContentList = chorus.views.MainContentView.extend({
    setup: function(options) {
        var modelClass = options.modelClass;
        var collection = this.collection;
        if(options.checkable) {
            this.content = new chorus.views.CheckableList(_.extend({
                    collection: collection,
                    entityType: modelClass.toLowerCase(),
                    entityViewType: chorus.views[modelClass]
                },
                options.contentOptions));
        } else {
            this.content = new chorus.views[modelClass + "List"](_.extend({collection: collection}, options.contentOptions));
        }

        this.contentHeader = options.contentHeader || new chorus.views.ListHeaderView({title: options.title || (!options.emptyTitleBeforeFetch && (modelClass + "s")), linkMenus: options.linkMenus, imageUrl: options.imageUrl, sandbox: options.sandbox});

        if (options.hasOwnProperty('persistent')) {
            this.persistent = options.persistent;
        }

        if (options.contentDetails) {
            this.contentDetails = options.contentDetails;
        } else {
            this.contentDetails = new chorus.views.ListContentDetails(
                _.extend({
                    collection: collection,
                    modelClass: modelClass,
                    buttons: options.buttons,
                    search: options.search && _.extend({list: $(this.content.el)}, options.search)
                }, options.contentDetailsOptions));

            this.contentFooter = new chorus.views.ListContentDetails({
                collection: collection,
                modelClass: modelClass,
                hideCounts: true,
                hideIfNoPagination: true
            });
        }
    },
    additionalClass: "main_content_list"
});
