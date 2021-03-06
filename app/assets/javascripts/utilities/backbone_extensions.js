/*
 * Copyright (c) 2011 EMC Corporation All Rights Reserved
 *
 * This software is protected, without limitation, by copyright law
 * and international treaties. Use of this software and the intellectual
 * property contained therein is expressly limited to the terms and
 * conditions of the License Agreement under which it is provided by
 * or on behalf of EMC.
 */
var methodMap = {
    'create': 'POST',
    'update': 'PUT',
    'delete': 'DELETE',
    'read'  : 'GET'
};

Backbone.emulateJSON = true;

Backbone.sync = function(method, model, options) {
    method = (options && options.method) || method;

    var type = methodMap[method];

    // Default options, unless specified.
    _.defaults(options || (options = {}), {
        emulateHTTP: Backbone.emulateHTTP,
        emulateJSON: Backbone.emulateJSON
    });

    // Default JSON-request options.
    var params = { type:type, dataType: 'json'};

    // Ensure that we have a URL.
    if (!options.url) {
        // urlError is in scope in the actual backbone file
        /*global urlError:true */
        params.url = model.url({ method: method }) || urlError();
        /*global urlError:false */
    }

    // Ensure that we have the appropriate request data.
    var json;
    if (!options.data && model && (method === 'create' || method === 'update' || method === 'patch')) {
        params.contentType = 'application/json';

        // Let the model specify its own params
        var string = JSON.stringify(model.toJSON());
        json = $.parseJSON(string);
        _.each(json, function(property, key) {
            if (property === null) delete json[key];
        });
        params.data = $.param(json);
    }

    // For older servers, emulate JSON by encoding the request into an HTML-form.
    if (options.emulateJSON) {
        params.contentType = 'application/x-www-form-urlencoded';
        params.data = params.data || {};
    }

    // For older servers, emulate HTTP by mimicking the HTTP method with `_method`
    // And an `X-HTTP-Method-Override` header.
    if (options.emulateHTTP && (type === 'PUT' || type === 'DELETE' || type === 'PATCH')) {
        params.type = 'POST';
        if (options.emulateJSON) params.data._method = type;
        var beforeSend = options.beforeSend;
        options.beforeSend = function(xhr) {
            xhr.setRequestHeader('X-HTTP-Method-Override', type);
            if (beforeSend) return beforeSend.apply(this, arguments);
        };
    }

    // Don't process data on a non-GET request.
    if (params.type !== 'GET' && !options.emulateJSON) {
        params.processData = false;
    }

    var success = options.success;
    options.success = function(resp, status, xhr) {
        if (success) success(resp, status, xhr);
        model.trigger('sync', model, resp, options);
    };

    var error = options.error;
    options.error = function(xhr, status, thrown) {
        if (error) error(model, xhr, options);
        model.trigger('error', model, xhr, options);
    };

    // Make the request, allowing the user to override any Ajax options.
    if (this.uploadObj && method === "create") {
        var uploadOptions = $(this.uploadObj.form).find("input[type=file]").data("fileupload").options;
        _.each(['success', 'error', 'url', 'type', 'dataType'], function(fieldName) {
            uploadOptions[fieldName] = params[fieldName];
        });
        uploadOptions.formData = json;
        return this.uploadObj.submit();
    } else {
        var xhr = Backbone.ajax(_.extend(params, options));
        model.trigger('request', model, xhr, options);
        return xhr;
    }
};

// This function overrides loadUrl from Backbone to strip off a trailing
// slash.
//
// http://localhost/users/ => http://localhost/users
// http://localhost/users/1/ => http://localhost/users/1
//
Backbone.History.prototype.loadUrl = function(fragmentOverride) {
    var fragment = this.fragment = this.getFragment(fragmentOverride);
    if (fragment[fragment.length - 1] === '/') {
        fragment = fragment.substr(0,fragment.length-1);
    }
    var matched = _.any(this.handlers, function(handler) {
        if (handler.route.test(fragment)) {
            handler.callback(fragment);
            return true;
        }
    });
    return matched;
}

// super function, taken from here:
// -- https://gist.github.com/1542120
;(function(Backbone) {

    // Find the next object up the prototype chain that has a
    // different implementation of the method.
    function findSuper(attributeName, childObject) {
        var object = childObject;
        while(object && (object[attributeName] === childObject[attributeName])) {
            object = object.constructor.__super__;
        }
        return object;
    }

    // The super method takes two parameters: a method name
    // and an array of arguments to pass to the overridden method.
    // This is to optimize for the common case of passing 'arguments'.
    function _super(methodName, args) {

        // Keep track of how far up the prototype chain we have traversed,
        // in order to handle nested calls to _super.
        this._superCallObjects || (this._superCallObjects = {});
        var currentObject = this._superCallObjects[methodName] || this,
            parentObject = findSuper(methodName, currentObject);
        this._superCallObjects[methodName] = parentObject;

        var result;
        if(_.isFunction(parentObject[methodName])) {
            result = parentObject[methodName].apply(this, args || []);
        } else {
            result = parentObject[methodName];
        }
        delete this._superCallObjects[methodName];
        return result;
    }

    function include(/* *modules */) {
        var modules = _.toArray(arguments);
        var mergedModules = _.extend.apply(_, [
            {}
        ].concat(modules));
        return this.extend(mergedModules);
    }

    _.each(["Model", "Collection", "View", "Router"], function(klass) {
        Backbone[klass].prototype._super = _super;
        Backbone[klass].include = include;
    });

})(Backbone);


